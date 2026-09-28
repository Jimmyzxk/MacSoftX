import XCTest
@testable import upmac

final class AppScanServiceTests: XCTestCase {

    /// 测试目录发现：排除根卷别名（如 /Volumes/Macintosh HD 归一后为 /）
    func testRootVolumeAliasDetection() {
        // 根目录 "/" 自身必须被判定为根卷
        XCTAssertTrue(AppScanService.isRootVolumeAlias(path: "/"))

        // 如果本机存在 /Volumes/Macintosh HD 别名链接到 /，应判定为根卷别名
        if FileManager.default.fileExists(atPath: "/Volumes/Macintosh HD") {
            let isAlias = AppScanService.isRootVolumeAlias(path: "/Volumes/Macintosh HD")
            // 在实际 macOS 系统中 /Volumes/Macintosh HD 指向根卷 /
            XCTAssertTrue(isAlias)
        }

        // 普通目录绝不能误判为根卷别名
        XCTAssertFalse(AppScanService.isRootVolumeAlias(path: "/Applications"))
        XCTAssertFalse(AppScanService.isRootVolumeAlias(path: "/Users"))
    }

    /// 测试目录发现：从 state.json 读取 extraScanDirs 并成功展开波浪号 ~
    func testExtraScanDirsLoadingFromStateJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let stateFile = tempDir.appendingPathComponent("state.json")
        let jsonContent = """
        {
            "lastCheck": "2026-09-13T10:00:00Z",
            "extraScanDirs": [
                "/Custom/Applications",
                "~/Developer/Applications"
            ]
        }
        """
        try jsonContent.write(to: stateFile, atomically: true, encoding: .utf8)

        let loaded = AppScanService.loadExtraScanDirs(from: stateFile.path)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0], "/Custom/Applications")
        XCTAssertTrue(loaded[1].hasPrefix("/Users/"))
        XCTAssertFalse(loaded[1].contains("~"))
    }

    /// 测试应用包解析：使用 PropertyListSerialization 提取 Info.plist 元数据并识别 App Store 渠道
    func testInspectAppBundleInfoMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let mockApp = tempDir.appendingPathComponent("MockTool.app")
        let contentsDir = mockApp.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let plistDict: [String: Any] = [
            "CFBundleDisplayName": "Mock Sparkle Tool",
            "CFBundleIdentifier": "com.example.mocktool",
            "CFBundleShortVersionString": "1.4.2",
            "SUFeedURL": "https://example.com/mocktool/appcast.xml"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        try plistData.write(to: plistURL)

        // 1. 无 _MASReceipt 时为常规 Sparkle 软件
        let scanned1 = AppScanService.inspectAppBundle(at: mockApp.path)
        XCTAssertNotNil(scanned1)
        XCTAssertEqual(scanned1?.name, "Mock Sparkle Tool")
        XCTAssertEqual(scanned1?.bundleId, "com.example.mocktool")
        XCTAssertEqual(scanned1?.version, "1.4.2")
        XCTAssertEqual(scanned1?.feedURL, "https://example.com/mocktool/appcast.xml")
        XCTAssertFalse(scanned1?.isAppStoreReceiptPresent ?? true)

        // 2. 加入 _MASReceipt 后标记为 App Store 渠道
        let receiptDir = contentsDir.appendingPathComponent("_MASReceipt")
        try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)

        let scanned2 = AppScanService.inspectAppBundle(at: mockApp.path)
        XCTAssertNotNil(scanned2)
        XCTAssertTrue(scanned2?.isAppStoreReceiptPresent ?? false)
    }

    /// 测试目录安全校验：过滤包含 ".." 路径穿越段、非绝对路径、敏感前缀及根目录
    func testExtraScanDirsSecurityFiltering() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let stateFile = tempDir.appendingPathComponent("state.json")
        let jsonContent = """
        {
            "extraScanDirs": [
                "/Valid/CustomAppDir",
                "/System/Library",
                "/usr/local/bin",
                "/bin",
                "/sbin",
                "/etc",
                "/var/log",
                "/private/etc",
                "/",
                "relative/path/apps",
                "/Applications/../etc",
                "~/Valid/UserApps"
            ]
        }
        """
        try jsonContent.write(to: stateFile, atomically: true, encoding: .utf8)

        let loaded = AppScanService.loadExtraScanDirs(from: stateFile.path)

        // 仅保留合法的绝对路径与展开后的波浪号路径
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0], "/Valid/CustomAppDir")
        XCTAssertTrue(loaded[1].hasPrefix("/Users/"))
        XCTAssertTrue(loaded[1].hasSuffix("/Valid/UserApps"))

        // 细化 helper 测试
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/System"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/System/Applications"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/usr/bin"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/etc/hosts"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/var/run"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/private/tmp"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("relative/dir"))
        XCTAssertFalse(AppScanService.isValidExtraScanDir("/Applications/../etc"))
        XCTAssertTrue(AppScanService.isValidExtraScanDir("/Applications"))
        XCTAssertTrue(AppScanService.isValidExtraScanDir("/Volumes/External/Applications"))
        XCTAssertTrue(AppScanService.isValidExtraScanDir("~/Applications"))
    }
}

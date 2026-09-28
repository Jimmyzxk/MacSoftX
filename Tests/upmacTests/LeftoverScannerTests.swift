import XCTest
@testable import upmac

final class LeftoverScannerTests: XCTestCase {

    var tempDir: URL!
    var tempHome: URL!
    var tempSystemLibrary: URL!
    var tempAppsDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempHome = tempDir.appendingPathComponent("Users/testuser")
        tempSystemLibrary = tempDir.appendingPathComponent("Library")
        tempAppsDir = tempDir.appendingPathComponent("Applications")

        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Logs"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Saved Application State"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Containers"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/LaunchAgents"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempAppsDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    // 1. 孤儿残留判定与系统白名单排除测试
    func testOrphanDetectionAndSystemExclusion() async {
        let scanner = LeftoverScanner(
            homeDirectory: tempHome,
            systemLibraryDirectory: tempSystemLibrary,
            applicationsDirectories: [tempAppsDir]
        )

        // 1) 构造已安装应用
        let installedItem = InventoryItem(
            id: "installed_app",
            name: "ActiveApp",
            version: "1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动安装",
            status: .unmanaged,
            bundleId: "com.example.activeapp",
            path: "/Applications/ActiveApp.app"
        )

        // 2) 构造真实文件条目：
        // A. 已安装应用的缓存（不应被判为孤儿）
        let activeCacheDir = tempHome.appendingPathComponent("Library/Caches/com.example.activeapp")
        try? FileManager.default.createDirectory(at: activeCacheDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: activeCacheDir.appendingPathComponent("cache.dat").path, contents: "data".data(using: .utf8))

        // B. 苹果系统组件缓存（不应被判为孤儿）
        let appleCacheDir = tempHome.appendingPathComponent("Library/Caches/com.apple.finder")
        try? FileManager.default.createDirectory(at: appleCacheDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: appleCacheDir.appendingPathComponent("finder.dat").path, contents: "data".data(using: .utf8))

        // C. 孤儿缓存（应被判为孤儿，安全类）
        let orphanCacheDir = tempHome.appendingPathComponent("Library/Caches/com.deleted.tool")
        try? FileManager.default.createDirectory(at: orphanCacheDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: orphanCacheDir.appendingPathComponent("cached.dat").path, contents: "cached data".data(using: .utf8))

        // D. 孤儿日志（应被判为孤儿，安全类）
        let orphanLogDir = tempHome.appendingPathComponent("Library/Logs/OldApp")
        try? FileManager.default.createDirectory(at: orphanLogDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: orphanLogDir.appendingPathComponent("old.log").path, contents: "log data".data(using: .utf8))

        // E. 孤儿偏好设置 plist（应被判为孤儿，谨慎类）
        let orphanPrefFile = tempHome.appendingPathComponent("Library/Preferences/com.deleted.tool.plist")
        FileManager.default.createFile(atPath: orphanPrefFile.path, contents: "pref data".data(using: .utf8))

        // F. 孤儿保存状态 savedState（应被判为孤儿，安全类）
        let orphanSavedStateDir = tempHome.appendingPathComponent("Library/Saved Application State/com.deleted.tool.savedState")
        try? FileManager.default.createDirectory(at: orphanSavedStateDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: orphanSavedStateDir.appendingPathComponent("window.state").path, contents: "state".data(using: .utf8))

        // G. 孤儿容器（应被判为孤儿，谨慎类）
        let orphanContainerDir = tempHome.appendingPathComponent("Library/Containers/com.deleted.tool")
        try? FileManager.default.createDirectory(at: orphanContainerDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: orphanContainerDir.appendingPathComponent("container.dat").path, contents: "cont".data(using: .utf8))

        // 执行扫描
        let results = await scanner.scanLeftovers(installedItems: [installedItem])

        let resultPaths = Set(results.map { $0.path })

        // 验证：已装与系统项未被误判
        XCTAssertFalse(resultPaths.contains(activeCacheDir.path))
        XCTAssertFalse(resultPaths.contains(appleCacheDir.path))

        // 验证：孤儿文件全部命中
        XCTAssertTrue(resultPaths.contains(orphanCacheDir.path))
        XCTAssertTrue(resultPaths.contains(orphanLogDir.path))
        XCTAssertTrue(resultPaths.contains(orphanPrefFile.path))
        XCTAssertTrue(resultPaths.contains(orphanSavedStateDir.path))
        XCTAssertTrue(resultPaths.contains(orphanContainerDir.path))

        // 验证分类与默认勾选属性
        let cacheLeftover = results.first { $0.path == orphanCacheDir.path }
        XCTAssertEqual(cacheLeftover?.category, .safe)
        XCTAssertTrue(cacheLeftover?.isSelected == true, "安全类默认勾选")

        let logLeftover = results.first { $0.path == orphanLogDir.path }
        XCTAssertEqual(logLeftover?.category, .safe)
        XCTAssertTrue(logLeftover?.isSelected == true, "安全类默认勾选")

        let prefLeftover = results.first { $0.path == orphanPrefFile.path }
        XCTAssertEqual(prefLeftover?.category, .caution)
        XCTAssertFalse(prefLeftover?.isSelected == true, "谨慎类默认不勾选")

        let containerLeftover = results.first { $0.path == orphanContainerDir.path }
        XCTAssertEqual(containerLeftover?.category, .caution)
        XCTAssertFalse(containerLeftover?.isSelected == true, "谨慎类默认不勾选")
    }

    // 2. 批量移入废纸篓 (trashItem) 安全执行测试
    func testTrashLeftoversExecution() async {
        let scanner = LeftoverScanner(
            homeDirectory: tempHome,
            systemLibraryDirectory: tempSystemLibrary,
            applicationsDirectories: [tempAppsDir]
        )

        let file1Path = tempHome.appendingPathComponent("Library/Caches/toBeTrashed1.dat").path
        let file2Path = tempHome.appendingPathComponent("Library/Caches/keepUntouched.dat").path
        FileManager.default.createFile(atPath: file1Path, contents: "trash me".data(using: .utf8))
        FileManager.default.createFile(atPath: file2Path, contents: "keep me".data(using: .utf8))

        let item1 = LeftoverItem(
            path: file1Path,
            name: "toBeTrashed1.dat",
            inferredAppName: "Tool1",
            category: .safe,
            sizeInBytes: 100,
            isSelected: true
        )
        let item2 = LeftoverItem(
            path: file2Path,
            name: "keepUntouched.dat",
            inferredAppName: "Tool2",
            category: .caution,
            sizeInBytes: 200,
            isSelected: false
        )

        let result = await scanner.trashLeftovers([item1, item2])

        XCTAssertEqual(result.trashedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.trashedPaths, [file1Path])

        // item1 移入废纸篓后原路径已不存在
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1Path))
        // item2 未勾选，原路径仍存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: file2Path))
    }

    // 3. LeftoverMatcher 双向 Token 与段前缀匹配测试 (fixture 1)
    func testLeftoverMatcherTokenAndPrefixMatching() {
        // 1) 候选名 Token 化：过滤停用词与短字符
        let tokens = LeftoverMatcher.tokenize("com.example.super-tool_helper.plist")
        XCTAssertTrue(tokens.contains("example"))
        XCTAssertTrue(tokens.contains("super"))
        XCTAssertTrue(tokens.contains("tool"))
        XCTAssertFalse(tokens.contains("com")) // 停用词
        XCTAssertFalse(tokens.contains("helper")) // 停用词

        // 2) 双向 Token 匹配
        let installedTokens: Set<String> = ["wechat", "slack", "postman"]
        XCTAssertTrue(LeftoverMatcher.hasTokenMatch(candidate: "com.tencent.xin.wechat", targetTokens: installedTokens))
        XCTAssertFalse(LeftoverMatcher.hasTokenMatch(candidate: "com.deleted.randomapp", targetTokens: installedTokens))

        // 3) Bundle ID 按段前缀匹配
        XCTAssertTrue(LeftoverMatcher.matchesBundleIdPrefix(
            candidate: "com.microsoft.teams.helper",
            installedBundleId: "com.microsoft.teams"
        ))
        XCTAssertTrue(LeftoverMatcher.matchesBundleIdPrefix(
            candidate: "com.microsoft.teams",
            installedBundleId: "com.microsoft.teams.alert"
        ))
        XCTAssertFalse(LeftoverMatcher.matchesBundleIdPrefix(
            candidate: "com.apple.safari",
            installedBundleId: "com.microsoft.teams"
        ))

        // 4) 互为子串（长度 >= 4）
        XCTAssertTrue(LeftoverMatcher.hasSubstringMatch(candidate: "wechat-cache-dir", installedName: "WeChat"))
        XCTAssertTrue(LeftoverMatcher.hasSubstringMatch(candidate: "PostmanApp", installedName: "Postman"))
        XCTAssertFalse(LeftoverMatcher.hasSubstringMatch(candidate: "xyz", installedName: "xyz")) // 长度 < 4
    }

    // 4. LeftoverMatcher 保守评估与置信度分级测试 (fixture 2)
    func testLeftoverMatcherConfidenceEvaluation() {
        // 1) 明确反向域名且在安全类目录 -> .confirmed
        let safeEval = LeftoverMatcher.evaluateConfidence(candidateName: "com.deleted.tool", category: .safe)
        XCTAssertEqual(safeEval.confidence, .confirmed)

        // 2) 明确反向域名但在谨慎类目录 -> .suspected（默认不勾选，防误删配置）
        let cautionEval = LeftoverMatcher.evaluateConfidence(candidateName: "com.deleted.tool.plist", category: .caution)
        XCTAssertEqual(cautionEval.confidence, .suspected)

        // 3) 弱线索/单一名词在谨慎类目录 -> .toConfirm
        let toConfirmEval = LeftoverMatcher.evaluateConfidence(candidateName: "OldHelper", category: .caution)
        XCTAssertEqual(toConfirmEval.confidence, .toConfirm)

        // 4) 综合匹配已装应用（应被判定为已装，排除在残留外）
        let installedBundleIds: Set<String> = ["com.apple.dt.xcode", "com.google.chrome"]
        let installedNames: Set<String> = ["Xcode", "Google Chrome"]
        let allTokens: Set<String> = ["xcode", "google", "chrome"]

        // 命中已装应用的 helper
        XCTAssertTrue(LeftoverMatcher.matchesInstalledApp(
            candidate: "com.google.chrome.framework",
            installedBundleIds: installedBundleIds,
            installedNames: installedNames,
            installedTokens: allTokens
        ))

        // 真正孤儿不匹配已装应用
        XCTAssertFalse(LeftoverMatcher.matchesInstalledApp(
            candidate: "com.unknown.oldtool",
            installedBundleIds: installedBundleIds,
            installedNames: installedNames,
            installedTokens: allTokens
        ))
    }

    // 5. 残留删除安全边界与符号链接拦截测试 (任务 D / P1-1)
    func testTrashLeftoversSymlinkAndBoundarySafety() async throws {
        let scanner = LeftoverScanner(
            homeDirectory: tempHome,
            systemLibraryDirectory: tempSystemLibrary,
            applicationsDirectories: [tempAppsDir]
        )

        // 1) 符号链接测试：指向外部敏感文件的符号链接绝不允许删除
        let externalTarget = tempDir.appendingPathComponent("do_not_delete.txt").path
        FileManager.default.createFile(atPath: externalTarget, contents: "important".data(using: .utf8))

        let symlinkCache = tempHome.appendingPathComponent("Library/Caches/symlink_cache.dat").path
        try FileManager.default.createSymbolicLink(atPath: symlinkCache, withDestinationPath: externalTarget)

        // 2) 越界路径测试：伪造的 LeftoverItem 路径位于受保护的 /System 目录
        let outOfBoundItem = LeftoverItem(
            path: "/System/Library/SomeApp",
            name: "SomeApp",
            inferredAppName: "SomeApp",
            category: .safe,
            sizeInBytes: 100,
            isSelected: true
        )

        let symlinkItem = LeftoverItem(
            path: symlinkCache,
            name: "symlink_cache.dat",
            inferredAppName: "SymlinkTool",
            category: .safe,
            sizeInBytes: 100,
            isSelected: true
        )

        let result = await scanner.trashLeftovers([symlinkItem, outOfBoundItem])

        XCTAssertEqual(result.trashedCount, 0, "符号链接和越界路径均不得被删除")
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertTrue(result.errors.keys.contains(symlinkCache))
        XCTAssertTrue(result.errors.keys.contains("/System/Library/SomeApp"))

        // 目标文件和链接本身未被破坏
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkCache))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalTarget))
    }
}

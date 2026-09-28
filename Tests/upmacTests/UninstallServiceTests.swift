import XCTest
@testable import upmac

final class UninstallServiceTests: XCTestCase {

    var tempDir: URL!
    var tempHome: URL!
    var tempSystemLibrary: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        tempHome = tempDir.appendingPathComponent("Users/testuser")
        tempSystemLibrary = tempDir.appendingPathComponent("Library")

        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Preferences"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Saved Application State"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Containers"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/Logs"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempHome.appendingPathComponent("Library/LaunchAgents"), withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempSystemLibrary.appendingPathComponent("LaunchDaemons"), withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    // 1. Apple 自家应用（com.apple. 或 /System 路径）安全红线拒绝卸载
    func testAppleSystemAppRejection() async {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        // Case 1: com.apple. 前缀
        let safari = InventoryItem(
            id: "safari",
            name: "Safari",
            version: "17.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "系统内置",
            status: .unmanaged,
            bundleId: "com.apple.Safari",
            path: "/Applications/Safari.app"
        )
        let safariPlan = service.generatePlan(for: safari)
        XCTAssertTrue(safariPlan.isAppleProtected)
        XCTAssertNotNil(safariPlan.warningMessage)

        do {
            _ = try await service.executePlan(safariPlan)
            XCTFail("Should throw appleSystemAppProtected error")
        } catch let error as UninstallError {
            if case .appleSystemAppProtected(let name, let bid) = error {
                XCTAssertEqual(name, "Safari")
                XCTAssertEqual(bid, "com.apple.Safari")
            } else {
                XCTFail("Wrong error thrown: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Case 2: /System/Applications/Notes.app
        let notes = InventoryItem(
            id: "notes",
            name: "Notes",
            version: "1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "系统内置",
            status: .unmanaged,
            bundleId: "com.apple.Notes",
            path: "/System/Applications/Notes.app"
        )
        let notesPlan = service.generatePlan(for: notes)
        XCTAssertTrue(notesPlan.isAppleProtected)
    }

    // 2. 路径规则命中测试（Preferences/AppSupport/Caches/Containers/Logs）
    func testScatteredFilesRuleMatching() {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        let bundleId = "com.sample.editor"
        let name = "SampleEditor"

        // 构造虚拟应用本体
        let appPath = tempDir.appendingPathComponent("SampleEditor.app").path
        FileManager.default.createFile(atPath: appPath, contents: "dummy binary".data(using: .utf8))

        // 构造命中文件
        let prefPath = tempHome.appendingPathComponent("Library/Preferences/\(bundleId).plist").path
        FileManager.default.createFile(atPath: prefPath, contents: "pref".data(using: .utf8))

        let supportDir = tempHome.appendingPathComponent("Library/Application Support/\(name)")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: supportDir.appendingPathComponent("data.db").path, contents: "db data".data(using: .utf8))

        let cacheDir = tempHome.appendingPathComponent("Library/Caches/\(bundleId)")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: cacheDir.appendingPathComponent("cache.tmp").path, contents: "temp".data(using: .utf8))

        let savedStateDir = tempHome.appendingPathComponent("Library/Saved Application State/\(bundleId).savedState")
        try? FileManager.default.createDirectory(at: savedStateDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: savedStateDir.appendingPathComponent("window.state").path, contents: "state".data(using: .utf8))

        let containerDir = tempHome.appendingPathComponent("Library/Containers/\(bundleId)")
        try? FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)

        let logDir = tempHome.appendingPathComponent("Library/Logs/\(name)")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logDir.appendingPathComponent("editor.log").path, contents: "logs".data(using: .utf8))

        let agentPath = tempHome.appendingPathComponent("Library/LaunchAgents/\(bundleId).helper.plist").path
        FileManager.default.createFile(atPath: agentPath, contents: "agent".data(using: .utf8))

        let item = InventoryItem(
            id: "sample_editor",
            name: name,
            version: "2.1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动安装",
            status: .unmanaged,
            bundleId: bundleId,
            path: appPath
        )

        let plan = service.generatePlan(for: item)
        XCTAssertFalse(plan.isAppleProtected)
        XCTAssertTrue(plan.hasScatteredFiles)

        let matchedPaths = Set(plan.files.map { $0.path })
        XCTAssertTrue(matchedPaths.contains(appPath))
        XCTAssertTrue(matchedPaths.contains(prefPath))
        XCTAssertTrue(matchedPaths.contains(supportDir.path))
        XCTAssertTrue(matchedPaths.contains(cacheDir.path))
        XCTAssertTrue(matchedPaths.contains(savedStateDir.path))
        XCTAssertTrue(matchedPaths.contains(containerDir.path))
        XCTAssertTrue(matchedPaths.contains(logDir.path))
        XCTAssertTrue(matchedPaths.contains(agentPath))

        // 验证分类属性
        let prefItem = plan.files.first { $0.path == prefPath }
        XCTAssertEqual(prefItem?.category, .preferences)

        let cacheItem = plan.files.first { $0.path == cacheDir.path }
        XCTAssertEqual(cacheItem?.category, .caches)

        let appItem = plan.files.first { $0.path == appPath }
        XCTAssertEqual(appItem?.category, .app)
    }

    // 3. 空散落文件测试（无散落文件命中，hasScatteredFiles == false）
    func testEmptyScatteredFiles() {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        let appPath = tempDir.appendingPathComponent("CleanApp.app").path
        FileManager.default.createFile(atPath: appPath, contents: "clean app".data(using: .utf8))

        let item = InventoryItem(
            id: "clean_app",
            name: "CleanApp",
            version: "1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动安装",
            status: .unmanaged,
            bundleId: "com.example.cleanapp",
            path: appPath
        )

        let plan = service.generatePlan(for: item)
        XCTAssertFalse(plan.isAppleProtected)
        XCTAssertFalse(plan.hasScatteredFiles)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.files.first?.category, .app)
        XCTAssertEqual(plan.files.first?.path, appPath)
    }

    // 4. 正规卸载命令映射测试（参数化，杜绝空格拆分错误）
    func testResolveUninstallMethod() {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        // 1) brew cask
        let cask = InventoryItem(
            id: "iterm2",
            name: "iterm2",
            version: "3.5.0",
            kind: .app,
            sourceId: "brew",
            sourceDisplayName: "Homebrew Cask",
            status: .managed
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: cask),
            .packageManager(executable: "brew", arguments: ["uninstall", "--cask", "iterm2"], provider: "Homebrew Cask")
        )

        // 2) brew formula
        let formula = InventoryItem(
            id: "wget",
            name: "wget",
            version: "1.24",
            kind: .cli,
            sourceId: "brew",
            sourceDisplayName: "Homebrew",
            status: .managed
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: formula),
            .packageManager(executable: "brew", arguments: ["uninstall", "wget"], provider: "Homebrew")
        )

        // 3) npm
        let npm = InventoryItem(
            id: "pnpm",
            name: "pnpm",
            version: "9.0",
            kind: .cli,
            sourceId: "npm",
            sourceDisplayName: "npm",
            status: .managed
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: npm),
            .packageManager(executable: "npm", arguments: ["uninstall", "-g", "pnpm"], provider: "npm")
        )

        // 4) gem
        let gem = InventoryItem(
            id: "cocoapods",
            name: "cocoapods",
            version: "1.15.0",
            kind: .cli,
            sourceId: "gem",
            sourceDisplayName: "RubyGems",
            status: .managed
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: gem),
            .packageManager(executable: "gem", arguments: ["uninstall", "cocoapods"], provider: "gem")
        )

        // 5) uv
        let uv = InventoryItem(
            id: "ruff",
            name: "ruff",
            version: "0.5.0",
            kind: .cli,
            sourceId: "uv",
            sourceDisplayName: "uv",
            status: .managed
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: uv),
            .packageManager(executable: "uv", arguments: ["tool", "uninstall", "ruff"], provider: "uv")
        )

        // 6) 独立应用 / apps
        let app = InventoryItem(
            id: "typora",
            name: "Typora",
            version: "1.8.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动安装",
            status: .unmanaged,
            path: "/Applications/Typora.app"
        )
        XCTAssertEqual(
            service.resolveUninstallMethod(for: app),
            .fileTrash(appPath: "/Applications/Typora.app")
        )

        // 7) 包含空格的包管理器项（P0-4：参数不被空格误拆分）
        let chromeCask = InventoryItem(
            id: "google-chrome",
            name: "Google Chrome",
            version: "128.0",
            kind: .app,
            sourceId: "brew",
            sourceDisplayName: "Homebrew Cask",
            status: .managed
        )
        let resolvedChrome = service.resolveUninstallMethod(for: chromeCask)
        XCTAssertEqual(
            resolvedChrome,
            .packageManager(executable: "brew", arguments: ["uninstall", "--cask", "Google Chrome"], provider: "Homebrew Cask")
        )
        XCTAssertEqual(resolvedChrome.displayCommand, "brew uninstall --cask \"Google Chrome\"")
    }

    // 5. 移入废纸篓 (trashItem) 真实执行测试
    func testTrashItemExecution() async throws {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        let targetFile = tempDir.appendingPathComponent("ToTrash.app").path
        FileManager.default.createFile(atPath: targetFile, contents: "to be trashed".data(using: .utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile))

        let item = InventoryItem(
            id: "totrash",
            name: "ToTrash",
            version: "1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动安装",
            status: .unmanaged,
            bundleId: "com.example.totrash",
            path: targetFile
        )

        let plan = service.generatePlan(for: item)
        let result = try await service.executePlan(plan)

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.trashedPaths, [targetFile])
        // 原路径应已不存在（已被移入废纸篓）
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile))
    }

    // 6. 任务 C：LaunchAgents 严格匹配（P1-4：短名如 git 不匹配他人 gitlab-backup.plist）
    func testLaunchAgentsStrictMatching() {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        let gitlabPlist = tempHome.appendingPathComponent("Library/LaunchAgents/com.example.gitlab-backup.plist").path
        let gitDaemonPlist = tempHome.appendingPathComponent("Library/LaunchAgents/org.git-scm.git.plist").path
        FileManager.default.createFile(atPath: gitlabPlist, contents: "plist".data(using: .utf8))
        FileManager.default.createFile(atPath: gitDaemonPlist, contents: "plist".data(using: .utf8))

        let gitItem = InventoryItem(
            id: "git",
            name: "git",
            version: "2.40",
            kind: .cli,
            sourceId: "brew",
            sourceDisplayName: "Homebrew",
            status: .managed,
            bundleId: nil,
            path: nil
        )

        let files = service.scanScatteredFiles(for: gitItem)
        let matchedPaths = Set(files.map { $0.path })

        // 核心断言：git 绝不能误匹配 gitlab-backup
        XCTAssertFalse(matchedPaths.contains(gitlabPlist), "短名应用 git 绝不能匹配 gitlab-backup.plist")
        // 允许匹配 git 自身的守护项
        XCTAssertTrue(matchedPaths.contains(gitDaemonPlist))
    }

    // 7. 任务 D：删除前 symlink 拦截与越界路径校验（P1-1）
    func testDeletionSafetySymlinkAndPathBoundary() async throws {
        let service = UninstallService(homeDirectory: tempHome, systemLibraryDirectory: tempSystemLibrary)

        // 构造合法文件与指向外部敏感文件的符号链接
        let validPref = tempHome.appendingPathComponent("Library/Preferences/com.test.app.plist").path
        FileManager.default.createFile(atPath: validPref, contents: "pref".data(using: .utf8))

        let externalTarget = tempDir.appendingPathComponent("external_file.txt").path
        FileManager.default.createFile(atPath: externalTarget, contents: "sensitive".data(using: .utf8))

        let symlinkPref = tempHome.appendingPathComponent("Library/Preferences/com.test.symlink.plist").path
        try FileManager.default.createSymbolicLink(atPath: symlinkPref, withDestinationPath: externalTarget)

        let item = InventoryItem(
            id: "test_app",
            name: "TestApp",
            version: "1.0",
            kind: .app,
            sourceId: "apps",
            sourceDisplayName: "手动",
            status: .unmanaged
        )

        let files = [
            ScatteredFileItem(path: validPref, name: "com.test.app.plist", category: .preferences, sizeInBytes: 10, isSelected: true),
            ScatteredFileItem(path: symlinkPref, name: "com.test.symlink.plist", category: .preferences, sizeInBytes: 10, isSelected: true)
        ]

        let plan = UninstallPlan(
            targetItem: item,
            method: .fileTrash(appPath: nil),
            appPath: nil,
            appSizeInBytes: 0,
            files: files
        )

        let result = try await service.executePlan(plan)

        // 验证：合法文件成功进入废纸篓
        XCTAssertTrue(result.trashedPaths.contains(validPref))
        // 验证：符号链接被拦截并记入 failedPaths，链接本身和目标文件均未被删除
        XCTAssertTrue(result.failedPaths.keys.contains(symlinkPref))
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(FileManager.default.fileExists(atPath: symlinkPref))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalTarget))
    }
}

import Foundation

/// 卸载与清理规划服务（实现正规卸载、规则库残留扫描与严格废纸篓安全红线）
public final class UninstallService: Sendable {
    public static let shared = UninstallService()

    private let homeDirectory: URL
    private let systemLibraryDirectory: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibraryDirectory: URL = URL(fileURLWithPath: "/Library")
    ) {
        self.homeDirectory = homeDirectory
        self.systemLibraryDirectory = systemLibraryDirectory
    }

    // MARK: - 1. 生成清理计划 (UninstallPlan)

    /// 针对指定应用或包生成清理计划
    public func generatePlan(for item: InventoryItem) -> UninstallPlan {
        // 安全红线检查：苹果自家应用（com.apple. 或 /System 路径）绝对禁止卸载
        let isAppleProtected = checkAppleSystemAppProtection(item)
        if isAppleProtected {
            return UninstallPlan(
                targetItem: item,
                method: .fileTrash(appPath: item.path),
                appPath: item.path,
                appSizeInBytes: 0,
                files: [],
                isAppleProtected: true,
                warningMessage: "系统保护：\(item.name) 为 Apple 核心系统组件，禁止卸载。"
            )
        }

        // 判定卸载方式（受管项走对应包管理器命令，游离项走文件清理）
        let method = resolveUninstallMethod(for: item)

        var candidateFiles: [ScatteredFileItem] = []

        // 计算应用本体大小与加入列表
        var appSize: Int64 = 0
        if let path = item.path, FileManager.default.fileExists(atPath: path) {
            let appURL = URL(fileURLWithPath: path)
            appSize = calculateSize(at: appURL)
            candidateFiles.append(
                ScatteredFileItem(
                    path: path,
                    name: (path as NSString).lastPathComponent,
                    category: .app,
                    sizeInBytes: appSize,
                    isSelected: true
                )
            )
        }

        // 仅当为应用或有 bundleId/名称时，扫描散落文件
        let scattered = scanScatteredFiles(for: item)
        candidateFiles.append(contentsOf: scattered)

        return UninstallPlan(
            targetItem: item,
            method: method,
            appPath: item.path,
            appSizeInBytes: appSize,
            files: candidateFiles,
            isAppleProtected: false,
            warningMessage: nil
        )
    }

    // MARK: - 2. 执行清理计划 (Execute Plan)

    /// 执行清理计划（严格遵循：受管走命令且失败绝不删文件；独立应用删除一律 trashItem）
    public func executePlan(_ plan: UninstallPlan) async throws -> UninstallResult {
        // 安全红线 1：拦截苹果系统应用
        if plan.isAppleProtected {
            throw UninstallError.appleSystemAppProtected(
                name: plan.targetItem.name,
                bundleId: plan.targetItem.bundleId
            )
        }

        // 安全红线 2：必须有勾选项
        let selectedFiles = plan.files.filter { $0.isSelected }
        guard !selectedFiles.isEmpty || (ifCasePackageManager(plan.method)) else {
            throw UninstallError.nothingSelected
        }

        switch plan.method {
        case .packageManager(let executable, let args, let provider):
            // 受管项：调用包管理器二进制执行卸载
            let toolBinary: String?
            switch executable.lowercased() {
            case "brew", "homebrew":
                toolBinary = ToolPaths.brew()
            case "npm":
                toolBinary = ToolPaths.npm()
            case "gem":
                toolBinary = ToolPaths.gem()
            case "uv":
                toolBinary = ToolPaths.uv()
            default:
                toolBinary = ToolPaths.resolveCandidate([executable])
            }

            guard let binary = toolBinary else {
                throw UninstallError.packageManagerMissing(provider)
            }

            // 直接调用 ShellRunner.run 传入参数数组，不再使用字符串 split
            let shellResult = try await ShellRunner.run(binary, arguments: args, timeout: 300)

            if shellResult.exitCode != 0 {
                // 安全红线 3：受管项包管理器命令失败，绝不 fallback 到文件删除
                let errText = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
                let summary = BrewProvider.extractTail(errText, maxLines: 5) ?? "Exit code \(shellResult.exitCode)"
                throw UninstallError.commandFailed(
                    command: plan.method.displayCommand,
                    exitCode: shellResult.exitCode,
                    stderr: summary
                )
            }

            // 包管理器命令成功后，若用户同时勾选了散落残留文件，经安全校验后将散落文件移入废纸篓
            var trashed: [String] = []
            var failed: [String: String] = [:]
            for file in selectedFiles where file.category != .app {
                switch validateDeletionSafety(for: file, appPath: plan.appPath) {
                case .failure(let reason):
                    failed[file.path] = reason.localizedDescription
                case .success(let fileURL):
                    do {
                        // 安全红线 4：一切删除必须走 trashItem 移入废纸篓
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                        trashed.append(file.path)
                    } catch {
                        failed[file.path] = error.localizedDescription
                    }
                }
            }

            return UninstallResult(
                targetName: plan.targetItem.name,
                isSuccess: failed.isEmpty,
                trashedPaths: trashed,
                failedPaths: failed,
                message: "已通过 \(provider) 完成卸载" + (trashed.isEmpty ? "" : "，并清理了 \(trashed.count) 项散落文件"),
                totalFreedBytes: plan.totalSelectedSize
            )

        case .fileTrash:
            // 独立应用 / 无包管理器：文件级清理（本体 + 散落文件经安全校验后移入废纸篓）
            var trashed: [String] = []
            var failed: [String: String] = [:]
            var totalFreed: Int64 = 0

            for file in selectedFiles {
                switch validateDeletionSafety(for: file, appPath: plan.appPath) {
                case .failure(let reason):
                    failed[file.path] = reason.localizedDescription
                case .success(let fileURL):
                    do {
                        // 安全红线 4：一切删除必须走 trashItem 移入废纸篓，绝不 rm
                        try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
                        trashed.append(file.path)
                        totalFreed += file.sizeInBytes
                    } catch {
                        failed[file.path] = error.localizedDescription
                    }
                }
            }

            let isSuccess = failed.isEmpty
            return UninstallResult(
                targetName: plan.targetItem.name,
                isSuccess: isSuccess,
                trashedPaths: trashed,
                failedPaths: failed,
                message: isSuccess
                    ? "已成功将 \(trashed.count) 项文件移入废纸篓"
                    : "部分文件移入废纸篓失败（\(failed.count) 项）",
                totalFreedBytes: totalFreed
            )
        }
    }

    private func ifCasePackageManager(_ method: UninstallMethod) -> Bool {
        if case .packageManager = method { return true }
        return false
    }

    // MARK: - 3. 卸载渠道规则判定

    /// 解析来源对应的正规卸载命令（返回参数化元组，杜绝空格拆分导致的命令执行错误）
    public func resolveUninstallMethod(for item: InventoryItem) -> UninstallMethod {
        let providerId = item.sourceId.lowercased()
        let name = item.name

        switch providerId {
        case "brew", "homebrew":
            if item.kind == .app {
                // cask
                return .packageManager(executable: "brew", arguments: ["uninstall", "--cask", name], provider: "Homebrew Cask")
            } else {
                // formula
                return .packageManager(executable: "brew", arguments: ["uninstall", name], provider: "Homebrew")
            }

        case "npm":
            return .packageManager(executable: "npm", arguments: ["uninstall", "-g", name], provider: "npm")

        case "gem", "rubygems":
            return .packageManager(executable: "gem", arguments: ["uninstall", name], provider: "gem")

        case "uv":
            return .packageManager(executable: "uv", arguments: ["tool", "uninstall", name], provider: "uv")

        default:
            // 独立应用 / apps / 未受管 / mas 等
            return .fileTrash(appPath: item.path)
        }
    }

    // MARK: - 4. 散落文件规则库扫描

    /// 根据规则库扫描当前应用的散落文件
    public func scanScatteredFiles(for item: InventoryItem) -> [ScatteredFileItem] {
        var results: [ScatteredFileItem] = []
        let fm = FileManager.default
        let userLibrary = homeDirectory.appendingPathComponent("Library")

        let bundleId = item.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty || (bundleId != nil && !bundleId!.isEmpty) else {
            return []
        }

        // 辅助检测闭包
        func addIfExists(path: String, category: ScatteredFileCategory) {
            guard fm.fileExists(atPath: path) else { return }
            // 避免重复与自身本体相同
            if let appPath = item.path, appPath == path { return }
            if results.contains(where: { $0.path == path }) { return }

            let url = URL(fileURLWithPath: path)
            let size = calculateSize(at: url)
            results.append(
                ScatteredFileItem(
                    path: path,
                    name: (path as NSString).lastPathComponent,
                    category: category,
                    sizeInBytes: size,
                    isSelected: category.isSafeDefault || category == .preferences || category == .applicationSupport
                )
            )
        }

        // 1. Preferences: ~/Library/Preferences/<bundleid>.plist & <name>.plist
        let prefsDir = userLibrary.appendingPathComponent("Preferences")
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: prefsDir.appendingPathComponent("\(bid).plist").path, category: .preferences)
        }
        addIfExists(path: prefsDir.appendingPathComponent("\(name).plist").path, category: .preferences)

        // 2. Application Support: ~/Library/Application Support/<name> & <bundleid>
        let appSupportDir = userLibrary.appendingPathComponent("Application Support")
        addIfExists(path: appSupportDir.appendingPathComponent(name).path, category: .applicationSupport)
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: appSupportDir.appendingPathComponent(bid).path, category: .applicationSupport)
        }

        // 3. Caches: ~/Library/Caches/<bundleid> & <name>
        let cachesDir = userLibrary.appendingPathComponent("Caches")
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: cachesDir.appendingPathComponent(bid).path, category: .caches)
        }
        addIfExists(path: cachesDir.appendingPathComponent(name).path, category: .caches)

        // 4. Saved Application State: ~/Library/Saved Application State/<bundleid>.savedState
        let savedStateDir = userLibrary.appendingPathComponent("Saved Application State")
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: savedStateDir.appendingPathComponent("\(bid).savedState").path, category: .savedState)
        }

        // 5. Containers: ~/Library/Containers/<bundleid>
        let containersDir = userLibrary.appendingPathComponent("Containers")
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: containersDir.appendingPathComponent(bid).path, category: .containers)
        }

        // 6. Group Containers: ~/Library/Group Containers/*<bundleid>*
        let groupContainersDir = userLibrary.appendingPathComponent("Group Containers")
        if let bid = bundleId, !bid.isEmpty, fm.fileExists(atPath: groupContainersDir.path) {
            if let entries = try? fm.contentsOfDirectory(atPath: groupContainersDir.path) {
                for entry in entries where entry.localizedCaseInsensitiveContains(bid) {
                    addIfExists(path: groupContainersDir.appendingPathComponent(entry).path, category: .groupContainers)
                }
            }
        }

        // 7. Logs: ~/Library/Logs/<name> & <bundleid>
        let logsDir = userLibrary.appendingPathComponent("Logs")
        addIfExists(path: logsDir.appendingPathComponent(name).path, category: .logs)
        if let bid = bundleId, !bid.isEmpty {
            addIfExists(path: logsDir.appendingPathComponent(bid).path, category: .logs)
        }

        // 8. LaunchAgents: ~/Library/LaunchAgents/*<bundleid>*.plist & *<name>*.plist (严格双向 Token 匹配)
        let launchAgentsDir = userLibrary.appendingPathComponent("LaunchAgents")
        if fm.fileExists(atPath: launchAgentsDir.path) {
            if let entries = try? fm.contentsOfDirectory(atPath: launchAgentsDir.path) {
                for entry in entries where matchesLaunchPlist(entry: entry, bundleId: bundleId, name: name) {
                    addIfExists(path: launchAgentsDir.appendingPathComponent(entry).path, category: .launchAgents)
                }
            }
        }

        // 9. LaunchDaemons: /Library/LaunchDaemons/*<bundleid>*.plist & *<name>*.plist (严格双向 Token 匹配)
        let launchDaemonsDir = systemLibraryDirectory.appendingPathComponent("LaunchDaemons")
        if fm.fileExists(atPath: launchDaemonsDir.path) {
            if let entries = try? fm.contentsOfDirectory(atPath: launchDaemonsDir.path) {
                for entry in entries where matchesLaunchPlist(entry: entry, bundleId: bundleId, name: name) {
                    addIfExists(path: launchDaemonsDir.appendingPathComponent(entry).path, category: .launchDaemons)
                }
            }
        }

        results.sort { $0.path < $1.path }
        return results
    }

    /// 严格匹配 LaunchAgents / LaunchDaemons 的 plist 文件名（复用 LeftoverMatcher 的双向 Token 与段前缀匹配，防短名误判他人 plist）
    private func matchesLaunchPlist(entry: String, bundleId: String?, name: String) -> Bool {
        guard entry.hasSuffix(".plist") else { return false }
        let stem = String(entry.dropLast(6)) // 去掉 .plist 后缀
        let lowerStem = stem.lowercased()

        // 1. 若有 Bundle ID，检查精确相等或反向域名扩展 (如 com.sample.editor.helper)
        if let bid = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty {
            let lowerBid = bid.lowercased()
            if lowerStem == lowerBid || lowerStem.hasPrefix(lowerBid + ".") {
                return true
            }
            if LeftoverMatcher.matchesBundleIdPrefix(candidate: stem, installedBundleId: bid) {
                return true
            }
        }

        // 2. Token 双向匹配（要求与 bundleId 或 name 的 token 集合有实质性交集）
        var targetTokens = Set<String>()
        if let bid = bundleId, !bid.isEmpty {
            targetTokens.formUnion(LeftoverMatcher.tokenize(bid))
        }
        targetTokens.formUnion(LeftoverMatcher.tokenize(name))

        guard !targetTokens.isEmpty else { return false }

        let candTokens = Set(LeftoverMatcher.tokenize(stem))
        let commonTokens = candTokens.intersection(targetTokens)

        // 必须有实质性交集（而非单纯子串包含）
        return !commonTokens.isEmpty
    }

    // MARK: - 5. 安全防护判定

    /// 检查是否为受系统保护的 Apple 核心应用
    public func checkAppleSystemAppProtection(_ item: InventoryItem) -> Bool {
        if let bid = item.bundleId, bid.hasPrefix("com.apple.") {
            return true
        }
        if let path = item.path {
            if path.hasPrefix("/System") {
                return true
            }
            if path.hasPrefix("/System/Applications") {
                return true
            }
        }
        let lowerName = item.name.lowercased()
        let protectedNames = ["finder", "safari", "system preferences", "system settings", "app store", "terminal", "console"]
        if protectedNames.contains(lowerName) {
            return true
        }
        return false
    }

    // MARK: - 6. 大小计算工具方法

    /// 递归计算文件或目录总大小
    public func calculateSize(at url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return 0
        }
        if !isDir.boolValue {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? Int64) ?? 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
               resourceValues.isRegularFile == true,
               let size = resourceValues.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - 7. 路径安全边界与符号链接校验

    /// 校验待删除路径安全性（防御符号链接劫持与越界路径穿越）
    private func validateDeletionSafety(
        for file: ScatteredFileItem,
        appPath: String?
    ) -> Result<URL, UninstallError> {
        let path = file.path
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            return .failure(.fileTrashFailed(path: path, reason: "文件不存在"))
        }

        // 1. 检查待删路径本身是否为符号链接（拒绝删除符号链接，防止外部目录劫持）
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let fileType = attrs[.type] as? FileAttributeType,
           fileType == .typeSymbolicLink {
            return .failure(.fileTrashFailed(path: path, reason: "安全防护：待删路径为符号链接，禁止删除链接本身"))
        }

        // 2. 规范化并解析 realpath
        let rawURL = URL(fileURLWithPath: path)
        let resolvedURL = rawURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedPath = resolvedURL.path

        // 3. 敏感系统根目录绝不允许删除
        // /var 与 /private 为 macOS 路径别名，真实路径常带此前缀，整段拉黑会误伤合法目标；
        // 越界风险由下方类别白名单兜底（白名单不含 /var 下的任意路径）。
        let forbiddenPrefixes = ["/System", "/usr", "/bin", "/sbin", "/etc", "/dev"]
        if resolvedPath == "/" || forbiddenPrefixes.contains(where: { resolvedPath == $0 || resolvedPath.hasPrefix($0 + "/") }) {
            return .failure(.fileTrashFailed(path: path, reason: "安全防护：命中系统敏感目录保护"))
        }

        // 4. 显式类别父目录白名单匹配
        let allowedParentURLs: [URL]
        switch file.category {
        case .preferences:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Preferences")]
        case .applicationSupport:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Application Support")]
        case .caches:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Caches")]
        case .savedState:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Saved Application State")]
        case .containers:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Containers")]
        case .groupContainers:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Group Containers")]
        case .logs:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/Logs")]
        case .launchAgents:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library/LaunchAgents")]
        case .launchDaemons:
            allowedParentURLs = [systemLibraryDirectory.appendingPathComponent("LaunchDaemons")]
        case .app:
            var appParents: [URL] = [
                URL(fileURLWithPath: "/Applications"),
                homeDirectory.appendingPathComponent("Applications"),
                URL(fileURLWithPath: "/Volumes")
            ]
            if let validAppPath = appPath, !validAppPath.isEmpty {
                let parentOfApp = URL(fileURLWithPath: validAppPath).deletingLastPathComponent()
                if parentOfApp.path != "/" {
                    appParents.append(parentOfApp)
                }
            }
            allowedParentURLs = appParents
        case .other:
            allowedParentURLs = [homeDirectory.appendingPathComponent("Library")]
        }

        var isWithinAllowed = false
        for parentURL in allowedParentURLs {
            let resolvedParent = parentURL.resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedPath.hasPrefix(resolvedParent + "/") {
                isWithinAllowed = true
                break
            }
        }

        guard isWithinAllowed else {
            return .failure(.fileTrashFailed(path: path, reason: "安全防护：不在类别「\(file.category.rawValue)」允许的父目录范围内"))
        }

        return .success(rawURL)
    }
}

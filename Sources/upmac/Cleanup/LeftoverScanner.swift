import Foundation

/// 孤儿残留扫描器（扫描已卸载软件在 Library 规则库遗留的孤儿配置、缓存与日志）
public final class LeftoverScanner: Sendable {
    public static let shared = LeftoverScanner()

    private let homeDirectory: URL
    private let systemLibraryDirectory: URL
    private let applicationsDirectories: [URL]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibraryDirectory: URL = URL(fileURLWithPath: "/Library"),
        applicationsDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Applications"))
        ]
    ) {
        self.homeDirectory = homeDirectory
        self.systemLibraryDirectory = systemLibraryDirectory
        self.applicationsDirectories = applicationsDirectories
    }

    // MARK: - 1. 扫描孤儿残留文件

    /// 扫描规则库路径，反查已装应用，产出孤儿残留清单
    public func scanLeftovers(installedItems: [InventoryItem]) async -> [LeftoverItem] {
        let fm = FileManager.default
        let userLibrary = homeDirectory.appendingPathComponent("Library")

        // 1. 汇总所有已安装应用的标识符与名称（全小写）
        var installedBundleIds = Set<String>()
        var installedNames = Set<String>()

        for item in installedItems {
            if let bid = item.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bid.isEmpty {
                installedBundleIds.insert(bid)
            }
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !name.isEmpty {
                installedNames.insert(name)
                // 去除 .app 后缀对比
                if name.hasSuffix(".app") {
                    installedNames.insert(String(name.dropLast(4)))
                }
            }
        }

        // 补全扫描应用程序目录中可能未入库的 app
        for appDir in applicationsDirectories where fm.fileExists(atPath: appDir.path) {
            if let entries = try? fm.contentsOfDirectory(atPath: appDir.path) {
                for entry in entries where entry.hasSuffix(".app") {
                    let appName = String(entry.dropLast(4)).lowercased()
                    installedNames.insert(appName)
                    let fullPath = appDir.appendingPathComponent(entry)
                    if let bundle = Bundle(url: fullPath), let bid = bundle.bundleIdentifier?.lowercased() {
                        installedBundleIds.insert(bid)
                    }
                }
            }
        }

        // 汇总已装应用的 Token 集合（用于双向匹配）
        var installedTokens = Set<String>()
        for bid in installedBundleIds {
            installedTokens.formUnion(LeftoverMatcher.tokenize(bid))
        }
        for name in installedNames {
            installedTokens.formUnion(LeftoverMatcher.tokenize(name))
        }

        var leftovers: [LeftoverItem] = []

        // 系统通用保留白名单，切勿标记为孤儿残留
        let systemIgnoreTokens: Set<String> = [
            ".ds_store", "crashreporter", "dock", "addressbook", "clouddocs",
            "quick look", "syncservices", "callhistorydb", "knowledge", "icloud",
            "accountsd", "mobilesync", "geoservices", "cloudkit", "familycircle",
            "diagnosticreports", "nsglobaldomain", "system", "apple", "safari"
        ]

        func isSystemOrInstalled(name: String) -> Bool {
            let lower = name.lowercased()
            if lower.hasPrefix(".") { return true }
            if lower.hasPrefix("com.apple.") { return true }
            if lower.hasPrefix("apple") { return true }
            for token in systemIgnoreTokens where lower.contains(token) {
                return true
            }

            // 借助 LeftoverMatcher 执行全套排除逻辑：精确匹配、段前缀、互为子串、双向 Token
            return LeftoverMatcher.matchesInstalledApp(
                candidate: name,
                installedBundleIds: installedBundleIds,
                installedNames: installedNames,
                installedTokens: installedTokens
            )
        }

        func inspectDirectory(
            _ dirURL: URL,
            category: LeftoverCategory,
            nameExtractor: (String) -> String?
        ) {
            guard fm.fileExists(atPath: dirURL.path) else { return }
            guard let entries = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return }

            for entry in entries {
                guard let candidateName = nameExtractor(entry) else { continue }
                if isSystemOrInstalled(name: candidateName) { continue }

                let fullURL = dirURL.appendingPathComponent(entry)
                let size = calculateSize(at: fullURL)
                // 忽略空文件/0字节项以防噪音
                guard size > 0 else { continue }

                let attrs = try? fm.attributesOfItem(atPath: fullURL.path)
                let modDate = attrs?[.modificationDate] as? Date

                let inferred = inferReadableAppName(from: candidateName)
                let (confidence, reason) = LeftoverMatcher.evaluateConfidence(
                    candidateName: candidateName,
                    category: category
                )

                leftovers.append(
                    LeftoverItem(
                        path: fullURL.path,
                        name: entry,
                        inferredAppName: inferred,
                        category: category,
                        sizeInBytes: size,
                        modificationDate: modDate,
                        confidence: confidence,
                        inferenceReason: reason
                    )
                )
            }
        }

        // 1. Caches (安全类)
        inspectDirectory(userLibrary.appendingPathComponent("Caches"), category: .safe) { entry in
            entry
        }

        // 2. Logs (安全类)
        inspectDirectory(userLibrary.appendingPathComponent("Logs"), category: .safe) { entry in
            entry
        }

        // 3. Saved Application State (安全类)
        inspectDirectory(userLibrary.appendingPathComponent("Saved Application State"), category: .safe) { entry in
            if entry.hasSuffix(".savedState") {
                return String(entry.dropLast(11))
            }
            return nil
        }

        // 4. Preferences (谨慎类)
        inspectDirectory(userLibrary.appendingPathComponent("Preferences"), category: .caution) { entry in
            if entry.hasSuffix(".plist") {
                return String(entry.dropLast(6))
            }
            return nil
        }

        // 5. Containers (谨慎类)
        inspectDirectory(userLibrary.appendingPathComponent("Containers"), category: .caution) { entry in
            entry
        }

        // 6. Application Support (谨慎类)
        inspectDirectory(userLibrary.appendingPathComponent("Application Support"), category: .caution) { entry in
            entry
        }

        // 7. LaunchAgents (谨慎类)
        inspectDirectory(userLibrary.appendingPathComponent("LaunchAgents"), category: .caution) { entry in
            if entry.hasSuffix(".plist") {
                return String(entry.dropLast(6))
            }
            return nil
        }

        // 按大小降序排列，方便用户优先审阅大文件
        leftovers.sort { $0.sizeInBytes > $1.sizeInBytes }
        return leftovers
    }

    // MARK: - 2. 批量移除残留（安全红线：严格 trashItem 与边界校验）

    /// 校验孤儿残留待删除路径安全性（防御符号链接劫持与越界路径穿越）
    private func validateLeftoverDeletionSafety(at path: String) -> Result<URL, UninstallError> {
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
        // 注意：/var 与 /private 是 macOS 的路径别名（/var 实为 /private/var，临时目录真实路径为
        // /private/var/folders/...），整段拉黑会误伤用户 ~/Library 之外的合法清理目标，
        // 因此仅拦截真正的系统目录，路径别名交由下方白名单裁决。
        let forbiddenPrefixes = ["/System", "/usr", "/bin", "/sbin", "/etc", "/dev"]
        if resolvedPath == "/" || forbiddenPrefixes.contains(where: { resolvedPath == $0 || resolvedPath.hasPrefix($0 + "/") }) {
            return .failure(.fileTrashFailed(path: path, reason: "安全防护：命中系统敏感目录保护"))
        }

        // 4. 显式父目录白名单匹配（必须在允许的 Library 规则库子目录下）
        let allowedParentURLs: [URL] = [
            homeDirectory.appendingPathComponent("Library/Caches"),
            homeDirectory.appendingPathComponent("Library/Logs"),
            homeDirectory.appendingPathComponent("Library/Saved Application State"),
            homeDirectory.appendingPathComponent("Library/Preferences"),
            homeDirectory.appendingPathComponent("Library/Containers"),
            homeDirectory.appendingPathComponent("Library/Application Support"),
            homeDirectory.appendingPathComponent("Library/LaunchAgents")
        ]

        var isWithinAllowed = false
        for parentURL in allowedParentURLs {
            let resolvedParent = parentURL.resolvingSymlinksInPath().standardizedFileURL.path
            if resolvedPath.hasPrefix(resolvedParent + "/") {
                isWithinAllowed = true
                break
            }
        }

        guard isWithinAllowed else {
            return .failure(.fileTrashFailed(path: path, reason: "安全防护：超出允许的残留清理目录范围"))
        }

        return .success(rawURL)
    }

    /// 将选中的残留项目移入废纸篓
    public func trashLeftovers(_ items: [LeftoverItem]) async -> LeftoverCleanupResult {
        let fm = FileManager.default
        var trashedPaths: [String] = []
        var failedErrors: [String: String] = [:]
        var totalFreed: Int64 = 0

        for item in items where item.isSelected {
            switch validateLeftoverDeletionSafety(at: item.path) {
            case .failure(let reason):
                failedErrors[item.path] = reason.localizedDescription
            case .success(let url):
                do {
                    // 安全红线：一切删除必须走 trashItem 移入废纸篓，绝不 rm
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    trashedPaths.append(item.path)
                    totalFreed += item.sizeInBytes
                } catch {
                    failedErrors[item.path] = error.localizedDescription
                }
            }
        }

        return LeftoverCleanupResult(
            trashedCount: trashedPaths.count,
            failedCount: failedErrors.count,
            totalFreedBytes: totalFreed,
            trashedPaths: trashedPaths,
            errors: failedErrors
        )
    }

    // MARK: - 3. 辅助方法

    /// 推测可读的所属应用名称
    public func inferReadableAppName(from rawIdentifier: String) -> String {
        let clean = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.contains(".") {
            let parts = clean.split(separator: ".")
            if let last = parts.last, last.count > 2 {
                return String(last).capitalized
            }
        }
        return clean.capitalized
    }

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
}

// MARK: - 孤儿残留匹配与置信度评估引擎
public enum LeftoverMatcher: Sendable {
    /// 通用网络与系统停用词（避免反向域名如 com/org/net/app 发生泛化交集误判）
    public static let stopTokens: Set<String> = [
        "com", "org", "net", "edu", "gov", "io", "app", "mac", "osx", "apple", "helper", "client", "daemon", "service"
    ]

    /// 候选名 token 化（按 -、_、. 拆分，token 长度≥3 参与匹配）
    public static func tokenize(_ name: String) -> [String] {
        let clean = name.lowercased()
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedstate", with: "")
        let delimiters = CharacterSet(charactersIn: "-_.")
        return clean.components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopTokens.contains($0) }
    }

    /// 双向 Token 匹配：候选名 token 与已装应用/bundle id token 列表是否存在交集
    public static func hasTokenMatch(candidate: String, targetTokens: Set<String>) -> Bool {
        let candTokens = tokenize(candidate)
        guard !candTokens.isEmpty, !targetTokens.isEmpty else { return false }
        for token in candTokens {
            if targetTokens.contains(token) {
                return true
            }
        }
        return false
    }

    /// Bundle ID 按段前缀匹配（如 com.example.* 对已装 bundleid 前缀，或反向包含）
    public static func matchesBundleIdPrefix(candidate: String, installedBundleId: String) -> Bool {
        let c = candidate.lowercased()
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedstate", with: "")
        let i = installedBundleId.lowercased()
        if c == i { return true }

        let cParts = c.split(separator: ".")
        let iParts = i.split(separator: ".")
        // 至少两段才构成域名空间结构
        guard cParts.count >= 2, iParts.count >= 2 else { return false }

        // 若前两段一致（例如 com.example 对 com.example.app）
        if cParts[0] == iParts[0] && cParts[1] == iParts[1] {
            if cParts.count >= 3 && iParts.count >= 3 {
                if cParts[2] == iParts[2] || cParts[2].hasPrefix(iParts[2]) || iParts[2].hasPrefix(cParts[2]) {
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }

    /// 应用名与候选名互为子串且长度≥4 也算命中
    public static func hasSubstringMatch(candidate: String, installedName: String) -> Bool {
        let c = candidate.lowercased()
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedstate", with: "")
        let i = installedName.lowercased()
        if c.count >= 4 && i.contains(c) { return true }
        if i.count >= 4 && c.contains(i) { return true }
        return false
    }

    /// 判断候选目录/文件是否属于已安装应用（如果是，则不是孤儿残留，必须排除）
    public static func matchesInstalledApp(
        candidate: String,
        installedBundleIds: Set<String>,
        installedNames: Set<String>,
        installedTokens: Set<String>
    ) -> Bool {
        let c = candidate.lowercased()
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedstate", with: "")

        // 1. 完全相同
        if installedBundleIds.contains(c) || installedNames.contains(c) {
            return true
        }

        // 2. 段前缀匹配（如 com.example.* 对已装 bundleid 前缀）
        for bid in installedBundleIds {
            if matchesBundleIdPrefix(candidate: c, installedBundleId: bid) {
                return true
            }
        }

        // 3. 应用名与候选名互为子串且长度≥4
        for name in installedNames {
            if hasSubstringMatch(candidate: c, installedName: name) {
                return true
            }
        }

        // 4. 双向 Token 匹配（按 -、_、. 拆分，token 长度≥3 参与匹配）
        if hasTokenMatch(candidate: c, targetTokens: installedTokens) {
            return true
        }

        return false
    }

    /// 置信度分级评估（宁缺毋滥）
    public static func evaluateConfidence(
        candidateName: String,
        category: LeftoverCategory
    ) -> (confidence: LeftoverConfidence, reason: String) {
        let clean = candidateName.lowercased()
            .replacingOccurrences(of: ".plist", with: "")
            .replacingOccurrences(of: ".savedstate", with: "")

        let parts = clean.split(separator: ".")
        let isReverseDomain = parts.count >= 3 && ["com", "org", "net", "io", "app", "dev", "co"].contains(parts[0])

        if category.isSafeDefault {
            // 安全类（Caches / Logs / Saved Application State）
            if isReverseDomain || clean.count >= 5 {
                return (.confirmed, "明确应用已卸载，日志与缓存为安全残留")
            } else {
                return (.toConfirm, "名称较短缺少完整包名标识，建议手动核实原路径")
            }
        } else {
            // 谨慎类（Preferences / Application Support / Containers / LaunchAgents）
            if isReverseDomain {
                return (.suspected, "已卸载应用配置与数据残留，清理将清除历史偏好，建议按需勾选")
            } else {
                return (.toConfirm, "名称非标准包名格式，推断为历史衍生配置，建议核对路径")
            }
        }
    }
}

import Foundation

/// 统一本地应用扫描服务
/// 负责扫描本地及外置卷中的 .app 软件，读取 Info.plist 元数据并提取 Sparkle 更新源
public enum AppScanService {

    /// state.json 默认路径
    public static var defaultStatePath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/upmac/state.json")
    }

    /// 解析需要扫描的根目录集合
    /// 包含：
    /// 1. /Applications
    /// 2. ~/Applications
    /// 3. /Volumes/*/Applications 中可写非根卷（过滤根卷别名如 /Volumes/Macintosh HD 及只读 DMG 卷）
    /// 4. state.json 中可选配置的 extraScanDirs
    public static func resolveSearchDirectories(
        volumesPath: String = "/Volumes",
        statePath: String? = nil,
        fileManager: FileManager = .default
    ) -> [String] {
        var dirs: [String] = []

        // 1. 系统主应用目录
        if fileManager.fileExists(atPath: "/Applications") {
            dirs.append("/Applications")
        }

        // 2. 用户主目录应用目录
        let userApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        if fileManager.fileExists(atPath: userApps) {
            dirs.append(userApps)
        }

        // 3. 扫描外置盘可写卷（/Volumes/*/Applications）
        if fileManager.fileExists(atPath: volumesPath) {
            if let entries = try? fileManager.contentsOfDirectory(atPath: volumesPath) {
                for entry in entries {
                    // 排除隐藏文件（如 .DS_Store, .timemachine）
                    if entry.hasPrefix(".") { continue }

                    let volPath = (volumesPath as NSString).appendingPathComponent(entry)

                    // 检查是否为根卷别名（如 /Volumes/Macintosh HD 归一后为 /）
                    if isRootVolumeAlias(path: volPath) {
                        continue
                    }

                    // 检查是否为只读卷（排除只读 DMG 等）
                    if isReadOnlyVolume(path: volPath, fileManager: fileManager) {
                        continue
                    }

                    // 检查卷是否可写
                    guard fileManager.isWritableFile(atPath: volPath) else {
                        continue
                    }

                    // 检查卷下是否存在 Applications 目录
                    let appDir = (volPath as NSString).appendingPathComponent("Applications")
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: appDir, isDirectory: &isDir), isDir.boolValue {
                        if !dirs.contains(appDir) {
                            dirs.append(appDir)
                        }
                    }
                }
            }
        }

        // 4. state.json 中额外指定的扫描目录
        let targetStatePath = statePath ?? defaultStatePath
        let extraDirs = loadExtraScanDirs(from: targetStatePath, fileManager: fileManager)
        for extra in extraDirs {
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: extra, isDirectory: &isDir), isDir.boolValue {
                if !dirs.contains(extra) {
                    dirs.append(extra)
                }
            }
        }

        return dirs
    }

    /// 扫描所有指定目录下的 .app 应用程序
    public static func scanInstalledApplications(
        directories: [String]? = nil,
        fileManager: FileManager = .default
    ) -> [ScannedApp] {
        let scanDirs = directories ?? resolveSearchDirectories(fileManager: fileManager)
        var apps: [ScannedApp] = []
        var seenPaths: Set<String> = []

        for dir in scanDirs {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else {
                continue
            }

            for item in contents {
                if item.hasPrefix(".") { continue }
                let itemPath = (dir as NSString).appendingPathComponent(item)

                if item.hasSuffix(".app") {
                    if seenPaths.insert(itemPath).inserted {
                        if let app = inspectAppBundle(at: itemPath, fileManager: fileManager) {
                            apps.append(app)
                        }
                    }
                } else {
                    // 仅探测一层子目录（如 /Applications/Utilities）
                    var isDir: ObjCBool = false
                    if fileManager.fileExists(atPath: itemPath, isDirectory: &isDir), isDir.boolValue {
                        if let subContents = try? fileManager.contentsOfDirectory(atPath: itemPath) {
                            for subItem in subContents {
                                if subItem.hasSuffix(".app") {
                                    let subPath = (itemPath as NSString).appendingPathComponent(subItem)
                                    if seenPaths.insert(subPath).inserted {
                                        if let app = inspectAppBundle(at: subPath, fileManager: fileManager) {
                                            apps.append(app)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 使用 PropertyListSerialization 严格解析 .app 的 Contents/Info.plist
    public static func inspectAppBundle(
        at path: String,
        fileManager: FileManager = .default
    ) -> ScannedApp? {
        let plistPath = (path as NSString).appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: plistPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            return nil
        }

        // 提取名称：优先 CFBundleDisplayName，其次 CFBundleName，最后降级为文件名
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent

        // 提取版本：优先 CFBundleShortVersionString，其次 CFBundleVersion
        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? "?"

        // 提取 Bundle ID
        let bundleId = plist["CFBundleIdentifier"] as? String

        // 提取 Sparkle Feed URL
        let feedURL = plist["SUFeedURL"] as? String

        // 检查 App Store 收据
        let receiptPath = (path as NSString).appendingPathComponent("Contents/_MASReceipt")
        let isAppStoreReceiptPresent = fileManager.fileExists(atPath: receiptPath)

        return ScannedApp(
            name: name,
            bundleId: bundleId,
            version: version,
            path: path,
            isAppStoreReceiptPresent: isAppStoreReceiptPresent,
            feedURL: feedURL
        )
    }

    // MARK: - 辅助判断与状态加载

    /// 判断路径是否为根卷别名（通过 realpath 或 symlink 归一后为 "/"）
    public static func isRootVolumeAlias(path: String) -> Bool {
        // POSIX realpath 解析
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &resolved) != nil {
            let canonical = String(cString: resolved)
            if canonical == "/" {
                return true
            }
        }

        // URL symlink 解析作为备选保险
        let url = URL(fileURLWithPath: path)
        let resolvedURL = url.resolvingSymlinksInPath()
        if resolvedURL.path == "/" {
            return true
        }

        return false
    }

    /// 判断卷是否为只读挂载（如只读 DMG 卷）
    public static func isReadOnlyVolume(path: String, fileManager: FileManager = .default) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]), values.volumeIsReadOnly == true {
            return true
        }
        // 如果无法写入，也视同只读
        if !fileManager.isWritableFile(atPath: path) {
            return true
        }
        return false
    }

    /// 校验 extraScanDir 路径安全性（拒绝包含 ".." 路径段、非绝对路径、敏感前缀及根目录）
    public static func isValidExtraScanDir(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let expanded = (trimmed as NSString).expandingTildeInPath

        // 1. 必须为绝对路径
        guard expanded.hasPrefix("/") else { return false }

        // 2. 拒绝包含 ".." 路径段
        let components = expanded.components(separatedBy: "/")
        if components.contains("..") { return false }

        // 3. 拒绝根目录 /
        if expanded == "/" { return false }

        // 4. 敏感前缀黑名单（拒绝系统及核心受限目录，保留正常的 /Applications、/Volumes/*、用户自定义目录）
        let sensitivePrefixes = [
            "/System",
            "/usr",
            "/bin",
            "/sbin",
            "/etc",
            "/var",
            "/private"
        ]
        for prefix in sensitivePrefixes {
            if expanded == prefix || expanded.hasPrefix(prefix + "/") {
                return false
            }
        }

        return true
    }

    /// 从 state.json 中安全读取 extraScanDirs 字段
    public static func loadExtraScanDirs(from statePath: String, fileManager: FileManager = .default) -> [String] {
        let json: [String: Any]
        if statePath == defaultStatePath {
            json = StateStore.read()
        } else {
            json = StateStore.read(at: statePath)
        }
        guard let extraDirs = json["extraScanDirs"] as? [String] else {
            return []
        }
        return extraDirs.compactMap { dir in
            let expanded = (dir as NSString).expandingTildeInPath
            guard isValidExtraScanDir(expanded) else { return nil }
            return expanded
        }
    }
}

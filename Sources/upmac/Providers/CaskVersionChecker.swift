import Foundation

// MARK: - Cask 匹配结果
public struct CaskMatch: Sendable, Equatable {
    public let latestVersion: String
    public let homepage: String?
    public let token: String
    public init(latestVersion: String, homepage: String?, token: String) {
        self.latestVersion = latestVersion
        self.homepage = homepage
        self.token = token
    }
}

// MARK: - Token 归一化与候选
public enum CaskToken {
    /// 单个 token 归一化：小写、空格/下划线转连字符、去 .app 后缀、压缩连字符、保留 alphanum-
    public static func normalize(_ appName: String) -> String {
        var name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去 .app 后缀（大小写不敏感）
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // 空格、下划线、点、加号等转连字符
        var tmp = ""
        for ch in name {
            if ch == " " || ch == "_" || ch == "." || ch == "+" {
                tmp.append("-")
            } else if ch.isLetter || ch.isNumber || ch == "-" {
                tmp.append(ch)
            } else {
                // 其他字符（如括号）丢弃，转连字符防粘连
                tmp.append("-")
            }
        }
        // 压缩连续连字符
        while tmp.contains("--") {
            tmp = tmp.replacingOccurrences(of: "--", with: "-")
        }
        tmp = tmp.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return tmp
    }

    /// 候选 token 列表：首选归一化 token；失败后再试去掉常见后缀词的变体
    public static func candidateTokens(for appName: String) -> [String] {
        let base = normalize(appName)
        guard !base.isEmpty else { return [] }
        var candidates: [String] = [base]
        // 常见后缀词（与 AppScanner 去重逻辑呼应）
        let suffixWords: Set<String> = ["app", "desktop", "browser", "client", "pro", "plus"]
        let parts = base.split(separator: "-").map(String.init)
        let filtered = parts.filter { !suffixWords.contains($0) }
        if filtered.count != parts.count && !filtered.isEmpty {
            let stripped = filtered.joined(separator: "-")
            if stripped != base && !stripped.isEmpty && !candidates.contains(stripped) {
                candidates.append(stripped)
            }
        }
        return candidates
    }

    /// 本地应用名归一化用于 artifacts 校验（大小写不敏感、去 .app）
    public static func normalizeAppName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
        return n.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Cask JSON 解析（纯函数，便于单测）
public enum CaskJSONParser {
    /// 解析 cask JSON，校验 artifacts 匹配后返回 CaskMatch
    /// - Parameters:
    ///   - data: cask/<token>.json 原始 data
    ///   - localAppName: 本地应用名（如 "Google Chrome"）
    ///   - token: 命中的 cask token（调用方传入，用于回填 CaskMatch.token）
    /// - Returns: 命中则 CaskMatch，否则 nil
    public static func parse(data: Data, localAppName: String, token: String? = nil) -> CaskMatch? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let versionRaw = json["version"] as? String, !versionRaw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let version = versionRaw.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? versionRaw
        if version.isEmpty { return nil }
        let homepage = json["homepage"] as? String
        // 优先使用 JSON 内的 token，否则使用调用方传入的 token
        let resolvedToken = (json["token"] as? String) ?? token ?? ""

        // artifacts 校验：无字段则保守不命中，防误报
        guard let artifacts = json["artifacts"] as? [[String: Any]] else { return nil }
        // artifacts 可能为空数组 -> 不命中
        if artifacts.isEmpty { return nil }
        let localNorm = CaskToken.normalizeAppName(localAppName)
        var matched = false
        for artifact in artifacts {
            if let apps = artifact["app"] as? [String] {
                for entry in apps {
                    if CaskToken.normalizeAppName(entry) == localNorm {
                        matched = true
                        break
                    }
                }
            }
            // 有的 cask 将 app 写作字符串而非数组（容错）
            if let appStr = artifact["app"] as? String {
                if CaskToken.normalizeAppName(appStr) == localNorm {
                    matched = true
                }
            }
            if matched { break }
        }
        if !matched { return nil }
        return CaskMatch(latestVersion: version, homepage: homepage, token: resolvedToken)
    }


}

// MARK: - Brew 受管 Cask 解析（纯函数）
public enum BrewCaskManagedParser {
    /// 解析 brew list --cask --json=v2 或 brew list --json --versions 输出
    /// 返回 (token集合, artifact app路径集合)，坏 JSON 保守返回空
    public static func parse(_ jsonString: String) -> (tokens: Set<String>, paths: Set<String>) {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else {
            return (Set<String>(), Set<String>())
        }
        var tokens = Set<String>()
        var paths = Set<String>()
        for c in casks {
            if let token = c["token"] as? String, !token.isEmpty {
                tokens.insert(token)
            } else if let name = c["name"] as? String, !name.isEmpty {
                tokens.insert(name)
            }
            // artifacts 可能在不同 brew 版本中以不同字段出现，尽力提取
            if let artifacts = c["artifacts"] as? [[String: Any]] {
                for art in artifacts {
                    if let apps = art["app"] as? [String] {
                        for a in apps { paths.insert("/Applications/" + a); paths.insert((NSHomeDirectory() as NSString).appendingPathComponent("Applications/" + a)) }
                    }
                    if let appStr = art["app"] as? String {
                        paths.insert("/Applications/" + appStr)
                    }
                }
            }
            // 兼容旧版：installed 字段包含路径？
            if let installed = c["installed"] as? [[String: Any]] {
                for inst in installed {
                    if let p = inst["path"] as? String { paths.insert(p) }
                }
            }
        }
        return (tokens, paths)
    }
}

// MARK: - 版本跨度校验（防 Telegram 等数据源怪癖误报，主版本差 ≥5 视为可疑）
public enum VersionSpanChecker {
    /// 判断是否疑似数据源差异（主版本差 ≥5 则跳过更新）
    public static func isSuspicious(current: String, latest: String) -> Bool {
        guard let c = extractMajor(current), let l = extractMajor(latest) else { return false }
        return abs(l - c) >= 5
    }

    private static func extractMajor(_ version: String) -> Int? {
        var s = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s = String(s.dropFirst()) }
        // 取第一个点前的组件
        let first = s.split(separator: ".").first.map(String.init) ?? s
        // 提取前导数字
        let digits = first.prefix(while: { $0.isNumber })
        return Int(digits)
    }
}

// MARK: - 缓存 Entry（含 token）
private struct CaskCacheEntry: Codable, Sendable {
    let latestVersion: String
    let homepage: String?
    let token: String
    let checkedAt: TimeInterval
}

// MARK: - 并发限流信号量（上限 6，渐进式后台）
private actor AsyncSemaphore {
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(_ count: Int) { self.count = count }
    func wait() async {
        if count > 0 { count -= 1; return }
        await withCheckedContinuation { c in waiters.append(c) }
    }
    func signal() {
        if !waiters.isEmpty {
            let w = waiters.removeFirst()
            w.resume()
        } else {
            count += 1
        }
    }
}

// MARK: - CaskVersionChecker（内存+state.json 12h 缓存、5s 超时、并发上限6）
public actor CaskVersionChecker {
    public static let shared = CaskVersionChecker()
    private let semaphore = AsyncSemaphore(6)
    private var memoryCache: [String: CaskCacheEntry] = [:]
    private var fileCacheLoaded = false
    private let cacheValidity: TimeInterval = 12 * 3600

    private init() {}

    // MARK: - 公开：为某应用获取 CaskMatch（命中才返回）
    public func fetch(for app: ScannedApp) async -> CaskMatch? {
        let key = app.path // key=app 路径（按任务要求）
        // 安全护栏 a：仅处理 /Applications 与 ~/Applications
        guard Self.isAllowedPath(app.path) else { return nil }
        // 1. 内存缓存 12h 内直接返回（token 为空视为未命中，需重新抓取以回填 token）
        if let entry = memoryCache[key], !entry.token.isEmpty, Date().timeIntervalSince1970 - entry.checkedAt < cacheValidity {
            return CaskMatch(latestVersion: entry.latestVersion, homepage: entry.homepage, token: entry.token)
        }
        // 2. 文件缓存懒加载
        if !fileCacheLoaded {
            loadFileCacheIntoMemory()
            fileCacheLoaded = true
            if let entry = memoryCache[key], !entry.token.isEmpty, Date().timeIntervalSince1970 - entry.checkedAt < cacheValidity {
                return CaskMatch(latestVersion: entry.latestVersion, homepage: entry.homepage, token: entry.token)
            }
        }
        // 3. 网络请求（限流 6）
        await semaphore.wait()
        // 双重检查：等待期间可能已被其他任务写入
        if let entry = memoryCache[key], !entry.token.isEmpty, Date().timeIntervalSince1970 - entry.checkedAt < cacheValidity {
            await semaphore.signal()
            return CaskMatch(latestVersion: entry.latestVersion, homepage: entry.homepage, token: entry.token)
        }
        let tokens = CaskToken.candidateTokens(for: app.name)
        var found: CaskMatch? = nil
        for token in tokens {
            if let match = await fetchToken(token, localAppName: app.name) {
                found = match
                break
            }
        }
        await semaphore.signal()
        if let match = found {
            let entry = CaskCacheEntry(latestVersion: match.latestVersion, homepage: match.homepage, token: match.token, checkedAt: Date().timeIntervalSince1970)
            memoryCache[key] = entry
            persistEntry(key: key, entry: entry)
            return match
        }
        return nil
    }

    // MARK: - Token 网络请求（5s 超时）
    private func fetchToken(_ token: String, localAppName: String) async -> CaskMatch? {
        guard !token.isEmpty else { return nil }
        guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(token).json") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("MacsoftX/1.0", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return CaskJSONParser.parse(data: data, localAppName: localAppName, token: token)
        } catch {
            return nil
        }
    }

    // MARK: - 安全护栏：路径校验（仅 /Applications 与 ~/Applications）
    public static func isAllowedPath(_ path: String) -> Bool {
        let standard = (path as NSString).standardizingPath
        if standard.hasPrefix("/Applications/") || standard == "/Applications" { return true }
        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
        let homeStandard = (homeApps as NSString).standardizingPath
        if standard.hasPrefix(homeStandard + "/") || standard == homeStandard { return true }
        return false
    }

    // MARK: - state.json 读写（key=caskCache）
    private func statePath() -> String {
        AppScanService.defaultStatePath
    }

    private func loadFileCacheIntoMemory() {
        let json = StateStore.read()
        guard let dict = json["caskCache"] as? [String: [String: Any]] else { return }
        for (k, v) in dict {
            guard let ver = v["latestVersion"] as? String,
                  let checked = v["checkedAt"] as? TimeInterval else { continue }
            let homepage = v["homepage"] as? String
            let token = v["token"] as? String ?? ""
            // 旧缓存无 token 视为过期，强制重新抓取以回填 token
            if token.isEmpty { continue }
            // 过期不导入内存（但保留文件，下次覆盖）
            if Date().timeIntervalSince1970 - checked < cacheValidity {
                memoryCache[k] = CaskCacheEntry(latestVersion: ver, homepage: homepage, token: token, checkedAt: checked)
            } else {
                // 仍可导入作为历史，避免重复写前丢失，但查询时已过期会重新请求；此处不导入以强制刷新
            }
        }
    }

    private func persistEntry(key: String, entry: CaskCacheEntry) {
        StateStore.update { root in
            var cache = root["caskCache"] as? [String: [String: Any]] ?? [:]
            var dict: [String: Any] = ["latestVersion": entry.latestVersion, "checkedAt": entry.checkedAt, "token": entry.token]
            if let hp = entry.homepage { dict["homepage"] = hp }
            cache[key] = dict
            root["caskCache"] = cache
        }
    }

    // 测试辅助：清空内存缓存
    public func clearMemoryCache() {
        memoryCache.removeAll()
        fileCacheLoaded = false
    }
}

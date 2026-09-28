import Foundation

public enum GemOutdatedParser {
    // 典型格式：「name (current < latest)」
    // 兼容可能的多版本或架构后缀，如「rake (13.0.6, 13.1.0 < 13.2.1)」或「ffi (1.16.3 arm64-darwin < 1.17.0)」
    private static let pattern = #"^([a-zA-Z0-9_\-]+)\s*\(([^<]+)<\s*([^)]+)\)"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [])
    }()

    /// 解析 gem outdated 输出文本
    /// - Parameter text: 命令 stdout 文本
    /// - Returns: UpdateItem 数组
    public static func parse(_ text: String) -> [UpdateItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [UpdateItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            guard let reg = regex,
                  let match = reg.firstMatch(in: line, options: [], range: fullRange),
                  match.numberOfRanges >= 4 else {
                continue
            }

            let nameRange = match.range(at: 1)
            let currentRange = match.range(at: 2)
            let latestRange = match.range(at: 3)

            guard nameRange.location != NSNotFound,
                  currentRange.location != NSNotFound,
                  latestRange.location != NSNotFound else {
                continue
            }

            let name = nsLine.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
            let rawCurrent = nsLine.substring(with: currentRange).trimmingCharacters(in: .whitespaces)
            let rawLatest = nsLine.substring(with: latestRange).trimmingCharacters(in: .whitespaces)

            // 若 current 包含多个版本逗号分隔，取其最高/最新已安装版本（即末尾一项）
            let currentVer: String
            if rawCurrent.contains(",") {
                let subParts = rawCurrent.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                currentVer = subParts.last ?? rawCurrent
            } else {
                // 若含架构后缀（如 "1.16.3 arm64-darwin"），取首个以空白分立的版本词
                currentVer = rawCurrent.components(separatedBy: .whitespaces).first ?? rawCurrent
            }

            let latestVer = rawLatest.components(separatedBy: .whitespaces).first ?? rawLatest

            items.append(UpdateItem(
                providerId: "gem",
                name: name,
                currentVersion: currentVer.isEmpty ? "?" : currentVer,
                latestVersion: latestVer.isEmpty ? nil : latestVer,
                kind: .cli,
                needsSudo: false,
                requiresLogin: false
            ))
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public enum GemDefaultParser {
    // 典型格式：「name (default: 3.1.3)」或「name (default: 2.6.3, 2.7.2)」
    private static let pattern = #"^([a-zA-Z0-9_\-]+)\s*\([^)]*default:\s*[^)]*\)"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [])
    }()

    /// 解析 gem list 输出文本，收集所有标记为 (default: ...) 的系统自带组件名称集合
    /// - Parameter text: 命令 stdout 文本
    /// - Returns: default gem 包名集合
    public static func parse(_ text: String) -> Set<String> {
        let lines = text.components(separatedBy: .newlines)
        var defaultNames = Set<String>()

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.contains("default:") else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            if let reg = regex,
               let match = reg.firstMatch(in: line, options: [], range: fullRange),
               match.numberOfRanges >= 2 {
                let nameRange = match.range(at: 1)
                if nameRange.location != NSNotFound {
                    let name = nsLine.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        defaultNames.insert(name)
                    }
                }
            }
        }

        return defaultNames
    }
}

public enum GemDetailsParser {
    // 纯函数：解析 gem list --details 输出，提取每个 gem 的 Installed at 路径
    // 支持两种行：「Installed at (default): /path」与「Installed at: /path」
    private static let headerPattern = #"^\s*([a-zA-Z0-9_\-\.]+)\s*\([^)]*\)\s*$"#
    private static let headerRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: headerPattern, options: [])
    }()

    /// 解析 gem list --details
    /// - Parameter text: gem list --details stdout
    /// - Returns: name -> installedPath 映射（缺失或无 Installed at 的 gem 不入表，调用方可保守保留）
    public static func parse(_ text: String) -> [String: String] {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return [:] }
        var map: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines)
        var currentName: String? = nil

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // 1. 优先检测 Installed at 行（需 currentName 已有）
            if line.contains("Installed at") {
                guard let name = currentName, map[name] == nil else { continue }
                guard let colonIdx = line.firstIndex(of: ":") else { continue }
                let after = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty {
                    map[name] = after
                }
                continue
            }

            // 2. 检测 gem 块头行：name (version...)
            // 跳过明显的非头行（如 Author/Homepage 等）
            if line.hasPrefix("***") { continue }
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let reg = headerRegex,
               let match = reg.firstMatch(in: line, options: [], range: fullRange),
               match.numberOfRanges >= 2 {
                let nameRange = match.range(at: 1)
                if nameRange.location != NSNotFound {
                    let name = nsLine.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        currentName = name
                    }
                }
            }
        }
        return map
    }
}

public final class GemProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "gem"
    public let displayName: String = "RubyGems"

    private let executableFinder: (@Sendable () async -> String?)?

    public init(executableFinder: (@Sendable () async -> String?)? = nil) {
        self.executableFinder = executableFinder
    }

    /// 定位 gem 二进制：优先 /usr/bin/gem，其次探测 brew/local/shell 路径
    public static func resolveGemPath() async -> String? {
        let candidates = [
            "/usr/bin/gem",
            "/opt/homebrew/bin/gem",
            "/usr/local/bin/gem",
            ("~/.local/bin/gem" as NSString).expandingTildeInPath
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        do {
            let res = try await ShellRunner.run("/bin/zsh", arguments: ["-lc", "command -v gem"], timeout: 5)
            if res.exitCode == 0 {
                let path = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}

        return nil
    }

    private func getExecutablePath() async -> String? {
        if let finder = executableFinder {
            return await finder()
        }
        return await Self.resolveGemPath()
    }

    public func isAvailable() async -> Bool {
        return await getExecutablePath() != nil
    }

    /// 标记 UpdateItem 中的系统自带组件（isSystemComponent）与需管理员提权（needsSudo）
    public func annotateItems(_ items: [UpdateItem], gemPath: String) async -> [UpdateItem] {
        var defaultGems = Set<String>()
        if let listResult = try? await ShellRunner.run(gemPath, arguments: ["list"], timeout: 30),
           listResult.exitCode == 0 {
            defaultGems = GemDefaultParser.parse(listResult.stdout)
        }

        let isGemDirWritable = FileManager.default.isWritableFile(atPath: "/Library/Ruby/Gems")

        return items.map { item in
            let isDefault = defaultGems.contains(item.name)
            return UpdateItem(
                providerId: item.providerId,
                name: item.name,
                currentVersion: item.currentVersion,
                latestVersion: item.latestVersion,
                kind: item.kind,
                needsSudo: !isDefault && !isGemDirWritable,
                requiresLogin: item.requiresLogin,
                externalId: item.externalId,
                isSystemComponent: isDefault
            )
        }
    }

    /// 一次性经 gem list --details 判定是否为系统 Ruby 路径，若是则剔除（单次调用，零并发）
    private func filterSystemRubyGems(_ items: [UpdateItem], gemPath: String) async -> [UpdateItem] {
        guard !items.isEmpty else { return items }
        guard let result = try? await ShellRunner.run(gemPath, arguments: ["list", "--details"], timeout: 30),
              result.exitCode == 0 else {
            // 解析失败或超时：保守保留
            return items
        }
        let pathMap = GemDetailsParser.parse(result.stdout)
        if pathMap.isEmpty {
            // 映射缺失：保守保留（由 (default:) 继续兜底）
            return items
        }
        return items.filter { item in
            guard let path = pathMap[item.name] else {
                // 映射缺失：保守保留
                return true
            }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("/Library/Ruby/") || trimmed.hasPrefix("/System/Library/") {
                return false
            }
            return true
        }
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        guard let gemPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("gem")
        }

        // 镜像加速：gem outdated 会逐个包请求 rubygems.org，国内直连常达 90s+。
        // 与 npm 同理，仅为本次只读扫描临时指定镜像，不改用户的 gem sources 配置。
        var args = ["outdated"]
        if let mirror = GemMirror.current {
            args = ["outdated", "--source", mirror]
        }
        let result = try await ShellRunner.run(gemPath, arguments: args, timeout: 90)
        guard result.exitCode == 0 else {
            // gem outdated 在无更新时返回 0；若发生错误返回非 0
            if let items = Optional(GemOutdatedParser.parse(result.stdout)), !items.isEmpty {
                let annotated = await annotateItems(items, gemPath: gemPath)
                return await filterSystemRubyGems(annotated, gemPath: gemPath)
            }
            let err = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ProviderError.parsingFailed("gem outdated 失败 (exit \(result.exitCode)): \(err.prefix(200))")
        }

        let parsed = GemOutdatedParser.parse(result.stdout)
        let annotated = await annotateItems(parsed, gemPath: gemPath)
        return await filterSystemRubyGems(annotated, gemPath: gemPath)
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        if item.isSystemComponent {
            return UpdateResult(ok: false, newVersion: nil, message: "macOS 自带组件，随系统更新")
        }

        guard let gemPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("gem")
        }

        // 更新命令：gem update <name>，超时 300s
        let shellResult: ShellRunner.ShellResult
        do {
            shellResult = try await ShellRunner.run(
                gemPath,
                arguments: ["update", item.name],
                timeout: 300
            )
        } catch let error as ProviderError {
            switch error {
            case .managerMissing, .timedOut:
                throw error
            default:
                return UpdateResult(ok: false, newVersion: nil, message: error.localizedDescription)
            }
        } catch {
            return UpdateResult(ok: false, newVersion: nil, message: error.localizedDescription)
        }

        let tailStderr = BrewProvider.extractTail(shellResult.stderr, maxLines: 5)
        if shellResult.exitCode == 0 {
            return UpdateResult(ok: true, newVersion: item.latestVersion, message: tailStderr)
        } else {
            let errorText = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
            let message = BrewProvider.extractTail(errorText, maxLines: 5) ?? "Exit code \(shellResult.exitCode)"
            return UpdateResult(ok: false, newVersion: nil, message: message)
        }
    }
}

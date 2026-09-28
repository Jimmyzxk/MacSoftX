import Foundation

public enum UvOutdatedParser {
    // 匹配 latest 括号标注，例如 "(latest: v0.5.1)" 或 "(latest: 0.5.1)"
    private static let latestPattern = #"\blatest:\s*v?([0-9a-zA-Z\.\-_]+)"#
    private static let latestRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: latestPattern, options: [.caseInsensitive])
    }()

    /// 解析 uv tool list 输出文本
    /// - Parameter text: 命令 stdout 文本
    /// - Returns: UpdateItem 数组
    public static func parse(_ text: String) -> [UpdateItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [UpdateItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // 过滤子项行（以 - 开头）与空行
            guard !line.isEmpty, !line.hasPrefix("-") else { continue }

            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let name = parts.first else { continue }

            var currentVersion = "?"
            if parts.count >= 2 {
                let verPart = parts[1]
                // 排除括号开头的非版本串
                if !verPart.hasPrefix("(") {
                    currentVersion = verPart.hasPrefix("v") ? String(verPart.dropFirst()) : verPart
                }
            }

            var latestVersion: String? = nil
            if let reg = latestRegex {
                let nsLine = line as NSString
                if let match = reg.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)),
                   match.numberOfRanges >= 2 {
                    let range = match.range(at: 1)
                    if range.location != NSNotFound {
                        latestVersion = nsLine.substring(with: range).trimmingCharacters(in: .whitespaces)
                    }
                }
            }

            items.append(UpdateItem(
                providerId: "uv",
                name: name,
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                kind: .cli,
                needsSudo: false,
                requiresLogin: false
            ))
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public final class UvProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "uv"
    public let displayName: String = "uv"

    private let executableFinder: (@Sendable () async -> String?)?

    public init(executableFinder: (@Sendable () async -> String?)? = nil) {
        self.executableFinder = executableFinder
    }

    /// 定位 uv 二进制：探测常见位置或 shell 查询
    public static func resolveUvPath() async -> String? {
        let candidates = [
            "/opt/homebrew/bin/uv",
            "/usr/local/bin/uv",
            ("~/.cargo/bin/uv" as NSString).expandingTildeInPath,
            ("~/.local/bin/uv" as NSString).expandingTildeInPath
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        do {
            let res = try await ShellRunner.run("/bin/zsh", arguments: ["-lc", "command -v uv"], timeout: 5)
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
        return await Self.resolveUvPath()
    }

    public func isAvailable() async -> Bool {
        return await getExecutablePath() != nil
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        guard let uvPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("uv")
        }

        // 优先使用 uv tool list --outdated（仅返回待更新项，避免 browser-use 误报）
        do {
            let outdatedResult = try await ShellRunner.run(uvPath, arguments: ["tool", "list", "--outdated"], timeout: 60)
            if outdatedResult.exitCode == 0 {
                let trimmed = outdatedResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    return []
                }
                return UvOutdatedParser.parse(outdatedResult.stdout)
            }
            // 非 0 视为不支持，落入回退
        } catch let error as ProviderError {
            // timedOut / managerMissing 直接抛出，其余回退
            if case .timedOut = error { throw error }
            if case .managerMissing = error { throw error }
        } catch {
            // 其它错误回退
        }

        // 回退：全量 list（老版本 uv 不支持 --outdated）
        let result = try await ShellRunner.run(uvPath, arguments: ["tool", "list"], timeout: 60)
        guard result.exitCode == 0 else {
            if let items = Optional(UvOutdatedParser.parse(result.stdout)), !items.isEmpty {
                return items
            }
            let err = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ProviderError.parsingFailed("uv tool list 失败 (exit \(result.exitCode)): \(err.prefix(200))")
        }

        return UvOutdatedParser.parse(result.stdout)
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        guard let uvPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("uv")
        }

        // 更新命令：uv tool upgrade <name>，超时 300s
        let shellResult: ShellRunner.ShellResult
        do {
            shellResult = try await ShellRunner.run(
                uvPath,
                arguments: ["tool", "upgrade", item.name],
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

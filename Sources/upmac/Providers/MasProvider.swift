import Foundation

public enum MasOutdatedParser {
    // 典型格式：「<id> <名称> (<已装版本>) (<可用版本>)」
    private static let standardPattern = #"^(\d+)\s+(.+?)\s+\((.+?)\)\s+\((.+?)\)$"#
    // 宽容处理：兼容结尾缺少右括号或版本号括号不全的非标格式
    private static let tolerantPattern = #"^(\d+)\s+(.+?)\s+\(([^)\n]+)\)?\s+\(([^)\n]+?)\)?\s*$"#

    private static let standardRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: standardPattern, options: [])
    }()

    private static let tolerantRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: tolerantPattern, options: [])
    }()

    /// 解析 mas outdated 输出文本
    /// - Parameters:
    ///   - text: 命令 stdout 输出
    ///   - requiresLogin: 是否标记为需要登录
    /// - Returns: UpdateItem 数组
    public static func parse(_ text: String, requiresLogin: Bool = false) -> [UpdateItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [UpdateItem] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)

            var matchedResult: NSTextCheckingResult?

            if let std = standardRegex, let match = std.firstMatch(in: line, options: [], range: fullRange) {
                matchedResult = match
            } else if let tol = tolerantRegex, let match = tol.firstMatch(in: line, options: [], range: fullRange) {
                matchedResult = match
            }

            guard let match = matchedResult, match.numberOfRanges >= 5 else {
                continue
            }

            let idRange = match.range(at: 1)
            let nameRange = match.range(at: 2)
            let currentVerRange = match.range(at: 3)
            let latestVerRange = match.range(at: 4)

            guard idRange.location != NSNotFound,
                  nameRange.location != NSNotFound,
                  currentVerRange.location != NSNotFound,
                  latestVerRange.location != NSNotFound else {
                continue
            }

            let id = nsLine.substring(with: idRange).trimmingCharacters(in: .whitespaces)
            let name = nsLine.substring(with: nameRange).trimmingCharacters(in: .whitespaces)
            let currentVersion = nsLine.substring(with: currentVerRange).trimmingCharacters(in: .whitespaces)
            let latestVersion = nsLine.substring(with: latestVerRange).trimmingCharacters(in: .whitespaces)

            items.append(UpdateItem(
                providerId: "mas",
                name: name,
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                kind: .mas,
                needsSudo: false,
                requiresLogin: requiresLogin,
                externalId: id
            ))
        }

        return items
    }
}

public final class MasProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "mas"
    public let displayName: String = "Mac App Store"
    private let executableFinder: () -> String?
    private static let masEnvironment: [String: String] = ["MAS_NO_AUTO_INDEX": "1"]

    public init(executableFinder: @escaping () -> String? = BrewPaths.masPath) {
        self.executableFinder = executableFinder
    }

    public func isAvailable() async -> Bool {
        return executableFinder() != nil
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        guard let masPath = executableFinder() else {
            throw ProviderError.managerMissing("mas")
        }

        // 1. 登录态探测：mas account（timeout 10s，禁用 Spotlight 自动索引）
        var requiresLogin = false
        do {
            let accountResult = try await ShellRunner.run(masPath, arguments: ["account"], timeout: 10, environment: Self.masEnvironment)
            if accountResult.exitCode != 0 ||
                accountResult.stdout.lowercased().contains("not logged in") ||
                accountResult.stderr.lowercased().contains("not logged in") {
                requiresLogin = true
            }
        } catch {
            requiresLogin = true
        }

        // 2. 获取过期列表：mas outdated（timeout 60s，禁用 Spotlight 自动索引）
        let outdatedResult = try await ShellRunner.run(masPath, arguments: ["outdated"], timeout: 60, environment: Self.masEnvironment)
        if outdatedResult.exitCode != 0 && !requiresLogin {
            if outdatedResult.stdout.lowercased().contains("not logged in") ||
                outdatedResult.stderr.lowercased().contains("not logged in") {
                requiresLogin = true
            } else {
                throw ProviderError.parsingFailed("mas outdated exited with code \(outdatedResult.exitCode): \(outdatedResult.stderr)")
            }
        }

        return MasOutdatedParser.parse(outdatedResult.stdout, requiresLogin: requiresLogin)
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        if item.requiresLogin {
            throw ProviderError.loginRequired
        }

        guard let masPath = executableFinder() else {
            throw ProviderError.managerMissing("mas")
        }

        let targetId = item.externalId ?? item.name

        let shellResult: ShellRunner.ShellResult
        do {
            shellResult = try await ShellRunner.run(masPath, arguments: ["upgrade", targetId], timeout: 600, environment: Self.masEnvironment)
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

        let isLoginFailure = shellResult.stdout.lowercased().contains("not logged in") ||
            shellResult.stderr.lowercased().contains("not logged in")
        if isLoginFailure {
            throw ProviderError.loginRequired
        }

        let tailStderr = BrewProvider.extractTail(shellResult.stderr, maxLines: 5)
        if shellResult.exitCode == 0 {
            return UpdateResult(ok: true, newVersion: nil, message: tailStderr)
        } else {
            let errorText = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
            let message = BrewProvider.extractTail(errorText, maxLines: 5) ?? "Exit code \(shellResult.exitCode)"
            return UpdateResult(ok: false, newVersion: nil, message: message)
        }
    }
}

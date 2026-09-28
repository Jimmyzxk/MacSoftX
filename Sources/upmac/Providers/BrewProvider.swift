import Foundation

public enum BrewOutdatedParser {
    private struct BrewOutdatedPayload: Decodable {
        let formulae: [FormulaEntry]?
        let casks: [CaskEntry]?
    }

    private struct FormulaEntry: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
        let pinned: Bool?
    }

    private struct CaskEntry: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
    }

    /// 解析 brew outdated --json=v2 输出的 JSON 字符串
    /// - Parameter jsonString: 命令 stdout 输出
    /// - Returns: 统一模型 UpdateItem 数组
    /// - Throws: ProviderError.parsingFailed
    public static func parse(_ jsonString: String) throws -> [UpdateItem] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProviderError.parsingFailed("Empty JSON input")
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ProviderError.parsingFailed("Invalid UTF-8 data")
        }

        let payload: BrewOutdatedPayload
        do {
            payload = try JSONDecoder().decode(BrewOutdatedPayload.self, from: data)
        } catch {
            throw ProviderError.parsingFailed(error.localizedDescription)
        }

        var items: [UpdateItem] = []

        if let formulae = payload.formulae {
            for f in formulae {
                let current = f.installed_versions?.first ?? "?"
                items.append(UpdateItem(
                    providerId: "brew",
                    name: f.name,
                    currentVersion: current.isEmpty ? "?" : current,
                    latestVersion: f.current_version,
                    kind: .formula,
                    needsSudo: false,
                    requiresLogin: false
                ))
            }
        }

        if let casks = payload.casks {
            for c in casks {
                let current = c.installed_versions?.first ?? "?"
                items.append(UpdateItem(
                    providerId: "brew",
                    name: c.name,
                    currentVersion: current.isEmpty ? "?" : current,
                    latestVersion: c.current_version,
                    kind: .cask,
                    needsSudo: false,
                    requiresLogin: false
                ))
            }
        }

        return items
    }
}

public final class BrewProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "brew"
    public let displayName: String = "Homebrew"
    private let executableFinder: () -> String?

    public init(executableFinder: @escaping () -> String? = BrewPaths.brewPath) {
        self.executableFinder = executableFinder
    }

    public func isAvailable() async -> Bool {
        return executableFinder() != nil
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        guard let brewPath = executableFinder() else {
            throw ProviderError.managerMissing("brew")
        }

        let result = try await ShellRunner.run(brewPath, arguments: ["outdated", "--json=v2"], timeout: 60)
        guard result.exitCode == 0 else {
            throw ProviderError.parsingFailed("brew outdated failed with code \(result.exitCode): \(result.stderr)")
        }

        return try BrewOutdatedParser.parse(result.stdout)
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        guard let brewPath = executableFinder() else {
            throw ProviderError.managerMissing("brew")
        }

        let args: [String]
        switch item.kind {
        case .cask:
            args = ["upgrade", "--cask", item.name]
        default:
            args = ["upgrade", item.name]
        }

        let shellResult: ShellRunner.ShellResult
        do {
            shellResult = try await ShellRunner.run(brewPath, arguments: args, timeout: 600)
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

        let tailStderr = Self.extractTail(shellResult.stderr, maxLines: 5)
        if shellResult.exitCode == 0 {
            return UpdateResult(ok: true, newVersion: nil, message: tailStderr)
        } else {
            let errorText = shellResult.stderr.isEmpty ? shellResult.stdout : shellResult.stderr
            let message = Self.extractTail(errorText, maxLines: 5) ?? "Exit code \(shellResult.exitCode)"
            return UpdateResult(ok: false, newVersion: nil, message: message)
        }
    }

    /// 截取多行文本末尾若干行
    public static func extractTail(_ text: String, maxLines: Int = 5) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}

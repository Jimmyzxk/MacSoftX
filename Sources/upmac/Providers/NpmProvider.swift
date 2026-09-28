import Foundation

public enum NpmOutdatedParser {
    public struct NpmPackageOutdatedInfo: Decodable, Sendable {
        public let current: String?
        public let wanted: String?
        public let latest: String?
        public let location: String?

        public init(current: String? = nil, wanted: String? = nil, latest: String? = nil, location: String? = nil) {
            self.current = current
            self.wanted = wanted
            self.latest = latest
            self.location = location
        }
    }

    /// 解析 npm outdated -g --json 输出
    /// - Parameter jsonString: 命令 stdout JSON 字符串
    /// - Returns: UpdateItem 数组
    public static func parse(_ jsonString: String) throws -> [UpdateItem] {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        guard let data = trimmed.data(using: .utf8) else {
            throw ProviderError.parsingFailed("Invalid UTF-8 data in npm outdated JSON")
        }

        // npm 当没有过期包时输出空对象 "{}" 或空数组 "[]"
        if trimmed == "{}" || trimmed == "[]" {
            return []
        }

        let dict: [String: NpmPackageOutdatedInfo]
        do {
            dict = try JSONDecoder().decode([String: NpmPackageOutdatedInfo].self, from: data)
        } catch {
            throw ProviderError.parsingFailed("Failed to decode npm outdated JSON: \(error.localizedDescription)")
        }

        var items: [UpdateItem] = []
        for (name, info) in dict {
            let current = info.current ?? "?"
            let latest = info.latest ?? info.wanted
            items.append(UpdateItem(
                providerId: "npm",
                name: name,
                currentVersion: current.isEmpty ? "?" : current,
                latestVersion: latest,
                kind: .cli,
                needsSudo: false,
                requiresLogin: false
            ))
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public final class NpmProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "npm"
    public let displayName: String = "npm"

    private let executableFinder: (@Sendable () async -> String?)?

    public init(executableFinder: (@Sendable () async -> String?)? = nil) {
        self.executableFinder = executableFinder
    }

    /// 定位 npm 二进制路径：
    /// 1. 优先通过 zsh login shell 查询 command -v npm (命中用户自定义 PATH 如 ~/.local/bin/npm、nvm)
    /// 2. 依次探测 /opt/homebrew/bin/npm、/usr/local/bin/npm、~/.local/bin/npm 等已知候选路径
    public static func resolveNpmPath() async -> String? {
        do {
            let res = try await ShellRunner.run("/bin/zsh", arguments: ["-lc", "command -v npm"], timeout: 5)
            if res.exitCode == 0 {
                let path = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // 继续探查静态候选路径
        }

        let candidates = [
            ("~/.local/bin/npm" as NSString).expandingTildeInPath,
            "/opt/homebrew/bin/npm",
            "/usr/local/bin/npm",
            ("~/.nvm/current/bin/npm" as NSString).expandingTildeInPath,
            "/usr/bin/npm"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return nil
    }

    private func getExecutablePath() async -> String? {
        if let finder = executableFinder {
            return await finder()
        }
        return await Self.resolveNpmPath()
    }

    public func isAvailable() async -> Bool {
        return await getExecutablePath() != nil
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        guard let npmPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("npm")
        }

        // 镜像加速：用户全局 registry 往往直连 registry.npmjs.org，国内访问单次请求可耗时 10s+，
        // 整轮 npm outdated 会累积到 90s 以上。此处仅为本次只读扫描临时指定镜像，
        // 不修改用户的 ~/.npmrc（那是用户的自主选择），也不影响 update() 的实际安装源。
        var args = ["outdated", "-g", "--json"]
        if let mirror = NpmMirror.current {
            args += ["--registry", mirror]
        }

        let result = try await ShellRunner.run(npmPath, arguments: args, timeout: 90)

        // npm outdated 规范：有过期包时退出码为 1，无过期包时为 0
        if result.exitCode == 0 || result.exitCode == 1 {
            return try NpmOutdatedParser.parse(result.stdout)
        }

        // 若退出码异常但 stdout 仍含有效 JSON，尝试容错解析
        if let items = try? NpmOutdatedParser.parse(result.stdout), !items.isEmpty {
            return items
        }

        let err = result.stderr.isEmpty ? result.stdout : result.stderr
        throw ProviderError.parsingFailed("npm outdated 失败 (exit \(result.exitCode)): \(err.prefix(200))")
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        guard let npmPath = await getExecutablePath() else {
            throw ProviderError.managerMissing("npm")
        }

        // 更新命令：npm install -g <name>@latest，超时 300s
        let shellResult: ShellRunner.ShellResult
        do {
            shellResult = try await ShellRunner.run(
                npmPath,
                arguments: ["install", "-g", "\(item.name)@latest"],
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

import Foundation
import AppKit

/// Sparkle 应用更新 Provider
/// 负责扫描本地及外置盘中的 Sparkle 应用并拉取 appcast 检测新版本
public final class AppUpdateProvider: UpdateProvider, @unchecked Sendable {
    public let id: String = "apps"
    public let displayName: String = "应用"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func isAvailable() async -> Bool {
        // macOS 环境恒常可用
        true
    }

    /// 快速段：仅本地 Sparkle 检测（不含 Cask 网络）
    public func fetchOutdatedWithoutCask() async throws -> [UpdateItem] {
        let apps = AppScanService.scanInstalledApplications(fileManager: fileManager)
        let sparkleApps = apps.filter { app in
            !app.isAppStoreReceiptPresent &&
            !(app.feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let sparkleResults: [UpdateItem] = await withTaskGroup(of: UpdateItem?.self, returning: [UpdateItem].self) { group in
            for app in sparkleApps {
                guard let feedURL = app.feedURL else { continue }
                group.addTask {
                    do {
                        guard let bestItem = try await AppcastFetcher.fetchLatestItem(from: feedURL, timeout: 5.0) else {
                            return nil
                        }
                        let latest = bestItem.displayVersion
                        let current = app.version
                        if SparkleVersionComparator.compare(latest, current) == .orderedDescending {
                            return UpdateItem(
                                providerId: "apps",
                                name: app.name,
                                currentVersion: current,
                                latestVersion: latest,
                                kind: .app,
                                needsSudo: false,
                                requiresLogin: false,
                                externalId: app.path
                            )
                        }
                    } catch {}
                    return nil
                }
            }
            var outdated: [UpdateItem] = []
            for await item in group { if let item = item { outdated.append(item) } }
            return outdated
        }
        return sparkleResults.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// 慢速段：Cask 网络检测（渐进式后台补齐）
    public func fetchCaskUpdates() async throws -> [UpdateItem] {
        let apps = AppScanService.scanInstalledApplications(fileManager: fileManager)
        let sparkleApps = apps.filter { app in
            !app.isAppStoreReceiptPresent &&
            !(app.feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
        let brewManaged = await Self.loadBrewManagedCasks()
        let standaloneCandidates = apps.filter { app in
            !app.isAppStoreReceiptPresent &&
            (app.feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
            CaskVersionChecker.isAllowedPath(app.path)
        }
        let sparklePaths = Set(sparkleApps.map { $0.path })
        let caskCandidates = standaloneCandidates.filter { app in
            if sparklePaths.contains(app.path) { return false }
            let tokens = CaskToken.candidateTokens(for: app.name)
            if tokens.contains(where: { brewManaged.tokens.contains($0) }) { return false }
            if brewManaged.paths.contains(app.path) { return false }
            return true
        }

        let caskResults: [UpdateItem] = await withTaskGroup(of: UpdateItem?.self, returning: [UpdateItem].self) { group in
            for app in caskCandidates {
                group.addTask {
                    guard let match = await CaskVersionChecker.shared.fetch(for: app) else { return nil }
                    let current = app.version
                    if SparkleVersionComparator.compare(match.latestVersion, current) == .orderedDescending {
                        if VersionSpanChecker.isSuspicious(current: current, latest: match.latestVersion) {
                            return nil
                        }
                        return UpdateItem(
                            providerId: "apps",
                            name: app.name,
                            currentVersion: current,
                            latestVersion: match.latestVersion,
                            kind: .app,
                            needsSudo: false,
                            requiresLogin: false,
                            externalId: app.path,
                            infoURL: match.homepage,
                            caskToken: match.token
                        )
                    }
                    return nil
                }
            }
            var res: [UpdateItem] = []
            for await item in group { if let item = item { res.append(item) } }
            return res
        }
        return caskResults.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func fetchOutdated() async throws -> [UpdateItem] {
        // 全量：快速段 + 慢速段（CLI 默认）
        let sparkle = try await fetchOutdatedWithoutCask()
        let cask = (try? await fetchCaskUpdates()) ?? []
        let combined = sparkle + cask
        return combined.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Brew 受管 Cask 单次探测（超时 30s，失败返回空）
    private static func loadBrewManagedCasks() async -> (tokens: Set<String>, paths: Set<String>) {
        guard let brewPath = BrewPaths.brewPath() else { return (Set(), Set()) }
        // 优先尝试 brew list --cask --json=v2（任务指定），失败回退 brew list --json --versions
        let attempts: [[String]] = [
            ["list", "--cask", "--json=v2"],
            ["list", "--json", "--versions"]
        ]
        for args in attempts {
            if let result = try? await ShellRunner.run(brewPath, arguments: args, timeout: 30),
               result.exitCode == 0 {
                let parsed = BrewCaskManagedParser.parse(result.stdout)
                // 若 tokens 非空则视为有效；空则继续下一尝试
                if !parsed.tokens.isEmpty || !parsed.paths.isEmpty {
                    return parsed
                }
                // 空但解析成功也返回（避免无意义重试）
                if result.stdout.contains("\"casks\"") {
                    return parsed
                }
            }
        }
        return (Set(), Set())
    }

    public func update(_ item: UpdateItem) async throws -> UpdateResult {
        // 1. 手动安装直接更新：走 brew install --cask --force
        if let token = item.caskToken, !token.isEmpty {
            guard let brewPath = BrewPaths.brewPath() else {
                throw ProviderError.managerMissing("brew")
            }
            return try await CaskInstaller.update(item: item, brewPath: brewPath)
        }
        // 2. 无 token 仅有下载页：打开下载页（handoff，非自动更新）
        // infoURL 来自远端 cask JSON，属不可信输入，仅允许 HTTPS
        if let info = item.infoURL, let url = URL(string: info), url.scheme?.lowercased() == "https" {
            let opened = await MainActor.run { NSWorkspace.shared.open(url) }
            if opened {
                return UpdateResult(ok: true, newVersion: item.latestVersion, message: "已打开下载页", autoUpdated: false)
            } else {
                return UpdateResult(ok: false, newVersion: nil, message: "无法打开下载页")
            }
        }
        guard let path = item.externalId, fileManager.fileExists(atPath: path) else {
            return UpdateResult(ok: false, newVersion: nil, message: "未找到应用路径")
        }
        let appURL = URL(fileURLWithPath: path)
        let opened = await MainActor.run {
            NSWorkspace.shared.open(appURL)
        }
        if opened {
            return UpdateResult(
                ok: true,
                newVersion: item.latestVersion,
                message: "应用已打开，请在应用内完成更新",
                autoUpdated: false
            )
        } else {
            return UpdateResult(
                ok: false,
                newVersion: nil,
                message: "无法唤起应用自更新"
            )
        }
    }
}

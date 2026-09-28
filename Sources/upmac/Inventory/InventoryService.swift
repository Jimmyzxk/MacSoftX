import Foundation
import SwiftUI

@MainActor
public final class InventoryService: ObservableObject {
    @Published public var items: [InventoryItem] = []
    @Published public var lastErrors: [String: String] = [:]
    @Published public var isLoading: Bool = false
    @Published public var lastScanDate: Date? = nil
    @Published public var lastReport: InventoryReport? = nil

    public init() {}

    public var appCount: Int {
        items.filter { $0.kind == .app }.count
    }

    public var cliCount: Int {
        items.filter { $0.kind == .cli }.count
    }

    public var orphanCount: Int {
        items.filter { $0.status == .unmanaged }.count
    }

    public var coveredSourcesCount: Int {
        Set(items.map { $0.sourceDisplayName }).count
    }

    /// 首次触发或复用缓存
    public func ensureLoaded() async {
        guard items.isEmpty && !isLoading else { return }
        await refresh()
    }

    /// 执行全量 Inventory 扫描
    public func refresh() async {
        isLoading = true
        defer {
            isLoading = false
            lastScanDate = Date()
        }

        let report = await Self.performScan()
        self.items = report.items
        self.lastErrors = report.errors
        self.lastReport = report
    }

    /// 独立的纯扫描执行逻辑（可在命令行模式和后台任务复用）
    public nonisolated static func performScan() async -> InventoryReport {
        // 1. 本地应用扫描与索引建立
        let scannedApps = AppScanner.scanInstalledApplications()
        AppIconFinder.shared.ensureIndexed()

        // 2. 并行获取各包管理器安装清单（走 ShellRunner，缺源自动跳过，源存在但失败记录错误）
        async let brewTask = fetchBrewList()
        async let masTask = fetchMasList()
        async let npmTask = fetchNpmList()
        async let pipxTask = fetchPipxList()
        async let uvTask = fetchUvList()
        async let gemTask = fetchGemList()
        async let cargoTask = fetchCargoList()

        let (brewFormulae, brewCasks, brewError) = await brewTask
        let (masEntries, masError) = await masTask
        let (npmItems, npmError) = await npmTask
        let (pipxItems, pipxError) = await pipxTask
        let (uvItems, uvError) = await uvTask
        let (gemItems, gemError) = await gemTask
        let (cargoItems, cargoError) = await cargoTask

        // 聚合各源失败信息（缺源静默，源存在但执行/解析失败记入 errors）
        var perSourceErrors: [String: String] = [:]
        if let err = brewError { perSourceErrors["brew"] = err }
        if let err = masError { perSourceErrors["mas"] = err }
        if let err = npmError { perSourceErrors["npm"] = err }
        if let err = pipxError { perSourceErrors["pipx"] = err }
        if let err = uvError { perSourceErrors["uv"] = err }
        if let err = gemError { perSourceErrors["gem"] = err }
        if let err = cargoError { perSourceErrors["cargo"] = err }

        // 3. 交叉比对应用管辖状态
        var matchedCaskTokens = Set<String>()
        var matchedMasIds = Set<String>()
        var appItems: [InventoryItem] = []

        for app in scannedApps {
            let appNorm = AppIconFinder.normalizeName(app.name)
            let fileStemNorm = AppIconFinder.normalizeName(URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent)

            // A. 比对 Brew Cask
            var matchedCask: InventoryItem? = nil
            for cask in brewCasks {
                let token = cask.id.replacingOccurrences(of: "brew-cask:", with: "")
                let tokenNorm = AppIconFinder.normalizeName(token)
                let nameNorm = AppIconFinder.normalizeName(cask.name)

                // 基础精确比对
                let exactMatch = (appNorm == tokenNorm || appNorm == nameNorm ||
                                  fileStemNorm == tokenNorm || fileStemNorm == nameNorm)

                // 增强容错比对（如 docker-desktop 与 Docker.app / Docker Desktop.app）
                let strippedToken = tokenNorm
                    .replacingOccurrences(of: "desktop", with: "")
                    .replacingOccurrences(of: "app", with: "")
                let strippedApp = appNorm
                    .replacingOccurrences(of: "desktop", with: "")
                    .replacingOccurrences(of: "app", with: "")
                let strippedFileStem = fileStemNorm
                    .replacingOccurrences(of: "desktop", with: "")
                    .replacingOccurrences(of: "app", with: "")

                let fuzzyMatch = (!strippedToken.isEmpty && (
                    strippedApp == strippedToken ||
                    strippedFileStem == strippedToken
                ))

                if exactMatch || fuzzyMatch {
                    matchedCask = cask
                    matchedCaskTokens.insert(cask.id)
                    break
                }
            }

            // B. 比对 App Store (mas)
            var matchedMas: MasListParser.MasEntry? = nil
            if matchedCask == nil {
                for mas in masEntries {
                    let masNorm = AppIconFinder.normalizeName(mas.name)
                    if appNorm == masNorm || fileStemNorm == masNorm {
                        matchedMas = mas
                        matchedMasIds.insert(mas.id)
                        break
                    }
                }
            }

            // C. 确定归属（真实应用 cask / mas 元数据）
            if let cask = matchedCask {
                let resolvedVersion = (app.version != "—" && !app.version.isEmpty) ? app.version : cask.version
                let resolvedName = app.name.isEmpty ? cask.name : app.name
                appItems.append(InventoryItem(
                    id: cask.id,
                    name: resolvedName,
                    version: resolvedVersion,
                    kind: .app,
                    sourceId: "brew-cask",
                    sourceDisplayName: "Homebrew Cask",
                    status: .managed,
                    bundleId: app.bundleId,
                    path: app.path
                ))
            } else if let mas = matchedMas {
                let resolvedVersion = (app.version != "—" && !app.version.isEmpty) ? app.version : mas.version
                let resolvedName = app.name.isEmpty ? mas.name : app.name
                appItems.append(InventoryItem(
                    id: "mas:\(mas.id)",
                    name: resolvedName,
                    version: resolvedVersion,
                    kind: .app,
                    sourceId: "mas",
                    sourceDisplayName: "App Store",
                    status: .managed,
                    bundleId: app.bundleId,
                    path: app.path
                ))
            } else if app.isAppStoreReceiptPresent {
                appItems.append(InventoryItem(
                    id: "app:\(app.path)",
                    name: app.name,
                    version: app.version,
                    kind: .app,
                    sourceId: "mas",
                    sourceDisplayName: "App Store",
                    status: .managed,
                    bundleId: app.bundleId,
                    path: app.path
                ))
            } else {
                // 游离项：独立下载未受管
                appItems.append(InventoryItem(
                    id: "app:\(app.path)",
                    name: app.name,
                    version: app.version,
                    kind: .app,
                    sourceId: "standalone",
                    sourceDisplayName: "独立应用",
                    status: .unmanaged,
                    bundleId: app.bundleId,
                    path: app.path
                ))
            }
        }

        // 4. 追加未在 /Applications 匹配到的已记录 cask 和 mas 项
        for cask in brewCasks where !matchedCaskTokens.contains(cask.id) {
            appItems.append(cask)
        }
        for mas in masEntries where !matchedMasIds.contains(mas.id) {
            appItems.append(InventoryItem(
                id: "mas:\(mas.id)",
                name: mas.name,
                version: mas.version,
                kind: .app,
                sourceId: "mas",
                sourceDisplayName: "App Store",
                status: .managed,
                bundleId: nil,
                path: nil
            ))
        }

        // 5. 组合命令行软件
        var cliItems: [InventoryItem] = []
        cliItems.append(contentsOf: brewFormulae)
        cliItems.append(contentsOf: npmItems)
        cliItems.append(contentsOf: pipxItems)
        cliItems.append(contentsOf: uvItems)
        cliItems.append(contentsOf: gemItems)
        cliItems.append(contentsOf: cargoItems)

        // 6. 统一排序与去重
        let allItems = (appItems + cliItems).sorted {
            if $0.kind != $1.kind {
                return $0.kind == .app
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        // 7. 统计计算
        let totalCount = allItems.count
        let appCount = allItems.filter { $0.kind == .app }.count
        let cliCount = allItems.filter { $0.kind == .cli }.count
        let orphanCount = allItems.filter { $0.status == .unmanaged }.count

        var sourceStats: [String: Int] = [:]
        for item in allItems {
            sourceStats[item.sourceDisplayName, default: 0] += 1
        }

        return InventoryReport(
            totalCount: totalCount,
            appCount: appCount,
            cliCount: cliCount,
            orphanCount: orphanCount,
            sourceStats: sourceStats,
            items: allItems,
            errors: perSourceErrors
        )
    }

    // MARK: - 各源异步只读探测与错误捕获

    private nonisolated static func fetchBrewList() async -> (formulae: [InventoryItem], casks: [InventoryItem], error: String?) {
        guard let brewPath = ToolPaths.brew() else { return ([], [], nil) }

        // 1. 新版 Homebrew 命令规范: brew list --json --versions
        do {
            let res = try await ShellRunner.run(brewPath, arguments: ["list", "--json", "--versions"], timeout: 120)
            if res.exitCode == 0 {
                do {
                    let parsed = try BrewListParser.parseDetailed(res.stdout)
                    return (parsed.formulae, parsed.casks, nil)
                } catch {
                    return ([], [], "brew list 解析失败: \(error.localizedDescription)")
                }
            } else {
                // 兼容回退尝试旧版旗标 brew list --json
                if let fallbackRes = try? await ShellRunner.run(brewPath, arguments: ["list", "--json"], timeout: 60),
                   fallbackRes.exitCode == 0,
                   let parsed = try? BrewListParser.parseDetailed(fallbackRes.stdout) {
                    return (parsed.formulae, parsed.casks, nil)
                }

                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], [], "brew list 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], [], "brew list 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchMasList() async -> (entries: [MasListParser.MasEntry], error: String?) {
        guard let masPath = ToolPaths.mas() else { return ([], nil) }
        do {
            let res = try await ShellRunner.run(masPath, arguments: ["list"], timeout: 30)
            if res.exitCode == 0 {
                let entries = MasListParser.parseEntries(res.stdout)
                return (entries, nil)
            } else {
                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], "mas list 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], "mas list 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchNpmList() async -> (items: [InventoryItem], error: String?) {
        guard let npmPath = ToolPaths.npm() else { return ([], nil) }
        do {
            let res = try await ShellRunner.run(npmPath, arguments: ["ls", "-g", "--json"], timeout: 30)
            // npm 偶有 peer 依赖警告返回非 0，但 stdout 仍含有完整 json
            if let items = try? NpmListParser.parse(res.stdout), !items.isEmpty {
                return (items, nil)
            }
            if res.exitCode == 0 {
                let items = (try? NpmListParser.parse(res.stdout)) ?? []
                return (items, nil)
            } else {
                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], "npm ls 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], "npm ls 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchPipxList() async -> (items: [InventoryItem], error: String?) {
        guard let pipxPath = ToolPaths.pipx() else { return ([], nil) }
        do {
            let res = try await ShellRunner.run(pipxPath, arguments: ["list", "--json"], timeout: 30)
            if res.exitCode == 0 {
                do {
                    let items = try PipxListParser.parse(res.stdout)
                    return (items, nil)
                } catch {
                    return ([], "pipx list 解析失败: \(error.localizedDescription)")
                }
            } else {
                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], "pipx list 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], "pipx list 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchUvList() async -> (items: [InventoryItem], error: String?) {
        guard let uvPath = ToolPaths.uv() else { return ([], nil) }
        do {
            let res = try await ShellRunner.run(uvPath, arguments: ["tool", "list"], timeout: 20)
            if res.exitCode == 0 {
                let items = UvToolListParser.parse(res.stdout)
                return (items, nil)
            } else {
                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], "uv tool list 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], "uv tool list 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchGemList() async -> (items: [InventoryItem], error: String?) {
        guard let gemPath = ToolPaths.gem() else { return ([], nil) }
        do {
            let res = try await ShellRunner.run(gemPath, arguments: ["list", "--local"], timeout: 30)
            if res.exitCode == 0 {
                let items = GemListParser.parse(res.stdout)
                return (items, nil)
            } else {
                let errText = res.stderr.isEmpty ? res.stdout : res.stderr
                return ([], "gem list 退出码 \(res.exitCode): \(errText.prefix(120))")
            }
        } catch {
            return ([], "gem list 执行失败: \(error.localizedDescription)")
        }
    }

    private nonisolated static func fetchCargoList() async -> (items: [InventoryItem], error: String?) {
        guard let cargoPath = ToolPaths.cargo() else { return ([], nil) }

        // 优先尝试 cargo install-update -l
        var firstError: String? = nil
        do {
            let res = try await ShellRunner.run(cargoPath, arguments: ["install-update", "-l"], timeout: 25)
            if res.exitCode == 0 {
                let items = CargoListParser.parse(res.stdout)
                return (items, nil)
            } else {
                firstError = "cargo install-update 退出码 \(res.exitCode)"
            }
        } catch {
            firstError = error.localizedDescription
        }

        // 回退尝试 cargo install --list
        do {
            let fallbackRes = try await ShellRunner.run(cargoPath, arguments: ["install", "--list"], timeout: 25)
            if fallbackRes.exitCode == 0 {
                let items = CargoListParser.parseInstallList(fallbackRes.stdout)
                return (items, nil)
            } else {
                let errText = fallbackRes.stderr.isEmpty ? fallbackRes.stdout : fallbackRes.stderr
                return ([], "cargo 失败: (1) \(firstError ?? "未知"); (2) cargo install --list 退出码 \(fallbackRes.exitCode): \(errText.prefix(80))")
            }
        } catch {
            return ([], "cargo 失败: (1) \(firstError ?? "未知"); (2) \(error.localizedDescription)")
        }
    }
}

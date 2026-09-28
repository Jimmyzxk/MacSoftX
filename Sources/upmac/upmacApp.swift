import SwiftUI
import AppKit
import UserNotifications

@MainActor
public final class AppState: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public enum ItemUpdateStatus: Equatable, Sendable {
        case idle
        case updating
        case success(newVersion: String?)
        case failure(message: String)
        case handoff(message: String)
    }

    public enum DetailPayload: Equatable, Sendable {
        case scan(item: UpdateItem)
        case inventory(item: InventoryItem)
    }

    @Published public var items: [UpdateItem] = []
    @Published public var lastErrors: [String: String] = [:]
    @Published public var isLoading: Bool = false
    @Published public var scanningProviders: Set<String> = []
    @Published public var updateStatuses: [String: ItemUpdateStatus] = [:]
    @Published public var updateStartedAt: [String: Date] = [:]
    @Published public var isUpdatingAll: Bool = false
    @Published public var updateAllProgress: (current: Int, total: Int, currentItemName: String)? = nil
    @Published public var lastScanDate: Date? = nil
    @Published public var pendingDetail: DetailPayload? = nil
    @Published public var ignoreRules: [IgnoreRule] = []
    @Published public var notificationsEnabled: Bool = true
    @Published public var scanIntervalMinutes: Int = 360
    @Published public var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @Published public var pendingQuitConfirmation: Bool = false
    private var skippedOnce: Set<String> = []
    private var scanTimer: Timer?
    private var scanTask: Task<Void, Never>?
    private var caskRefreshTask: Task<Void, Never>?
    private let lastNotifiedKey = "upmac.lastNotifiedIds"
    private var lastNotifiedAt: Date?
    public let providers: [any UpdateProvider]

    private var isRunningTests: Bool { NSClassFromString("XCTestCase") != nil }

    public init(providers: [any UpdateProvider] = [
        BrewProvider(),
        MasProvider(),
        AppUpdateProvider(),
        NpmProvider(),
        GemProvider(),
        UvProvider()
    ]) {
        self.providers = providers
        super.init()
        loadIgnoreRules()
        loadSettings()
        if !isRunningTests {
            UNUserNotificationCenter.current().delegate = self
            refreshNotificationAuthStatus()
            scheduleScanTimer()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                ShellRunner.terminateAllActive()
            }
        }
        Task {
            await reloadAll()
        }
    }

    // MARK: - Persistence: ignoreRules & settings

    private var statePath: String { AppScanService.defaultStatePath }

    private func loadIgnoreRules() {
        let json = StateStore.read()
        guard let arr = json["ignoreRules"] as? [[String: Any]] else {
            ignoreRules = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let d = try? JSONSerialization.data(withJSONObject: arr),
           let decoded = try? decoder.decode([IgnoreRule].self, from: d) {
            ignoreRules = IgnoreRuleFilter.cleaned(rules: decoded)
        } else {
            ignoreRules = []
        }
    }

    private func persistIgnoreRules() {
        let rules = ignoreRules
        StateStore.update { dict in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(rules),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                dict["ignoreRules"] = arr
            }
        }
    }

    private func loadSettings() {
        let json = StateStore.read()
        guard let settings = json["settings"] as? [String: Any] else { return }
        if let v = settings["notificationsEnabled"] as? Bool { notificationsEnabled = v }
        if let v = settings["scanIntervalMinutes"] as? Int { scanIntervalMinutes = v }
        else if let v = settings["scanIntervalMinutes"] as? Double { scanIntervalMinutes = Int(v) }
    }

    private func persistSettings() {
        let notifEnabled = notificationsEnabled
        let interval = scanIntervalMinutes
        StateStore.update { dict in
            var settings = (dict["settings"] as? [String: Any]) ?? [:]
            settings["notificationsEnabled"] = notifEnabled
            settings["scanIntervalMinutes"] = interval
            dict["settings"] = settings
        }
    }

    // MARK: - Ignore API

    public func ignore(item: UpdateItem, scope: IgnoreScope, durationDays: Int = 7) {
        let rule: IgnoreRule
        switch scope {
        case .forever:
            rule = IgnoreRule(providerId: item.providerId, name: item.name, scope: .forever, until: nil, createdAt: Date())
        case .until:
            let until = Calendar.current.date(byAdding: .day, value: durationDays, to: Date())
            rule = IgnoreRule(providerId: item.providerId, name: item.name, scope: .until, until: until, createdAt: Date())
        }
        // 去重
        ignoreRules.removeAll { $0.providerId == rule.providerId && $0.name == rule.name }
        ignoreRules.append(rule)
        persistIgnoreRules()
        // 立即过滤当前 items
        items.removeAll { rule.matches(item: $0) }
    }

    public func ignore(inventoryItem: InventoryItem, scope: IgnoreScope, durationDays: Int = 7) {
        // 将 Inventory 转为伪 UpdateItem 用于规则匹配（providerId 用 sourceId）
        let pseudo = UpdateItem(providerId: inventoryItem.sourceId, name: inventoryItem.name, currentVersion: inventoryItem.version, kind: .app)
        ignore(item: pseudo, scope: scope, durationDays: durationDays)
    }

    public func restore(rule: IgnoreRule) {
        ignoreRules.removeAll { $0.id == rule.id }
        persistIgnoreRules()
    }

    public func restoreAll() {
        ignoreRules.removeAll()
        persistIgnoreRules()
    }

    public func skipOnce(item: UpdateItem) {
        skippedOnce.insert(item.id)
        items.removeAll { $0.id == item.id }
    }

    // MARK: - Filtering helpers

    private func filterAndClean() {
        let cleaned = IgnoreRuleFilter.cleaned(rules: ignoreRules)
        if cleaned.count != ignoreRules.count {
            ignoreRules = cleaned
            persistIgnoreRules()
        }
    }

    // MARK: - Reload

    public func reloadAll() async {
        if let existing = scanTask, !existing.isCancelled {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            self.isLoading = true
            // 渐进式：初始化扫描中集合（dispatch 时全量插入）
            self.scanningProviders = Set(self.providers.map { $0.id })
            defer {
                self.isLoading = false
                self.lastScanDate = Date()
                self.scanTask = nil
                self.scanningProviders.removeAll()
            }

            // 清理过期规则
            self.filterAndClean()

            var newErrors: [String: String] = [:]
            var allItems: [UpdateItem] = []
            let pendingSkipped = self.skippedOnce

            // 快速段：本地数据秒出（Cask 网络跳过）— 渐进式合并
            await withTaskGroup(of: (providerId: String, items: [UpdateItem], error: String?).self) { group in
                for provider in self.providers {
                    group.addTask {
                        if let appProv = provider as? AppUpdateProvider {
                            do {
                                let fetched = try await appProv.fetchOutdatedWithoutCask()
                                return (provider.id, fetched, nil)
                            } catch {
                                return (provider.id, [], error.localizedDescription)
                            }
                        }
                        guard await provider.isAvailable() else {
                            return (provider.id, [], nil)
                        }
                        do {
                            let fetched = try await provider.fetchOutdated()
                            return (provider.id, fetched, nil)
                        } catch {
                            return (provider.id, [], error.localizedDescription)
                        }
                    }
                }

                for await result in group {
                    // group 每返回一个结果即移除对应源（扫描进行中集合维护）
                    self.scanningProviders.remove(result.providerId)
                    if let err = result.error {
                        newErrors[result.providerId] = err
                    } else {
                        allItems.append(contentsOf: result.items)
                    }
                    // 渐进式：每收到一个 provider 结果就立即合并进 items（先到先显示）
                    // 用 pendingSkipped 过滤 + 排序逻辑保持
                    let filtered = IgnoreRuleFilter.filterIgnored(items: allItems, rules: self.ignoreRules, skippedOnce: pendingSkipped)
                    self.items = filtered.sorted { ($0.providerId, $0.name) < ($1.providerId, $1.name) }
                    self.lastErrors = newErrors
                }
            }

            // 跳过本次仅生效一次，清空
            self.skippedOnce.removeAll()

            self.lastErrors = newErrors
            // 确保最终 items 为已过滤排序后的完整结果（与渐进式最后一次一致，双保险）
            let finalFiltered = IgnoreRuleFilter.filterIgnored(items: allItems, rules: self.ignoreRules, skippedOnce: pendingSkipped)
            self.items = finalFiltered.sorted { ($0.providerId, $0.name) < ($1.providerId, $1.name) }
            self.maybeNotify()
            // 慢速段：Cask 网络后台补齐
            Task { await self.refreshCaskUpdates() }
        }
        scanTask = task
        await task.value
    }

    /// 后台刷新 Cask 可更新项并增量合并（过滤忽略）
    public func refreshCaskUpdates() async {
        if let existing = caskRefreshTask, !existing.isCancelled {
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.caskRefreshTask = nil }
            guard let appProv = self.providers.first(where: { $0 is AppUpdateProvider }) as? AppUpdateProvider else { return }
            guard let caskItemsRaw = try? await appProv.fetchCaskUpdates(), !caskItemsRaw.isEmpty else { return }
            let caskItems = IgnoreRuleFilter.filterIgnored(items: caskItemsRaw, rules: self.ignoreRules, skippedOnce: self.skippedOnce)
            guard !caskItems.isEmpty else { return }
            var current = self.items
            current.removeAll { $0.providerId == "apps" && $0.caskToken != nil }
            let existingIds = Set(current.map { $0.id })
            let newItems = caskItems.filter { !existingIds.contains($0.id) }
            // 再过滤一次（双保险）
            let filteredNew = IgnoreRuleFilter.filterIgnored(items: newItems, rules: self.ignoreRules, skippedOnce: Set())
            current.append(contentsOf: filteredNew)
            self.items = current.sorted { ($0.providerId, $0.name) < ($1.providerId, $1.name) }
            self.maybeNotify()
        }
        caskRefreshTask = task
        await task.value
    }

    @discardableResult
    public func update(_ item: UpdateItem) async -> UpdateResult {
        guard let provider = providers.first(where: { $0.id == item.providerId }) else {
            let msg = "Provider not found for id: \(item.providerId)"
            updateStatuses[item.id] = .failure(message: msg)
            return UpdateResult(ok: false, newVersion: nil, message: msg)
        }
        if case .updating = updateStatuses[item.id] {
            return UpdateResult(ok: false, newVersion: nil, message: "更新已在进行中")
        }

        updateStatuses[item.id] = .updating
        updateStartedAt[item.id] = Date()
        do {
            let result = try await provider.update(item)
            if result.ok {
                if result.autoUpdated == false {
                    updateStatuses[item.id] = .handoff(message: result.message ?? "已打开应用")
                } else {
                    updateStatuses[item.id] = .success(newVersion: result.newVersion ?? item.latestVersion)
                }
            } else {
                updateStatuses[item.id] = .failure(message: result.message ?? "Update failed")
            }
            return result
        } catch {
            let msg = error.localizedDescription
            updateStatuses[item.id] = .failure(message: msg)
            return UpdateResult(ok: false, newVersion: nil, message: msg)
        }
    }

    @discardableResult
    public func updateAll() async -> [String: UpdateResult] {
        guard !isUpdatingAll else { return [:] }
        isUpdatingAll = true
        defer {
            isUpdatingAll = false
            updateAllProgress = nil
        }

        var results: [String: UpdateResult] = [:]
        let updatableItems = items.filter { item in
            guard !item.needsSudo, !item.requiresLogin, !item.isSystemComponent else { return false }
            if case .success = updateStatuses[item.id] { return false }
            if case .handoff = updateStatuses[item.id] { return false }
            // Bug A fix: skip handoff/manual items (apps without caskToken)
            if item.providerId == "apps" && (item.caskToken == nil || item.caskToken?.isEmpty == true) {
                return false
            }
            return true
        }
        let total = updatableItems.count
        updateAllProgress = total > 0 ? (current: 0, total: total, currentItemName: "") : nil
        for (idx, item) in updatableItems.enumerated() {
            updateAllProgress = (current: idx + 1, total: total, currentItemName: item.name)
            let res = await update(item)
            results[item.id] = res
        }
        return results
    }

    public var pendingItems: [UpdateItem] {
        let filtered = IgnoreRuleFilter.filterIgnored(items: items, rules: ignoreRules, skippedOnce: skippedOnce)
        return filtered.filter { item in
            guard !item.isSystemComponent else { return false }
            if case .success = updateStatuses[item.id] {
                return false
            }
            if case .handoff = updateStatuses[item.id] {
                return false
            }
            return true
        }
    }

    public var remainingCount: Int {
        pendingItems.count
    }

    public var manualFallbackCount: Int {
        items.filter { item in
            guard !item.needsSudo, !item.requiresLogin, !item.isSystemComponent else { return false }
            if case .success = updateStatuses[item.id] { return false }
            if case .handoff = updateStatuses[item.id] { return false }
            return item.providerId == "apps" && (item.caskToken == nil || item.caskToken?.isEmpty == true)
        }.count
    }

    public var ecosystemBreakdown: [(providerId: String, count: Int)] {
        let grouped = Dictionary(grouping: pendingItems, by: { $0.providerId })
        return grouped.map { (providerId: $0.key, count: $0.value.count) }
            .sorted { $0.providerId < $1.providerId }
    }

    // MARK: - 通知

    public func refreshNotificationAuthStatus() {
        guard !isRunningTests else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.notificationAuthStatus = settings.authorizationStatus
            }
        }
    }

    public func requestNotificationPermission() {
        guard !isRunningTests else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in
                self.refreshNotificationAuthStatus()
            }
        }
    }

    public func openNotificationSettings() {
        guard !isRunningTests else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func shortVersion(_ v: String) -> String {
        if let idx = v.firstIndex(of: ",") { return String(v[..<idx]) }
        return v
    }

    private func maybeNotify() {
        guard !isRunningTests else { return }
        guard notificationsEnabled else { return }
        let currentPending = pendingItems
        guard !currentPending.isEmpty else { return }
        let currentIds = Set(currentPending.map { $0.id })
        let previous: Set<String>? = {
            guard let data = UserDefaults.standard.data(forKey: lastNotifiedKey),
                  let arr = try? JSONDecoder().decode(Set<String>.self, from: data) else { return nil }
            return arr
        }()
        guard NotificationSnapshot.shouldNotify(previous: previous, current: currentIds) else { return }
        if let last = lastNotifiedAt, Date().timeIntervalSince(last) < 300 { return }
        var lines = currentPending.prefix(3).map { "\($0.name) \(shortVersion($0.currentVersion)) → \(shortVersion($0.latestVersion ?? "?"))" }
        if currentPending.count > 3 {
            lines.append("…等 \(currentPending.count) 项")
        }
        let names = lines.joined(separator: "\n")
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let self else { return }
            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in
                        self.refreshNotificationAuthStatus()
                        guard granted else { return }
                        self.sendNotification(ids: currentIds, names: names)
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                Task { @MainActor in
                    self.sendNotification(ids: currentIds, names: names)
                }
            } else {
                Task { @MainActor in self.refreshNotificationAuthStatus() }
            }
        }
    }

    private func sendNotification(ids: Set<String>, names: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(ids.count) 项软件可更新"
        content.body = names
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // 仅在 add 成功后才记录已通知快照；失败则保持未记录，下轮扫描可重试
        UNUserNotificationCenter.current().add(req) { [weak self] error in
            guard error == nil else {
                Task { @MainActor in self?.lastNotifiedAt = nil }
                return
            }
            Task { @MainActor in
                guard let self else { return }
                if let data = try? JSONEncoder().encode(ids) {
                    UserDefaults.standard.set(data, forKey: self.lastNotifiedKey)
                }
                self.lastNotifiedAt = Date()
            }
        }
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.title == "Macsoft X" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
        completionHandler()
    }

    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - 定时扫描

    public func updateScanInterval(minutes: Int) {
        scanIntervalMinutes = minutes
        persistSettings()
        scheduleScanTimer()
    }

    public func updateNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        persistSettings()
        if enabled {
            requestNotificationPermission()
        }
    }

    private func scheduleScanTimer() {
        guard !isRunningTests else { return }
        scanTimer?.invalidate()
        scanTimer = nil
        guard scanIntervalMinutes > 0 else { return }
        let interval = TimeInterval(scanIntervalMinutes * 60)
        scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.reloadAll()
            }
        }
        // Fire tolerance
        scanTimer?.tolerance = 60
    }
}

// MARK: - 统一退出入口
@MainActor
public func requestQuit(appState: AppState) {
    if appState.isUpdatingAll || appState.updateStatuses.values.contains(where: { if case .updating = $0 { return true }; return false }) {
        appState.pendingQuitConfirmation = true
    } else {
        ShellRunner.terminateAllActive()
        NSApplication.shared.terminate(nil)
    }
}

@main
struct UpMacMain {
    static func main() {
        if let idx = CommandLine.arguments.firstIndex(of: "--update-cask") {
            guard idx + 1 < CommandLine.arguments.count else {
                let out: [String: Any] = ["ok": false, "message": "missing token"]
                if let data = try? JSONSerialization.data(withJSONObject: out), let str = String(data: data, encoding: .utf8) { print(str) }
                exit(1)
            }
            let token = CommandLine.arguments[idx + 1]
            let semaphore = DispatchSemaphore(value: 0)
            final class ExitBox: @unchecked Sendable { var code: Int32 = 0 }
            let box = ExitBox()
            DispatchQueue.global().async {
                Task {
                    guard let brewPath = BrewPaths.brewPath() else {
                        let out: [String: Any] = ["ok": false, "message": ProviderError.managerMissing("brew").localizedDescription]
                        if let data = try? JSONSerialization.data(withJSONObject: out), let str = String(data: data, encoding: .utf8) { print(str) }
                        box.code = 1
                        semaphore.signal()
                        return
                    }
                    let scanned = AppScanService.scanInstalledApplications()
                    let matchedPath: String? = {
                        let candidates = CaskToken.candidateTokens(for: token)
                        for app in scanned {
                            let appTokens = CaskToken.candidateTokens(for: app.name)
                            if !Set(candidates).isDisjoint(with: Set(appTokens)) { return app.path }
                            if CaskToken.normalizeAppName(app.name) == CaskToken.normalizeAppName(token) { return app.path }
                        }
                        return nil
                    }()
                    let item = UpdateItem(providerId: "apps", name: token, currentVersion: "?", kind: .app, externalId: matchedPath, caskToken: token)
                    do {
                        let result = try await CaskInstaller.update(item: item, brewPath: brewPath)
                        let out: [String: Any] = ["ok": result.ok, "message": result.message ?? ""]
                        if let data = try? JSONSerialization.data(withJSONObject: out), let str = String(data: data, encoding: .utf8) { print(str) }
                        box.code = result.ok ? 0 : 1
                        semaphore.signal()
                    } catch let error as ProviderError {
                        let out: [String: Any] = ["ok": false, "message": error.localizedDescription]
                        if let data = try? JSONSerialization.data(withJSONObject: out), let str = String(data: data, encoding: .utf8) { print(str) }
                        box.code = 1
                        semaphore.signal()
                    } catch {
                        let out: [String: Any] = ["ok": false, "message": error.localizedDescription]
                        if let data = try? JSONSerialization.data(withJSONObject: out), let str = String(data: data, encoding: .utf8) { print(str) }
                        box.code = 1
                        semaphore.signal()
                    }
                }
            }
            semaphore.wait()
            exit(box.code)
        } else if CommandLine.arguments.contains("--scan-fast") {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                Task {
                    await ScanMode.run(includeCask: false)
                    semaphore.signal()
                }
            }
            semaphore.wait()
            exit(0)
        } else if CommandLine.arguments.contains("--scan") {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                Task {
                    await ScanMode.run(includeCask: true)
                    semaphore.signal()
                }
            }
            semaphore.wait()
            exit(0)
        } else if CommandLine.arguments.contains("--inventory") {
            let semaphore = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                Task {
                    await InventoryMode.run()
                    semaphore.signal()
                }
            }
            semaphore.wait()
            exit(0)
        } else {
            MainActor.assumeIsolated {
                upmacApp.main()
            }
        }
    }
}

struct upmacApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @Environment(\.openWindow) private var openWindow

    private static let menuBarIcon: NSImage? = {
        let bundlePath = Bundle.main.path(forResource: "menuicon-template@2x", ofType: "png")
            ?? Bundle.main.path(forResource: "menuicon-template@1x", ofType: "png")
        guard let path = bundlePath,
              let img = NSImage(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarBubbleView(appState: appState)
                .preferredColorScheme(appearanceManager.appearance.colorScheme)
        } label: {
            HStack(spacing: 5) {
                if let img = Self.menuBarIcon {
                    Image(nsImage: img)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                if appState.remainingCount > 0 {
                    Text("\(appState.remainingCount)")
                        .font(.system(.body, design: .rounded))
                }
            }
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Macsoft X", id: "main") {
            CockpitView(appState: appState)
                .frame(minWidth: 880, minHeight: 520)
                .preferredColorScheme(appearanceManager.appearance.colorScheme)
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    WindowManager.openOrFocusSettingsWindow(openWindow: openWindow)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("打开主窗") {
                    WindowManager.openOrFocusMainWindow(openWindow: openWindow)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .appTermination) {
                Button("退出 Macsoft X") {
                    requestQuit(appState: appState)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Window("详情", id: "detail") {
            DetailFloatingView(appState: appState)
                .preferredColorScheme(appearanceManager.appearance.colorScheme)
        }
        .windowResizability(.contentSize)

        Window("设置", id: "settings") {
            SettingsView()
                .preferredColorScheme(appearanceManager.appearance.colorScheme)
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
    }
}

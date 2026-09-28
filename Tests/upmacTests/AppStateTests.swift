import XCTest
@testable import upmac

final class AppStateTests: XCTestCase {

    private final class MockCustomProvider: UpdateProvider, @unchecked Sendable {
        let id: String
        let displayName: String
        let shouldFailUpdate: Bool
        let mockItems: [UpdateItem]

        init(
            id: String,
            displayName: String,
            shouldFailUpdate: Bool = false,
            mockItems: [UpdateItem]? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.shouldFailUpdate = shouldFailUpdate
            self.mockItems = mockItems ?? [
                UpdateItem(
                    providerId: id,
                    name: "test-pkg",
                    currentVersion: "1.0.0",
                    latestVersion: "1.1.0",
                    kind: .formula
                )
            ]
        }

        func isAvailable() async -> Bool { true }

        func fetchOutdated() async throws -> [UpdateItem] {
            mockItems
        }

        func update(_ item: UpdateItem) async throws -> UpdateResult {
            if shouldFailUpdate {
                return UpdateResult(ok: false, newVersion: nil, message: "Error: permission denied (tail)")
            } else {
                return UpdateResult(ok: true, newVersion: item.latestVersion ?? "1.1.0", message: nil)
            }
        }
    }

    @MainActor
    func testUpdateSuccessStateFlow() async {
        let provider = MockCustomProvider(id: "custom", displayName: "Custom")
        let appState = AppState(providers: [provider])

        let item = UpdateItem(
            providerId: "custom",
            name: "test-pkg",
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            kind: .formula
        )

        // 初始状态为 nil (等价于 .idle)
        XCTAssertNil(appState.updateStatuses[item.id])

        // 执行更新
        let result = await appState.update(item)
        XCTAssertTrue(result.ok)

        // 状态转为 .success
        XCTAssertEqual(appState.updateStatuses[item.id], .success(newVersion: "1.1.0"))
    }

    @MainActor
    func testUpdateFailureStateFlow() async {
        let provider = MockCustomProvider(id: "custom-fail", displayName: "Custom Fail", shouldFailUpdate: true)
        let appState = AppState(providers: [provider])

        let item = UpdateItem(
            providerId: "custom-fail",
            name: "test-pkg",
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            kind: .formula
        )

        let result = await appState.update(item)
        XCTAssertFalse(result.ok)

        // 状态转为 .failure 携带错误文案
        XCTAssertEqual(appState.updateStatuses[item.id], .failure(message: "Error: permission denied (tail)"))
    }

    @MainActor
    func testUpdateMissingProviderFails() async {
        let appState = AppState(providers: [])
        let item = UpdateItem(
            providerId: "nonexistent",
            name: "test-pkg",
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            kind: .formula
        )

        let result = await appState.update(item)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(appState.updateStatuses[item.id], .failure(message: "Provider not found for id: nonexistent"))
    }

    // MARK: - 迭代 1.5 新增功能测试

    @MainActor
    func testUpdateAllSkipsSudoAndLoginItems() async {
        let items = [
            UpdateItem(
                providerId: "custom",
                name: "normal-pkg",
                currentVersion: "1.0.0",
                latestVersion: "1.1.0",
                kind: .formula,
                needsSudo: false,
                requiresLogin: false
            ),
            UpdateItem(
                providerId: "custom",
                name: "sudo-pkg",
                currentVersion: "1.0.0",
                latestVersion: "1.1.0",
                kind: .cli,
                needsSudo: true,
                requiresLogin: false
            ),
            UpdateItem(
                providerId: "custom",
                name: "login-pkg",
                currentVersion: "1.0.0",
                latestVersion: "1.1.0",
                kind: .mas,
                needsSudo: false,
                requiresLogin: true
            )
        ]

        let provider = MockCustomProvider(id: "custom", displayName: "Custom", mockItems: items)
        let appState = AppState(providers: [provider])
        appState.items = items

        let results = await appState.updateAll()

        // 仅 normal-pkg 执行了更新
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results["custom:normal-pkg"]?.ok, true)
        XCTAssertEqual(appState.updateStatuses["custom:normal-pkg"], .success(newVersion: "1.1.0"))

        // sudo 与 login 项被严格规避，未被更新
        XCTAssertNil(appState.updateStatuses["custom:sudo-pkg"])
        XCTAssertNil(appState.updateStatuses["custom:login-pkg"])
    }

    @MainActor
    func testRemainingCountAndEcosystemBreakdown() async {
        let items = [
            UpdateItem(providerId: "brew", name: "git", currentVersion: "2.43.0", latestVersion: "2.44.0", kind: .formula),
            UpdateItem(providerId: "brew", name: "node", currentVersion: "20.11.0", latestVersion: "21.6.2", kind: .formula),
            UpdateItem(providerId: "mas", name: "Xcode", currentVersion: "15.2", latestVersion: "15.3", kind: .mas)
        ]

        let brewProvider = MockCustomProvider(id: "brew", displayName: "Homebrew", mockItems: [items[0], items[1]])
        let masProvider = MockCustomProvider(id: "mas", displayName: "Mac App Store", mockItems: [items[2]])
        let appState = AppState(providers: [brewProvider, masProvider])
        appState.items = items

        // 初始剩余总数应为 3
        XCTAssertEqual(appState.remainingCount, 3)
        XCTAssertEqual(appState.ecosystemBreakdown.count, 2)
        XCTAssertEqual(appState.ecosystemBreakdown.first(where: { $0.providerId == "brew" })?.count, 2)
        XCTAssertEqual(appState.ecosystemBreakdown.first(where: { $0.providerId == "mas" })?.count, 1)

        // 模拟一项更新成功
        _ = await appState.update(items[0])

        // 剩余总数降为 2，brew 分布降为 1
        XCTAssertEqual(appState.remainingCount, 2)
        XCTAssertEqual(appState.ecosystemBreakdown.first(where: { $0.providerId == "brew" })?.count, 1)
        XCTAssertEqual(appState.ecosystemBreakdown.first(where: { $0.providerId == "mas" })?.count, 1)
    }

    @MainActor
    func testLastScanDateIsRecordedOnReload() async {
        let provider = MockCustomProvider(id: "custom", displayName: "Custom")
        let appState = AppState(providers: [provider])

        XCTAssertNil(appState.lastScanDate)

        await appState.reloadAll()

        XCTAssertNotNil(appState.lastScanDate)
    }

    // MARK: - 修复 BUG B：handoff 状态诚实性 & updateAll 跳过打开类

    @MainActor
    func testUpdateAllSkipsAppsWithoutCaskToken() async {
        let caskItem = UpdateItem(
            providerId: "apps",
            name: "CaskApp",
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            kind: .app,
            externalId: "/Applications/CaskApp.app",
            caskToken: "cask-app"
        )
        let openItemNoCask = UpdateItem(
            providerId: "apps",
            name: "ManualApp",
            currentVersion: "2.0.0",
            latestVersion: "2.1.0",
            kind: .app,
            externalId: "/Applications/ManualApp.app",
            caskToken: nil
        )
        let openItemEmptyCask = UpdateItem(
            providerId: "apps",
            name: "InfoURLApp",
            currentVersion: "3.0.0",
            latestVersion: "3.1.0",
            kind: .app,
            externalId: "/Applications/InfoURLApp.app",
            infoURL: "https://example.com/download",
            caskToken: ""
        )
        let provider = MockCustomProvider(id: "apps", displayName: "Apps", mockItems: [caskItem, openItemNoCask, openItemEmptyCask])
        let appState = AppState(providers: [provider])
        appState.items = [caskItem, openItemNoCask, openItemEmptyCask]

        let results = await appState.updateAll()

        // 仅 caskItem 被执行
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[caskItem.id])
        XCTAssertNil(results[openItemNoCask.id])
        XCTAssertNil(results[openItemEmptyCask.id])
        XCTAssertEqual(appState.updateStatuses[caskItem.id], .success(newVersion: "1.1.0"))
        XCTAssertNil(appState.updateStatuses[openItemNoCask.id])
        XCTAssertNil(appState.updateStatuses[openItemEmptyCask.id])
        // 进度总数应为实际执行数 1
        XCTAssertEqual(appState.manualFallbackCount, 2)
        // updateAllProgress 在完成后应被清理为 nil（验证不崩溃即可）
        XCTAssertNil(appState.updateAllProgress)
    }

    @MainActor
    func testUpdateHandoffSetsHandoffStatus() async {
        final class HandoffMockProvider: UpdateProvider, @unchecked Sendable {
            let id = "apps"
            let displayName = "Apps"
            func isAvailable() async -> Bool { true }
            func fetchOutdated() async throws -> [UpdateItem] { [] }
            func update(_ item: UpdateItem) async throws -> UpdateResult {
                UpdateResult(ok: true, newVersion: item.latestVersion, message: "已打开下载页", autoUpdated: false)
            }
        }
        let provider = HandoffMockProvider()
        let appState = AppState(providers: [provider])
        let item = UpdateItem(
            providerId: "apps",
            name: "ManualApp",
            currentVersion: "2.0.0",
            latestVersion: "2.1.0",
            kind: .app,
            externalId: "/Applications/ManualApp.app"
        )
        let result = await appState.update(item)
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.autoUpdated, false)
        XCTAssertEqual(appState.updateStatuses[item.id], .handoff(message: "已打开下载页"))

        // 验证默认 message 回退为 "已打开应用"
        final class HandoffNilMessageProvider: UpdateProvider, @unchecked Sendable {
            let id = "apps2"
            let displayName = "Apps2"
            func isAvailable() async -> Bool { true }
            func fetchOutdated() async throws -> [UpdateItem] { [] }
            func update(_ item: UpdateItem) async throws -> UpdateResult {
                UpdateResult(ok: true, newVersion: item.latestVersion, message: nil, autoUpdated: false)
            }
        }
        let provider2 = HandoffNilMessageProvider()
        let appState2 = AppState(providers: [provider2])
        let item2 = UpdateItem(
            providerId: "apps2",
            name: "ManualApp2",
            currentVersion: "1.0",
            latestVersion: "2.0",
            kind: .app,
            externalId: "/Applications/ManualApp2.app"
        )
        let result2 = await appState2.update(item2)
        XCTAssertEqual(appState2.updateStatuses[item2.id], .handoff(message: "已打开应用"))
        _ = result2
    }

    @MainActor
    func testHandoffItemsExcludedFromPendingItems() async {
        let handoffItem = UpdateItem(
            providerId: "apps",
            name: "ManualApp",
            currentVersion: "2.0.0",
            latestVersion: "2.1.0",
            kind: .app,
            externalId: "/Applications/ManualApp.app",
            caskToken: nil
        )
        let brewItem = UpdateItem(providerId: "brew", name: "git", currentVersion: "2.43.0", latestVersion: "2.44.0", kind: .formula)
        let appState = AppState(providers: [])
        appState.items = [handoffItem, brewItem]
        appState.updateStatuses[handoffItem.id] = .handoff(message: "已打开应用")
        // handoff 已移交处理，不计入待更新
        XCTAssertFalse(appState.pendingItems.contains(where: { $0.id == handoffItem.id }))
        XCTAssertTrue(appState.pendingItems.contains(where: { $0.id == brewItem.id }))
        XCTAssertEqual(appState.remainingCount, 1)
        XCTAssertEqual(appState.pendingItems.count, 1)
        // manualFallbackCount 同步排除已 handoff 的项
        XCTAssertEqual(appState.manualFallbackCount, 0)
        // 切换为 success 同样排除，保证口径一致
        appState.updateStatuses[handoffItem.id] = .success(newVersion: "2.1.0")
        XCTAssertFalse(appState.pendingItems.contains(where: { $0.id == handoffItem.id }))
    }
}

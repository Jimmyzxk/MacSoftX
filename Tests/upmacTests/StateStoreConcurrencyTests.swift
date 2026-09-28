import XCTest
@testable import upmac
import Foundation

final class StateStoreConcurrencyTests: XCTestCase {
    func testConcurrentUpdatesNotLosingData() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("upmac_test_state_\(UUID().uuidString).json").path
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let count = 20
        for i in 0..<count {
            group.enter()
            queue.async {
                StateStore.update(at: tmp) { dict in
                    dict["key\(i)"] = "value\(i)"
                    // also preserve caskCache pattern?
                    var cc = dict["caskCache"] as? [String: Any] ?? [:]
                    cc["k\(i)"] = i
                    dict["caskCache"] = cc
                }
                group.leave()
            }
        }
        // concurrent mixed with ignoreRules pattern
        for i in 0..<5 {
            group.enter()
            queue.async {
                StateStore.update(at: tmp) { dict in
                    var settings = dict["settings"] as? [String: Any] ?? [:]
                    settings["interval\(i)"] = i
                    dict["settings"] = settings
                }
                group.leave()
            }
        }
        group.wait()
        let final = StateStore.read(at: tmp)
        // 验证 20 个 key 都存在
        for i in 0..<count {
            XCTAssertEqual(final["key\(i)"] as? String, "value\(i)", "lost key\(i)")
        }
        let cc = final["caskCache"] as? [String: Any]
        XCTAssertNotNil(cc)
        XCTAssertEqual(cc?.count, 20)
        print("StateStore concurrent test passed: \(final.count) keys")
    }

    @MainActor
    func testUpdateReentrancyGuard() async {
        final class SleepingProvider: UpdateProvider, @unchecked Sendable {
            let id = "sleepy"
            let displayName = "Sleepy"
            func isAvailable() async -> Bool { true }
            func fetchOutdated() async throws -> [UpdateItem] { [] }
            func update(_ item: UpdateItem) async throws -> UpdateResult {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                return UpdateResult(ok: true, newVersion: "2.0", message: nil)
            }
        }
        let provider = SleepingProvider()
        let state = AppState(providers: [provider])
        let item = UpdateItem(providerId: "sleepy", name: "pkg", currentVersion: "1.0", latestVersion: "2.0", kind: .formula)
        // 并发两次 update
        async let r1 = state.update(item)
        // 稍微延迟让第一次进入 updating
        try? await Task.sleep(nanoseconds: 50_000_000)
        let r2 = await state.update(item)
        let res1 = await r1
        XCTAssertTrue(res1.ok)
        XCTAssertEqual(r2.ok, false)
        XCTAssertEqual(r2.message, "更新已在进行中")
        XCTAssertEqual(state.updateStatuses[item.id], .success(newVersion: "2.0"))
        print("Reentrancy test passed: r2.message=\(r2.message ?? "")")
    }
}

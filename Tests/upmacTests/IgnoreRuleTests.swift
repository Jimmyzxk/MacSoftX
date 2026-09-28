import XCTest
@testable import upmac

final class IgnoreRuleTests: XCTestCase {

    func testCodableRoundTrip() throws {
        let rule = IgnoreRule(providerId: "brew", name: "git", scope: .forever, until: nil, createdAt: Date(timeIntervalSince1970: 1000))
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(IgnoreRule.self, from: data)
        XCTAssertEqual(decoded, rule)
        let untilDate = Date(timeIntervalSinceNow: 86400)
        let rule2 = IgnoreRule(providerId: "npm", name: "corepack", scope: .until, until: untilDate, createdAt: Date())
        let data2 = try JSONEncoder().encode(rule2)
        let decoded2 = try JSONDecoder().decode(IgnoreRule.self, from: data2)
        XCTAssertEqual(decoded2.providerId, "npm")
        XCTAssertEqual(decoded2.scope, .until)
    }

    func testForeverFilter() {
        let item = UpdateItem(providerId: "brew", name: "git", currentVersion: "1.0", kind: .formula)
        let rule = IgnoreRule(providerId: "brew", name: "git", scope: .forever, createdAt: Date())
        XCTAssertTrue(IgnoreRuleFilter.isIgnored(item: item, rules: [rule]))
        let filtered = IgnoreRuleFilter.filterIgnored(items: [item], rules: [rule], skippedOnce: Set())
        XCTAssertTrue(filtered.isEmpty)
    }

    func testUntilNotExpired() {
        let item = UpdateItem(providerId: "mas", name: "Xcode", currentVersion: "1.0", kind: .mas)
        let future = Date(timeIntervalSinceNow: 3600)
        let rule = IgnoreRule(providerId: "mas", name: "Xcode", scope: .until, until: future, createdAt: Date())
        XCTAssertTrue(IgnoreRuleFilter.isIgnored(item: item, rules: [rule]))
    }

    func testUntilExpired() {
        let item = UpdateItem(providerId: "mas", name: "Xcode", currentVersion: "1.0", kind: .mas)
        let past = Date(timeIntervalSinceNow: -3600)
        let rule = IgnoreRule(providerId: "mas", name: "Xcode", scope: .until, until: past, createdAt: Date(timeIntervalSinceNow: -7200))
        XCTAssertFalse(IgnoreRuleFilter.isIgnored(item: item, rules: [rule]))
        let cleaned = IgnoreRuleFilter.cleaned(rules: [rule])
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testSkipOnce() {
        let item = UpdateItem(providerId: "npm", name: "corepack", currentVersion: "0.35", kind: .cli)
        let filtered = IgnoreRuleFilter.filterIgnored(items: [item], rules: [], skippedOnce: Set([item.id]))
        XCTAssertTrue(filtered.isEmpty)
        // 再次过滤不带 skippedOnce 则出现
        let filtered2 = IgnoreRuleFilter.filterIgnored(items: [item], rules: [], skippedOnce: Set())
        XCTAssertEqual(filtered2.count, 1)
    }

    func testExpiredAutoClean() {
        let futureRule = IgnoreRule(providerId: "brew", name: "a", scope: .until, until: Date(timeIntervalSinceNow: 3600), createdAt: Date())
        let pastRule = IgnoreRule(providerId: "brew", name: "b", scope: .until, until: Date(timeIntervalSinceNow: -10), createdAt: Date())
        let forever = IgnoreRule(providerId: "brew", name: "c", scope: .forever, createdAt: Date())
        let cleaned = IgnoreRuleFilter.cleaned(rules: [futureRule, pastRule, forever])
        XCTAssertEqual(Set(cleaned.map { $0.name }), ["a", "c"])
    }
}

final class NotificationSnapshotTests: XCTestCase {
    func testEmptyToHasShouldNotify() {
        XCTAssertTrue(NotificationSnapshot.shouldNotify(previous: nil, current: ["a", "b"]))
    }
    func testHasToSameShouldNotNotify() {
        let set: Set<String> = ["a", "b"]
        XCTAssertFalse(NotificationSnapshot.shouldNotify(previous: set, current: set))
    }
    func testHasToChangedShouldNotify() {
        // 新增场景
        XCTAssertTrue(NotificationSnapshot.shouldNotify(previous: ["a", "b"], current: ["a", "c"]))
        XCTAssertTrue(NotificationSnapshot.shouldNotify(previous: ["a"], current: ["a", "b"]))
    }
    func testPureDecreaseShouldNotNotify() {
        // 纯减少（无新增）不应通知
        XCTAssertFalse(NotificationSnapshot.shouldNotify(previous: ["a", "b", "c"], current: ["a", "b"]))
        XCTAssertFalse(NotificationSnapshot.shouldNotify(previous: ["a", "b"], current: ["a"]))
    }
    func testHasToEmptyShouldNotNotify() {
        XCTAssertFalse(NotificationSnapshot.shouldNotify(previous: ["a", "b"], current: []))
    }
    func testEmptyToEmptyNoNotify() {
        XCTAssertFalse(NotificationSnapshot.shouldNotify(previous: Set(), current: []))
    }
}

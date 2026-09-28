import XCTest
@testable import upmac

final class ShellRunnerTests: XCTestCase {
    // 1. /bin/echo 输出断言
    func testEchoOutput() async throws {
        let result = try await ShellRunner.run("/bin/echo", arguments: ["hello", "world"], timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
    }

    // 2. /usr/bin/false 断言 exitCode != 0
    func testFalseExitCode() async throws {
        let result = try await ShellRunner.run("/usr/bin/false", arguments: [], timeout: 5)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    // 3. 不存在路径断言抛 managerMissing
    func testNonExistentPathThrowsManagerMissing() async {
        let nonexistentPath = "/path/to/nonexistent/executable_\(UUID().uuidString)"
        do {
            _ = try await ShellRunner.run(nonexistentPath, arguments: [], timeout: 5)
            XCTFail("Expected managerMissing error to be thrown")
        } catch let error as ProviderError {
            switch error {
            case .managerMissing(let path):
                XCTAssertEqual(path, nonexistentPath)
            default:
                XCTFail("Expected .managerMissing, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }
    }

    // 4. /bin/sleep 5 配 0.5s 超时断言抛 timedOut
    func testSleepTimeoutThrowsTimedOut() async {
        do {
            _ = try await ShellRunner.run("/bin/sleep", arguments: ["5"], timeout: 0.5)
            XCTFail("Expected timedOut error to be thrown")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Expected ProviderError.timedOut, got \(error)")
        }
    }

    // 5. UpdateItem Codable 编解码往返测试
    func testUpdateItemCodableRoundTrip() throws {
        let original = UpdateItem(
            providerId: "brew",
            name: "wireshark-chmodbpf",
            currentVersion: "4.2.0",
            latestVersion: "4.2.2",
            kind: .cli,
            needsSudo: true,
            requiresLogin: false
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UpdateItem.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.providerId, "brew")
        XCTAssertEqual(decoded.name, "wireshark-chmodbpf")
        XCTAssertEqual(decoded.currentVersion, "4.2.0")
        XCTAssertEqual(decoded.latestVersion, "4.2.2")
        XCTAssertEqual(decoded.kind, .cli)
        XCTAssertTrue(decoded.needsSudo)
        XCTAssertFalse(decoded.requiresLogin)
    }

    // 6. MockBrewProvider 可用性与数据获取测试
    func testMockBrewProvider() async throws {
        let mock = MockBrewProvider()
        let isAvail = await mock.isAvailable()
        XCTAssertTrue(isAvail)
        let items = try await mock.fetchOutdated()
        XCTAssertEqual(items.count, 4)
        let result = try await mock.update(items[0])
        XCTAssertTrue(result.ok)
    }

    // 7. GUI 窄 PATH 修复：resolvedUserPATH 必须包含常见 bin 目录（不依赖 node 是否存在）
    func testResolvedUserPATHContainsCommonBinDir() {
        let path = ShellRunner.resolvedUserPATH()
        let hasCommon = path.contains("/opt/homebrew/bin")
            || path.contains("/usr/local/bin")
            || path.contains("/usr/bin")
        XCTAssertTrue(hasCommon, "resolvedUserPATH should contain at least one common bin dir, got: \(path)")
        // 缓存一致性
        let second = ShellRunner.resolvedUserPATH()
        XCTAssertEqual(path, second, "resolvedUserPATH should be cached")
    }

    // 8. GUI 窄 PATH 修复：子进程可见注入后的 PATH（即使父进程 PATH 窄，ShellRunner 仍注入）
    func testShellRunnerInjectsResolvedPATHIntoChild() async throws {
        let result = try await ShellRunner.run("/bin/sh", arguments: ["-c", "echo $PATH"], timeout: 5)
        XCTAssertEqual(result.exitCode, 0)
        let childPATH = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCommon = childPATH.contains("/opt/homebrew/bin")
            || childPATH.contains("/usr/local/bin")
        XCTAssertTrue(hasCommon, "child PATH should contain injected common bin dir via ShellRunner, got: \(childPATH)")
    }

    // 9. 压测：30 并发 sleep 0.5 验证不打满协作线程池（Bug B 根治验证，阈值宽松防 CI 抖动）
    func testConcurrentSleep30NoThreadStarvation() async throws {
        let start = Date()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<30 {
                group.addTask {
                    _ = try await ShellRunner.run("/bin/sleep", arguments: ["0.5"], timeout: 5)
                }
            }
            for try await _ in group {}
        }
        let elapsed = Date().timeIntervalSince(start)
        // 30 * 0.5 并发理想耗时 ~0.5s，串行/线程池耗尽则 > 2s；阈值 2.0s 宽松防 CI 抖动，显著低于串行 15s
        XCTAssertLessThan(elapsed, 2.0, "30 concurrent sleep 0.5 elapsed \(elapsed)s exceeds 2.0s — thread pool still blocking")
    }
}

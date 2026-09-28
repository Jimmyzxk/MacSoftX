import XCTest
@testable import upmac
import Foundation

final class StateStoreRecoveryTests: XCTestCase {

    /// 测试当 state.json 损坏时，原损坏文件被重命名为 .corrupt-*，且通过 .bak 回退恢复历史数据，新 key 也成功写入
    func testCorruptedStateIsBackedUpNotSilentlyLost() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("statestore_recovery_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let statePath = tempDir.appendingPathComponent("state.json").path

        // 1. update(at:) 写入含多个 key 的 state.json
        StateStore.update(at: statePath) { dict in
            dict["key1"] = "value1"
            dict["key2"] = "value2"
            dict["settings"] = ["autoCheck": true]
        }

        // 2. 把文件内容改成非法 JSON
        let corruptedRaw = "{ invalid json content, broken syntax ... "
        try corruptedRaw.write(toFile: statePath, atomically: true, encoding: .utf8)

        // 3. update(at:) 写新 key
        StateStore.update(at: statePath) { dict in
            dict["newKey"] = "newValue"
        }

        // 4. 断言 (a): 目录内存在至少一个 state.json.corrupt-* 文件
        let files = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        let corruptFiles = files.filter { $0.hasPrefix("state.json.corrupt-") }
        XCTAssertFalse(corruptFiles.isEmpty, "目录内应存在至少一个 state.json.corrupt-* 文件，当前文件列表: \(files)")

        // 断言 (b): 原 key 中至少一个仍存在于更新后结果（.bak 回退恢复）
        let finalState = StateStore.read(at: statePath)
        XCTAssertEqual(finalState["key1"] as? String, "value1", "原 key1 应当通过 .bak 回退恢复")
        XCTAssertEqual(finalState["key2"] as? String, "value2", "原 key2 应当通过 .bak 回退恢复")

        // 断言 (c): 新 key 存在
        XCTAssertEqual(finalState["newKey"] as? String, "newValue", "新写入的 key 必须存在")
    }

    /// 测试主文件解析失败时，read(at:) 能够自动回退读取 .bak 内容而非返回空字典
    func testBackupFallbackOnReadFailure() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("statestore_fallback_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let statePath = tempDir.appendingPathComponent("state.json").path

        // 写 state.json 并触发一次 update 生成 .bak
        StateStore.update(at: statePath) { dict in
            dict["savedKey"] = "savedValue"
            dict["checkInterval"] = 3600
        }

        let bakPath = statePath + ".bak"
        XCTAssertTrue(FileManager.default.fileExists(atPath: bakPath), "应当生成 state.json.bak 备份文件")

        // 主文件改成非法 JSON
        let badContent = "NOT_A_VALID_JSON_AT_ALL"
        try badContent.write(toFile: statePath, atomically: true, encoding: .utf8)

        // 设置 lastWriteError 以验证 read() 成功回退后是否将其清空
        StateStore.lastWriteError = "先前的写入错误提示"

        // 断言 read(at:) 返回 .bak 内容而非空字典
        let readResult = StateStore.read(at: statePath)
        XCTAssertFalse(readResult.isEmpty, "主文件解析失败时 read(at:) 应回退到 .bak，不应返回空字典")
        XCTAssertEqual(readResult["savedKey"] as? String, "savedValue")
        XCTAssertEqual(readResult["checkInterval"] as? Int, 3600)
        XCTAssertNil(StateStore.lastWriteError, "read() 成功读取后应清空 lastWriteError")
    }

    /// 测试写入后文件权限严格收紧为 0o600
    func testFilePermissionsAreRestrictive() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("statestore_perms_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let statePath = tempDir.appendingPathComponent("state.json").path

        StateStore.update(at: statePath) { dict in
            dict["secretData"] = "protected"
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: statePath)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertNotNil(perms, "无法获取 state.json 文件权限")
        XCTAssertEqual(perms?.intValue, 0o600, "state.json 权限应为 0o600 (实际: \(String(format: "%o", perms?.intValue ?? 0)))")
    }
}

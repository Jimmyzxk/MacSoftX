import Foundation

/// state.json 唯一读写入口，解决并发竞态。
/// 内部 NSLock 保证 read→mutate→write 原子性。
public final class StateStore: @unchecked Sendable {
    public static let shared = StateStore()
    private let lock = NSLock()
    private var _lastWriteError: String?
    private init() {}

    /// 最近一次写入操作的错误描述；read() 成功时清空为 nil
    public static var lastWriteError: String? {
        get {
            let store = shared
            store.lock.lock()
            defer { store.lock.unlock() }
            return store._lastWriteError
        }
        set {
            let store = shared
            store.lock.lock()
            defer { store.lock.unlock() }
            store._lastWriteError = newValue
        }
    }

    private static var defaultStatePath: String {
        AppScanService.defaultStatePath
    }

    /// 锁内原子更新：读文件→JSON 解析→mutate→原子写回
    public static func update(_ mutate: (inout [String: Any]) -> Void) {
        update(at: defaultStatePath, mutate)
    }

    /// 锁内读快照
    public static func read() -> [String: Any] {
        read(at: defaultStatePath)
    }

    // MARK: - 测试辅助：指定路径的重载（供单测并发验证）

    public static func update(at path: String, _ mutate: (inout [String: Any]) -> Void) {
        let store = shared
        store.lock.lock()
        defer { store.lock.unlock() }
        store.performUpdate(at: path, mutate)
    }

    public static func read(at path: String) -> [String: Any] {
        let store = shared
        store.lock.lock()
        defer { store.lock.unlock() }
        return store.performRead(at: path)
    }

    // MARK: - 私有 helper（调用方必须已持锁，严禁在此调用 public 方法以防死锁）

    private func performRead(at path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        if let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            _lastWriteError = nil
            return json
        }

        // 主文件解析失败，回退读 .bak
        let bakPath = "\(path).bak"
        let bakUrl = URL(fileURLWithPath: bakPath)
        if let bakData = try? Data(contentsOf: bakUrl),
           let bakJson = try? JSONSerialization.jsonObject(with: bakData) as? [String: Any] {
            _lastWriteError = nil
            return bakJson
        }

        return [:]
    }

    private func performUpdate(at path: String, _ mutate: (inout [String: Any]) -> Void) {
        let url = URL(fileURLWithPath: path)
        let bakPath = "\(path).bak"
        let bakUrl = URL(fileURLWithPath: bakPath)

        var parsedDict: [String: Any]? = nil

        // 1. 尝试读主文件；若存在但解析失败，重命名为 .corrupt-<ISO8601> 保留
        if FileManager.default.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                parsedDict = json
            } else {
                let timestamp = ISO8601DateFormatter().string(from: Date())
                let corruptPath = "\(path).corrupt-\(timestamp)"
                let corruptUrl = URL(fileURLWithPath: corruptPath)
                if FileManager.default.fileExists(atPath: corruptPath) {
                    try? FileManager.default.removeItem(at: corruptUrl)
                }
                try? FileManager.default.moveItem(at: url, to: corruptUrl)
            }
        }

        // 2. 主文件不存在或解析失败时，回退读 .bak；若 .bak 也不可用则以空字典继续
        if parsedDict == nil {
            if let bakData = try? Data(contentsOf: bakUrl),
               let bakJson = try? JSONSerialization.jsonObject(with: bakData) as? [String: Any] {
                parsedDict = bakJson
            } else {
                parsedDict = [:]
            }
        }

        var dict = parsedDict ?? [:]
        mutate(&dict)

        // 3. 确保目录存在，设置目录权限 0o700
        let dirUrl = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dirUrl, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o700)], ofItemAtPath: dirUrl.path)
        } catch {
            _lastWriteError = "创建状态目录失败: \(error.localizedDescription)"
            return
        }

        // 4. JSON 序列化并原子写入主文件，设置权限 0o600
        guard let out = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            _lastWriteError = "序列化状态 JSON 失败"
            return
        }

        do {
            try out.write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: url.path)
            _lastWriteError = nil
        } catch {
            _lastWriteError = "写入状态文件失败: \(error.localizedDescription)"
            return
        }

        // 5. 成功写入主文件后，复制到 .bak，并收紧权限 0o600
        if FileManager.default.fileExists(atPath: bakPath) {
            try? FileManager.default.removeItem(atPath: bakPath)
        }
        do {
            try FileManager.default.copyItem(atPath: url.path, toPath: bakPath)
            try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: bakPath)
        } catch {
            if (try? out.write(to: bakUrl, options: [.atomic])) != nil {
                try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: bakPath)
            }
        }
    }
}

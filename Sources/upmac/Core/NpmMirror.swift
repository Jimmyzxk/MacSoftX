import Foundation

/// npm 只读扫描的镜像加速器
///
/// 背景：用户全局 registry 通常是 https://registry.npmjs.org/，国内直连单次请求可达 10s+，
/// `npm outdated -g` 会按包逐个请求，一轮下来常超过 90 秒。这里为**只读扫描**临时指定可用镜像，
/// 不修改用户的 ~/.npmrc，也不影响 `update()` 实际安装时使用的源。
public enum NpmMirror: Sendable {

    /// 候选镜像，按国内可用性排序
    private static let candidates = [
        "https://registry.npmmirror.com",
        "https://mirrors.cloud.tencent.com/npm/",
        "https://registry.npmjs.org"
    ]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// 返回本次扫描应使用的 registry；探测失败时返回 nil（交回 npm 默认行为）
    public static var current: String? {
        cacheLock.lock()
        let hit = cached
        cacheLock.unlock()
        if let hit { return hit == candidates[candidates.count - 1] ? nil : hit }

        // 探测在锁外进行，避免并发扫描时互相阻塞
        let probed = Self.probe()
        cacheLock.lock()
        cached = probed ?? candidates[candidates.count - 1]
        cacheLock.unlock()
        return probed
    }

    /// 逐个候选做一次轻量 HEAD 请求，取首个在 1.5s 内响应的
    private static func probe() -> String? {
        let probePath = "https://registry.npmmirror.com/-/ping"
        var request = URLRequest(url: URL(string: probePath)!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                reachable = true
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2.0)

        if reachable { return candidates[0] }
        // 探测不可用时不强行指定，退回 npm 自带源（行为与改造前一致）
        return nil
    }

    /// 仅供测试重置缓存
    public static func resetCache() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }
}

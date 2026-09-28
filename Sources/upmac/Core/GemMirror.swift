import Foundation

/// gem 只读扫描的镜像加速器
///
/// 背景：用户 gem sources 通常直连 https://rubygems.org/，国内 `gem outdated` 逐包请求可累积到 90s+。
/// 与 `NpmMirror` 同构：仅为只读扫描临时指定镜像，不改用户的 gem sources 全局配置。
public enum GemMirror: Sendable {

    /// 国内 RubyGems 镜像，按实测可用性排序
    private static let candidates = [
        "https://mirrors.cloud.tencent.com/rubygems/",
        "https://mirrors.aliyun.com/rubygems/",
        "https://gems.ruby-china.com/"
    ]

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    /// 返回本次扫描应使用的 gem source；探测失败时返回 nil（交回 gem 默认行为）
    public static var current: String? {
        cacheLock.lock()
        let hit = cached
        cacheLock.unlock()
        if let hit { return hit == candidates[candidates.count - 1] ? nil : hit }

        let probed = Self.probe()
        cacheLock.lock()
        cached = probed ?? candidates[candidates.count - 1]
        cacheLock.unlock()
        return probed
    }

    /// 探测镜像根路径是否可达（部分镜像会对具体文件路径返回 403，根路径更稳定）
    private static func probe() -> String? {
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 1.5
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let semaphore = DispatchSemaphore(value: 0)
            var ok = false
            URLSession.shared.dataTask(with: request) { _, response, _ in
                // 403 同样代表"服务端可达"，只是拒绝了该路径，仍视为镜像在线
                if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                    ok = true
                }
                semaphore.signal()
            }.resume()
            if semaphore.wait(timeout: .now() + 2.0) == .success, ok {
                return candidate
            }
        }
        return nil
    }

    /// 仅供测试重置缓存
    public static func resetCache() {
        cacheLock.lock()
        cached = nil
        cacheLock.unlock()
    }
}

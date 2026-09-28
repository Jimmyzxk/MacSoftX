import Foundation
import AppKit

public final class AppIconFinder: @unchecked Sendable {
    public static let shared = AppIconFinder()

    private let lock = NSLock()
    private var pathToIconCache: [String: NSImage] = [:]
    private var nameToPathCache: [String: String] = [:]
    private var isIndexed = false

    public init() {}

    /// 规范化名字（小写、移除标点连字符、空格）便于模糊匹配
    public static func normalizeName(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    /// 建立应用名称与路径的索引表
    public func ensureIndexed() {
        lock.lock()
        defer { lock.unlock() }
        guard !isIndexed else { return }

        let apps = AppScanner.scanInstalledApplications()
        for app in apps {
            let directKey = app.name.lowercased()
            nameToPathCache[directKey] = app.path

            let normalizedKey = Self.normalizeName(app.name)
            nameToPathCache[normalizedKey] = app.path

            let fileStem = URL(fileURLWithPath: app.path).deletingPathExtension().lastPathComponent
            nameToPathCache[fileStem.lowercased()] = app.path
            nameToPathCache[Self.normalizeName(fileStem)] = app.path

            if let bId = app.bundleId?.lowercased() {
                nameToPathCache[bId] = app.path
            }
        }
        isIndexed = true
    }

    /// 根据软件名称与路径寻找本地真实安装的 .app 路径
    public func findPath(for name: String, externalId: String? = nil) -> String? {
        if let externalId = externalId, !externalId.isEmpty {
            if externalId.hasSuffix(".app") && FileManager.default.fileExists(atPath: externalId) {
                return externalId
            }
        }

        ensureIndexed()

        lock.lock()
        defer { lock.unlock() }

        // 1. 直查名称
        if let path = nameToPathCache[name.lowercased()] {
            return path
        }

        // 2. 规范化模糊查找（如 visual-studio-code 匹配 Visual Studio Code）
        let norm = Self.normalizeName(name)
        if let path = nameToPathCache[norm] {
            return path
        }

        // 3. 直查标准目录
        for base in ["/Applications/\(name).app", "\(NSHomeDirectory())/Applications/\(name).app"] {
            if FileManager.default.fileExists(atPath: base) {
                return base
            }
        }

        return nil
    }

    /// 获取文件真实图标（40x40 缓存）
    public func icon(forPath path: String) -> NSImage {
        lock.lock()
        if let cached = pathToIconCache[path] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 40, height: 40)

        lock.lock()
        pathToIconCache[path] = image
        lock.unlock()

        return image
    }

    /// 根据名称获取图标
    public func icon(forItemName name: String) -> NSImage? {
        if let path = findPath(for: name) {
            return icon(forPath: path)
        }
        return nil
    }
}

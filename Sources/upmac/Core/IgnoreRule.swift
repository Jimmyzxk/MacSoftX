import Foundation

public enum IgnoreScope: String, Codable, Sendable, Equatable {
    case forever
    case until
}

public struct IgnoreRule: Codable, Sendable, Equatable, Identifiable {
    public let providerId: String
    public let name: String
    public let scope: IgnoreScope
    public let until: Date?
    public let createdAt: Date

    public var id: String { "\(providerId):\(name)" }

    public init(providerId: String, name: String, scope: IgnoreScope, until: Date? = nil, createdAt: Date = Date()) {
        self.providerId = providerId
        self.name = name
        self.scope = scope
        self.until = until
        self.createdAt = createdAt
    }

    public var isExpired: Bool {
        guard scope == .until, let until = until else { return false }
        return Date() >= until
    }

    public func matches(item: UpdateItem) -> Bool {
        providerId == item.providerId && name == item.name
    }

    public func matches(inventoryItem: InventoryItem) -> Bool {
        // Inventory 已忽略页主要按 name 匹配，providerId 可能为 sourceId
        // 规则存的是 UpdateItem 的 providerId/name，Inventory 的匹配放宽到 name 相同即可？
        // 严格按 providerId+name 匹配，若 providerId 不一致（如 standalone）则按 name 匹配
        if providerId == inventoryItem.sourceId && name == inventoryItem.name { return true }
        // 兼容：规则 providerId 可能为 "apps"，inventory sourceId 为 "standalone" 等，按 name 匹配
        return name == inventoryItem.name
    }
}

// MARK: - 过滤与快照纯函数

public enum IgnoreRuleFilter {
    /// 是否被忽略（forever 命中 或 until 未过期命中）
    public static func isIgnored(item: UpdateItem, rules: [IgnoreRule]) -> Bool {
        for rule in rules {
            if rule.isExpired { continue }
            if rule.matches(item: item) { return true }
        }
        return false
    }

    /// 过滤已忽略项
    public static func filterIgnored(items: [UpdateItem], rules: [IgnoreRule], skippedOnce: Set<String>) -> [UpdateItem] {
        items.filter { item in
            if skippedOnce.contains(item.id) { return false }
            return !isIgnored(item: item, rules: rules)
        }
    }

    /// 过期自动清理
    public static func cleaned(rules: [IgnoreRule]) -> [IgnoreRule] {
        rules.filter { !$0.isExpired }
    }
}

public enum NotificationSnapshot {
    /// 是否应发通知：只有出现新增可更新项才通知
    public static func shouldNotify(previous: Set<String>?, current: Set<String>) -> Bool {
        guard !current.isEmpty else { return false }
        guard let prev = previous else { return true }
        return !current.subtracting(prev).isEmpty
    }
}

public enum VersionSpanCheckerExtended {
    // 已在 CaskVersionChecker.swift 定义 VersionSpanChecker，此处为别名测试辅助
}

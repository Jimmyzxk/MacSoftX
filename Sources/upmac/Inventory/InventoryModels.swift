import Foundation

public enum SoftwareKind: String, Codable, Sendable, CaseIterable {
    case app = "应用"
    case cli = "命令行"
}

public enum ManagementStatus: String, Codable, Sendable, CaseIterable {
    case managed = "受管"
    case unmanaged = "游离"
}

public struct InventoryItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let kind: SoftwareKind
    public let sourceId: String
    public let sourceDisplayName: String
    public let status: ManagementStatus
    public let bundleId: String?
    public let path: String?

    public init(
        id: String,
        name: String,
        version: String,
        kind: SoftwareKind,
        sourceId: String,
        sourceDisplayName: String,
        status: ManagementStatus,
        bundleId: String? = nil,
        path: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.kind = kind
        self.sourceId = sourceId
        self.sourceDisplayName = sourceDisplayName
        self.status = status
        self.bundleId = bundleId
        self.path = path
    }
}

public struct InventoryReport: Codable, Sendable {
    public let totalCount: Int
    public let appCount: Int
    public let cliCount: Int
    public let orphanCount: Int
    public let sourceStats: [String: Int]
    public let items: [InventoryItem]
    public let timestamp: String
    public let errors: [String: String]

    public init(
        totalCount: Int,
        appCount: Int,
        cliCount: Int,
        orphanCount: Int,
        sourceStats: [String: Int],
        items: [InventoryItem],
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        errors: [String: String] = [:]
    ) {
        self.totalCount = totalCount
        self.appCount = appCount
        self.cliCount = cliCount
        self.orphanCount = orphanCount
        self.sourceStats = sourceStats
        self.items = items
        self.timestamp = timestamp
        self.errors = errors
    }

    enum CodingKeys: String, CodingKey {
        case totalCount
        case appCount
        case cliCount
        case orphanCount
        case sourceStats
        case items
        case timestamp
        case errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalCount = try container.decode(Int.self, forKey: .totalCount)
        self.appCount = try container.decode(Int.self, forKey: .appCount)
        self.cliCount = try container.decode(Int.self, forKey: .cliCount)
        self.orphanCount = try container.decode(Int.self, forKey: .orphanCount)
        self.sourceStats = try container.decode([String: Int].self, forKey: .sourceStats)
        self.items = try container.decode([InventoryItem].self, forKey: .items)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp) ?? ""
        self.errors = try container.decodeIfPresent([String: String].self, forKey: .errors) ?? [:]
    }
}

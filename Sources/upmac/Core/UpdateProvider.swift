import Foundation

public protocol UpdateProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func isAvailable() async -> Bool
    func fetchOutdated() async throws -> [UpdateItem]
    func update(_ item: UpdateItem) async throws -> UpdateResult
}

public enum Kind: String, Codable, Sendable, CaseIterable, Equatable {
    case formula
    case cask
    case cli
    case mas
    case app
}

public struct UpdateItem: Identifiable, Codable, Sendable, Equatable {
    public let providerId: String
    public let name: String
    public let currentVersion: String
    public let latestVersion: String?
    public let kind: Kind
    public let needsSudo: Bool
    public let requiresLogin: Bool
    public let externalId: String?
    public let isSystemComponent: Bool
    public let infoURL: String?
    public let caskToken: String?

    public var id: String {
        "\(providerId):\(name)"
    }

    public init(
        providerId: String,
        name: String,
        currentVersion: String,
        latestVersion: String? = nil,
        kind: Kind,
        needsSudo: Bool = false,
        requiresLogin: Bool = false,
        externalId: String? = nil,
        isSystemComponent: Bool = false,
        infoURL: String? = nil,
        caskToken: String? = nil
    ) {
        self.providerId = providerId
        self.name = name
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.kind = kind
        self.needsSudo = needsSudo
        self.requiresLogin = requiresLogin
        self.externalId = externalId
        self.isSystemComponent = isSystemComponent
        self.infoURL = infoURL
        self.caskToken = caskToken
    }

    enum CodingKeys: String, CodingKey {
        case providerId, name, currentVersion, latestVersion, kind, needsSudo, requiresLogin, externalId, isSystemComponent, infoURL, caskToken
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerId = try container.decode(String.self, forKey: .providerId)
        name = try container.decode(String.self, forKey: .name)
        currentVersion = try container.decode(String.self, forKey: .currentVersion)
        latestVersion = try container.decodeIfPresent(String.self, forKey: .latestVersion)
        kind = try container.decode(Kind.self, forKey: .kind)
        needsSudo = try container.decodeIfPresent(Bool.self, forKey: .needsSudo) ?? false
        requiresLogin = try container.decodeIfPresent(Bool.self, forKey: .requiresLogin) ?? false
        externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        isSystemComponent = try container.decodeIfPresent(Bool.self, forKey: .isSystemComponent) ?? false
        infoURL = try container.decodeIfPresent(String.self, forKey: .infoURL)
        caskToken = try container.decodeIfPresent(String.self, forKey: .caskToken)
    }
}

public enum ProviderError: Error, Sendable, Equatable, LocalizedError {
    case managerMissing(String)
    case sudoRequired
    case loginRequired
    case timedOut
    case parsingFailed(String)

    /// 面向用户的中文文案（docs/08 §6.6 状态诚实性：不向用户抛技术黑话）
    public var errorDescription: String? {
        switch self {
        case .managerMissing(let path):
            return "未找到 \(Self.displayName(for: path))，请先安装后再试"
        case .sudoRequired:
            return "此更新需要管理员权限，请前往终端手动执行"
        case .loginRequired:
            return "此更新需要登录凭据，请先在对应工具中完成登录"
        case .timedOut:
            return "获取更新信息超时，请检查网络后重试"
        case .parsingFailed:
            return "解析返回结果失败，对应工具的输出格式可能已变化"
        }
    }

    /// 技术细节，供日志与调试，不直接展示给用户
    public var debugDescription: String {
        switch self {
        case .managerMissing(let path):
            return "Manager executable not found at path: \(path)"
        case .sudoRequired:
            return "Sudo privilege required"
        case .loginRequired:
            return "Login credentials required"
        case .timedOut:
            return "Operation timed out"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        }
    }

    private static func displayName(for path: String) -> String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "所需工具" : name
    }
}

public struct UpdateResult: Codable, Sendable, Equatable {
    public let ok: Bool
    public let newVersion: String?
    public let message: String?
    public let autoUpdated: Bool?

    public init(ok: Bool, newVersion: String? = nil, message: String? = nil, autoUpdated: Bool? = nil) {
        self.ok = ok
        self.newVersion = newVersion
        self.message = message
        self.autoUpdated = autoUpdated
    }
}

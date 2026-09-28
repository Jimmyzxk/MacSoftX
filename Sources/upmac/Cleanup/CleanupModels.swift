import Foundation

/// 散落文件类别
public enum ScatteredFileCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case app = "应用本体"
    case preferences = "偏好设置"
    case applicationSupport = "应用支持"
    case caches = "缓存文件"
    case savedState = "保存状态"
    case containers = "沙盒容器"
    case groupContainers = "共享容器"
    case logs = "运行日志"
    case launchAgents = "用户自启"
    case launchDaemons = "系统守护"
    case other = "其他"

    public var isSafeDefault: Bool {
        switch self {
        case .caches, .logs, .savedState:
            return true
        case .app, .preferences, .applicationSupport, .containers, .groupContainers, .launchAgents, .launchDaemons, .other:
            return false
        }
    }
}

/// 散落文件条目
public struct ScatteredFileItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let category: ScatteredFileCategory
    public let sizeInBytes: Int64
    public var isSelected: Bool

    public init(
        id: String = UUID().uuidString,
        path: String,
        name: String,
        category: ScatteredFileCategory,
        sizeInBytes: Int64,
        isSelected: Bool = true
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.category = category
        self.sizeInBytes = sizeInBytes
        self.isSelected = isSelected
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

/// 卸载方式
public enum UninstallMethod: Codable, Equatable, Sendable {
    case packageManager(executable: String, arguments: [String], provider: String)
    case fileTrash(appPath: String?)

    /// 供 UI 展示的只读命令字符串（绝不能用于底层 Process 执行）
    public var displayCommand: String {
        switch self {
        case .packageManager(let executable, let arguments, _):
            let formattedArgs = arguments.map { arg in
                arg.contains(" ") ? "\"\(arg)\"" : arg
            }.joined(separator: " ")
            return formattedArgs.isEmpty ? executable : "\(executable) \(formattedArgs)"
        case .fileTrash(let path):
            return path ?? ""
        }
    }
}

/// 卸载错误定义（遵循安全红线）
public enum UninstallError: LocalizedError, Equatable, Sendable {
    case appleSystemAppProtected(name: String, bundleId: String?)
    case packageManagerMissing(String)
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    case fileTrashFailed(path: String, reason: String)
    case nothingSelected

    public var errorDescription: String? {
        switch self {
        case .appleSystemAppProtected(let name, let id):
            return "安全红线保护：\(name) (\(id ?? "系统级")) 为 Apple 核心应用，禁止卸载。"
        case .packageManagerMissing(let tool):
            return "未检测到包管理器工具：\(tool)，无法执行卸载。"
        case .commandFailed(let cmd, let code, let err):
            return "卸载命令执行失败 [退出码 \(code)]：\(cmd)\n\(err)"
        case .fileTrashFailed(let path, let reason):
            return "移入废纸篓失败 (\(path))：\(reason)"
        case .nothingSelected:
            return "未选择任何清理项目。"
        }
    }
}

/// 卸载清理计划（可序列化，支持二次确认与自动化测试）
public struct UninstallPlan: Codable, Equatable, Sendable {
    public let targetItem: InventoryItem
    public let method: UninstallMethod
    public let appPath: String?
    public let appSizeInBytes: Int64
    public var files: [ScatteredFileItem]
    public let isAppleProtected: Bool
    public let warningMessage: String?

    public init(
        targetItem: InventoryItem,
        method: UninstallMethod,
        appPath: String?,
        appSizeInBytes: Int64,
        files: [ScatteredFileItem],
        isAppleProtected: Bool = false,
        warningMessage: String? = nil
    ) {
        self.targetItem = targetItem
        self.method = method
        self.appPath = appPath
        self.appSizeInBytes = appSizeInBytes
        self.files = files
        self.isAppleProtected = isAppleProtected
        self.warningMessage = warningMessage
    }

    public var selectedFilesCount: Int {
        files.filter { $0.isSelected }.count
    }

    public var totalSelectedSize: Int64 {
        files.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeInBytes }
    }

    public var formattedTotalSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSelectedSize, countStyle: .file)
    }

    public var hasScatteredFiles: Bool {
        files.contains { $0.category != .app }
    }
}

/// 卸载执行结果报告
public struct UninstallResult: Codable, Equatable, Sendable {
    public let targetName: String
    public let isSuccess: Bool
    public let trashedPaths: [String]
    public let failedPaths: [String: String]
    public let message: String?
    public let totalFreedBytes: Int64

    public init(
        targetName: String,
        isSuccess: Bool,
        trashedPaths: [String],
        failedPaths: [String: String] = [:],
        message: String? = nil,
        totalFreedBytes: Int64 = 0
    ) {
        self.targetName = targetName
        self.isSuccess = isSuccess
        self.trashedPaths = trashedPaths
        self.failedPaths = failedPaths
        self.message = message
        self.totalFreedBytes = totalFreedBytes
    }

    public var formattedFreedSize: String {
        ByteCountFormatter.string(fromByteCount: totalFreedBytes, countStyle: .file)
    }
}

/// 残留类别（安全类 vs 谨慎类）
public enum LeftoverCategory: String, Codable, Equatable, Sendable, CaseIterable {
    case safe = "安全类"      // Caches, Logs, SavedState
    case caution = "谨慎类"   // Preferences, ApplicationSupport, Containers, LaunchAgents

    public var isSafeDefault: Bool {
        self == .safe
    }

    public var subtitle: String {
        switch self {
        case .safe:
            return "临时缓存与日志，清理不影响数据，默认勾选"
        case .caution:
            return "偏好设置与数据目录，清理后将重置配置，需谨慎勾选"
        }
    }
}

/// 残留置信度分级（宁缺毋滥，严格区分确认残留与疑似残留）
public enum LeftoverConfidence: String, Codable, Equatable, Sendable, CaseIterable {
    case confirmed = "确认残留"
    case suspected = "疑似残留"
    case toConfirm = "待确认"
}

/// 孤儿残留条目
public struct LeftoverItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let name: String
    public let inferredAppName: String
    public let category: LeftoverCategory
    public let sizeInBytes: Int64
    public let modificationDate: Date?
    public var isSelected: Bool
    public let confidence: LeftoverConfidence
    public let inferenceReason: String?

    public init(
        id: String = UUID().uuidString,
        path: String,
        name: String,
        inferredAppName: String,
        category: LeftoverCategory,
        sizeInBytes: Int64,
        modificationDate: Date? = nil,
        isSelected: Bool? = nil,
        confidence: LeftoverConfidence = .confirmed,
        inferenceReason: String? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.inferredAppName = inferredAppName
        self.category = category
        self.sizeInBytes = sizeInBytes
        self.modificationDate = modificationDate
        self.confidence = confidence
        self.inferenceReason = inferenceReason
        if let customSelected = isSelected {
            self.isSelected = customSelected
        } else {
            // 只有明确"应用已卸载+名字强匹配"才默认勾选（安全类 Caches/Logs）
            self.isSelected = (confidence == .confirmed && category.isSafeDefault)
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, path, name, inferredAppName, category, sizeInBytes, modificationDate, isSelected, confidence, inferenceReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        inferredAppName = try container.decode(String.self, forKey: .inferredAppName)
        category = try container.decode(LeftoverCategory.self, forKey: .category)
        sizeInBytes = try container.decode(Int64.self, forKey: .sizeInBytes)
        modificationDate = try container.decodeIfPresent(Date.self, forKey: .modificationDate)
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        confidence = try container.decodeIfPresent(LeftoverConfidence.self, forKey: .confidence) ?? .confirmed
        inferenceReason = try container.decodeIfPresent(String.self, forKey: .inferenceReason)
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

/// 残留清理执行结果
public struct LeftoverCleanupResult: Codable, Equatable, Sendable {
    public let trashedCount: Int
    public let failedCount: Int
    public let totalFreedBytes: Int64
    public let trashedPaths: [String]
    public let errors: [String: String]

    public init(
        trashedCount: Int,
        failedCount: Int,
        totalFreedBytes: Int64,
        trashedPaths: [String],
        errors: [String: String] = [:]
    ) {
        self.trashedCount = trashedCount
        self.failedCount = failedCount
        self.totalFreedBytes = totalFreedBytes
        self.trashedPaths = trashedPaths
        self.errors = errors
    }

    public var formattedFreedSize: String {
        ByteCountFormatter.string(fromByteCount: totalFreedBytes, countStyle: .file)
    }
}

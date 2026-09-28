import SwiftUI
import AppKit

/// 外观模式定义（跟随系统 / 浅色 / 深色）
public enum AppAppearance: String, CaseIterable, Identifiable, Codable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 外观管理器：管理全局外观偏好，并持久化到 state.json settings.appearance
@MainActor
public final class AppearanceManager: ObservableObject {
    public static let shared = AppearanceManager()

    @Published public var appearance: AppAppearance = .system {
        didSet {
            persist()
        }
    }

    private init() {
        load()
    }

    public func load() {
        let json = StateStore.read()
        guard let settings = json["settings"] as? [String: Any],
              let appearanceRaw = settings["appearance"] as? String,
              let appAppearance = AppAppearance(rawValue: appearanceRaw) else {
            return
        }
        self.appearance = appAppearance
    }

    private func persist() {
        let current = appearance
        StateStore.update { dict in
            var settingsDict = (dict["settings"] as? [String: Any]) ?? [:]
            settingsDict["appearance"] = current.rawValue
            dict["settings"] = settingsDict
        }
    }
}

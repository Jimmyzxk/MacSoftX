import Foundation

public enum BrewPaths {
    /// brew 二进制候选探测路径列表（依次探测 Apple Silicon 与 Intel 默认安装位置）
    public static let brewCandidatePaths: [String] = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    /// mas 二进制候选探测路径列表（依次探测 Apple Silicon 与 Intel 默认安装位置）
    public static let masCandidatePaths: [String] = [
        "/opt/homebrew/bin/mas",
        "/usr/local/bin/mas"
    ]

    /// 探测可用的 brew 二进制路径，若不存在返回 nil
    public static func brewPath() -> String? {
        brewCandidatePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// 探测可用的 mas 二进制路径，若不存在返回 nil
    public static func masPath() -> String? {
        masCandidatePaths.first { FileManager.default.fileExists(atPath: $0) }
    }
}

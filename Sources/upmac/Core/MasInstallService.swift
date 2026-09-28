import Foundation
import AppKit

/// Mac App Store (mas) 命令行工具安装服务
@MainActor
public final class MasInstallService: ObservableObject {
    public static let shared = MasInstallService()

    @Published public var isInstalling: Bool = false
    @Published public var showConfirmDialog: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var successMessage: String? = nil
    @Published public var executionOutput: String? = nil

    private init() {}

    public func promptInstall() {
        showConfirmDialog = true
    }

    /// 执行 brew install mas
    public func runInstall(appState: AppState) async {
        isInstalling = true
        errorMessage = nil
        successMessage = nil
        executionOutput = nil
        defer { isInstalling = false }

        guard let brewPath = ToolPaths.brew() else {
            errorMessage = "未检测到 Homebrew 工具路径，无法自动安装 mas。请先安装 Homebrew。"
            return
        }

        do {
            let result = try await ShellRunner.run(brewPath, arguments: ["install", "mas"], timeout: 300)
            executionOutput = result.stdout.isEmpty ? result.stderr : result.stdout

            if result.exitCode == 0 {
                successMessage = "mas 命令行工具安装成功！已自动开启 Mac App Store 应用更新支持。"
                // 自动刷新应用状态
                await appState.reloadAll()
            } else {
                let errText = result.stderr.isEmpty ? result.stdout : result.stderr
                let summary = BrewProvider.extractTail(errText, maxLines: 5) ?? "Exit code \(result.exitCode)"
                errorMessage = "安装 mas 失败 [退出码 \(result.exitCode)]：\(summary)"
            }
        } catch {
            errorMessage = "执行安装遇到异常：\(error.localizedDescription)"
        }
    }
}

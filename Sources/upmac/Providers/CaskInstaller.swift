import Foundation
import AppKit

/// 手动安装应用的直接更新执行器：brew install --cask --force
public enum CaskInstaller {

    /// 执行更新（同一代码路径供 UI 与 CLI 复用）
    /// - Parameters:
    ///   - item: UpdateItem（需 caskToken 与 externalId 路径）
    ///   - brewPath: brew 二进制路径
    public static func update(item: UpdateItem, brewPath: String) async throws -> UpdateResult {
        guard let token = item.caskToken, !token.isEmpty else {
            return UpdateResult(ok: false, newVersion: nil, message: "缺少 cask token")
        }
        // token 会被当作 brew 参数执行，必须限定为 Homebrew cask 的合法命名形态，
        // 杜绝以 "-" 开头被解析为 flag（--force 会覆盖安装，放大后果）
        guard token.range(of: "^[a-z0-9][a-z0-9._-]*$", options: .regularExpression) != nil else {
            return UpdateResult(ok: false, newVersion: nil, message: "cask token 格式不合法，已拒绝执行")
        }
        // a) 优雅退出正在运行的应用（bundleIdentifier 匹配）
        if let path = item.externalId,
           let bundle = Bundle(url: URL(fileURLWithPath: path)),
           let bundleId = bundle.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            for app in running {
                // 仅对正在运行的实例发 terminate
                if !app.isTerminated {
                    app.terminate()
                }
            }
            // 最多等 5 秒
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let still = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).contains(where: { !$0.isTerminated })
                if !still { break }
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
            }
        }

        // b) brew install --cask --force token
        // 超时 360s 而非 900s：绝大多数 cask 更新在 1-2 分钟内完成，少数 cask 会启动自带
        // GUI 安装器（如 quarkclouddrive 的 --quark-install）并静默挂起，等满 900s 只是让用户白等。
        let caskTimeout: TimeInterval = 360
        let result: ShellRunner.ShellResult
        do {
            result = try await ShellRunner.run(brewPath, arguments: ["install", "--cask", "--force", token], timeout: caskTimeout)
        } catch let error as ProviderError {
            switch error {
            case .managerMissing:
                throw error
            case .timedOut:
                return UpdateResult(
                    ok: false,
                    newVersion: nil,
                    message: "更新超时（已等待 \(Int(caskTimeout / 60)) 分钟）。该应用的安装程序可能需要手动交互，请改为从官网或应用内更新。"
                )
            default:
                return UpdateResult(ok: false, newVersion: nil, message: error.localizedDescription)
            }
        } catch {
            return UpdateResult(ok: false, newVersion: nil, message: error.localizedDescription)
        }

        if result.exitCode == 0 {
            return UpdateResult(ok: true, newVersion: nil, message: "已通过 Homebrew 更新并接管后续管理")
        } else {
            let errorText = result.stderr.isEmpty ? result.stdout : result.stderr
            // 交接给用户手动更新：多数 cask 更新失败是安装器要求 GUI 交互或需要登录，
            // 直接倾泻 brew 的整段英文 stderr 对用户无意义（docs/08 §6.6 状态诚实性）
            let lower = errorText.lowercased()
            let needsManual = lower.contains("cancel") || lower.contains("gui")
                || lower.contains("already open") || lower.contains("permission")
                || lower.contains("login") || lower.contains("password")
                || lower.contains("cask installation failed")
            if needsManual {
                return UpdateResult(
                    ok: false,
                    newVersion: nil,
                    message: "\(token) 更新未完成，该应用的安装程序可能需要手动确认。请关闭应用后重试，或前往官网下载更新。"
                )
            }
            let tail = BrewProvider.extractTail(errorText, maxLines: 6) ?? "brew 返回退出码 \(result.exitCode)"
            return UpdateResult(ok: false, newVersion: nil, message: "更新失败：\(tail)")
        }
    }
}

import SwiftUI
import AppKit

/// 窗口管理辅助：统一窗口打开与激活入口，防重防多开
@MainActor
public enum WindowManager {

    /// 移除 NSToolbar 里的侧栏折叠按钮
    ///
    /// `columnVisibility` 被锁死在 `.all`（侧栏不可折叠），该按钮点了没有任何反应，
    /// 留着会让用户以为界面坏了。SwiftUI 的 `.toolbar(removing: .sidebarToggle)`
    /// 在 macOS 26 下不生效，只能直接操作 NSToolbar。
    /// 注意：窗口首次布局时 toolbar 可能尚未创建（为 nil），调用方需延迟重试一次。
    public static func removeSidebarToggle(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        let indices = toolbar.items.enumerated()
            .filter { $0.element.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebar") }
            .map(\.offset)
            .reversed()
        for index in indices {
            toolbar.removeItem(at: index)
        }
    }
    /// 统一打开或聚焦主窗
    /// 激活应用后，若 NSApp.windows 中已存在 title == "最好用的 Mac 软件管理工具"（或旧标题兼容）的窗口则 makeKeyAndOrderFront 前置，否则才调用 openWindow(id: "main")
    public static func openOrFocusMainWindow(openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: {
            $0.title == "最好用的 Mac 软件管理工具" || $0.title == "Macsoft X" || $0.title == "MSI" || $0.title == "UpMac"
        }) {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    /// 统一打开或聚焦设置窗口
    public static func openOrFocusSettingsWindow(openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.title == "设置" }) {
            existing.deminiaturize(nil)
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "settings")
        }
    }

    /// 将详情浮窗居中定位到主窗范围，若主窗不在屏幕上则屏幕居中兜底（迭代 2.10）
    public static func centerDetailWindowRelativeToMainWindow(detailWindow: NSWindow) {
        if let mainWindow = NSApp.windows.first(where: {
            ($0.title == "最好用的 Mac 软件管理工具" || $0.title == "Macsoft X" || $0.title == "MSI" || $0.title == "UpMac") &&
            $0.isVisible &&
            !$0.isMiniaturized
        }) {
            let mainFrame = mainWindow.frame
            let detailSize = detailWindow.frame.size
            let newX = mainFrame.origin.x + (mainFrame.width - detailSize.width) / 2.0
            let newY = mainFrame.origin.y + (mainFrame.height - detailSize.height) / 2.0
            detailWindow.setFrameOrigin(CGPoint(x: newX, y: newY))
        } else {
            detailWindow.center()
        }
    }

    /// 统一打开或聚焦详情浮窗（居中于主窗范围，迭代 2.10）
    public static func openOrFocusDetailWindow(openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.title == "详情" }) {
            existing.deminiaturize(nil)
            centerDetailWindowRelativeToMainWindow(detailWindow: existing)
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "detail")
        }
    }
}

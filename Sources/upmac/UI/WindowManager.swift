import SwiftUI
import AppKit

/// 窗口管理辅助：统一窗口打开与激活入口，防重防多开
@MainActor
public enum WindowManager {
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

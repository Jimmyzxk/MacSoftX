import SwiftUI
import AppKit
import ServiceManagement

/// 设置视图窗口（约 420×560）
/// 严格遵循 docs/08 §6.5 交互完整性：只包含 100% 真实实现的功能，禁止假开关
public struct SettingsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @StateObject private var launchHelper = LaunchAtLoginHelper()
    @StateObject private var extraDirsHelper = ExtraScanDirsHelper()
    @State private var copiedMasCommand: Bool = false
    @ObservedObject private var masInstaller = MasInstallService.shared
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        Form {
            // MARK: - 1. 外观模式
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("外观模式", selection: $appearanceManager.appearance) {
                        ForEach(AppAppearance.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("外观设置将立即应用于 Macsoft X 的主窗、气泡、详情及设置窗口。")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("外观")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }

            // MARK: - 2. 开机自启
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("登录时自动启动 Macsoft X", isOn: Binding(
                        get: { launchHelper.isEnabled },
                        set: { launchHelper.toggle(enable: $0) }
                    ))
                    .toggleStyle(.switch)

                    HStack(spacing: 4) {
                        Image(systemName: launchHelper.statusIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(launchHelper.statusColor)

                        Text(launchHelper.statusText)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    if let error = launchHelper.errorMessage {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.Colors.warning)

                            Text(error)
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(DesignSystem.Colors.warning)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("启动项")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }

            // MARK: - 3. 额外扫描目录
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("除系统目录 (/Applications) 与用户目录 (~/Applications) 外，Macsoft X 还将扫描以下目录中的应用：")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if extraDirsHelper.extraScanDirs.isEmpty {
                        HStack {
                            Spacer()
                            Text("未配置额外扫描目录")
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))
                    } else {
                        VStack(spacing: 4) {
                            ForEach(extraDirsHelper.extraScanDirs, id: \.self) { dir in
                                HStack {
                                    Image(systemName: "folder")
                                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    Text(dir)
                                        .font(DesignSystem.Typography.meta)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        extraDirsHelper.removeDir(dir)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(DesignSystem.Colors.error)
                                    }
                                    .buttonStyle(.plain)
                                    .help("移除此目录")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    HStack {
                        Spacer()
                        Button {
                            selectFolder()
                        } label: {
                            Label("添加目录…", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("提示：修改扫描目录后将在下次扫描生效。")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("扫描范围")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }

            // MARK: - 4. 包管理与环境增强（mas 提示）
            if ToolPaths.mas() == nil {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "app.badge.checkmark")
                                .foregroundStyle(Color.blue)
                                .font(.system(size: 16))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mac App Store (mas) 命令行工具未安装")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                                Text("检测到系统中安装了 App Store 应用。安装 mas 后可自动管理其版本识别与更新。")
                                    .font(DesignSystem.Typography.meta)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                            }
                        }

                        HStack {
                            Text("brew install mas")
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))

                            Spacer()

                            Button(copiedMasCommand ? "已复制" : "复制命令") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install mas", forType: .string)
                                copiedMasCommand = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedMasCommand = false
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                masInstaller.promptInstall()
                            } label: {
                                if masInstaller.isInstalling {
                                    HStack(spacing: 3) {
                                        ProgressView().controlSize(.small)
                                        Text("安装中…")
                                    }
                                } else {
                                    Text("安装 mas")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.blue)
                            .controlSize(.small)
                            .disabled(masInstaller.isInstalling)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("包管理器增强")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                }
            }

            // MARK: - 5. 通知
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("权限状态：")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text(notificationStatusText)
                            .font(DesignSystem.Typography.meta.weight(.medium))
                            .foregroundStyle(notificationStatusColor)
                        Spacer()
                        if appState.notificationAuthStatus == .denied {
                            Button("前往系统设置") {
                                appState.openNotificationSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    Toggle("发现更新时通知我", isOn: Binding(
                        get: { appState.notificationsEnabled },
                        set: { appState.updateNotificationsEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    Text("开启后，当扫描发现可更新软件且内容变化时将发送系统通知")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("通知")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }

            // MARK: - 6. 自动扫描
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("自动扫描间隔", selection: Binding(
                        get: { appState.scanIntervalMinutes },
                        set: { appState.updateScanInterval(minutes: $0) }
                    )) {
                        Text("关闭").tag(0)
                        Text("1 小时").tag(60)
                        Text("6 小时").tag(360)
                        Text("12 小时").tag(720)
                        Text("每天").tag(1440)
                    }
                    .pickerStyle(.segmented)
                    // 窄窗下分段放不下 5 项，回退为 menu
                    .labelsHidden()

                    Text("选择自动扫描频率，修改后立即生效，0 为关闭")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("扫描")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }

            // MARK: - 7. 关于（居中布局）
            Section {
                VStack(alignment: .center, spacing: 8) {
                    BrandMarkView(size: 64)
                        .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1.5)

                    HStack(spacing: 0) {
                        Text("Macsoft")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .tracking(-0.5)

                        Text("X")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.05, green: 0.52, blue: 1.00),
                                        Color(red: 0.00, green: 0.85, blue: 0.72)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .tracking(-0.5)
                    }

                    Text("版本 \(AppVersion.short)")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("最好用的 Mac 软件管理工具")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("现代化 macOS 软件全景管理平台")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } header: {
                Text("关于")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, idealWidth: 420, maxWidth: 480, minHeight: 520, idealHeight: 560)
        .alert("安装 mas 命令行工具", isPresented: $masInstaller.showConfirmDialog) {
            Button("开始安装") {
                Task {
                    await masInstaller.runInstall(appState: appState)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将通过 Homebrew 执行安装：\nbrew install mas\n\n安装完成后，Mac App Store 来源将自动接入更新扫描。")
        }
        .alert("mas 安装提示", isPresented: Binding(
            get: { masInstaller.errorMessage != nil || masInstaller.successMessage != nil },
            set: { _ in
                masInstaller.errorMessage = nil
                masInstaller.successMessage = nil
            }
        )) {
            Button("好") {}
        } message: {
            if let err = masInstaller.errorMessage {
                Text(err)
            } else if let ok = masInstaller.successMessage {
                Text(ok)
            }
        }
    }

    private var notificationStatusText: String {
        switch appState.notificationAuthStatus {
        case .authorized: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未授权"
        case .provisional: return "临时授权"
        case .ephemeral: return "临时"
        @unknown default: return "未知"
        }
    }

    private var notificationStatusColor: Color {
        switch appState.notificationAuthStatus {
        case .authorized: return DesignSystem.Colors.success
        case .denied: return DesignSystem.Colors.error
        default: return DesignSystem.Colors.textSecondary
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "选择"
        panel.message = "选择包含 macOS 应用 (.app) 的自定义目录"

        if panel.runModal() == .OK, let url = panel.url {
            extraDirsHelper.addDir(url.path)
        }
    }
}

/// 开机自启服务辅助器
@MainActor
private final class LaunchAtLoginHelper: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var statusText: String = ""
    @Published var statusColor: Color = .secondary
    @Published var statusIcon: String = "info.circle"
    @Published var errorMessage: String? = nil

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            isEnabled = true
            statusText = "已启用（登录时自动在后台启动）"
            statusColor = DesignSystem.Colors.success
            statusIcon = "checkmark.circle.fill"
        case .notRegistered:
            isEnabled = false
            statusText = "未启用"
            statusColor = DesignSystem.Colors.textSecondary
            statusIcon = "minus.circle"
        case .requiresApproval:
            isEnabled = false
            statusText = "需在系统设置 > 通用 > 登录项中批准"
            statusColor = DesignSystem.Colors.warning
            statusIcon = "exclamationmark.triangle.fill"
        case .notFound:
            isEnabled = false
            statusText = "未找到主程序包（打包为 .app 后生效）"
            statusColor = DesignSystem.Colors.textTertiary
            statusIcon = "questionmark.circle"
        @unknown default:
            isEnabled = false
            statusText = "状态未知"
            statusColor = DesignSystem.Colors.textTertiary
            statusIcon = "questionmark.circle"
        }
    }

    func toggle(enable: Bool) {
        errorMessage = nil
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            errorMessage = "操作失败: \(error.localizedDescription)"
            refresh()
        }
    }
}

/// 额外扫描目录持久化辅助器（写入 state.json extraScanDirs）
@MainActor
private final class ExtraScanDirsHelper: ObservableObject {
    @Published var extraScanDirs: [String] = []
    @Published var hasChangesNotice: Bool = false
    @Published var errorMessage: String? = nil

    init() {
        loadDirs()
    }

    func loadDirs() {
        let json = StateStore.read()
        if let dirs = json["extraScanDirs"] as? [String] {
            extraScanDirs = dirs.map { ($0 as NSString).expandingTildeInPath }
        } else {
            extraScanDirs = []
        }
    }

    func addDir(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !extraScanDirs.contains(trimmed) else { return }
        extraScanDirs.append(trimmed)
        persist()
    }

    func removeDir(_ path: String) {
        extraScanDirs.removeAll { $0 == path }
        persist()
    }

    private func persist() {
        let dirsToSave = extraScanDirs
        StateStore.update { root in
            root["extraScanDirs"] = dirsToSave
        }
        hasChangesNotice = true
        errorMessage = nil
    }
}

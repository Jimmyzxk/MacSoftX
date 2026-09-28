import SwiftUI
import AppKit

/// 菜单栏玻璃气泡迷你面板（.menuBarExtraStyle(.window)）
/// 参考 Raycast/iStat Menus 信息层级：顶部紧凑状态行 + 列表 32pt 行 + 全宽主按钮
public struct MenuBarBubbleView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 10) {
            // MARK: - 顶部紧凑状态行：左「N 项待更新」大字 17pt 右「上次扫描 HH:MM」小字 11pt
            HStack(alignment: .firstTextBaseline) {
                if appState.remainingCount == 0 {
                    Text("所有软件均是最新版本")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                } else {
                    Text("\(appState.remainingCount) 项待更新")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }
                Spacer()
                if let lastScan = appState.lastScanDate {
                    Text("上次扫描 \(lastScan.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else if appState.isLoading {
                    Text("扫描中…")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                Button {
                    Task { await appState.reloadAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: appState.isLoading && !reduceMotion)
                }
                .buttonStyle(.borderless)
                .disabled(appState.isLoading || appState.isUpdatingAll)
                .help("立即扫描")
            }
            .padding(.horizontal, 2)

            Divider()

            // MARK: - 列表区：每项 32pt，图标 18 圆形底 + 名称 12 medium + 版本 10 mono
            if appState.items.isEmpty {
                // 状态诚实性：全源失败 ≠ 全部最新。errors 非空时不得显示绿色勾。
                if !appState.lastErrors.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Text("本次扫描未完成")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text("\(appState.lastErrors.count) 个来源获取失败，请检查网络或对应工具")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("所有软件均是最新版本")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        if let lastScan = appState.lastScanDate {
                            Text("上次扫描 \(lastScan.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(appState.items.prefix(5)) { item in
                        MiniRowItem(item: item, appState: appState)
                    }
                    if appState.items.count > 5 {
                        Text("还有 \(appState.items.count - 5) 项可在主窗中查看")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.top, 2)
                    }
                }
            }

            Divider()

            // MARK: - 底部：主按钮全宽 28pt + 次排两个文字按钮居中
            VStack(spacing: 8) {
                Button {
                    Task { await appState.updateAll() }
                } label: {
                    if appState.isUpdatingAll {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.small)
                            Text("更新中…")
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                    } else {
                        Text("全部更新")
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(appState.remainingCount == 0 || appState.isUpdatingAll)

                HStack(spacing: 16) {
                    Spacer()
                    Button("打开主窗") {
                        WindowManager.openOrFocusMainWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("设置") {
                        WindowManager.openOrFocusSettingsWindow(openWindow: openWindow)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("退出") {
                        requestQuit(appState: appState)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .alert("有更新正在进行", isPresented: $appState.pendingQuitConfirmation) {
            Button("仍然退出", role: .destructive) {
                ShellRunner.terminateAllActive()
                NSApplication.shared.terminate(nil)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("退出将中断正在进行的更新。确定要退出吗？")
        }
    }
}

/// 菜单栏迷你卡片：图标 18 圆形底 + 名称 12 medium + 版本 10 mono，行高 32pt
private struct MiniRowItem: View {
    let item: UpdateItem
    @ObservedObject var appState: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: AppState.ItemUpdateStatus {
        appState.updateStatuses[item.id] ?? .idle
    }

    private var matchedPath: String? {
        guard item.kind == .cask || item.kind == .mas || item.kind == .app else { return nil }
        return AppIconFinder.shared.findPath(for: item.name, externalId: item.externalId)
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(
                name: item.name,
                kind: item.kind,
                sourceId: item.providerId,
                path: matchedPath,
                size: 18
            )
            .clipShape(Circle())

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: 110, alignment: .leading)

            Spacer(minLength: 4)

            // 版本变迁常显 10 mono
            // 必须 fixedSize：否则横向空间紧张时版本号会被压缩折成两行（如 0.12.18 显示为 "0.12.1"+"8"）。
            // 名字已 lineLimit(1) 且限宽 110pt，空间不足时应由名字截断，而不是把版本号折断。
            HStack(spacing: 2) {
                Text(item.currentVersion)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                if let latest = item.latestVersion {
                    Text("→")
                        .font(.system(size: 8))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(latest)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(DesignSystem.Colors.cardBackground, in: Capsule())

            miniActionArea
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(DesignSystem.Colors.subtleFill.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))
    }

    @ViewBuilder
    private var miniActionArea: some View {
        if item.isSystemComponent {
            Text("系统组件")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.75))
                .help("macOS 自带组件，随系统更新")
        } else if item.requiresLogin {
            Text("需登录")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .help("需要登录账户后方可更新")
        } else if item.needsSudo {
            Text("需管理员")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning)
                .help("需要管理员提权，请在终端中使用 sudo 命令执行更新")
        } else {
            switch status {
            case .idle:
                if let token = item.caskToken, !token.isEmpty {
                    Button("更新") {
                        Task { await appState.update(item) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("通过 Homebrew 下载并安装新版本，应用会先退出，更新后由 Homebrew 接管管理")
                } else if item.providerId.lowercased() == "apps" {
                    Button("更新") {
                        Task { await appState.update(item) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("将启动该应用并触发其内置更新检查")
                } else {
                    Button("更新") {
                        Task { await appState.update(item) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(DesignSystem.Colors.accent)
                    .help("立即更新")
                }

            case .updating:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    if let start = appState.updateStartedAt[item.id] {
                        TimelineView(.periodic(from: start, by: 1)) { context in
                            let elapsed = Int(context.date.timeIntervalSince(start))
                            Text("\(elapsed)s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .monospacedDigit()
                        }
                    }
                }

            case .success(let newVersion):
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.success)
                    if let ver = newVersion ?? item.latestVersion {
                        Text(ver)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.success)
                    }
                }

            case .handoff(let message):
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 70, alignment: .trailing)
                }

            case .failure(let message):
                HStack(spacing: 4) {
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.error)
                        .lineLimit(1)
                        .frame(maxWidth: 70, alignment: .trailing)
                    Button("重试") {
                        Task { await appState.update(item) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
    }
}

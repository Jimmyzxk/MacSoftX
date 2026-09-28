import SwiftUI
import AppKit

public struct ScanRowView: View {
    let item: UpdateItem
    @ObservedObject var appState: AppState
    let isSelected: Bool
    let onSelect: (() -> Void)?
    let onDetail: (() -> Void)?

    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        item: UpdateItem,
        appState: AppState,
        isSelected: Bool = false,
        onSelect: (() -> Void)? = nil,
        onDetail: (() -> Void)? = nil
    ) {
        self.item = item
        self.appState = appState
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDetail = onDetail
    }

    private var status: AppState.ItemUpdateStatus {
        appState.updateStatuses[item.id] ?? .idle
    }

    private var matchedAppPath: String? {
        guard item.kind == .cask || item.kind == .mas || item.kind == .app else { return nil }
        return AppIconFinder.shared.findPath(for: item.name, externalId: item.externalId)
    }

    private var upgradeCommand: String {
        switch item.providerId.lowercased() {
        case "brew", "homebrew":
            return item.kind == .cask ? "brew upgrade --cask \(item.name)" : "brew upgrade \(item.name)"
        case "mas":
            return "mas upgrade \(item.externalId ?? item.name)"
        case "apps":
            return "open \"\(item.externalId ?? item.name)\""
        case "npm":
            return "npm install -g \(item.name)@latest"
        case "gem", "rubygems":
            return "gem update \(item.name)"
        case "uv":
            return "uv tool upgrade \(item.name)"
        default:
            return "\(item.providerId) upgrade \(item.name)"
        }
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 主行：图标 36pt（RowMetrics.iconSize，与 InventoryRowView 统一）
            AppIconView(
                name: item.name,
                kind: item.kind,
                sourceId: item.providerId,
                path: matchedAppPath
            )
            .frame(width: DesignSystem.RowMetrics.iconSize, height: DesignSystem.RowMetrics.iconSize)

            // 两行结构（行 1：名称 13pt medium + 右侧徽章组；行 2：元信息 11pt secondary）
            VStack(alignment: .leading, spacing: 2) {
                // 行 1：名称 13pt medium + 状态徽章（与 InventoryRowView 同语义同色同形，Badge 10pt medium h6/v2 corner 4）
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    if item.isSystemComponent {
                        Text("系统组件")
                            .font(DesignSystem.RowMetrics.badgeFont)
                            .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.75))
                            .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                            .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                            .background(Color(red: 0.35, green: 0.55, blue: 0.75).opacity(0.12), in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                    } else if item.needsSudo {
                        Text("需管理员")
                            .font(DesignSystem.RowMetrics.badgeFont)
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                            .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                            .background(DesignSystem.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                    }

                    if item.requiresLogin {
                        Text("需登录")
                            .font(DesignSystem.RowMetrics.badgeFont)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                            .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                            .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                    }
                }

                // 行 2：元信息 11pt secondary 用 · 分隔（来源 · 当前版本 → 目标版本，版本过渡统一：旧 secondary 箭头 新 primary medium 等宽）
                HStack(spacing: 4) {
                    Circle()
                        .fill(EcosystemTheme.color(for: item.providerId))
                        .frame(width: DesignSystem.Spacing.dotSize, height: DesignSystem.Spacing.dotSize)

                    Text(EcosystemTheme.displayName(for: item.providerId))
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("·")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Text(item.currentVersion)
                        .font(DesignSystem.Typography.version)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Text(item.latestVersion ?? "?")
                        .font(DesignSystem.Typography.version.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    // 类型标签统一为副行 10pt tertiary 小字或省略：此处省略，类型由图标隐式表达
                }
            }

            Spacer(minLength: 8)

            // 尾缀操作钮（与 InventoryRowView 统一 hover 按钮区逻辑：hover/选中/状态非 idle 时显现）
            actionArea
                .opacity((isHovered || isSelected || status != .idle || item.requiresLogin || item.needsSudo || item.isSystemComponent) ? 1.0 : 0.0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovered || isSelected)
        }
        .padding(.horizontal, DesignSystem.RowMetrics.leadingPadding)
        .frame(height: DesignSystem.RowMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile)
                .fill(
                    isSelected
                        ? Color(nsColor: .quaternaryLabelColor)
                        : (isHovered ? DesignSystem.Colors.rowHoverBackground : Color.clear)
                )
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(EcosystemTheme.heroGradient)
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if case .updating = status {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(DesignSystem.Colors.accent)
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .padding(.horizontal, 12)
                    .padding(.bottom, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?()
        }
        .onTapGesture(count: 2) {
            onDetail?()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onDetail?()
            } label: {
                Label("查看详情", systemImage: "info.circle")
            }

            Divider()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(upgradeCommand, forType: .string)
            } label: {
                Label("复制升级命令", systemImage: "doc.on.doc")
            }

            Menu {
                Button("跳过本次") {
                    appState.skipOnce(item: item)
                }
                Button("稍后 7 天") {
                    appState.ignore(item: item, scope: .until, durationDays: 7)
                }
                Button("永久忽略") {
                    appState.ignore(item: item, scope: .forever)
                }
            } label: {
                Label("忽略此项", systemImage: "eye.slash")
            }

            if let path = matchedAppPath {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }

            Divider()

            Button {
                Task {
                    await appState.reloadAll()
                }
            } label: {
                Label("立即扫描", systemImage: "arrow.clockwise")
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: status)
    }

    @ViewBuilder
    private var actionArea: some View {
        HStack(spacing: 8) {
            Button {
                onDetail?()
            } label: {
                Text("详情")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)

            if item.isSystemComponent {
                Button("更新") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                    .help("macOS 自带组件，随系统更新")
            } else if item.requiresLogin {
                Text("需登录")
                    .font(DesignSystem.RowMetrics.badgeFont)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                    .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                    .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                    .help("需要登录账户后方可更新")
            } else if item.needsSudo {
                Text("需管理员")
                    .font(DesignSystem.RowMetrics.badgeFont)
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                    .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                    .background(DesignSystem.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                    .help("需要管理员提权，请在终端中使用 sudo 命令执行更新")
            } else {
                switch status {
                case .idle:
                    if let token = item.caskToken, !token.isEmpty {
                        Button("更新") {
                            Task { await appState.update(item) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                        .controlSize(.small)
                        .help("通过 Homebrew 下载并安装新版本，应用会先退出，更新后由 Homebrew 接管管理")
                    } else if let infoURL = item.infoURL, !infoURL.isEmpty {
                        Button {
                            Task { await appState.update(item) }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 9))
                                Text("打开下载页")
                                    .font(DesignSystem.RowMetrics.badgeFont)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                        .controlSize(.small)
                        .help(infoURL)
                    } else if item.providerId.lowercased() == "apps" {
                        Button {
                            Task { await appState.update(item) }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 9))
                                Text("内置更新器")
                                    .font(DesignSystem.RowMetrics.badgeFont)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("将启动该应用并触发其内置更新检查")
                    } else {
                        Button("更新") {
                            Task {
                                await appState.update(item)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                        .controlSize(.small)
                        .disabled(appState.isUpdatingAll)
                    }

                case .updating:
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.small)
                        Text("更新中")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        if let start = appState.updateStartedAt[item.id] {
                            TimelineView(.periodic(from: start, by: 1)) { context in
                                let elapsed = Int(context.date.timeIntervalSince(start))
                                Text("· \(elapsed)s")
                                    .font(DesignSystem.Typography.meta)
                                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, 6)

                case .success(let newVersion):
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.success)
                        if let ver = newVersion ?? item.latestVersion {
                            Text("已更新 \(ver)")
                                .font(DesignSystem.Typography.version.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.success)
                        } else {
                            Text("已更新")
                                .font(DesignSystem.Typography.meta.weight(.medium))
                                .foregroundStyle(DesignSystem.Colors.success)
                        }
                    }
                    .padding(.horizontal, 6)

                case .handoff(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.circle")
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)

                case .failure(let message):
                    HStack(spacing: 6) {
                        Text(message)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.error)
                            .lineLimit(2)
                            .frame(maxWidth: 140, alignment: .trailing)

                        Button("重试") {
                            Task {
                                await appState.update(item)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(appState.isUpdatingAll)
                    }
                }
            }
        }
    }
}

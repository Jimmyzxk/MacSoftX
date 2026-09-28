import SwiftUI
import AppKit

public struct InventoryRowView: View {
    let item: InventoryItem
    let isSelected: Bool
    /// 若经 cask API 检测出可更新，则展示主色「可更新」徽章（有价值状态，替代 hover 的内置更新器）
    let caskLatestVersion: String?
    let appState: AppState?
    let onSelect: (() -> Void)?
    let onDetail: (() -> Void)?

    @State private var isHovered: Bool = false

    private var isCaskUpdatable: Bool { caskLatestVersion != nil }

    public init(
        item: InventoryItem,
        isSelected: Bool = false,
        caskLatestVersion: String? = nil,
        appState: AppState? = nil,
        onSelect: (() -> Void)? = nil,
        onDetail: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.caskLatestVersion = caskLatestVersion
        self.appState = appState
        self.onSelect = onSelect
        self.onDetail = onDetail
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 主行：图标 36pt（与 ScanRowView 统一，RowMetrics.iconSize）
            AppIconView(
                name: item.name,
                softwareKind: item.kind,
                sourceId: item.sourceId,
                path: item.path
            )
            .frame(width: DesignSystem.RowMetrics.iconSize, height: DesignSystem.RowMetrics.iconSize)

            // 两行结构（行 1：名称 13pt medium + 右侧徽章组；行 2：元信息 11pt secondary 用 · 分隔）
            VStack(alignment: .leading, spacing: 2) {
                // 行 1：名称 13pt medium + 右侧徽章组
                // 决策：有价值的「可更新」用主色常显，降噪的「内置更新器」降级为 hover 才显现
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    if isCaskUpdatable, let latest = caskLatestVersion {
                        Text("可更新")
                            .font(DesignSystem.RowMetrics.badgeFont)
                            .foregroundStyle(DesignSystem.Colors.accent)
                            .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                            .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                            .background(DesignSystem.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                            .help("检测到新版本 \(latest)，点击详情查看下载页")
                    } else if item.status == .unmanaged {
                        Button {
                            if let path = item.path {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.system(size: 9))
                                Text("内置更新器")
                                    .font(DesignSystem.RowMetrics.badgeFont)
                            }
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .padding(.horizontal, DesignSystem.RowMetrics.badgeHorizontalPadding)
                            .padding(.vertical, DesignSystem.RowMetrics.badgeVerticalPadding)
                            .background(DesignSystem.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignSystem.RowMetrics.badgeCornerRadius))
                        }
                        .buttonStyle(.plain)
                        .help("此类应用由自身携带的更新器管理，Macsoft X 无法代查更新")
                        .opacity((isHovered || isSelected) ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered || isSelected)
                    }
                }

                // 行 2：元信息 11pt secondary 用 · 分隔（来源 · 版本 · 路径简写）
                HStack(spacing: 4) {
                    Circle()
                        .fill(EcosystemTheme.color(for: item.sourceId))
                        .frame(width: DesignSystem.Spacing.dotSize, height: DesignSystem.Spacing.dotSize)

                    Text(item.sourceDisplayName)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    Text("·")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Text(item.version)
                        .font(DesignSystem.Typography.version)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if let path = item.path {
                        Text("·")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)

                        Text(path)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    // 类型标签统一为副行 10pt tertiary 小字或省略：此处省略，类型由图标与来源隐式表达，避免冗余
                }
            }

            Spacer(minLength: 8)

            // 尾缀 Hover 按钮区（与 ScanRowView 统一：hover/选中时显现）
            Button {
                onDetail?()
            } label: {
                Text("详情")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .opacity((isHovered || isSelected) ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered || isSelected)
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

            if let path = item.path {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.name, forType: .string)
            } label: {
                Label("复制名称", systemImage: "doc.on.doc")
            }

            if let path = item.path {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: {
                    Label("复制路径", systemImage: "link")
                }
            }

            Divider()

            if item.status == .unmanaged, let state = appState {
                Menu {
                    Button("跳过本次") {
                        let pseudo = UpdateItem(providerId: item.sourceId, name: item.name, currentVersion: item.version, kind: .app, externalId: item.path)
                        state.skipOnce(item: pseudo)
                    }
                    Button("稍后 7 天") {
                        state.ignore(inventoryItem: item, scope: .until, durationDays: 7)
                    }
                    Button("永久忽略") {
                        state.ignore(inventoryItem: item, scope: .forever)
                    }
                } label: {
                    Label("忽略此项", systemImage: "eye.slash")
                }
            }
        }
    }
}

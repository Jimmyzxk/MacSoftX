import SwiftUI

public struct AllSoftwareView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var inventoryService: InventoryService
    let searchText: String
    let categoryFilter: CategoryFilter
    let sortOrder: SortOrder
    @Binding var selectedItemId: String?
    @Binding var selectedSourceFilter: String?
    @Binding var onlyShowUnmanaged: Bool

    @Environment(\.openWindow) private var openWindow

    public init(
        appState: AppState,
        inventoryService: InventoryService,
        searchText: String,
        categoryFilter: CategoryFilter,
        sortOrder: SortOrder,
        selectedItemId: Binding<String?> = .constant(nil),
        selectedSourceFilter: Binding<String?> = .constant(nil),
        onlyShowUnmanaged: Binding<Bool> = .constant(false)
    ) {
        self.appState = appState
        self.inventoryService = inventoryService
        self.searchText = searchText
        self.categoryFilter = categoryFilter
        self.sortOrder = sortOrder
        self._selectedItemId = selectedItemId
        self._selectedSourceFilter = selectedSourceFilter
        self._onlyShowUnmanaged = onlyShowUnmanaged
    }

    private var filteredItems: [InventoryItem] {
        inventoryService.items.filter { item in
            // 类别过滤
            let matchesCategory: Bool
            switch categoryFilter {
            case .all:
                matchesCategory = true
            case .app:
                matchesCategory = (item.kind == .app)
            case .cli:
                matchesCategory = (item.kind == .cli)
            }

            // 手动安装二次过滤
            let matchesUnmanaged = !onlyShowUnmanaged || (item.status == .unmanaged)

            // 来源过滤（侧栏联动）
            let matchesSource: Bool
            if let filter = selectedSourceFilter {
                matchesSource = (item.sourceDisplayName == filter || item.sourceId == filter)
            } else {
                matchesSource = true
            }

            // 搜索关键字（支持软件名、源展示名、版本、路径以及类别名称）
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool
            if q.isEmpty {
                matchesSearch = true
            } else {
                let matchesKind: Bool
                if item.kind == .app && ("应用".localizedCaseInsensitiveContains(q) || "app".localizedCaseInsensitiveContains(q)) {
                    matchesKind = true
                } else if item.kind == .cli && ("命令行".localizedCaseInsensitiveContains(q) || "cli".localizedCaseInsensitiveContains(q)) {
                    matchesKind = true
                } else {
                    matchesKind = false
                }

                matchesSearch = item.name.localizedCaseInsensitiveContains(q) ||
                    item.sourceDisplayName.localizedCaseInsensitiveContains(q) ||
                    item.version.localizedCaseInsensitiveContains(q) ||
                    matchesKind ||
                    (item.path?.localizedCaseInsensitiveContains(q) ?? false)
            }

            return matchesCategory && matchesUnmanaged && matchesSource && matchesSearch
        }
        .sorted { first, second in
            switch sortOrder {
            case .name:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .source:
                if first.sourceDisplayName != second.sourceDisplayName {
                    return first.sourceDisplayName < second.sourceDisplayName
                }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .version:
                return first.version.localizedStandardCompare(second.version) == .orderedDescending
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - 顶部统计条（仅在已有数据时展示）
            if !inventoryService.items.isEmpty {
                topStatsBar
            }

            // MARK: - 错误细横幅（源失败带出）
            if !inventoryService.lastErrors.isEmpty {
                errorBanner
            }

            // MARK: - 清单内容状态路由
            if inventoryService.isLoading || (inventoryService.items.isEmpty && inventoryService.lastScanDate == nil) {
                // 1. 加载中显示进度占位（ProgressView + 「正在扫描软件清单…」）
                loadingPlaceholder
            } else if inventoryService.items.isEmpty && !inventoryService.lastErrors.isEmpty {
                // 2. 加载失败显示错误状态
                loadFailedState
            } else if inventoryService.items.isEmpty {
                // 3. 扫描完成且确实为 0 时才显示空态
                emptyState
            } else if filteredItems.isEmpty {
                // 4. 搜索/过滤无匹配项
                searchEmptyState
            } else {
                // 5. 正常渲染软件列表（行间无分割线，2pt 间距，docs/09 §4）
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.rowSpacing) {
                        ForEach(filteredItems) { item in
                            // 若该应用经 cask API 检测出可更新，则行内以主色「可更新」替代 hover 的内置更新器
                            let caskLatest: String? = {
                                // 匹配逻辑：path 精确，其次 name 大小写不敏感
                                if let path = item.path {
                                    if let hit = appState.items.first(where: { $0.externalId == path && $0.infoURL != nil }) {
                                        return hit.latestVersion
                                    }
                                }
                                // 降级按名称匹配（处理路径不一致但名称相同的孤儿应用）
                                let lower = item.name.lowercased()
                                if let hit = appState.items.first(where: { $0.name.lowercased() == lower && $0.infoURL != nil }) {
                                    return hit.latestVersion
                                }
                                return nil
                            }()
                            InventoryRowView(
                                item: item,
                                isSelected: selectedItemId == item.id,
                                caskLatestVersion: caskLatest,
                                appState: appState,
                                onSelect: {
                                    selectedItemId = item.id
                                    appState.pendingDetail = .inventory(item: item)
                                    WindowManager.openOrFocusDetailWindow(openWindow: openWindow)
                                },
                                onDetail: {
                                    selectedItemId = item.id
                                    appState.pendingDetail = .inventory(item: item)
                                    WindowManager.openOrFocusDetailWindow(openWindow: openWindow)
                                }
                            )
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await inventoryService.ensureLoaded()
        }
    }

    // MARK: - 加载中进度占位（ProgressView + 「正在扫描软件清单…」）
    private var loadingPlaceholder: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            ProgressView()
            Text("正在扫描软件清单…")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 失败状态
    private var loadFailedState: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.Colors.error)

            Text("软件清单扫描遇到错误")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("部分软件源执行失败，请检查网络或权限设置")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Button {
                Task {
                    await inventoryService.refresh()
                }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 空状态（确实为 0）
    private var emptyState: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: "shippingbox")
                .font(.system(size: 36))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("未检测到已安装的软件")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Button {
                Task {
                    await inventoryService.refresh()
                }
            } label: {
                Label("重新扫描", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 搜索/过滤无结果空状态
    private var searchEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("未找到匹配软件")
                .font(DesignSystem.Typography.bodyMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if selectedSourceFilter != nil || onlyShowUnmanaged {
                Button("重置所有过滤") {
                    selectedSourceFilter = nil
                    onlyShowUnmanaged = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 顶部统计条（简化为：X 应用 · Y 命令行，12pt secondary，数字 medium）
    private var topStatsBar: some View {
        HStack(spacing: DesignSystem.Spacing.m) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("\(inventoryService.appCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("应用")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            Text("·")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            HStack(spacing: DesignSystem.Spacing.xs) {
                Text("\(inventoryService.cliCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("命令行")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            // 来源过滤指示胶囊（保留，仅为已选过滤时显现）
            if let filter = selectedSourceFilter {
                HStack(spacing: 4) {
                    Text("来源: \(filter)")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Button {
                        selectedSourceFilter = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.subtleFill, in: Capsule())
            }

            Spacer()

            if inventoryService.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 错误细横幅
    private var errorBanner: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.warning)
                .font(DesignSystem.Typography.meta)

            Text("清单扫描部分源警告：")
                .font(DesignSystem.Typography.meta.weight(.bold))

            ForEach(Array(inventoryService.lastErrors.keys.sorted()), id: \.self) { sourceId in
                if let msg = inventoryService.lastErrors[sourceId] {
                    Text("\(sourceId): \(msg)")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("关闭") {
                inventoryService.lastErrors.removeAll()
            }
            .buttonStyle(.borderless)
            .font(DesignSystem.Typography.meta)
            .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.warning.opacity(0.1))
        .overlay(Divider(), alignment: .bottom)
    }
}

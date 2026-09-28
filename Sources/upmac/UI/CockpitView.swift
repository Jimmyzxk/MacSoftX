import SwiftUI
import AppKit

public enum NavigationTab: Hashable {
    case scan
    case allSoftware
    case cleanup
    case ignored
}

public enum CategoryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case app = "应用"
    case cli = "命令行"
    public var id: String { rawValue }
}

public enum SortOrder: String, CaseIterable, Identifiable {
    case name = "名称"
    case source = "来源"
    case version = "版本"
    public var id: String { rawValue }
}

/// 主窗视图（侧栏任务导向重设计：状态卡 + 任务分组 + 来源快捷过滤区；单列主列表区，详情浮窗居中弹出）
/// 严格遵循 docs/08-design-spec.md、docs/09-art-direction.md 与 docs/10-branding-sidebar.md
public struct CockpitView: View {
    @ObservedObject public var appState: AppState
    @StateObject private var inventoryService: InventoryService

    @State private var selectedTab: NavigationTab = .scan
    @State private var searchText: String = ""
    @State private var categoryFilter: CategoryFilter = .all
    @State private var sortOrder: SortOrder = .source

    // 选中态单选模型（单击仅高亮，双击/详情呼出单例小浮窗）
    @State private var selectedScanItemId: String? = nil
    @State private var selectedInventoryItemId: String? = nil
    @State private var selectedSourceFilter: String? = nil
    @State private var showOnlyManualInstall: Bool = false
    @State private var isSettingsHovered: Bool = false
    // 侧栏列可见性锁死（侧栏为产品核心导航，不可折叠，防止收起后主窗白页，docs/10）
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    public init(appState: AppState, inventoryService: InventoryService? = nil) {
        self.appState = appState
        self._inventoryService = StateObject(wrappedValue: inventoryService ?? InventoryService())
    }

    /// 各 Tab 独立的加载态隔离，防止互相干扰
    private var isLoading: Bool {
        switch selectedTab {
        case .scan:
            return appState.isLoading
        case .allSoftware:
            return inventoryService.isLoading
        case .cleanup:
            return false
        case .ignored:
            return false
        }
    }

    private var activeProvidersCount: Int {
        let set = Set(appState.items.map { $0.providerId })
        return max(set.count, appState.providers.count)
    }

    private var activeSources: [String] {
        let itemsSources = Set(appState.items.map { $0.providerId })
        if !itemsSources.isEmpty {
            return Array(itemsSources).sorted()
        }
        return Array(Set(appState.providers.map { $0.id })).sorted()
    }

    /// 侧栏已启用源统计（按 sourceDisplayName 聚合；降级为快捷过滤区，docs/10 §2）
    private var sourceStatsList: [(sourceId: String, name: String, count: Int)] {
        let managed = inventoryService.items.filter { $0.status == .managed }
        if !managed.isEmpty {
            let grouped = Dictionary(grouping: managed, by: { $0.sourceDisplayName })
            return grouped.map { (sourceId: $0.value.first?.sourceId ?? $0.key, name: $0.key, count: $0.value.count) }
                .sorted { first, second in
                    if first.count != second.count {
                        return first.count > second.count
                    }
                    return first.name < second.name
                }
        } else {
            // 当清单正在后台扫描时，优先使用已启用的 providers 显示骨架项
            return appState.providers.map { provider in
                (sourceId: provider.id, name: provider.displayName, count: 0)
            }
        }
    }

    /// 过滤后的待更新项列表（用于键盘导航移动选中）
    private var filteredScanItems: [UpdateItem] {
        appState.items.filter { item in
            let matchesCategory: Bool
            switch categoryFilter {
            case .all: matchesCategory = true
            case .app: matchesCategory = (item.kind == .cask || item.kind == .mas || item.kind == .app)
            case .cli: matchesCategory = (item.kind == .formula || item.kind == .cli)
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return matchesCategory }
            let sourceDisplay = EcosystemTheme.displayName(for: item.providerId)
            let matchesSearch = item.name.localizedCaseInsensitiveContains(q) ||
                item.providerId.localizedCaseInsensitiveContains(q) ||
                sourceDisplay.localizedCaseInsensitiveContains(q) ||
                (item.externalId?.localizedCaseInsensitiveContains(q) ?? false)
            return matchesCategory && matchesSearch
        }
        .sorted { first, second in
            switch sortOrder {
            case .name: return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .source:
                if first.providerId != second.providerId { return first.providerId < second.providerId }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .version: return (first.latestVersion ?? "") > (second.latestVersion ?? "")
            }
        }
    }

    /// 过滤后的全部软件列表（用于键盘导航移动选中）
    private var filteredInventoryItems: [InventoryItem] {
        inventoryService.items.filter { item in
            let matchesCategory: Bool
            switch categoryFilter {
            case .all: matchesCategory = true
            case .app: matchesCategory = (item.kind == .app)
            case .cli: matchesCategory = (item.kind == .cli)
            }
            let matchesUnmanaged = !showOnlyManualInstall || (item.status == .unmanaged)
            let matchesSource: Bool
            if let filter = selectedSourceFilter {
                matchesSource = (item.sourceDisplayName == filter || item.sourceId == filter)
            } else {
                matchesSource = true
            }
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return matchesCategory && matchesUnmanaged && matchesSource }
            let matchesSearch = item.name.localizedCaseInsensitiveContains(q) ||
                item.sourceDisplayName.localizedCaseInsensitiveContains(q) ||
                item.version.localizedCaseInsensitiveContains(q) ||
                (item.path?.localizedCaseInsensitiveContains(q) ?? false)
            return matchesCategory && matchesUnmanaged && matchesSource && matchesSearch
        }
        .sorted { first, second in
            switch sortOrder {
            case .name: return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .source:
                if first.sourceDisplayName != second.sourceDisplayName { return first.sourceDisplayName < second.sourceDisplayName }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .version: return first.version.localizedStandardCompare(second.version) == .orderedDescending
            }
        }
    }

    /// 键盘 ↑↓ 移动选中项逻辑
    private func moveSelection(delta: Int) {
        guard !isSearchFocused else { return }

        if selectedTab == .scan {
            let list = filteredScanItems
            guard !list.isEmpty else { return }
            if let currentId = selectedScanItemId, let idx = list.firstIndex(where: { $0.id == currentId }) {
                let newIdx = min(max(0, idx + delta), list.count - 1)
                selectedScanItemId = list[newIdx].id
            } else {
                selectedScanItemId = (delta > 0) ? list.first?.id : list.last?.id
            }
        } else if selectedTab == .allSoftware {
            let list = filteredInventoryItems
            guard !list.isEmpty else { return }
            if let currentId = selectedInventoryItemId, let idx = list.firstIndex(where: { $0.id == currentId }) {
                let newIdx = min(max(0, idx + delta), list.count - 1)
                selectedInventoryItemId = list[newIdx].id
            } else {
                selectedInventoryItemId = (delta > 0) ? list.first?.id : list.last?.id
            }
        }
    }

    /// 全部软件中符合搜索条件的匹配数
    private var allSoftwareSearchMatchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        return inventoryService.items.filter { item in
            let q = searchText
            return item.name.localizedCaseInsensitiveContains(q) ||
                item.sourceDisplayName.localizedCaseInsensitiveContains(q) ||
                item.version.localizedCaseInsensitiveContains(q) ||
                (item.path?.localizedCaseInsensitiveContains(q) ?? false) ||
                (item.kind == .app && ("应用".localizedCaseInsensitiveContains(q) || "app".localizedCaseInsensitiveContains(q))) ||
                (item.kind == .cli && ("命令行".localizedCaseInsensitiveContains(q) || "cli".localizedCaseInsensitiveContains(q)))
        }.count
    }

    /// 扫描待更新软件中符合搜索条件的匹配数
    private var scanSearchMatchCount: Int {
        guard !searchText.isEmpty else { return 0 }
        return appState.items.filter { item in
            let q = searchText
            return item.name.localizedCaseInsensitiveContains(q) ||
                item.providerId.localizedCaseInsensitiveContains(q) ||
                EcosystemTheme.displayName(for: item.providerId).localizedCaseInsensitiveContains(q) ||
                (item.externalId?.localizedCaseInsensitiveContains(q) ?? false) ||
                ((item.kind == .app || item.kind == .cask || item.kind == .mas) && ("应用".localizedCaseInsensitiveContains(q) || "app".localizedCaseInsensitiveContains(q))) ||
                ((item.kind == .formula || item.kind == .cli) && ("命令行".localizedCaseInsensitiveContains(q) || "cli".localizedCaseInsensitiveContains(q)))
        }.count
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - 侧栏（宽 200pt，系统侧栏材质，docs/09 §3 & docs/10 §2）
            sidebarPane
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            // MARK: - 单列主列表区（回归单列，无检查器尾栏）
            middleListPane
        }
        .navigationTitle("")
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 880, minHeight: 520)
        .background {
            shortcutsOverlay
        }
        .background {
            WindowAccessor { window in
                // 标题仅用于 WindowManager 防多开匹配（见 openOrFocusMainWindow 的标题白名单），
                // 视觉上隐藏——品牌展示已由工具栏 Slogan 与侧栏品牌头承担，再显示标题就是第三次重复。
                window.title = "最好用的 Mac 软件管理工具"
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true

                // 移除侧栏折叠按钮：columnVisibility 被锁死在 .all（见下方 onChange），
                // 该按钮点了也没反应，留着只会让人以为界面坏了（用户 2026-09-28 反馈）。
                // .toolbar(removing: .sidebarToggle) 在 macOS 26 下不生效，只能从 NSToolbar 摘；
                // 工具栏晚于窗口创建，故立即 + 延迟各清一次。
                WindowManager.removeSidebarToggle(from: window)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    WindowManager.removeSidebarToggle(from: window)
                    }
            }
        }
        .onAppear {
            columnVisibility = .all
        }
        .onChange(of: columnVisibility) { _, newVisibility in
            // 锁死侧栏全部可见：任何路径尝试折叠侧栏均强制恢复 .all
            if newVisibility != .all {
                columnVisibility = .all
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .allSoftware {
                Task {
                    await inventoryService.ensureLoaded()
                }
            }
        }
        .task {
            // 启动时在后台静默加载一次 inventory 数据，让侧栏源统计与资料库计数实时就绪
            await inventoryService.ensureLoaded()
        }
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

    // MARK: - 侧栏静态缓存渐变（参考端点 #2A5F8F → #1E7A6F 中低饱和蓝绿，饱和度降低 35%，视疲劳修复）
    private static let sidebarGradientDark = LinearGradient(
        colors: [
            Color(red: 0x1E / 255.0, green: 0x3E / 255.0, blue: 0x5C / 255.0).opacity(0.85),
            Color(red: 0x14 / 255.0, green: 0x4E / 255.0, blue: 0x46 / 255.0).opacity(0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private static let sidebarGradientLight = LinearGradient(
        colors: [
            Color(red: 0x2A / 255.0, green: 0x5F / 255.0, blue: 0x8F / 255.0).opacity(0.92),
            Color(red: 0x1E / 255.0, green: 0x7A / 255.0, blue: 0x6F / 255.0).opacity(0.92)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var sidebarGradient: LinearGradient {
        colorScheme == .dark ? Self.sidebarGradientDark : Self.sidebarGradientLight
    }

    // MARK: - 工具栏 Slogan 字标（与搜索框同排）
    private var toolbarSlogan: some View {
        HStack(spacing: 4) {
            Text("最好用的")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .tracking(-0.3)

            Text("Mac")
                .font(.system(size: 14, weight: .heavy))
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

            Text("软件管理工具")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .tracking(-0.3)
        }
        .fixedSize()
        .padding(.leading, 4)
    }

    // MARK: - 侧栏顶部品牌头（与右侧工具栏同高，保证两侧列表起点对齐）
    // 迭代 2.15 曾把品牌块移到底部并居中，结果是侧栏顶部留出一大片空白渐变，看起来像渲染缺失。
    // 现移回顶部：既填满顶部，又与右侧 Slogan 条等高，两个区域的第一个列表项自然对齐。
    private var sidebarBrandHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                BrandMarkView(size: 28, style: .colorful)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 3, x: 0, y: 1)

                HStack(spacing: 0) {
                    Text("Macsoft")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .tracking(-0.4)

                    Text("X")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.35, green: 0.75, blue: 1.00),
                                    Color(red: 0.00, green: 0.96, blue: 0.83)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .tracking(-0.4)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
        }
    }

    // MARK: - 侧栏底部设置行（最底一行，设置入口永远最后）
    private var sidebarFooter: some View {
        Button {
            WindowManager.openOrFocusSettingsWindow(openWindow: openWindow)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.70) : Color.white.opacity(0.85))
                    .frame(width: 16, height: 16)

                Text("设置")
                    .font(.system(size: 13, weight: colorScheme == .dark ? .regular : .medium))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)

                Spacer()

                Text(AppVersion.display)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.45) : Color.white.opacity(0.65))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSettingsHovered ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.14)) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isSettingsHovered = hovering
        }
        .help("打开设置 (⌘,)")
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    // MARK: - 侧栏 v3：品牌头 + 导航项 + 来源紧凑列表 + 底部设置（docs/10 §2 & 迭代 2.10）
    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部品牌头（原底部品牌块，见 sidebarBrandHeader 注释）
            sidebarBrandHeader

            // 导航项与来源列表（ScrollView 自然填满剩余高度，不再用 Spacer 撑开）
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // ⟳ 待更新
                    SidebarRow(
                        title: "待更新",
                        icon: "arrow.triangle.2.circlepath",
                        isSelected: selectedTab == .scan,
                        badgeCount: appState.remainingCount > 0 ? appState.remainingCount : nil,
                        isDimmed: false
                    ) {
                        selectedTab = .scan
                        selectedSourceFilter = nil
                        showOnlyManualInstall = false
                    }

                    // ▤ 全部软件
                    SidebarRow(
                        title: "全部软件",
                        icon: "square.grid.2x2",
                        isSelected: selectedTab == .allSoftware && selectedSourceFilter == nil && !showOnlyManualInstall,
                        badgeCount: inventoryService.items.count > 0 ? inventoryService.items.count : nil,
                        isDimmed: false
                    ) {
                        selectedTab = .allSoftware
                        selectedSourceFilter = nil
                        showOnlyManualInstall = false
                        Task {
                            await inventoryService.ensureLoaded()
                        }
                    }

                    // ○ 手动安装
                    SidebarRow(
                        title: "手动安装",
                        icon: "circle",
                        isSelected: selectedTab == .allSoftware && showOnlyManualInstall,
                        badgeCount: inventoryService.orphanCount > 0 ? inventoryService.orphanCount : nil,
                        isDimmed: false
                    ) {
                        selectedTab = .allSoftware
                        selectedSourceFilter = nil
                        showOnlyManualInstall = true
                        Task {
                            await inventoryService.ensureLoaded()
                        }
                    }

                    // ⌫ 清理（迭代 4 清理模块 v1）
                    SidebarRow(
                        title: "清理",
                        icon: "trash",
                        isSelected: selectedTab == .cleanup,
                        badgeCount: nil,
                        isDimmed: false
                    ) {
                        selectedTab = .cleanup
                        selectedSourceFilter = nil
                        showOnlyManualInstall = false
                    }

                    // ⊘ 已忽略
                    SidebarRow(
                        title: "已忽略",
                        icon: "slash.circle",
                        isSelected: selectedTab == .ignored,
                        badgeCount: appState.ignoreRules.count > 0 ? appState.ignoreRules.count : nil,
                        isDimmed: false
                    ) {
                        selectedTab = .ignored
                    }

                    // 来源分组：间距 18pt，hairline 分隔线，组头 11pt medium 白色 60%
                    if !sourceStatsList.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Rectangle()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 0.5)
                                .padding(.horizontal, 4)

                            Text("来源")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.60))
                                .padding(.horizontal, 4)
                        }
                        .padding(.top, 18)
                        .padding(.bottom, 4)

                        ForEach(sourceStatsList, id: \.name) { src in
                            SidebarRow(
                                title: src.name,
                                dotColor: EcosystemTheme.color(for: src.sourceId),
                                isSelected: selectedTab == .allSoftware && selectedSourceFilter == src.name && !showOnlyManualInstall,
                                badgeCount: src.count > 0 ? src.count : nil,
                                isDimmed: false,
                                compact: true
                            ) {
                                if selectedTab == .allSoftware && selectedSourceFilter == src.name && !showOnlyManualInstall {
                                    // 再次点击取消过滤
                                    selectedSourceFilter = nil
                                } else {
                                    selectedTab = .allSoftware
                                    selectedSourceFilter = src.name
                                    showOnlyManualInstall = false
                                    Task {
                                        await inventoryService.ensureLoaded()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            // 底部只保留设置行（品牌块已上移至顶部）
            sidebarFooter
        }
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(sidebarGradient)
        )
    }

    // MARK: - 中间列表区与底部状态栏
    private var middleListPane: some View {
        VStack(spacing: 0) {
            // 页头 Slogan 位于工具栏（见 toolbarSlogan），此处不再占一行

            // 跨页全局检索跳转提示条（当另一页有更多匹配时）
            if !searchText.isEmpty {
                if selectedTab == .scan && allSoftwareSearchMatchCount > scanSearchMatchCount {
                    crossPageJumpBanner(
                        title: "在全部软件中查找 \(allSoftwareSearchMatchCount) 项",
                        targetTab: .allSoftware
                    )
                } else if selectedTab == .allSoftware && scanSearchMatchCount > allSoftwareSearchMatchCount {
                    crossPageJumpBanner(
                        title: "在待更新中查找 \(scanSearchMatchCount) 项",
                        targetTab: .scan
                    )
                }
            }

            // 主展示列表
            Group {
                switch selectedTab {
                case .scan:
                    ScanListView(
                        appState: appState,
                        inventoryService: inventoryService,
                        searchText: searchText,
                        categoryFilter: categoryFilter,
                        sortOrder: sortOrder,
                        selectedItemId: $selectedScanItemId
                    )
                case .allSoftware:
                    AllSoftwareView(
                        appState: appState,
                        inventoryService: inventoryService,
                        searchText: searchText,
                        categoryFilter: categoryFilter,
                        sortOrder: sortOrder,
                        selectedItemId: $selectedInventoryItemId,
                        selectedSourceFilter: $selectedSourceFilter,
                        onlyShowUnmanaged: $showOnlyManualInstall
                    )
                case .cleanup:
                    CleanupView(
                        appState: appState,
                        inventoryService: inventoryService
                    )
                case .ignored:
                    ignoredRulesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 底部状态栏
            bottomStatusBar
        }
        .toolbar {
            // Slogan 字标：工具栏最左（用户要求与搜索栏同排，省下内容区一整行）
            ToolbarItem(placement: .navigation) {
                toolbarSlogan
            }

            // 弹性空格把后续控件顶到工具栏尾部（靠右）。
            // 实测本窗口在 macOS 26 下，单靠 ToolbarItemPlacement(.primaryAction) 不会右对齐，
            // 必须显式插入弹性空格；ToolbarSpacer 是 macOS 26 起的官方 API，低版本自动降级。
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.flexible)
            }

            // 搜索框（支持 ⌘F 聚焦）
            ToolbarItemGroup(placement: .primaryAction) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .font(DesignSystem.Typography.meta)
                        .frame(width: 14, height: 14)

                    TextField("搜索软件名称或来源", text: $searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.body)
                        .frame(width: 160)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.s)
                .padding(.vertical, DesignSystem.Spacing.xs)
                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))

                // 排序菜单（与搜索框同组，随组一起落到工具栏尾区）
                Menu {
                    Menu("类别") {
                        Picker("类别", selection: $categoryFilter) {
                            ForEach(CategoryFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                    }

                    Divider()

                    Picker("排序", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text("按\(order.rawValue)").tag(order)
                        }
                    }
                } label: {
                    Label(categoryFilter == .all ? "排序" : "排序 (\(categoryFilter.rawValue))", systemImage: "arrow.up.arrow.down")
                }
            }

            // ⌘R 立即扫描（状态互不干扰）
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if selectedTab == .scan {
                            await appState.reloadAll()
                        } else if selectedTab == .allSoftware {
                            await inventoryService.refresh()
                        }
                    }
                } label: {
                    Label("立即扫描", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeating, isActive: isLoading && !reduceMotion)
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("立即扫描 (⌘R)")
                .disabled(isLoading)
            }
        }
    }

    // MARK: - 主窗内容区顶部页头 Slogan 组件（混排字重 + 品牌渐变 + 装饰竖条）

    // MARK: - 跨页跳转条
    private func crossPageJumpBanner(title: String, targetTab: NavigationTab) -> some View {
        Button {
            selectedTab = targetTab
            if targetTab == .allSoftware {
                Task {
                    await inventoryService.ensureLoaded()
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .font(DesignSystem.Typography.meta)

                Text(title)
                    .font(DesignSystem.Typography.meta.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.accent)

                Spacer()

                Text("切换页面")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(DesignSystem.Colors.accent.opacity(0.08))
            .overlay(Divider(), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 底部状态栏
    private var bottomStatusBar: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            if selectedTab == .scan {
                if appState.isLoading {
                    Text("正在扫描更新…")
                } else if let lastScan = appState.lastScanDate {
                    Text("上次扫描 \(lastScan.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("未扫描")
                }

                Text("·").foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(activeProvidersCount) 源")
                Text("·").foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(appState.remainingCount) 项待更新")
            } else if selectedTab == .allSoftware {
                if inventoryService.isLoading {
                    Text("正在扫描软件清单…")
                } else if let lastScan = inventoryService.lastScanDate {
                    Text("上次整理 \(lastScan.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("清单已就绪")
                }

                Text("·").foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(inventoryService.coveredSourcesCount) 源")
                Text("·").foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("\(inventoryService.items.count) 项软件")
            } else if selectedTab == .cleanup {
                Text("安全红线：所有清理操作一律移入废纸篓，支持随时放回")
            } else {
                Text("已忽略软件")
            }

            Spacer()
        }
        .font(DesignSystem.Typography.meta)
        .foregroundStyle(DesignSystem.Colors.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - 已忽略真实页
    private var ignoredRulesView: some View {
        VStack(spacing: 0) {
            if appState.ignoreRules.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("没有被忽略的软件")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("右键待更新项，选择忽略规则后在此查看")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack {
                    Text("\(appState.ignoreRules.count) 条规则")
                        .font(DesignSystem.Typography.meta.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("全部恢复") {
                        appState.restoreAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay(Divider(), alignment: .bottom)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.ignoreRules) { rule in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(EcosystemTheme.color(for: rule.providerId))
                                    .frame(width: 6, height: 6)
                                Text(rule.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    .lineLimit(1)
                                Text(EcosystemTheme.displayName(for: rule.providerId))
                                    .font(DesignSystem.Typography.badge)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(DesignSystem.Colors.subtleFill, in: Capsule())
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if rule.scope == .forever {
                                        Text("永久")
                                            .font(DesignSystem.Typography.badge)
                                            .foregroundStyle(DesignSystem.Colors.warning)
                                    } else if let until = rule.until {
                                        Text("至 \(until.formatted(date: .numeric, time: .omitted))")
                                            .font(DesignSystem.Typography.badge)
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    }
                                    Text(rule.createdAt.formatted(date: .numeric, time: .omitted))
                                        .font(.system(size: 9))
                                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                                }
                                Button("恢复") {
                                    appState.restore(rule: rule)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var ignoredPlaceholderView: some View {
        ignoredRulesView
    }

    // MARK: - 快捷键辅助覆盖
    private var shortcutsOverlay: some View {
        Group {
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("") {
                selectedTab = .scan
                selectedSourceFilter = nil
                showOnlyManualInstall = false
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("") {
                selectedTab = .allSoftware
                selectedSourceFilter = nil
                showOnlyManualInstall = false
                Task {
                    await inventoryService.ensureLoaded()
                }
            }
            .keyboardShortcut("2", modifiers: .command)

            // 键盘 ↑↓ 键移动选中项
            Button("") {
                moveSelection(delta: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: [])

            Button("") {
                moveSelection(delta: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: [])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

/// 侧栏导航行组件（iOS 风渐变侧栏专用：深浅模式微调白系透明度与权重，保证 WCAG AA 对比度 ≥4.5:1，迭代 2.10）
private struct SidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String?
    let dotColor: Color?
    let isSelected: Bool
    let badgeCount: Int?
    let isDimmed: Bool
    let compact: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    init(
        title: String,
        icon: String? = nil,
        dotColor: Color? = nil,
        isSelected: Bool,
        badgeCount: Int?,
        isDimmed: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.dotColor = dotColor
        self.isSelected = isSelected
        self.badgeCount = badgeCount
        self.isDimmed = isDimmed
        self.compact = compact
        self.action = action
    }

    private var iconColor: Color {
        if isDimmed {
            return colorScheme == .dark ? Color.white.opacity(0.40) : Color.white.opacity(0.60)
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.70) : Color.white.opacity(0.85)
        }
    }

    private var textColor: Color {
        if isDimmed {
            return colorScheme == .dark ? Color.white.opacity(0.40) : Color.white.opacity(0.65)
        } else {
            return Color.white.opacity(0.92)
        }
    }

    private var selectionFillColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.24)
        } else if isHovered {
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.14)
        } else {
            return Color.clear
        }
    }

    private var badgeFillColor: Color {
        return Color.white.opacity(0.12)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: compact ? 6 : 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                } else if let dotColor = dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
                        .frame(width: compact ? 12 : 18, height: compact ? 12 : 18)
                }

                Text(title)
                    .font(.system(size: compact ? 12 : 13, weight: isSelected ? .semibold : (colorScheme == .dark ? .regular : .medium)))
                    .foregroundStyle(textColor)
                    .lineLimit(1)

                Spacer()

                if let count = badgeCount, count > 0 {
                    if compact {
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.50) : Color.white.opacity(0.65))
                    } else {
                        Text("\(count)")
                            .font(DesignSystem.Typography.badge.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .frame(minWidth: 20)
                            .background(badgeFillColor, in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 2 : 5)
            .frame(height: compact ? 28 : nil)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8)
                    .fill(selectionFillColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - 原生窗口属性配置器（隐藏标题文字，使顶栏干净通透）
public struct WindowAccessor: NSViewRepresentable {
    public let configure: (NSWindow) -> Void

    public init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowConfiguringView(configure: configure)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window)
        }
    }

    private final class WindowConfiguringView: NSView {
        let configure: (NSWindow) -> Void

        init(configure: @escaping (NSWindow) -> Void) {
            self.configure = configure
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window = window {
                configure(window)
            }
        }
    }
}


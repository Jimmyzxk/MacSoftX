import SwiftUI
import AppKit

public enum CleanupSubSection: String, CaseIterable, Identifiable {
    case software = "可卸载软件"
    case leftovers = "发现的残留"
    public var id: String { rawValue }
}

/// 清理页（两区块：可卸载软件 + 发现的残留孤儿文件）
/// 严格遵循 docs/07 §2、docs/08 状态诚实性原则
public struct CleanupView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var inventoryService: InventoryService

    @State private var activeSection: CleanupSubSection = .software
    @State private var searchText: String = ""
    @State private var categoryFilter: CategoryFilter = .all

    // 卸载弹窗
    @State private var selectedItemForUninstall: InventoryItem? = nil

    // 残留扫描状态
    @State private var leftovers: [LeftoverItem] = []
    @State private var isScanningLeftovers: Bool = false
    @State private var isTrashingLeftovers: Bool = false
    @State private var isProcessing: Bool = false
    @State private var showTrashConfirmAlert: Bool = false
    @State private var cleanupResultBanner: String? = nil
    @State private var isSuspectedExpanded: Bool = false

    // 悬浮行状态
    @State private var hoveredItemId: String? = nil

    public init(appState: AppState, inventoryService: InventoryService) {
        self.appState = appState
        self.inventoryService = inventoryService
    }

    // 过滤掉系统保护应用的可卸载项
    private var filteredSoftware: [InventoryItem] {
        inventoryService.items.filter { item in
            // 排除 Apple 核心应用（com.apple. 或 /System 目录）
            if let bid = item.bundleId, bid.hasPrefix("com.apple.") { return false }
            if let path = item.path, path.hasPrefix("/System") { return false }

            // 分类过滤
            switch categoryFilter {
            case .all: break
            case .app:
                guard item.kind == .app else { return false }
            case .cli:
                guard item.kind == .cli else { return false }
            }

            // 搜索过滤
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return item.name.lowercased().contains(q) ||
                   item.sourceDisplayName.lowercased().contains(q) ||
                   (item.bundleId?.lowercased().contains(q) ?? false)
        }
    }

    private var confirmedLeftovers: [LeftoverItem] {
        leftovers.filter { $0.confidence == .confirmed }
    }

    private var suspectedLeftovers: [LeftoverItem] {
        leftovers.filter { $0.confidence == .suspected || $0.confidence == .toConfirm }
    }

    private var safeLeftovers: [LeftoverItem] {
        leftovers.filter { $0.category == .safe }
    }

    private var cautionLeftovers: [LeftoverItem] {
        leftovers.filter { $0.category == .caution }
    }

    private var selectedLeftoversCount: Int {
        leftovers.filter { $0.isSelected }.count
    }

    private var selectedLeftoversSize: Int64 {
        leftovers.filter { $0.isSelected }.reduce(0) { $0 + $1.sizeInBytes }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部子分段选择器与工具条
            headerToolbar

            // 结果通知条（若有）
            if let banner = cleanupResultBanner {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text(banner)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Button {
                        cleanupResultBanner = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(DesignSystem.Colors.success.opacity(0.12))
                .overlay(Divider(), alignment: .bottom)
            }

            // 主体内容
            Group {
                switch activeSection {
                case .software:
                    softwareListView
                case .leftovers:
                    leftoversListView
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedItemForUninstall) { item in
            UninstallPlanSheet(item: item) {
                Task {
                    await inventoryService.refresh()
                    await scanLeftovers()
                }
            }
        }
        .task {
            await inventoryService.ensureLoaded()
            if leftovers.isEmpty {
                await scanLeftovers()
            }
        }
        .alert("确认移入废纸篓？", isPresented: $showTrashConfirmAlert) {
            Button("移入废纸篓", role: .destructive) {
                trashSelectedLeftovers()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将把已选的 \(selectedLeftoversCount) 项残留文件（共 \(ByteCountFormatter.string(fromByteCount: selectedLeftoversSize, countStyle: .file))）移入废纸篓。\n文件可随时在 macOS 废纸篓中还原。")
        }
    }

    // MARK: - 1. 顶部工具条
    private var headerToolbar: some View {
        HStack(spacing: 12) {
            Picker("", selection: $activeSection) {
                Text("可卸载软件 (\(filteredSoftware.count))").tag(CleanupSubSection.software)
                Text("发现的残留 (\(leftovers.count))").tag(CleanupSubSection.leftovers)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            if activeSection == .software {
                // 搜索框
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    TextField("搜索软件名称或来源…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(DesignSystem.Typography.meta)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 180)

                // 分类选择
                Picker("", selection: $categoryFilter) {
                    ForEach(CategoryFilter.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            } else {
                Button {
                    Task {
                        await scanLeftovers()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("重新扫描")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isScanningLeftovers || isProcessing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 2. 区块 A：可卸载软件列表
    private var softwareListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredSoftware) { item in
                    softwareRow(item)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func softwareRow(_ item: InventoryItem) -> some View {
        let isHovered = hoveredItemId == item.id

        HStack(spacing: 12) {
            // 图标
            AppIconView(
                name: item.name,
                softwareKind: item.kind,
                sourceId: item.sourceId,
                path: item.path,
                size: 32
            )

            // 详情
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    Text(item.version)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                HStack(spacing: 6) {
                    Text(item.sourceDisplayName)
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)

                    if let path = item.path {
                        Text("·")
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(path)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            // Hover 显示「卸载」按钮
            if isHovered {
                Button {
                    selectedItemForUninstall = item
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("卸载")
                            .font(DesignSystem.Typography.badge.weight(.medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red)
                .controlSize(.small)
                .disabled(isProcessing || isScanningLeftovers || isTrashingLeftovers)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredItemId = item.id
            } else if hoveredItemId == item.id {
                hoveredItemId = nil
            }
        }
    }

    // MARK: - 3. 区块 B：发现的残留列表
    private var leftoversListView: some View {
        VStack(spacing: 0) {
            if isScanningLeftovers {
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在扫描孤儿残留文件…")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if leftovers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("未发现孤儿残留文件")
                        .font(DesignSystem.Typography.headline)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("规则库中暂未检测到已卸载软件遗留的无主配置或缓存，系统很规整。")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 顶部统计条：确认残留 N 项 / 疑似 M 项（分开关，疑似默认折叠，宁缺毋滥原则）
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.blue)
                        Text("确认残留 \(confirmedLeftovers.count) 项")
                            .font(DesignSystem.Typography.bodyMedium.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }

                    Text("·").foregroundStyle(DesignSystem.Colors.textTertiary)

                    HStack(spacing: 6) {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(Color.orange)
                        Text("疑似 \(suspectedLeftovers.count) 项")
                            .font(DesignSystem.Typography.bodyMedium.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }

                    Spacer()

                    // 疑似项折叠开关（默认折叠）
                    Button {
                        isSuspectedExpanded.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSuspectedExpanded ? "收起疑似项" : "展开疑似项 (\(suspectedLeftovers.count))")
                            Image(systemName: isSuspectedExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(Color.blue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .overlay(Divider(), alignment: .bottom)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 1. 确认残留分组（应用已卸载+名字强匹配，默认勾选安全项）
                        if !confirmedLeftovers.isEmpty {
                            leftoverCategoryGroup(
                                title: "确认残留（明确已卸载软件的日志与缓存，可安全清理）",
                                category: .safe,
                                items: confirmedLeftovers
                            )
                        }

                        // 2. 疑似残留分组（默认折叠，包含配置偏好或待核验项，默认不勾选）
                        if isSuspectedExpanded && !suspectedLeftovers.isEmpty {
                            leftoverCategoryGroup(
                                title: "疑似与待确认残留（含偏好配置或弱线索项，清理将丢失历史配置）",
                                category: .caution,
                                items: suspectedLeftovers
                            )
                        }
                    }
                    .padding(14)
                }

                // 底部移除确认操作条
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已选 \(selectedLeftoversCount) 项 · 共 \(ByteCountFormatter.string(fromByteCount: selectedLeftoversSize, countStyle: .file))")
                            .font(DesignSystem.Typography.bodyMedium.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Text("安全红线：所有清理一律移入废纸篓，可放回原处")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }

                    Spacer()

                    Button {
                        showTrashConfirmAlert = true
                    } label: {
                        if isTrashingLeftovers {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                Text("移入废纸篓")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.red)
                    .disabled(isProcessing || isTrashingLeftovers || selectedLeftoversCount == 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .overlay(Divider(), alignment: .top)
            }
        }
    }

    @ViewBuilder
    private func leftoverCategoryGroup(
        title: String,
        category: LeftoverCategory,
        items: [LeftoverItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(DesignSystem.Typography.badge.weight(.semibold))
                    .foregroundStyle(category == .safe ? Color.blue : Color.orange)

                Spacer()

                Button(items.allSatisfy { $0.isSelected } ? "取消全选" : "全选") {
                    let shouldSelect = !items.allSatisfy { $0.isSelected }
                    for item in items {
                        if let idx = leftovers.firstIndex(where: { $0.id == item.id }) {
                            leftovers[idx].isSelected = shouldSelect
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(Color.blue)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 2) {
                ForEach(items) { item in
                    leftoverRow(item)
                }
            }
            .padding(6)
            .background(DesignSystem.Colors.subtleFill.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func confidenceColor(_ confidence: LeftoverConfidence) -> Color {
        switch confidence {
        case .confirmed:
            return Color.blue
        case .suspected:
            return Color.orange
        case .toConfirm:
            return DesignSystem.Colors.textSecondary
        }
    }

    @ViewBuilder
    private func leftoverRow(_ item: LeftoverItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { newValue in
                    if let idx = leftovers.firstIndex(where: { $0.id == item.id }) {
                        leftovers[idx].isSelected = newValue
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)

                    Text(item.inferredAppName)
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(DesignSystem.Colors.subtleFill, in: Capsule())

                    // 置信度分类徽章
                    Text(item.confidence.rawValue)
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(confidenceColor(item.confidence))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(confidenceColor(item.confidence).opacity(0.12), in: Capsule())
                }

                Text(item.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let reason = item.inferenceReason {
                    HStack(spacing: 3) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text(reason)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
                }
            }

            Spacer()

            Text(item.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isSelected ? Color.blue.opacity(0.04) : Color.clear)
        )
    }

    // 扫描孤儿残留
    private func scanLeftovers() async {
        if isProcessing { return }
        isProcessing = true
        isScanningLeftovers = true
        defer {
            isScanningLeftovers = false
            isProcessing = false
        }
        let results = await LeftoverScanner.shared.scanLeftovers(installedItems: inventoryService.items)
        await MainActor.run {
            self.leftovers = results
        }
    }

    // 批量清理已选孤儿残留
    private func trashSelectedLeftovers() {
        if isProcessing || isTrashingLeftovers { return }
        isProcessing = true
        isTrashingLeftovers = true
        Task {
            let res = await LeftoverScanner.shared.trashLeftovers(leftovers)
            await MainActor.run {
                self.isTrashingLeftovers = false
                self.isProcessing = false
                if res.trashedCount > 0 {
                    self.cleanupResultBanner = "已将 \(res.trashedCount) 项残留（共 \(res.formattedFreedSize)）移入废纸篓"
                }
            }
            await scanLeftovers()
        }
    }
}

import SwiftUI

public struct ScanListView: View {
    @ObservedObject var appState: AppState
    private let inventoryService: InventoryService?
    let searchText: String
    let categoryFilter: CategoryFilter
    let sortOrder: SortOrder
    @Binding var selectedItemId: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @State private var hasAppeared: Bool = false
    @State private var copiedMasCommand: Bool = false
    @State private var isMasNoticeDismissed: Bool = false
    @ObservedObject private var masInstaller = MasInstallService.shared

    public init(
        appState: AppState,
        inventoryService: InventoryService? = nil,
        searchText: String,
        categoryFilter: CategoryFilter,
        sortOrder: SortOrder,
        selectedItemId: Binding<String?> = .constant(nil)
    ) {
        self.appState = appState
        self.inventoryService = inventoryService
        self.searchText = searchText
        self.categoryFilter = categoryFilter
        self.sortOrder = sortOrder
        self._selectedItemId = selectedItemId
    }

    private var filteredItems: [UpdateItem] {
        appState.items.filter { item in
            // 分段过滤
            let matchesCategory: Bool
            switch categoryFilter {
            case .all:
                matchesCategory = true
            case .app:
                matchesCategory = (item.kind == .cask || item.kind == .mas || item.kind == .app)
            case .cli:
                matchesCategory = (item.kind == .formula || item.kind == .cli)
            }

            // 搜索过滤（支持软件名、源 ID、源展示名、路径及类型名称）
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch: Bool
            if q.isEmpty {
                matchesSearch = true
            } else {
                let sourceDisplay = EcosystemTheme.displayName(for: item.providerId)
                let matchesKind: Bool
                if (item.kind == .app || item.kind == .cask || item.kind == .mas) && ("应用".localizedCaseInsensitiveContains(q) || "app".localizedCaseInsensitiveContains(q)) {
                    matchesKind = true
                } else if (item.kind == .formula || item.kind == .cli) && ("命令行".localizedCaseInsensitiveContains(q) || "cli".localizedCaseInsensitiveContains(q)) {
                    matchesKind = true
                } else {
                    matchesKind = false
                }

                matchesSearch = item.name.localizedCaseInsensitiveContains(q) ||
                    item.providerId.localizedCaseInsensitiveContains(q) ||
                    sourceDisplay.localizedCaseInsensitiveContains(q) ||
                    matchesKind ||
                    (item.externalId?.localizedCaseInsensitiveContains(q) ?? false)
            }

            return matchesCategory && matchesSearch
        }
        .sorted { first, second in
            switch sortOrder {
            case .name:
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .source:
                if first.providerId != second.providerId {
                    return first.providerId < second.providerId
                }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .version:
                return (first.latestVersion ?? "") > (second.latestVersion ?? "")
            }
        }
    }

    private var updatableCount: Int {
        appState.pendingItems.filter { item in
            guard !item.needsSudo, !item.requiresLogin else { return false }
            if item.providerId == "apps" && (item.caskToken == nil || item.caskToken?.isEmpty == true) {
                return false
            }
            return true
        }.count
    }

    private var detectedMasAppsCount: Int {
        inventoryService?.items.filter({ $0.sourceId == "mas" }).count ?? 0
    }

    private var shouldShowMasBanner: Bool {
        guard !isMasNoticeDismissed else { return false }
        return ToolPaths.mas() == nil
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - mas 未安装提示横幅（检测到 App Store 应用但未安装 mas）
            if shouldShowMasBanner {
                masMissingBanner
            }

            // MARK: - 错误细横幅（内容区顶部通栏细带，扫描中的源不显示错误）
            if !visibleErrors.isEmpty {
                errorBanner
            }

            // MARK: - 扫描中提示（渐进式：正在扫描 npm、gem…）
            if !appState.scanningProviders.isEmpty {
                scanningIndicator
            }

            // MARK: - 可更新提示与一键全部更新操作条
            if updatableCount > 0 {
                batchActionBar
            }

            // MARK: - 列表主体（行间无分割线，2pt 间距，docs/09 §4）
            if appState.isLoading && appState.items.isEmpty {
                VStack(spacing: DesignSystem.Spacing.m) {
                    ProgressView()
                    Text("扫描中…")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.items.isEmpty {
                // 状态诚实性：全源失败 ≠ 全部最新。errors 非空时显示失败态而非绿色勾。
                if !appState.lastErrors.isEmpty {
                    allSourcesFailedState
                } else {
                    compactCelebrationState
                }
            } else if filteredItems.isEmpty {
                searchEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: DesignSystem.Spacing.rowSpacing) {
                        ForEach(filteredItems) { item in
                            ScanRowView(
                                item: item,
                                appState: appState,
                                isSelected: selectedItemId == item.id,
                                onSelect: {
                                    selectedItemId = item.id
                                    appState.pendingDetail = .scan(item: item)
                                    WindowManager.openOrFocusDetailWindow(openWindow: openWindow)
                                },
                                onDetail: {
                                    selectedItemId = item.id
                                    appState.pendingDetail = .scan(item: item)
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

    // MARK: - mas 未安装提示横幅（检测到 App Store 应用但未安装 mas）
    private var masMissingBanner: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(systemName: "app.badge.checkmark")
                .foregroundStyle(Color.blue)
                .font(DesignSystem.Typography.meta)

            Text("检测到 \(detectedMasAppsCount) 个 App Store 应用。安装 mas 后可管理其更新：")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text("brew install mas")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: 4))

            Button(copiedMasCommand ? "已复制" : "复制命令") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install mas", forType: .string)
                copiedMasCommand = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedMasCommand = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button {
                masInstaller.promptInstall()
            } label: {
                if masInstaller.isInstalling {
                    HStack(spacing: 3) {
                        ProgressView().controlSize(.mini)
                        Text("安装中…")
                    }
                } else {
                    Text("安装 mas")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.blue)
            .controlSize(.mini)
            .disabled(masInstaller.isInstalling)

            Spacer()

            Button {
                isMasNoticeDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("关闭提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.blue.opacity(0.08))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 可见错误（过滤扫描中的源）
    private var visibleErrors: [(providerId: String, message: String)] {
        appState.lastErrors
            .filter { !appState.scanningProviders.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { (providerId: $0.key, message: $0.value) }
    }

    private func friendlyErrorMessage(providerId: String, raw: String) -> String {
        let name = EcosystemTheme.displayName(for: providerId)
        let lower = raw.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") || lower.contains("timedout") {
            return "\(name) 扫描超时（网络较慢），下次扫描将重试"
        }
        if lower.contains("parsing failed") {
            return "\(name) 返回的数据格式无法解析，该工具版本可能已变化"
        }
        if lower.contains("not found") || lower.contains("no such file") {
            return "\(name) 未安装或路径不可用，请先安装后重试"
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("unreachable") {
            return "\(name) 网络不可用，请检查连接后重试"
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return "\(name) 无权访问所需资源，请在「系统设置 - 隐私与安全性」中授权"
        }
        if lower.contains("sudo privilege required") {
            return "\(name) 此项需要管理员权限，请前往终端手动执行"
        }
        // 兜底：原始报错常常是整段英文 stderr，直接倾泻到 UI 既不可读也无信息量
        return "\(name) 扫描失败，详情请查看终端模式（--scan）输出"
    }

    // MARK: - 扫描中指示（11pt tertiary + 12pt 转圈）
    private var scanningIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
            Text("正在扫描：\(scanningDisplayNames)")
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .overlay(Divider(), alignment: .bottom)
    }

    private var scanningDisplayNames: String {
        let sortedIds = appState.scanningProviders.sorted()
        let names = sortedIds.map { EcosystemTheme.displayName(for: $0) }
        return names.joined(separator: "、")
    }

    // MARK: - 顶部细带错误横幅
    private var errorBanner: some View {
        HStack(spacing: DesignSystem.Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Colors.warning)
                .font(DesignSystem.Typography.meta)

            Text("扫描告警")
                .font(DesignSystem.Typography.meta.weight(.bold))

            ForEach(visibleErrors, id: \.providerId) { entry in
                Text(friendlyErrorMessage(providerId: entry.providerId, raw: entry.message))
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("关闭") {
                appState.lastErrors.removeAll()
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

    // MARK: - 批量更新条（保留逐项流转 + 总进度 2/5 · Spotify）
    private var batchActionBar: some View {
        VStack(spacing: 6) {
            HStack {
                if appState.isUpdatingAll, let prog = appState.updateAllProgress {
                    Text("正在更新 \(prog.current)/\(prog.total) · \(prog.currentItemName)")
                        .font(DesignSystem.Typography.meta.weight(.medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                } else {
                    Text("\(updatableCount) 项可直接更新")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    if appState.manualFallbackCount > 0 {
                        Text("另有 \(appState.manualFallbackCount) 项需应用内更新")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    } else if appState.items.contains(where: { $0.needsSudo || $0.requiresLogin || $0.isSystemComponent }) {
                        Text("（已自动跳过需管理员/登录/系统组件项）")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
                Spacer()
                Button {
                    Task {
                        await appState.updateAll()
                    }
                } label: {
                    if appState.isUpdatingAll {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("更新中…")
                        }
                    } else {
                        Label("全部更新 (\(updatableCount))", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .controlSize(.small)
                .disabled(appState.isUpdatingAll)
            }
            if appState.isUpdatingAll, let prog = appState.updateAllProgress, prog.total > 0 {
                ProgressView(value: Double(prog.current), total: Double(prog.total))
                    .progressViewStyle(.linear)
                    .tint(DesignSystem.Colors.accent)
                    .animation(.easeInOut(duration: 0.3), value: prog.current)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 收敛的空状态（48pt 渐变圆底白勾 + 11pt secondary 说明 + 居中上移 1/3 + 一次性 spring 入场，零常驻闪烁，移除内容区扫描按钮）
    private var compactCelebrationState: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.20, green: 0.82, blue: 0.48),
                                Color(red: 0.10, green: 0.68, blue: 0.38)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)

                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
            }

            VStack(spacing: 4) {
                Text("所有软件均是最新版本")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if let lastScan = appState.lastScanDate {
                    Text("上次扫描 \(lastScan.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                } else {
                    Text("所有软件包均处于最新版本")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(hasAppeared ? 1.0 : (reduceMotion ? 1.0 : 0.90))
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                    hasAppeared = true
                }
            }
        }
    }

    // MARK: - 全源失败（与"全部最新"严格区分，docs/08 §6.6 状态诚实性）
    private var allSourcesFailedState: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.98, green: 0.65, blue: 0.22),
                                Color(red: 0.92, green: 0.48, blue: 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
            }

            VStack(spacing: 4) {
                Text("本次扫描未完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Text("\(appState.lastErrors.count) 个来源获取失败，请检查网络连接或对应工具是否正常")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task { await appState.reloadAll() }
            } label: {
                Text("重新扫描")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoading)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 搜索无结果
    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("未找到匹配的待更新软件")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

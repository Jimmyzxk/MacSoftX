import SwiftUI
import AppKit

/// 软件详情独立浮窗（默认 380×520）
/// 严格遵循 docs/08 §6.6 状态诚实性：废弃「受管/游离」用词，不声称任何未经核验的「已是最新」
public struct DetailFloatingView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        Group {
            if let payload = appState.pendingDetail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch payload {
                        case .scan(let item):
                            scanDetailContent(item: item)
                        case .inventory(let item):
                            inventoryDetailContent(item: item)
                        }
                    }
                    .padding(24)
                }
            } else {
                emptyGuidanceView
            }
        }
        .frame(minWidth: 360, idealWidth: 380, maxWidth: 440, minHeight: 480, idealHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.title == "详情" }) {
                    WindowManager.centerDetailWindowRelativeToMainWindow(detailWindow: window)
                }
            }
        }
        .onChange(of: appState.pendingDetail) { _, _ in
            DispatchQueue.main.async {
                if let window = NSApp.windows.first(where: { $0.title == "详情" }) {
                    WindowManager.centerDetailWindowRelativeToMainWindow(detailWindow: window)
                }
            }
        }
    }

    // MARK: - 扫描待更新软件详情
    @ViewBuilder
    private func scanDetailContent(item: UpdateItem) -> some View {
        // 头部：72pt 大图标 + 名称 + 来源徽章
        headerView(
            name: item.name,
            kind: item.kind,
            softwareKind: nil,
            sourceId: item.providerId,
            sourceDisplayName: EcosystemTheme.displayName(for: item.providerId),
            path: matchedAppPath(for: item),
            isManualInstall: false
        )

        Divider()

        // 版本信息（当前 → 最新，有更新时高亮）
        VStack(alignment: .leading, spacing: 8) {
            Text("版本升级")
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前版本")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(item.currentVersion)
                        .font(DesignSystem.Typography.version)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("最新可用")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(item.latestVersion ?? "?")
                        .font(DesignSystem.Typography.version)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }

                Spacer()

                if item.isSystemComponent {
                    Text("系统组件")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.35, green: 0.55, blue: 0.75).opacity(0.12), in: Capsule())
                } else {
                    Text("待更新")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.accent.opacity(0.12), in: Capsule())
                }
            }
            .padding(12)
            .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))
        }

        // 路径卡片（等宽 11pt + 复制按钮）
        if let path = matchedAppPath(for: item) {
            pathCardView(path: path)
        }

        Divider()

        // 操作按钮组：主操作独占一行（主 CTA 全宽是常规做法），次要操作并排，
        // 避免三个全宽按钮纵向堆叠成「长又窄」的条状（用户 2026-09-28 反馈）
        VStack(spacing: 10) {
            scanActionButtons(item: item)

            HStack(spacing: 10) {
                if let path = matchedAppPath(for: item) {
                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.name, forType: .string)
                } label: {
                    Label("复制名称", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: - 清单软件详情（诚实陈述，不声称更新结论）
    @ViewBuilder
    private func inventoryDetailContent(item: InventoryItem) -> some View {
        // 头部：72pt 大图标 + 名称 + 来源徽章（若是手动安装则展示「手动安装」徽章，来源本身即表达管辖）
        headerView(
            name: item.name,
            kind: nil,
            softwareKind: item.kind,
            sourceId: item.sourceId,
            sourceDisplayName: item.sourceDisplayName,
            path: item.path,
            isManualInstall: item.status == .unmanaged
        )

        Divider()

        // 已安装版本卡片（诚实陈述事实，不声称已是最新）
        VStack(alignment: .leading, spacing: 8) {
            Text("安装信息")
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已安装版本")
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(item.version)
                        .font(DesignSystem.Typography.version)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: item.kind == .app ? "app.fill" : "terminal.fill")
                        .font(.system(size: 10))
                    Text(item.kind == .app ? "应用软件" : "命令行工具")
                        .font(DesignSystem.Typography.badge)
                }
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.subtleFill, in: Capsule())
            }
            .padding(12)
            .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))
        }

        // 路径卡片
        if let path = item.path {
            pathCardView(path: path)
        }

        Divider()

        // 操作按钮组（内置更新器：启动并检查更新 / 可更新打开下载页 + 11pt secondary 说明）
        VStack(spacing: 10) {
            // 若经 cask 检测出可更新，优先展示主色「打开下载页」
            if let caskItem = appState.items.first(where: { $0.externalId == item.path && $0.infoURL != nil }), let infoURL = caskItem.infoURL, let url = URL(string: infoURL) {
                VStack(spacing: 6) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打开下载页", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help(infoURL)
                    Text("检测到新版本 \(caskItem.latestVersion ?? "")，点击打开下载页")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            } else if item.status == .unmanaged {
                VStack(spacing: 6) {
                    Button {
                        if let path = item.path {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    } label: {
                        Label("启动并检查更新", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("此类应用由自身携带的更新器管理，Macsoft X 无法代查更新")

                    Text("此类应用由自身携带的更新器管理，Macsoft X 无法代查更新")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 10) {
                if let path = item.path {
                    Button {
                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.regular)
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.name, forType: .string)
                } label: {
                    Label("复制名称", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: - 通用头部
    private func headerView(
        name: String,
        kind: Kind?,
        softwareKind: SoftwareKind?,
        sourceId: String,
        sourceDisplayName: String,
        path: String?,
        isManualInstall: Bool
    ) -> some View {
        HStack(spacing: 16) {
            AppIconView(
                name: name,
                kind: kind,
                softwareKind: softwareKind,
                sourceId: sourceId,
                path: path,
                size: 72
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    // 来源徽章（来源本身表达管辖）
                    HStack(spacing: 4) {
                        Circle()
                            .fill(EcosystemTheme.color(for: sourceId))
                            .frame(width: 6, height: 6)
                        Text(sourceDisplayName)
                            .font(DesignSystem.Typography.badge)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DesignSystem.Colors.subtleFill, in: Capsule())

                    // 未受包管理器管辖时，诚实标注「手动安装」
                    if isManualInstall {
                        Text("手动安装")
                            .font(DesignSystem.Typography.badge)
                            .foregroundStyle(DesignSystem.Colors.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.warning.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: - 路径卡片
    private func pathCardView(path: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("文件路径")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(DesignSystem.Typography.badge)
                }
                .buttonStyle(.borderless)
            }

            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(3)
                .truncationMode(.middle)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - 扫描更新操作组
    @ViewBuilder
    private func scanActionButtons(item: UpdateItem) -> some View {
        let status = appState.updateStatuses[item.id] ?? .idle

        if item.isSystemComponent {
            HStack {
                Spacer()
                Text("macOS 自带组件，随系统更新")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(Color(red: 0.35, green: 0.55, blue: 0.75))
                Spacer()
            }
            .padding(.vertical, 6)
        } else if item.requiresLogin {
            HStack {
                Spacer()
                Text("需登录账户后方可在 App Store 更新")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.vertical, 6)
        } else if item.needsSudo {
            HStack {
                Spacer()
                Text("需要管理员提权，请在终端中使用 sudo 更新")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.warning)
                Spacer()
            }
            .padding(.vertical, 6)
        } else {
            switch status {
            case .idle:
                if let token = item.caskToken, !token.isEmpty {
                    VStack(spacing: 10) {
                        Button {
                            Task { await appState.update(item) }
                        } label: {
                            Label("更新", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .help("通过 Homebrew 下载并安装新版本，应用会先退出，更新后由 Homebrew 接管管理")
                        if let infoURL = item.infoURL, let url = URL(string: infoURL) {
                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                Label("打开下载页", systemImage: "arrow.up.forward.app")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                            .help(infoURL)
                        }
                    }
                } else if let infoURL = item.infoURL, !infoURL.isEmpty {
                    VStack(spacing: 6) {
                        Button {
                            Task { await appState.update(item) }
                        } label: {
                            Label("打开下载页", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .help(infoURL)
                        if let latest = item.latestVersion {
                            Text("检测到新版本 \(latest)")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                    }
                } else if item.providerId.lowercased() == "apps" {
                    Button {
                        Task { await appState.update(item) }
                    } label: {
                        Label("启动并检查更新", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("将启动该应用并触发其内置更新检查")
                } else {
                    Button {
                        Task { await appState.update(item) }
                    } label: {
                        Label("立即更新", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

            case .updating:
                VStack(spacing: 10) {
                    Text("正在更新 \(item.name)")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(DesignSystem.Colors.accent)
                    HStack(spacing: 6) {
                        Text(item.currentVersion)
                            .font(.system(size: 15, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(item.latestVersion ?? "?")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Spacer()
                        if let start = appState.updateStartedAt[item.id] {
                            TimelineView(.periodic(from: start, by: 1)) { context in
                                let elapsed = Int(context.date.timeIntervalSince(start))
                                Text("已进行 \(elapsed)s")
                                    .font(DesignSystem.Typography.meta)
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    Text("通过 Homebrew 下载中，完成后应用由 Homebrew 接管")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.tile))

            case .success(let newVersion):
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.success)
                        .symbolEffect(.bounce, value: newVersion ?? item.latestVersion)
                    if let ver = newVersion ?? item.latestVersion {
                        Text("已更新到 \(ver)")
                            .font(DesignSystem.Typography.version.weight(.medium))
                            .foregroundStyle(DesignSystem.Colors.success)
                    } else {
                        Text("已更新")
                            .font(DesignSystem.Typography.meta.weight(.medium))
                            .foregroundStyle(DesignSystem.Colors.success)
                    }
                    Text("由 Homebrew 接管后续更新")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            case .handoff(let message):
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.circle")
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

            case .failure(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(DesignSystem.Colors.error)
                    Text(msg)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.error)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Button {
                        Task { await appState.update(item) }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 空态引导
    private var emptyGuidanceView: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .font(.system(size: 44))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Text("最好用的 Mac 软件管理工具")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("在主窗列表中双击任意软件，或将鼠标悬停点击「详情」按钮，即可在此查看完整的软件与版本信息。")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func matchedAppPath(for item: UpdateItem) -> String? {
        // externalId 对 apps 来源是应用路径（如 /Applications/Foo.app），不是 bundleId，
        // 直接喂给 urlForApplication(withBundleIdentifier:) 永远返回 nil。
        if let externalId = item.externalId,
           externalId.hasSuffix(".app"),
           FileManager.default.fileExists(atPath: externalId) {
            return externalId
        }
        let appDirs = ["/Applications", (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        for dir in appDirs {
            let direct = (dir as NSString).appendingPathComponent("\(item.name).app")
            if FileManager.default.fileExists(atPath: direct) { return direct }
        }
        return nil
    }
}

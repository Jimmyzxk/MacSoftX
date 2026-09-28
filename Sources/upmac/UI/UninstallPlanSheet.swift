import SwiftUI
import AppKit

/// 卸载清理计划弹窗（展示本体与散落文件、按目录分组勾选、二次确认移入废纸篓、展示执行结果）
public struct UninstallPlanSheet: View {
    let item: InventoryItem
    let onCompleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var plan: UninstallPlan? = nil
    @State private var isGenerating: Bool = true
    @State private var isExecuting: Bool = false
    @State private var executionResult: UninstallResult? = nil
    @State private var executionError: String? = nil
    @State private var showConfirmAlert: Bool = false

    public init(item: InventoryItem, onCompleted: @escaping () -> Void) {
        self.item = item
        self.onCompleted = onCompleted
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Text(executionResult == nil ? "清理计划" : "卸载结果")
                    .font(DesignSystem.Typography.headline)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(isExecuting)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .overlay(Divider(), alignment: .bottom)

            // 主体区域
            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在扫描散落残留文件…")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = executionResult {
                resultView(result)
            } else if let currentPlan = plan {
                if currentPlan.isAppleProtected {
                    appleProtectedView(currentPlan)
                } else {
                    planContentView(currentPlan)
                }
            } else {
                Text("无法生成清理计划")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 540, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            let generated = UninstallService.shared.generatePlan(for: item)
            self.plan = generated
            self.isGenerating = false
        }
        .alert("确认移入废纸篓？", isPresented: $showConfirmAlert) {
            Button("移入废纸篓", role: .destructive) {
                performUninstall()
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let p = plan {
                Text("将把已选的 \(p.selectedFilesCount) 项文件（共 \(p.formattedTotalSelectedSize)）移入废纸篓。\n您可以随时在 macOS 废纸篓中还原。")
            } else {
                Text("确认继续？")
            }
        }
    }

    // MARK: - 计划内容视图
    @ViewBuilder
    private func planContentView(_ plan: UninstallPlan) -> some View {
        VStack(spacing: 0) {
            // 目标软件头部信息卡
            HStack(spacing: 12) {
                AppIconView(
                    name: item.name,
                    softwareKind: item.kind,
                    sourceId: item.sourceId,
                    path: item.path,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(DesignSystem.Typography.headline)
                            .foregroundStyle(DesignSystem.Colors.textPrimary)

                        Text(item.version)
                            .font(DesignSystem.Typography.badge)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(DesignSystem.Colors.subtleFill, in: Capsule())
                    }

                    HStack(spacing: 6) {
                        Text(item.sourceDisplayName)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)

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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .overlay(Divider(), alignment: .bottom)

            // 卸载方式提示条
            HStack(spacing: 8) {
                switch plan.method {
                case .packageManager(_, _, let provider):
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(Color.blue)
                        .font(.system(size: 13))
                    Text("受管卸载：将执行 \(plan.method.displayCommand)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Text(provider)
                        .font(DesignSystem.Typography.badge)
                        .foregroundStyle(Color.blue)

                case .fileTrash:
                    Image(systemName: "trash.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 13))
                    Text("文件清理：选定文件将安全移入废纸篓（非 rm 删除，可放回原处）")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.subtleFill.opacity(0.3))
            .overlay(Divider(), alignment: .bottom)

            // 散落文件列表 / 无散落文件提示
            if !plan.hasScatteredFiles {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.success)

                    Text("未发现散落文件，仅移除应用本体")
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    if let path = plan.appPath {
                        Text(path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .padding(.horizontal, 20)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ScatteredFileCategory.allCases, id: \.self) { category in
                            let catFiles = plan.files.filter { $0.category == category }
                            if !catFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(category.rawValue)
                                            .font(DesignSystem.Typography.badge.weight(.semibold))
                                            .foregroundStyle(DesignSystem.Colors.textSecondary)

                                        Spacer()

                                        let catSize = catFiles.reduce(0) { $0 + $1.sizeInBytes }
                                        Text(ByteCountFormatter.string(fromByteCount: catSize, countStyle: .file))
                                            .font(DesignSystem.Typography.meta)
                                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                                    }
                                    .padding(.top, 4)

                                    ForEach(catFiles) { file in
                                        fileRow(file)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
            }

            // 底部操作确认栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已选 \(plan.selectedFilesCount) 项 · 共 \(plan.formattedTotalSelectedSize)")
                        .font(DesignSystem.Typography.bodyMedium.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)

                    Text("安全红线：所有文件一律移入废纸篓，绝不执行硬删除")
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Spacer()

                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    showConfirmAlert = true
                } label: {
                    if isExecuting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(isManagedItem ? "确认执行卸载" : "移入废纸篓")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.red)
                .disabled(isExecuting || plan.selectedFilesCount == 0 && !isManagedItem)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            .overlay(Divider(), alignment: .top)
        }
    }

    private var isManagedItem: Bool {
        if let p = plan, case .packageManager = p.method {
            return true
        }
        return false
    }

    // 单个文件勾选行
    @ViewBuilder
    private func fileRow(_ file: ScatteredFileItem) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { file.isSelected },
                set: { newValue in
                    if var current = plan, let idx = current.files.firstIndex(where: { $0.id == file.id }) {
                        current.files[idx].isSelected = newValue
                        plan = current
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Text(file.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(file.formattedSize)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(file.isSelected ? Color.blue.opacity(0.05) : Color.clear)
        )
    }

    // MARK: - 苹果系统应用保护视图
    @ViewBuilder
    private func appleProtectedView(_ plan: UninstallPlan) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.red)

            Text("受系统保护的核心应用")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            Text(plan.warningMessage ?? "Apple 系统应用禁止卸载。")
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 执行结果视图
    @ViewBuilder
    private func resultView(_ result: UninstallResult) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(result.isSuccess ? DesignSystem.Colors.success : DesignSystem.Colors.warning)

            Text(result.isSuccess ? "卸载完成" : "卸载未完全成功")
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if let msg = result.message {
                Text(msg)
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }

            if result.totalFreedBytes > 0 {
                Text("已释放约 \(result.formattedFreedSize) 空间（已安全移至废纸篓）")
                    .font(DesignSystem.Typography.badge)
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.10), in: Capsule())
            }

            if !result.failedPaths.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("未能移入废纸篓的文件：")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.warning)

                    ForEach(Array(result.failedPaths.keys.prefix(3)), id: \.self) { path in
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .background(DesignSystem.Colors.subtleFill, in: RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 24)
            }

            Spacer()

            Button("完成") {
                dismiss()
                onCompleted()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 执行卸载
    private func performUninstall() {
        guard !isExecuting else { return }
        guard let p = plan else { return }
        isExecuting = true
        executionError = nil

        Task {
            do {
                let res = try await UninstallService.shared.executePlan(p)
                await MainActor.run {
                    self.executionResult = res
                    self.isExecuting = false
                }
            } catch {
                await MainActor.run {
                    self.executionError = error.localizedDescription
                    self.executionResult = UninstallResult(
                        targetName: p.targetItem.name,
                        isSuccess: false,
                        trashedPaths: [],
                        failedPaths: [:],
                        message: error.localizedDescription,
                        totalFreedBytes: 0
                    )
                    self.isExecuting = false
                }
            }
        }
    }
}

import SwiftUI

/// Macsoft X 设计系统 Token 唯一出口
/// 严格遵循 docs/08-design-spec.md、docs/09-art-direction.md 与 docs/10-branding-sidebar.md
public enum DesignSystem {

    // MARK: - 颜色语义（docs/08 §3 & docs/09 §6）
    public enum Colors {
        /// 主操作（唯一强调色，系统蓝）
        public static let accent = Color.accentColor
        /// 错误（系统红）
        public static let error = Color.red
        /// 警示（系统橙）
        public static let warning = Color.orange
        /// 成功（系统绿）
        public static let success = Color.green

        /// 文本主要
        public static let textPrimary = Color.primary
        /// 文本次要
        public static let textSecondary = Color.secondary
        /// 文本三级（Color 无静态 tertiary，按 0.4 透明度保证类型一致与消费端兼容）
        public static let textTertiary = Color.primary.opacity(0.4)

        /// 卡片浅色背景底
        public static let cardBackground = Color.primary.opacity(0.04)
        /// 徽章与胶囊浅底
        public static let subtleFill = Color.primary.opacity(0.06)

        /// 内容行 hover 背景：primary 6%（迭代 2.10）
        public static let rowHoverBackground = Color.primary.opacity(0.06)
        /// 分组间隔 hairline: primary 8%（docs/09 §4）
        public static let hairline = Color.primary.opacity(0.08)
    }

    // MARK: - 圆角 Tokens（三档，禁止自造，docs/08 §3 & docs/09 §4）
    public enum CornerRadius {
        /// 卡片圆角：20pt
        public static let card: CGFloat = 20
        /// 图标砖与行 hover 圆角：8pt
        public static let tile: CGFloat = 8
        /// 胶囊圆角：999pt
        public static let capsule: CGFloat = 999
    }

    // MARK: - 间距与尺寸 Tokens（docs/09 §4 & 迭代 2.10）
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24

        /// 内容区标准行高：56pt（增加呼吸感，迭代 2.10）
        public static let rowHeight: CGFloat = 56
        /// 行内图标标准尺寸：36pt（docs/09 §4）
        public static let iconSize: CGFloat = 36
        /// 内容行间距：2pt（docs/09 §4）
        public static let rowSpacing: CGFloat = 2
        /// 生态标记点（4-6pt）
        public static let dotSize: CGFloat = 5
        /// 最小可点热区
        public static let minTouchTarget: CGFloat = 28
    }

    // MARK: - 列表行布局度量（ScanRowView / InventoryRowView 共用，迭代 2.11）
    public enum RowMetrics {
        /// 行高：56pt（与 Spacing.rowHeight 对齐）
        public static let rowHeight: CGFloat = 56
        /// 行内图标尺寸：36pt（与 Spacing.iconSize 对齐）
        public static let iconSize: CGFloat = 36
        /// 行首内边距：16pt
        public static let leadingPadding: CGFloat = 16
        /// 徽章字体：10pt medium
        public static let badgeFont = Font.system(size: 10, weight: .medium)
        /// 徽章水平内边距：6pt
        public static let badgeHorizontalPadding: CGFloat = 6
        /// 徽章垂直内边距：2pt
        public static let badgeVerticalPadding: CGFloat = 2
        /// 徽章圆角：4pt（胶囊退化为小圆角胶囊，增强统一感）
        public static let badgeCornerRadius: CGFloat = 4
        /// 徽章字体备用（语义同 badgeFont）
        public static let badgeFontAlternative = Font.system(size: 10, weight: .medium, design: .rounded)
    }

    // MARK: - 类型标尺（六档严格规范，docs/09 §2 & 迭代 2.10）
    public enum Typography {
        /// 1. 大数字：34pt rounded bold（侧栏头部剩余数）
        public static let metricLarge = Font.system(size: 34, weight: .bold, design: .rounded)

        /// 2. 页面标题：22pt bold
        public static let pageTitle = Font.system(size: 22, weight: .bold)

        /// 3. 区块头：13pt semibold secondary（分组标题）
        public static let sectionHeader = Font.system(size: 13, weight: .semibold)
        public static let headline = Font.system(size: 13, weight: .semibold)

        /// 4. 正文：13pt regular（行名称 14pt medium，迭代 2.10）
        public static let body = Font.system(size: 13, weight: .regular)
        public static let bodyMedium = Font.system(size: 14, weight: .medium)
        public static let bodyBold = Font.system(size: 14, weight: .medium)
        public static let subheadline = Font.system(size: 13, weight: .regular)

        /// 5. 元信息：11pt regular secondary（副标题/路径/时间）
        public static let meta = Font.system(size: 11, weight: .regular)
        public static let caption = Font.system(size: 11, weight: .regular)
        public static let caption2 = Font.system(size: 11, weight: .regular)
        public static let footnote = Font.system(size: 11, weight: .regular)

        /// 6. 徽章：11pt rounded medium（计数/版本胶囊）
        public static let badge = Font.system(size: 11, weight: .medium, design: .rounded)
        public static let version = Font.system(size: 11, weight: .regular, design: .monospaced)
        public static let number = Font.system(size: 11, weight: .medium, design: .rounded)
    }
}

/// 生态色板与视觉设计 Tokens（原 Theme.swift，已迁移至 DesignSystem 以消除死文件）
public enum EcosystemTheme {
    // MARK: - 全局唯一强调色（系统蓝）
    public static let systemAccent = DesignSystem.Colors.accent

    // MARK: - 生态色板（每源一对渐变色：Homebrew 琥珀系、npm 红系、AppStore 蓝系、gem 宝石红系、uv 黄系、独立应用中性灰蓝系）
    public static let homebrew = Color(red: 0.94, green: 0.58, blue: 0.16) // Homebrew 琥珀
    public static let appStore = Color(red: 0.08, green: 0.48, blue: 0.98) // App Store 蓝
    public static let apps = Color(red: 0.20, green: 0.55, blue: 0.95)     // Sparkle 应用 蓝
    public static let npm = Color(red: 0.82, green: 0.18, blue: 0.22)      // npm 红
    public static let pip = Color(red: 0.95, green: 0.77, blue: 0.18)      // pip/uv 黄
    public static let cargo = Color(red: 0.83, green: 0.43, blue: 0.18)    // Cargo 橙棕
    public static let gem = Color(red: 0.76, green: 0.12, blue: 0.28)      // RubyGems 宝石红
    public static let standalone = Color(red: 0.45, green: 0.55, blue: 0.65) // 游离应用 灰蓝
    public static let fallback = Color.secondary

    // MARK: - 主题渐变（主数字 / 环仪表盘主色系）
    public static let heroGradient = LinearGradient(
        colors: [Color(red: 0.15, green: 0.55, blue: 0.98), Color(red: 0.05, green: 0.38, blue: 0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - 尺寸与圆角 Tokens（严格对齐 DesignSystem）
    public static let rowHeight: CGFloat = DesignSystem.Spacing.rowHeight
    public static let iconSize: CGFloat = DesignSystem.Spacing.iconSize
    public static let dotSize: CGFloat = DesignSystem.Spacing.dotSize
    public static let cardCornerRadius: CGFloat = DesignSystem.CornerRadius.card       // 20
    public static let iconTileCornerRadius: CGFloat = DesignSystem.CornerRadius.tile   // 8
    public static let heroCornerRadius: CGFloat = DesignSystem.CornerRadius.card       // 20

    /// 获取更新源对应的标准生态主色
    public static func color(for providerId: String) -> Color {
        switch providerId.lowercased() {
        case "brew", "homebrew", "brew-formula", "brew-cask":
            return homebrew
        case "mas", "appstore", "app store":
            return appStore
        case "apps":
            return apps
        case "npm", "pnpm", "yarn", "bun":
            return npm
        case "pip", "pipx", "uv", "python":
            return pip
        case "cargo", "rust":
            return cargo
        case "gem", "rubygems", "ruby":
            return gem
        case "standalone", "app":
            return standalone
        default:
            return fallback
        }
    }

    /// 获取更新源对应的渐变色对 (start, end)
    public static func gradientColors(for providerId: String) -> (Color, Color) {
        switch providerId.lowercased() {
        case "brew", "homebrew", "brew-formula", "brew-cask":
            return (Color(red: 0.98, green: 0.65, blue: 0.16), Color(red: 0.85, green: 0.44, blue: 0.08))
        case "mas", "appstore", "app store":
            return (Color(red: 0.20, green: 0.58, blue: 1.00), Color(red: 0.05, green: 0.38, blue: 0.88))
        case "apps":
            return (Color(red: 0.30, green: 0.62, blue: 0.98), Color(red: 0.12, green: 0.44, blue: 0.86))
        case "npm", "pnpm", "yarn", "bun":
            return (Color(red: 0.95, green: 0.30, blue: 0.30), Color(red: 0.78, green: 0.14, blue: 0.16))
        case "pip", "pipx", "uv", "python":
            return (Color(red: 0.98, green: 0.78, blue: 0.18), Color(red: 0.86, green: 0.60, blue: 0.06))
        case "cargo", "rust":
            return (Color(red: 0.92, green: 0.50, blue: 0.22), Color(red: 0.74, green: 0.34, blue: 0.12))
        case "gem", "rubygems", "ruby":
            return (Color(red: 0.90, green: 0.20, blue: 0.40), Color(red: 0.68, green: 0.08, blue: 0.24))
        case "standalone", "app":
            return (Color(red: 0.52, green: 0.62, blue: 0.74), Color(red: 0.38, green: 0.48, blue: 0.60))
        default:
            return (Color(red: 0.55, green: 0.55, blue: 0.62), Color(red: 0.40, green: 0.40, blue: 0.46))
        }
    }

    /// 获取生态渐变（从左上到右下）
    public static func gradient(for providerId: String) -> LinearGradient {
        let (start, end) = gradientColors(for: providerId)
        return LinearGradient(
            colors: [start, end],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 获取生态源的用户友好展示名称
    public static func displayName(for providerId: String) -> String {
        switch providerId.lowercased() {
        case "brew", "homebrew":
            return "Homebrew"
        case "brew-formula":
            return "Homebrew Formula"
        case "brew-cask":
            return "Homebrew Cask"
        case "mas", "appstore", "app store":
            return "App Store"
        case "apps":
            return "应用"
        case "npm":
            return "npm"
        case "pip", "pipx", "uv":
            return "pip / uv"
        case "cargo":
            return "Cargo"
        case "gem":
            return "RubyGems"
        case "standalone", "app":
            return "应用"
        default:
            return providerId.uppercased()
        }
    }

    /// 获取生态图标砖 SF Symbol 图标名
    public static func symbol(for providerId: String, kind: Kind) -> String {
        switch providerId.lowercased() {
        case "apps":
            return "macwindow"
        case "mas", "appstore", "app store":
            return "arrow.down.app.fill"
        case "brew", "homebrew", "brew-formula", "brew-cask":
            switch kind {
            case .formula, .cli:
                return "terminal.fill"
            case .cask, .app:
                return "macwindow"
            case .mas:
                return "arrow.down.app.fill"
            }
        case "npm":
            return "shippingbox.fill"
        case "pip", "pipx", "uv":
            return "puzzlepiece.fill"
        case "cargo":
            return "cube.box.fill"
        case "gem":
            return "suit.diamond.fill"
        default:
            switch kind {
            case .formula, .cli:
                return "terminal.fill"
            case .cask, .app:
                return "macwindow"
            case .mas:
                return "arrow.down.app.fill"
            }
        }
    }

    /// 获取命令行工具的 1-2 字母 Monogram 简称
    public static func monogram(for name: String) -> String {
        let clean = name.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let parts = clean.split(separator: "-").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        } else if clean.count >= 2 {
            return String(clean.prefix(2)).uppercased()
        } else if clean.count == 1 {
            return clean.uppercased()
        }
        return ">"
    }
}

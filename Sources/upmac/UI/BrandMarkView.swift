import SwiftUI

/// C2 徽记背部 M 字负空间高亮发光轮廓（docs/10 §1）
public struct BrandMContourShape: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // 对应 concept-c2.svg 中 M 318 700 L 318 396 L 512 534 L 706 396 L 706 700 相对坐标
        path.move(to: CGPoint(x: w * 0.265, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.265, y: h * 0.36))
        path.addLine(to: CGPoint(x: w * 0.500, y: h * 0.53))
        path.addLine(to: CGPoint(x: w * 0.735, y: h * 0.36))
        path.addLine(to: CGPoint(x: w * 0.735, y: h * 0.72))

        return path
    }
}

/// 纯 SwiftUI 矢量循环双箭头剪影（上弧+下弧+双箭头，C2 核心徽记与菜单栏同款）
public struct BrandDualArrowsView: View {
    public var color: Color

    public init(color: Color = .white) {
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let scale = s / 32.0
            let ox = (proxy.size.width - s) / 2
            let oy = (proxy.size.height - s) / 2

            ZStack {
                // 1. 上弧与下弧（贝塞尔平滑圆弧）
                Path { path in
                    // 上弧：从 (25.6, 10.2) 经顶部拱形扫向 (7.0, 12.2)
                    path.move(to: brandPoint(25.6, 10.2, ox: ox, oy: oy, scale: scale))
                    path.addQuadCurve(
                        to: brandPoint(7.0, 12.2, ox: ox, oy: oy, scale: scale),
                        control: brandPoint(16.3, 1.0, ox: ox, oy: oy, scale: scale)
                    )

                    // 下弧：从 (6.4, 21.8) 经底部拱形扫向 (25.0, 19.8)
                    path.move(to: brandPoint(6.4, 21.8, ox: ox, oy: oy, scale: scale))
                    path.addQuadCurve(
                        to: brandPoint(25.0, 19.8, ox: ox, oy: oy, scale: scale),
                        control: brandPoint(15.7, 31.0, ox: ox, oy: oy, scale: scale)
                    )
                }
                .stroke(color, style: StrokeStyle(lineWidth: max(1.2, 3.4 * scale), lineCap: .round))

                // 2. 上下箭头三角（实心填充）
                Path { path in
                    // 上箭头三角
                    path.move(to: brandPoint(26.6, 3.9, ox: ox, oy: oy, scale: scale))
                    path.addLine(to: brandPoint(27.2, 13.0, ox: ox, oy: oy, scale: scale))
                    path.addLine(to: brandPoint(18.3, 9.8, ox: ox, oy: oy, scale: scale))
                    path.closeSubpath()

                    // 下箭头三角
                    path.move(to: brandPoint(5.4, 28.1, ox: ox, oy: oy, scale: scale))
                    path.addLine(to: brandPoint(4.8, 19.0, ox: ox, oy: oy, scale: scale))
                    path.addLine(to: brandPoint(13.7, 22.2, ox: ox, oy: oy, scale: scale))
                    path.closeSubpath()
                }
                .fill(color)
            }
        }
    }
}

/// 菜单栏同款循环箭头剪影（SwiftUI Path 直接绘制，Color.primary 黑色/白色自动适配系统明暗菜单栏）
public struct MenuBarCycleIcon: View {
    public var size: CGFloat

    public init(size: CGFloat = 16) {
        self.size = size
    }

    public var body: some View {
        BrandDualArrowsView(color: .primary)
            .frame(width: size, height: size)
    }
}

/// 纯 SwiftUI 复刻 C2 定稿品牌徽记（Macsoft X 官方 Logo，docs/10 §1）
/// ZStack 三元素构图：
/// 1. 左侧圆角竖片（系统蓝至深蓝渐变，#0A84FF -> #0055CC）
/// 2. 右侧圆角竖片（青至电光蓝渐变，#00C7BE -> #008877）
/// 3. 顶部中心循环箭头徽记圆（青色渐变底 + 纯白双弧线与三角箭头）
/// 支持 .colorful（侧栏与关于页彩色主徽记，去掉暗色底座）与 .silhouette（单色剪影）样式
public struct BrandMarkView: View {
    public enum Style {
        case colorful    // concept-c2 纯彩色矢量：去掉暗色底座，左蓝右青彩色渐变，青底白箭头
        case silhouette  // 单色剪影：仅供未来菜单栏模板或单色印刷场景使用
    }

    public var size: CGFloat
    public var style: Style

    public init(size: CGFloat = 28, style: Style = .colorful) {
        self.size = size
        self.style = style
    }

    public init(size: CGFloat = 28, includeBase: Bool) {
        self.size = size
        self.style = .colorful
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            // 按 concept-c2 核心三元素边界 568×410 等比居中缩放
            let scale = min(w / 568.0, h / 410.0)
            let cx = w / 2
            let cy = h / 2

            let blockW = 180 * scale
            let blockH = 350 * scale
            let cornerR = max(2.0, 32 * scale)
            let badgeD = 152 * scale

            ZStack {
                switch style {
                case .colorful:
                    // 1. 左侧圆角竖片（蓝渐变：#0A84FF -> #0055CC）
                    RoundedRectangle(cornerRadius: cornerR)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 10/255.0, green: 132/255.0, blue: 255/255.0),
                                    Color(red: 0/255.0, green: 85/255.0, blue: 204/255.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerR)
                                .stroke(Color.white.opacity(0.35), lineWidth: max(0.5, 2.0 * scale))
                        )
                        .frame(width: blockW, height: blockH)
                        .position(x: cx - 194 * scale, y: cy + 30 * scale)

                    // 2. 右侧圆角竖片（青渐变：#00C7BE -> #008877）
                    RoundedRectangle(cornerRadius: cornerR)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0/255.0, green: 199/255.0, blue: 190/255.0),
                                    Color(red: 0/255.0, green: 136/255.0, blue: 119/255.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerR)
                                .stroke(Color.white.opacity(0.35), lineWidth: max(0.5, 2.0 * scale))
                        )
                        .frame(width: blockW, height: blockH)
                        .position(x: cx + 194 * scale, y: cy + 30 * scale)

                    // 3. 顶部中心循环箭头徽记圆（青色渐变底 + 纯白循环双箭头）
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0/255.0, green: 245/255.0, blue: 212/255.0),
                                        Color(red: 0/255.0, green: 199/255.0, blue: 190/255.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.70), lineWidth: max(0.5, 2.0 * scale))
                            )
                            .shadow(color: Color(red: 0, green: 40/255.0, blue: 100/255.0).opacity(0.30), radius: max(1.0, 4.0 * scale), y: max(0.5, 2.0 * scale))

                        BrandDualArrowsView(color: .white)
                            .padding(badgeD * 0.16)
                    }
                    .frame(width: badgeD, height: badgeD)
                    .position(x: cx, y: cy - 129 * scale)

                case .silhouette:
                    // 单色剪影模式（仅用于菜单栏模板等场景）
                    RoundedRectangle(cornerRadius: cornerR)
                        .fill(Color.primary)
                        .frame(width: blockW, height: blockH)
                        .position(x: cx - 194 * scale, y: cy + 30 * scale)

                    RoundedRectangle(cornerRadius: cornerR)
                        .fill(Color.primary)
                        .frame(width: blockW, height: blockH)
                        .position(x: cx + 194 * scale, y: cy + 30 * scale)

                    ZStack {
                        Circle()
                            .fill(Color.primary)
                        BrandDualArrowsView(color: Color(nsColor: .windowBackgroundColor))
                            .padding(badgeD * 0.16)
                    }
                    .frame(width: badgeD, height: badgeD)
                    .position(x: cx, y: cy - 129 * scale)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 矢量缩放坐标转换私有助手
private func brandPoint(_ x: CGFloat, _ y: CGFloat, ox: CGFloat, oy: CGFloat, scale: CGFloat) -> CGPoint {
    CGPoint(x: ox + x * scale, y: oy + y * scale)
}


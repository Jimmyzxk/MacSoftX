import SwiftUI
import AppKit

public struct AppIconView: View {
    let name: String
    let kind: Kind?
    let softwareKind: SoftwareKind?
    let sourceId: String
    let path: String?
    let size: CGFloat

    public init(
        name: String,
        kind: Kind? = nil,
        softwareKind: SoftwareKind? = nil,
        sourceId: String,
        path: String? = nil,
        size: CGFloat = EcosystemTheme.iconSize
    ) {
        self.name = name
        self.kind = kind
        self.softwareKind = softwareKind
        self.sourceId = sourceId
        self.path = path
        self.size = size
    }

    private var isApp: Bool {
        if let softwareKind = softwareKind {
            return softwareKind == .app
        }
        if let kind = kind {
            return kind == .cask || kind == .mas || kind == .app
        }
        return false
    }

    private var realAppIcon: NSImage? {
        guard isApp else { return nil }
        if let path = path, !path.isEmpty {
            return AppIconFinder.shared.icon(forPath: path)
        }
        return AppIconFinder.shared.icon(forItemName: name)
    }

    private var cornerRadius: CGFloat {
        if size > 48 {
            return 16.0
        }
        return EcosystemTheme.iconTileCornerRadius
    }

    public var body: some View {
        if let icon = realAppIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // 图标砖升级为生态渐变底（每源一对渐变色，渐变→白色 SF Symbol/monogram）
            let gradient = EcosystemTheme.gradient(for: sourceId)
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(gradient)

                Text(EcosystemTheme.monogram(for: name))
                    .font(.system(size: size > 48 ? 26 : 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
        }
    }
}

import AppKit
import SwiftUI

/// Layout numbers for tabs and the folder panel. Derived only from Shape and Font
/// settings — never from Style (Flat/Gradient/Liquid/…).
struct TabMetrics: Equatable {
    var fontSize: CGFloat
    var fontWeight: Font.Weight
    var nsFontWeight: NSFont.Weight
    var fontDesign: Font.Design
    var fontName: String?
    var tabThickness: CGFloat
    var protrusion: CGFloat
    var iconSize: CGFloat
    var iconSpacing: CGFloat
    var horizontalEndPad: CGFloat
    var verticalEndPad: CGFloat
    var panelPadding: CGFloat
    var cornerRadius: CGFloat
    var slant: CGFloat
    var overlap: CGFloat
    var tabHeight: CGFloat

    var font: Font {
        if let fontName {
            return Font.custom(fontName, size: fontSize).weight(fontWeight)
        }
        return Font.system(size: fontSize, weight: fontWeight, design: fontDesign)
    }

    var nsFont: NSFont {
        if let fontName, let custom = NSFont(name: fontName, size: fontSize) {
            return custom
        }
        return NSFont.systemFont(ofSize: fontSize, weight: nsFontWeight)
    }

    /// Space a label needs besides its text. `TabFaceLabel` reserves the same amount, so a
    /// tab sized with `fittedLength(for:horizontal:)` never truncates its title.
    func labelChrome(horizontal: Bool) -> CGFloat {
        let ends = horizontal ? horizontalEndPad * 2 : verticalEndPad * 2
        return iconSize + iconSpacing + ends + overlap
    }

    func fittedLength(for title: String, horizontal: Bool) -> CGFloat {
        // SwiftUI can render a hair wider than AppKit measures, hence the slack.
        let text = ceil((title as NSString).size(withAttributes: [.font: nsFont]).width) + 2
        return text + labelChrome(horizontal: horizontal)
    }

    static func make(settings: SkuffSettings, isPro: Bool) -> TabMetrics {
        make(
            shape: settings.effectiveShape(isPro: isPro),
            fontName: isPro ? settings.globalFontName : nil,
            fontSize: isPro ? settings.globalFontSize : 13,
            fontWeight: isPro ? settings.globalFontWeight : 0.4
        )
    }

    static func make(shape: EffectiveShape, fontName: String?, fontSize: Double, fontWeight: Double) -> TabMetrics {
        let size = CGFloat(fontSize)
        let resolvedName: String?
        if let fontName, !fontName.isEmpty, NSFont(name: fontName, size: size) != nil {
            resolvedName = fontName
        } else {
            resolvedName = nil
        }
        return TabMetrics(
            fontSize: size,
            fontWeight: skuffFontWeight(fontWeight),
            nsFontWeight: skuffNSFontWeight(fontWeight),
            fontDesign: .default,
            fontName: resolvedName,
            tabThickness: shape.tabWidth,
            protrusion: 12,
            iconSize: 13,
            iconSpacing: 6,
            horizontalEndPad: shape.slant + 10,
            verticalEndPad: shape.slant + 6,
            panelPadding: 16,
            cornerRadius: shape.cornerRadius,
            slant: shape.slant,
            overlap: shape.overlap,
            tabHeight: shape.tabHeight
        )
    }
}

/// Horizontal label composed first, then rotated for left/right tabs.
struct TabFaceLabel: View {
    var title: String
    var icon: TabIcon?
    var locked: Bool
    var metrics: TabMetrics
    var ink: Color
    var horizontal: Bool
    var maxAlong: CGFloat

    var body: some View {
        let row = HStack(spacing: metrics.iconSpacing) {
            glyph
            Text(title)
                .font(metrics.font)
                .foregroundStyle(ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
        }
        .fixedSize()
        Group {
            if horizontal {
                row
            } else {
                RotatedTabLabel {
                    row.rotationEffect(.degrees(90))
                }
            }
        }
        .padding(labelInsets)
        .help(title)
    }

    private var maxTextWidth: CGFloat {
        max(24, maxAlong - metrics.labelChrome(horizontal: horizontal))
    }

    /// Each later tab is drawn over the end of the one before it, so the overlap is
    /// reserved at the trailing end (right, or bottom when vertical).
    private var labelInsets: EdgeInsets {
        if horizontal {
            return EdgeInsets(top: 0, leading: metrics.horizontalEndPad, bottom: 0, trailing: metrics.horizontalEndPad + metrics.overlap)
        }
        return EdgeInsets(top: metrics.verticalEndPad, leading: 2, bottom: metrics.verticalEndPad + metrics.overlap, trailing: 2)
    }

    @ViewBuilder
    private var glyph: some View {
        Group {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: metrics.iconSize - 1, weight: .bold))
                    .foregroundStyle(ink)
            } else {
                switch icon {
                case .emoji(let value):
                    Text(value).font(.system(size: metrics.iconSize - 1))
                case .sfSymbol(let value):
                    Image(systemName: value)
                        .font(.system(size: metrics.iconSize - 1, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(ink)
                case .image(let filename):
                    if let image = IconStore.image(named: filename) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: metrics.iconSize, height: metrics.iconSize)
                    } else {
                        Image(systemName: "folder")
                            .font(.system(size: metrics.iconSize - 1, weight: .semibold))
                            .foregroundStyle(ink)
                    }
                case nil:
                    Image(systemName: "folder")
                        .font(.system(size: metrics.iconSize - 1, weight: .semibold))
                        .foregroundStyle(ink)
                }
            }
        }
        .frame(width: metrics.iconSize, height: metrics.iconSize)
        .accessibilityHidden(true)
    }
}

/// Swaps width/height after the child is composed horizontally and rotated.
struct RotatedTabLabel: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.height, height: size.width)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.height, height: bounds.width)
        )
    }
}

#if DEBUG
enum TabMetricsProbe {
    @MainActor
    static func assertStyleIndependentFrames() {
        let settings = SkuffSettings()
        let metrics = TabMetrics.make(settings: settings, isPro: true)
        let paint = SkuffColor(hex: "F6C6CE")
        let face = TrapezoidTabShape(
            slant: metrics.slant,
            cornerRadius: metrics.cornerRadius,
            edge: .bottom,
            skew: 0
        )
        var firstTab: CGSize?
        var firstPanel: CGSize?
        for finish in TabFinish.allCases {
            let tabSize = fittingSize(of: tabProbe(finish: finish, metrics: metrics, paint: paint, face: face))
            let panelSize = fittingSize(of: panelProbe(finish: finish, metrics: metrics, paint: paint))
            if let firstTab {
                assert(
                    abs(tabSize.width - firstTab.width) < 1 && abs(tabSize.height - firstTab.height) < 1,
                    "Style \(finish.rawValue) changed tab layout \(tabSize) vs \(firstTab)"
                )
            } else {
                firstTab = tabSize
            }
            if let firstPanel {
                assert(
                    abs(panelSize.width - firstPanel.width) < 1 && abs(panelSize.height - firstPanel.height) < 1,
                    "Style \(finish.rawValue) changed panel layout \(panelSize) vs \(firstPanel)"
                )
            } else {
                firstPanel = panelSize
            }
        }
    }

    @MainActor
    private static func fittingSize(of view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 240)
        return host.fittingSize
    }

    private static func tabProbe(finish: TabFinish, metrics: TabMetrics, paint: SkuffColor, face: TrapezoidTabShape) -> some View {
        TabFaceLabel(
            title: "Office",
            icon: .sfSymbol("briefcase"),
            locked: false,
            metrics: metrics,
            ink: skuffTabInk(finish: finish, paint: paint),
            horizontal: true,
            maxAlong: 120
        )
        .background {
            TabBackground(
                style: finish,
                face: face,
                paint: paint,
                palette: [paint.color],
                locked: false,
                isActive: true,
                isHovered: false,
                reduceMotion: true,
                edge: .bottom
            )
        }
        .frame(width: 120, height: metrics.tabThickness)
    }

    private static func panelProbe(finish: TabFinish, metrics: TabMetrics, paint: SkuffColor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Office").font(metrics.font)
            Text("3 items").font(metrics.font)
        }
        .padding(metrics.panelPadding)
        .frame(width: 240, height: 160)
        .background {
            TabBackground(
                style: finish,
                face: TrapezoidTabShape(slant: 0, cornerRadius: metrics.cornerRadius, edge: .bottom),
                paint: paint,
                palette: [paint.color],
                locked: false,
                isActive: false,
                isHovered: false,
                reduceMotion: true,
                edge: .bottom
            )
        }
    }
}
#endif

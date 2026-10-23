import SwiftUI

struct TabBackground: View {
    var style: TabFinish
    var face: TrapezoidTabShape
    var paint: SkuffColor
    var palette: [Color]
    var locked: Bool
    var isActive: Bool
    var isHovered: Bool
    var reduceMotion: Bool
    var edge: ScreenEdge

    @State private var neonGlow = 0.82

    var body: some View {
        let color = paint.color.opacity(locked ? 0.55 : 1)
        // The window server sends clicks on fully transparent pixels to the window below.
        // Glass finishes are composited outside the window's buffer, which leaves the tab
        // face transparent there, so about a third of clicks fell through. A 1% fill is
        // invisible but keeps the whole face clickable.
        return face.fill(Color.black.opacity(0.01))
            .background {
                fillLayer(color: color)
                    .shadow(color: shadowColor, radius: shadowRadius, x: shadowX, y: shadowY)
                    .shadow(color: neonOuter, radius: style == .neon ? 12 : 0)
            }
            .overlay {
                face.stroke(strokeColor, lineWidth: strokeWidth)
            }
            .onAppear {
                guard style == .neon, isActive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    neonGlow = 1
                }
            }
            .onChange(of: isActive) { _, active in
                if style == .neon, active, !reduceMotion {
                    neonGlow = 0.82
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        neonGlow = 1
                    }
                } else {
                    neonGlow = 0.82
                }
            }
    }

    @ViewBuilder
    private func fillLayer(color: Color) -> some View {
        switch style {
        case .flat:
            face.fill(color)
        case .gradient:
            face.fill(tabGradient(color: color, edge: edge))
        case .liquid:
            Color.clear.glassEffect(.regular, in: face)
        case .glass:
            Color.clear.glassEffect(.regular.tint(paint.color.opacity(isActive ? 0.38 : 0.25)), in: face)
        case .neon:
            face.fill(paint.color.opacity(locked ? 0.06 : 0.1))
        case .sticker:
            face.fill(color)
        case .aurora:
            if isActive {
                auroraFill
            } else {
                face.fill(color)
            }
        }
    }

    private var strokeColor: Color {
        switch style {
        case .liquid: Color.primary.opacity(0.22)
        case .glass: Color.white.opacity(0.28)
        case .neon: paint.color
        case .sticker: Color.black.opacity(0.82)
        case .aurora: Color.primary.opacity(isActive ? 0.12 : 0.18)
        default: Color.primary.opacity(isActive || isHovered ? 0.28 : 0.18)
        }
    }

    private var strokeWidth: CGFloat {
        switch style {
        case .neon: 1.5
        case .sticker: 2
        case .glass: 1
        default: 0.8
        }
    }

    @ViewBuilder
    private var auroraFill: some View {
        let colors = auroraColors
        if reduceMotion {
            face.fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        } else {
            TimelineView(.animation(minimumInterval: 1 / 24)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10) / 10
                let start = UnitPoint(x: 0.15 + 0.7 * sin(phase * .pi * 2), y: 0.1)
                let end = UnitPoint(x: 0.85 - 0.7 * sin(phase * .pi * 2), y: 0.9)
                face.fill(LinearGradient(colors: colors, startPoint: start, endPoint: end))
            }
        }
    }

    private var auroraColors: [Color] {
        let mapped = palette.prefix(4)
        if mapped.count >= 2 { return Array(mapped) }
        return [paint.color.mix(with: .white, by: 0.4), paint.color, paint.color.mix(with: .black, by: 0.2)]
    }

    private func tabGradient(color: Color, edge: ScreenEdge) -> LinearGradient {
        let lift = color.mix(with: .white, by: locked ? 0.28 : 0.68)
        let deep = color.mix(with: .black, by: locked ? 0.18 : 0.32)
        let start: UnitPoint
        let end: UnitPoint
        switch edge {
        case .left:
            start = .trailing
            end = .leading
        case .right:
            start = .leading
            end = .trailing
        case .bottom:
            start = .top
            end = .bottom
        case .top:
            start = .bottom
            end = .top
        }
        return LinearGradient(colors: [lift, color, deep], startPoint: start, endPoint: end)
    }

    private var shadowColor: Color {
        switch style {
        case .neon:
            return paint.color.opacity(isActive ? neonGlow : 0.55)
        case .sticker:
            return Color.black.opacity(0.72)
        case .glass:
            return Color.black.opacity(isActive ? 0.22 : 0.14)
        case .liquid:
            return Color.black.opacity(isActive || isHovered ? 0.22 : 0.12)
        default:
            return Color.black.opacity(isActive || isHovered ? 0.34 : 0.16)
        }
    }

    private var neonOuter: Color {
        style == .neon ? paint.color.opacity(isActive ? neonGlow * 0.55 : 0.28) : .clear
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .neon: 4
        case .sticker: 0
        case .glass: isActive ? 8 : 5
        default: isActive || isHovered ? 7 : 2
        }
    }

    private var shadowX: CGFloat {
        style == .sticker ? (isActive ? 4 : (isHovered ? 1 : 3)) : 0
    }

    private var shadowY: CGFloat {
        switch style {
        case .sticker: isActive ? 4 : (isHovered ? 1 : 3)
        default: isActive || isHovered ? -2 : -1
        }
    }
}

func skuffTabInk(finish: TabFinish, paint: SkuffColor) -> Color {
    switch finish {
    case .liquid, .glass: .primary
    case .neon: Color.white.opacity(0.92)
    default: paint.textColor
    }
}

func skuffSkewPadding(skew: CGFloat, thickness: CGFloat) -> CGFloat {
    thickness * abs(tan(min(max(skew, -30), 30) * .pi / 180))
}

func skuffTiltAnchor(_ edge: ScreenEdge) -> UnitPoint {
    switch edge {
    case .left: .leading
    case .right: .trailing
    case .top: .top
    case .bottom: .bottom
    }
}

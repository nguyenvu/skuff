import SwiftUI

struct FolderPanelShape: Shape {
    var tabRect: CGRect
    var edge: ScreenEdge
    var panelCorner: CGFloat
    var tabCorner: CGFloat
    var joinRadius: CGFloat
    var tuck: CGFloat = 8

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(tabRect.origin.x, tabRect.origin.y),
                AnimatablePair(tabRect.width, tabRect.height)
            )
        }
        set {
            tabRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in panel: CGRect) -> Path {
        guard let panel = GeometrySafety.usableRect(panel) else {
            return GeometrySafety.safeDefaultPath(in: panel)
        }
        guard GeometrySafety.isUsable(tabRect) else {
            let radius = GeometrySafety.clampRadius(panelCorner, in: panel)
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: panel)
        }
        switch edge {
        case .left:
            return leftPath(panel: panel, tab: tabRect)
        case .right:
            let mirrored = CGRect(
                x: panel.maxX - tabRect.maxX + panel.minX,
                y: tabRect.minY,
                width: tabRect.width,
                height: tabRect.height
            )
            let transform = CGAffineTransform(translationX: panel.midX, y: 0)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -panel.midX, y: 0)
            return leftPath(panel: panel, tab: mirrored).applying(transform)
        case .top:
            return topPath(panel: panel, tab: tabRect)
        case .bottom:
            let flipped = CGRect(
                x: tabRect.minX,
                y: panel.maxY - tabRect.maxY + panel.minY,
                width: tabRect.width,
                height: tabRect.height
            )
            let transform = CGAffineTransform(translationX: 0, y: panel.midY)
                .scaledBy(x: 1, y: -1)
                .translatedBy(x: 0, y: -panel.midY)
            return topPath(panel: panel, tab: flipped).applying(transform)
        }
    }

    private func leftPath(panel: CGRect, tab: CGRect) -> Path {
        let corner = GeometrySafety.clampRadius(panelCorner, in: panel)
        let tabR = GeometrySafety.clampRadius(min(tabCorner, tab.height / 2 - 1, tab.width / 2 - 1), in: tab)
        let joint = min(max(tab.maxX - tuck, panel.minX + 10), panel.midX)
        let top = min(max(tab.minY, panel.minY + 1), panel.maxY - 2)
        let bottom = min(max(tab.maxY, top + 8), panel.maxY - 1)
        let out = min(tab.minX, joint - 4)
        let join = min(
            GeometrySafety.clampJoinRadius(joinRadius),
            max(0, (bottom - top) / 2 - 2),
            max(0, top - panel.minY - corner),
            max(0, panel.maxY - bottom - corner)
        )
        var path = Path()
        path.move(to: CGPoint(x: joint + corner, y: panel.minY))
        path.addLine(to: CGPoint(x: panel.maxX - corner, y: panel.minY))
        path.addArc(
            tangent1End: CGPoint(x: panel.maxX, y: panel.minY),
            tangent2End: CGPoint(x: panel.maxX, y: panel.minY + corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: panel.maxX, y: panel.maxY - corner))
        path.addArc(
            tangent1End: CGPoint(x: panel.maxX, y: panel.maxY),
            tangent2End: CGPoint(x: panel.maxX - corner, y: panel.maxY),
            radius: corner
        )
        path.addLine(to: CGPoint(x: joint + corner, y: panel.maxY))
        path.addArc(
            tangent1End: CGPoint(x: joint, y: panel.maxY),
            tangent2End: CGPoint(x: joint, y: panel.maxY - corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: joint, y: bottom + join))
        if join > 0.5 {
            path.addQuadCurve(to: CGPoint(x: joint - join, y: bottom), control: CGPoint(x: joint, y: bottom))
        }
        path.addLine(to: CGPoint(x: out + tabR, y: bottom))
        path.addArc(
            tangent1End: CGPoint(x: out, y: bottom),
            tangent2End: CGPoint(x: out, y: bottom - tabR),
            radius: tabR
        )
        path.addLine(to: CGPoint(x: out, y: top + tabR))
        path.addArc(
            tangent1End: CGPoint(x: out, y: top),
            tangent2End: CGPoint(x: out + tabR, y: top),
            radius: tabR
        )
        path.addLine(to: CGPoint(x: joint - join, y: top))
        if join > 0.5 {
            path.addQuadCurve(to: CGPoint(x: joint, y: top - join), control: CGPoint(x: joint, y: top))
        }
        path.addLine(to: CGPoint(x: joint, y: panel.minY + corner))
        path.addArc(
            tangent1End: CGPoint(x: joint, y: panel.minY),
            tangent2End: CGPoint(x: joint + corner, y: panel.minY),
            radius: corner
        )
        path.closeSubpath()
        return path
    }

    private func topPath(panel: CGRect, tab: CGRect) -> Path {
        let corner = GeometrySafety.clampRadius(panelCorner, in: panel)
        let tabR = GeometrySafety.clampRadius(min(tabCorner, tab.width / 2 - 1, tab.height / 2 - 1), in: tab)
        let joint = min(max(tab.maxY - tuck, panel.minY + 10), panel.midY)
        let leading = min(max(tab.minX, panel.minX + 1), panel.maxX - 2)
        let trailing = min(max(tab.maxX, leading + 8), panel.maxX - 1)
        let out = min(tab.minY, joint - 4)
        let join = min(
            GeometrySafety.clampJoinRadius(joinRadius),
            max(0, (trailing - leading) / 2 - 2),
            max(0, leading - panel.minX - corner),
            max(0, panel.maxX - trailing - corner)
        )
        var path = Path()
        path.move(to: CGPoint(x: panel.minX + corner, y: joint))
        path.addArc(
            tangent1End: CGPoint(x: panel.minX, y: joint),
            tangent2End: CGPoint(x: panel.minX, y: joint + corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: panel.minX, y: panel.maxY - corner))
        path.addArc(
            tangent1End: CGPoint(x: panel.minX, y: panel.maxY),
            tangent2End: CGPoint(x: panel.minX + corner, y: panel.maxY),
            radius: corner
        )
        path.addLine(to: CGPoint(x: panel.maxX - corner, y: panel.maxY))
        path.addArc(
            tangent1End: CGPoint(x: panel.maxX, y: panel.maxY),
            tangent2End: CGPoint(x: panel.maxX, y: panel.maxY - corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: panel.maxX, y: joint + corner))
        path.addArc(
            tangent1End: CGPoint(x: panel.maxX, y: joint),
            tangent2End: CGPoint(x: panel.maxX - corner, y: joint),
            radius: corner
        )
        path.addLine(to: CGPoint(x: trailing + join, y: joint))
        if join > 0.5 {
            path.addQuadCurve(to: CGPoint(x: trailing, y: joint - join), control: CGPoint(x: trailing, y: joint))
        }
        path.addLine(to: CGPoint(x: trailing, y: out + tabR))
        path.addArc(
            tangent1End: CGPoint(x: trailing, y: out),
            tangent2End: CGPoint(x: trailing - tabR, y: out),
            radius: tabR
        )
        path.addLine(to: CGPoint(x: leading + tabR, y: out))
        path.addArc(
            tangent1End: CGPoint(x: leading, y: out),
            tangent2End: CGPoint(x: leading, y: out + tabR),
            radius: tabR
        )
        path.addLine(to: CGPoint(x: leading, y: joint - join))
        if join > 0.5 {
            path.addQuadCurve(to: CGPoint(x: leading - join, y: joint), control: CGPoint(x: leading, y: joint))
        }
        path.addLine(to: CGPoint(x: panel.minX + corner, y: joint))
        path.closeSubpath()
        return path
    }
}

func skuffFolderShape(store: LibraryStore, tabRect: CGRect) -> FolderPanelShape {
    let shape = store.settings.effectiveShape(isPro: store.pro.isPro)
    return FolderPanelShape(
        tabRect: tabRect,
        edge: store.settings.edge,
        panelCorner: 18,
        tabCorner: shape.cornerRadius,
        joinRadius: CGFloat(store.settings.joinRadius)
    )
}

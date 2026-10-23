import SwiftUI

struct TrapezoidTabShape: Shape {
    var slant: CGFloat
    var cornerRadius: CGFloat
    var edge: ScreenEdge
    var skew: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(slant, AnimatablePair(cornerRadius, skew)) }
        set {
            slant = newValue.first
            cornerRadius = newValue.second.first
            skew = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard let rect = GeometrySafety.usableRect(rect) else {
            return GeometrySafety.safeDefaultPath(in: rect)
        }
        let along = edge.runsAlongX ? rect.width : rect.height
        let clampedSlant = GeometrySafety.clamp(slant, min: 0, max: max(0, along / 2 - 1))
        let outer = max(0, along - clampedSlant * 2)
        let radius = GeometrySafety.clampRadius(min(max(cornerRadius, 0), outer / 2), in: rect)
        let corners = corners(in: rect, slant: clampedSlant)
        let path = roundedPath(corners: corners, radius: radius)
        let degrees = min(max(skew, -30), 30)
        guard abs(degrees) > 0.05 else { return path }
        let k = tan(degrees * .pi / 180)
        let transform: CGAffineTransform
        switch edge {
        case .bottom:
            transform = CGAffineTransform(a: 1, b: 0, c: -k, d: 1, tx: k * rect.maxY, ty: 0)
        case .top:
            transform = CGAffineTransform(a: 1, b: 0, c: k, d: 1, tx: -k * rect.minY, ty: 0)
        case .left:
            transform = CGAffineTransform(a: 1, b: -k, c: 0, d: 1, tx: 0, ty: k * rect.minX)
        case .right:
            transform = CGAffineTransform(a: 1, b: k, c: 0, d: 1, tx: 0, ty: -k * rect.maxX)
        }
        return path.applying(transform)
    }

    private func corners(in rect: CGRect, slant: CGFloat) -> [(CGPoint, Bool)] {
        switch edge {
        case .right:
            return [
                (CGPoint(x: rect.maxX, y: rect.minY), false),
                (CGPoint(x: rect.maxX, y: rect.maxY), false),
                (CGPoint(x: rect.minX, y: rect.maxY - slant), true),
                (CGPoint(x: rect.minX, y: rect.minY + slant), true)
            ]
        case .left:
            return [
                (CGPoint(x: rect.minX, y: rect.minY), false),
                (CGPoint(x: rect.maxX, y: rect.minY + slant), true),
                (CGPoint(x: rect.maxX, y: rect.maxY - slant), true),
                (CGPoint(x: rect.minX, y: rect.maxY), false)
            ]
        case .bottom:
            return [
                (CGPoint(x: rect.minX, y: rect.maxY), false),
                (CGPoint(x: rect.maxX, y: rect.maxY), false),
                (CGPoint(x: rect.maxX - slant, y: rect.minY), true),
                (CGPoint(x: rect.minX + slant, y: rect.minY), true)
            ]
        case .top:
            return [
                (CGPoint(x: rect.minX, y: rect.minY), false),
                (CGPoint(x: rect.maxX, y: rect.minY), false),
                (CGPoint(x: rect.maxX - slant, y: rect.maxY), true),
                (CGPoint(x: rect.minX + slant, y: rect.maxY), true)
            ]
        }
    }

    private func roundedPath(corners: [(CGPoint, Bool)], radius: CGFloat) -> Path {
        guard corners.count > 2 else { return Path() }
        var path = Path()
        path.move(to: corners[0].0)
        for index in corners.indices {
            let next = corners[(index + 1) % corners.count]
            let after = corners[(index + 2) % corners.count]
            let cornerRadius = next.1 ? radius : 0
            if cornerRadius < 0.5 {
                path.addLine(to: next.0)
            } else {
                path.addArc(tangent1End: next.0, tangent2End: after.0, radius: cornerRadius)
            }
        }
        path.closeSubpath()
        return path
    }
}

import CoreGraphics
import os
import SwiftUI

enum GeometrySafety {
    static func isFinite(_ value: CGFloat) -> Bool {
        value.isFinite && !value.isNaN
    }

    static func isUsable(_ rect: CGRect) -> Bool {
        isFinite(rect.origin.x)
            && isFinite(rect.origin.y)
            && isFinite(rect.size.width)
            && isFinite(rect.size.height)
            && rect.width > 1
            && rect.height > 1
    }

    static func isUsable(_ size: CGSize) -> Bool {
        isFinite(size.width) && isFinite(size.height) && size.width > 1 && size.height > 1
    }

    /// Returns a clamped rect, or `nil` when the input cannot be drawn.
    static func usableRect(_ rect: CGRect) -> CGRect? {
        guard isUsable(rect) else { return nil }
        return CGRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: min(rect.width, 20_000),
            height: min(rect.height, 20_000)
        )
    }

    static func sanitizedSize(_ size: CGSize, fallback: CGSize) -> CGSize {
        let width = isFinite(size.width) && size.width > 1 ? min(size.width, 20_000) : fallback.width
        let height = isFinite(size.height) && size.height > 1 ? min(size.height, 20_000) : fallback.height
        return CGSize(width: max(width, 2), height: max(height, 2))
    }

    static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        let lo = isFinite(lower) ? lower : 0
        let hi = isFinite(upper) ? max(lo, upper) : lo
        guard isFinite(value) else { return lo }
        return Swift.min(Swift.max(value, lo), hi)
    }

    static func clampRadius(_ radius: CGFloat, in rect: CGRect) -> CGFloat {
        guard isUsable(rect) else { return 0 }
        let cap = min(rect.width, rect.height) / 2
        return clamp(radius, min: 0, max: max(0, cap))
    }

    static func clampJoinRadius(_ radius: CGFloat) -> CGFloat {
        clamp(radius, min: 0, max: 40)
    }

    static func safeDefaultPath(in rect: CGRect) -> Path {
        guard let usable = usableRect(rect) else { return Path() }
        let radius = min(4, min(usable.width, usable.height) / 4)
        return Path(roundedRect: usable, cornerRadius: max(0, radius))
    }

    static func pathIsFinite(_ path: Path) -> Bool {
        if path.isEmpty { return true }
        let bounds = path.boundingRect
        if bounds.isNull || bounds.isInfinite { return false }
        return isFinite(bounds.origin.x)
            && isFinite(bounds.origin.y)
            && isFinite(bounds.size.width)
            && isFinite(bounds.size.height)
    }
}

enum GeometrySafetyTests {
    static func testDegenerateRects() {
        let rects: [CGRect] = [
            .zero,
            CGRect(x: 0, y: 0, width: 1, height: 1),
            CGRect(x: 0, y: 0, width: CGFloat.nan, height: 40),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: CGFloat.infinity),
            CGRect(x: 0, y: 0, width: -12, height: -8),
            CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 80, height: 40)
        ]
        for edge in ScreenEdge.allCases {
            for rect in rects {
                let tab = TrapezoidTabShape(slant: 8, cornerRadius: 8, edge: edge, skew: 80)
                precondition(GeometrySafety.pathIsFinite(tab.path(in: rect)), "trapezoid \(edge) \(rect)")
                let folder = FolderPanelShape(
                    tabRect: rect,
                    edge: edge,
                    panelCorner: 18,
                    tabCorner: 8,
                    joinRadius: 40
                )
                precondition(GeometrySafety.pathIsFinite(folder.path(in: rect)), "folder \(edge) \(rect)")
                let folderOnTinyPanel = FolderPanelShape(
                    tabRect: CGRect(x: 0, y: 0, width: 48, height: 88),
                    edge: edge,
                    panelCorner: 18,
                    tabCorner: 8,
                    joinRadius: 10
                )
                precondition(
                    GeometrySafety.pathIsFinite(folderOnTinyPanel.path(in: rect)),
                    "folder-in-panel \(edge) \(rect)"
                )
            }
        }
    }
}

extension Logger {
    static let spaces = Logger(subsystem: "no.voq.skuff", category: "spaces")
    /// Click diagnostics for the tab strip (DEBUG builds only).
    static let input = Logger(subsystem: "no.voq.skuff", category: "input")
}

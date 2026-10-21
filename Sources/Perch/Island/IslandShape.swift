import SwiftUI

/// The island outline. Attached: outward-curving "ears" where it meets the screen edge,
/// straight sides, and rounded far corners. Detached (floating styles): a plain rounded
/// rectangle. Fill and outline share this path, so they always line up.
struct IslandShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    /// `false` leaves the edge side open, for stroking the outline of an attached island.
    var closed = true
    /// Which screen edge an attached island is joined to.
    var edge: IslandPosition = .top
    var detached = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        if detached {
            let radius = min(bottom, rect.width / 2, rect.height / 2)
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        // Draw as if joined to the top edge, then turn the path to face the real edge.
        let vertical = edge.isVertical
        let canonical = CGRect(x: 0, y: 0,
                               width: vertical ? rect.height : rect.width,
                               height: vertical ? rect.width : rect.height)
        let path = topPath(in: canonical)
        let transform: CGAffineTransform
        switch edge {
        case .top: transform = .identity
        case .left: transform = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: rect.width, ty: 0)
        }
        return path.applying(transform.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }

    private func topPath(in rect: CGRect) -> Path {
        let e = max(0, min(ear, rect.height / 2))
        let b = max(0, min(bottom, rect.height - e, (rect.width - 2 * e) / 2))
        let left = rect.minX + e
        let right = rect.maxX - e

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: curves from the screen edge down into the left side.
        p.addArc(tangent1End: CGPoint(x: left, y: rect.minY),
                 tangent2End: CGPoint(x: left, y: rect.maxY),
                 radius: e)
        // Left side + bottom-left corner.
        p.addArc(tangent1End: CGPoint(x: left, y: rect.maxY),
                 tangent2End: CGPoint(x: right, y: rect.maxY),
                 radius: b)
        // Bottom + bottom-right corner.
        p.addArc(tangent1End: CGPoint(x: right, y: rect.maxY),
                 tangent2End: CGPoint(x: right, y: rect.minY),
                 radius: b)
        // Right side + right ear.
        p.addArc(tangent1End: CGPoint(x: right, y: rect.minY),
                 tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                 radius: e)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        if closed { p.closeSubpath() }
        return p
    }
}

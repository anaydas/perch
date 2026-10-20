import SwiftUI

/// The island outline: outward-curving "ears" where it meets the top of the screen,
/// straight sides, and rounded bottom corners. Fill and outline share this path,
/// so they always line up.
struct IslandShape: Shape {
    var ear: CGFloat
    var bottom: CGFloat
    /// `false` leaves the top edge open, for stroking the outline.
    var closed = true

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottom) }
        set { ear = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
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

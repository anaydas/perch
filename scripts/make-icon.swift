// Draws the Perch app icon (a little bird perched on the island) and writes Resources/AppIcon.icns,
// plus Resources/social-preview.png (1280×640, for GitHub → Settings → Social preview).
// Run from the project folder:  swift scripts/make-icon.swift
import AppKit

/// The design, on a 96-point grid (y down). The tile spans 4…92.
func drawIcon(in ctx: CGContext, size: CGFloat) {
    // Apple's icon grid: the rounded tile is 824/1024 of the canvas, centred.
    let tile = size * 824 / 1024
    let scale = tile / 88
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1) // y down, like the design grid
    ctx.translateBy(x: (size - tile) / 2 - 4 * scale, y: (size - tile) / 2 - 4 * scale)
    ctx.scaleBy(x: scale, y: scale)

    func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    func fill(_ path: CGPath, _ hex: UInt32) {
        ctx.addPath(path)
        ctx.setFillColor(color(hex))
        ctx.fillPath()
    }

    // Tile
    fill(CGPath(roundedRect: CGRect(x: 4, y: 4, width: 88, height: 88), cornerWidth: 20, cornerHeight: 20, transform: nil), 0xDCE8F7)
    // The island (perch)
    fill(CGPath(roundedRect: CGRect(x: 18, y: 58, width: 60, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil), 0x141414)
    // Legs
    fill(CGPath(rect: CGRect(x: 44, y: 55, width: 2, height: 4), transform: nil), 0x141414)
    fill(CGPath(rect: CGRect(x: 50, y: 55, width: 2, height: 4), transform: nil), 0x141414)
    // Tail
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: 34, y: 44))
    tail.addQuadCurve(to: CGPoint(x: 24, y: 50), control: CGPoint(x: 26, y: 42))
    tail.addQuadCurve(to: CGPoint(x: 34, y: 48), control: CGPoint(x: 30, y: 50))
    tail.closeSubpath()
    fill(tail, 0xB85E40)
    // Body and head
    fill(CGPath(ellipseIn: CGRect(x: 33, y: 34, width: 30, height: 24), transform: nil), 0xD97757)
    fill(CGPath(ellipseIn: CGRect(x: 48, y: 28, width: 16, height: 16), transform: nil), 0xD97757)
    // Eye
    fill(CGPath(ellipseIn: CGRect(x: 56.7, y: 32.7, width: 3.6, height: 3.6), transform: nil), 0x141414)
    // Beak
    let beak = CGMutablePath()
    beak.move(to: CGPoint(x: 63, y: 36))
    beak.addLine(to: CGPoint(x: 69, y: 37.5))
    beak.addLine(to: CGPoint(x: 63, y: 39))
    beak.closeSubpath()
    fill(beak, 0xF5B13A)
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    drawIcon(in: context.cgContext, size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// GitHub social preview: the icon on the left, name and tagline on the right.
func socialPreview() -> Data {
    let width = 1280, height = 640
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext

    NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    // Icon (its canvas includes Apple's margin, so draw it a bit larger than it looks).
    let iconSize: CGFloat = 520
    ctx.saveGState()
    ctx.translateBy(x: 70, y: (CGFloat(height) - iconSize) / 2)
    drawIcon(in: ctx, size: iconSize)
    ctx.restoreGState()

    let left: CGFloat = 610
    let title = NSAttributedString(string: "Perch", attributes: [
        .font: NSFont.systemFont(ofSize: 132, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    title.draw(at: NSPoint(x: left - 6, y: 318))

    let tagline = NSAttributedString(string: "A shelf at the top of your Mac screen\nfor screenshots, text and files.", attributes: [
        .font: NSFont.systemFont(ofSize: 38, weight: .regular),
        .foregroundColor: NSColor(white: 0.78, alpha: 1),
        .paragraphStyle: { let p = NSMutableParagraphStyle(); p.lineSpacing = 8; return p }(),
    ])
    tagline.draw(in: NSRect(x: left, y: 190, width: 620, height: 120))

    let accent = NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    let footer = NSAttributedString(string: "macOS 13+  ·  Swift  ·  Claude Code sessions and usage", attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .medium),
        .foregroundColor: accent,
    ])
    footer.draw(at: NSPoint(x: left, y: 130))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try png(size: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
try socialPreview().write(to: URL(fileURLWithPath: "Resources/social-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? fm.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and Resources/social-preview.png" : "iconutil failed")

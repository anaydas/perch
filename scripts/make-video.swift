// Builds the Perch intro video: 1920×1080, 30 fps, H.264 + AAC, ~99 s, with generated background
// music and sound effects (no voiceover, no licensed audio). Run from the project folder:
//
//   build/Perch.app/Contents/MacOS/Perch --render-video-states build/video-states
//   swiftc -O -o build/make-video scripts/make-video.swift && build/make-video build/video-states ~/Downloads/Perch-intro.mp4
import AVFoundation
import AppKit
import CoreImage

let args = CommandLine.arguments
let statesDir = URL(fileURLWithPath: args.count > 1 ? args[1] : "build/video-states")
let finalURL = URL(fileURLWithPath: args.count > 2 ? args[2] : "build/perch-intro.mp4")
let W: CGFloat = 1920, H: CGFloat = 1080
let FPS = 30
let duration = 99.0
let menuBarHeight: CGFloat = 34

// MARK: - Assets

func load(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: statesDir.appendingPathComponent(name)) else {
        fatalError("Missing \(name). Run: Perch --render-video-states \(statesDir.path)")
    }
    return image
}
func px(_ image: NSImage) -> CGSize {
    let rep = image.representations.first
    return CGSize(width: rep?.pixelsWide ?? Int(image.size.width), height: rep?.pixelsHigh ?? Int(image.size.height))
}

let pill0 = load("pill-0.png"), pill = load("pill.png")
let shelf0 = load("shelf-0.png"), shelf1 = load("shelf-1.png"), shelf2 = load("shelf-2.png"), shelf3 = load("shelf-3.png")
let shelfSelect = load("shelf-select.png"), searchImg = load("search.png"), claudeImg = load("claude.png")
let shelfFixed = load("shelf-fixed.png"), shelfSecret = load("shelf-secret.png")
let shelfLight = load("shelf-light.png"), shelfOrange = load("shelf-orange.png"), shelfPurple = load("shelf-purple.png")
let sideImg = load("side.png"), styleNotch = load("style-notch.png"), styleOrb = load("style-orb.png")
let shortcutsImg = load("shortcuts.png"), dashboard = load("drag-thumb.png")
let sunset = load("thumb-sunset.png"), loginThumb = load("thumb-login.png")
guard let appIcon = NSImage(contentsOf: URL(fileURLWithPath: "Resources/AppIcon-1024.png")) else { fatalError("Missing app icon") }

// Island images are 2× with 48 px of transparent padding for the glow.
let S: CGFloat = 1500 / px(shelf0).width
let pad: CGFloat = 48
func topRect(_ image: NSImage, scale: CGFloat = S, cx: CGFloat = W / 2, top: CGFloat = menuBarHeight + 10) -> CGRect {
    let size = px(image)
    return CGRect(x: cx - size.width * scale / 2, y: top - pad * scale, width: size.width * scale, height: size.height * scale)
}
let shelfRect = topRect(shelf0)
let pillRect = topRect(pill)
/// A card in the shelf images (index from the left), in screen points.
func cardRect(_ i: Int) -> CGRect {
    CGRect(x: shelfRect.minX + (88 + 224 * CGFloat(i)) * S, y: shelfRect.minY + 161 * S, width: 208 * S, height: 252 * S)
}
func cardPreview(_ i: Int) -> CGRect {
    CGRect(x: shelfRect.minX + (98 + 224 * CGFloat(i)) * S, y: shelfRect.minY + 171 * S, width: 184 * S, height: 116 * S)
}
func center(_ r: CGRect) -> CGPoint { CGPoint(x: r.midX, y: r.midY) }

// MARK: - Easing

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func inOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
func out(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
func spring(_ p: Double) -> Double { p <= 0 ? 0 : (p >= 1 ? 1 : 1 - exp(-6 * p) * cos(9 * p)) }
func fade(_ t: Double, _ a: Double, _ b: Double, _ f: Double = 0.35) -> Double { min(prog(t, a, a + f), 1 - prog(t, b - f, b)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }

// MARK: - Drawing helpers (top-left origin)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func draw(_ image: NSImage, in r: CGRect, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    image.draw(in: r, from: .zero, operation: .sourceOver, fraction: CGFloat(min(alpha, 1)), respectFlipped: true,
               hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
}
/// Scaled around the top centre (how the island grows).
func draw(_ image: NSImage, rect r: CGRect, scale k: CGFloat, alpha: Double) {
    let w = r.width * k, h = r.height * k
    draw(image, in: CGRect(x: r.midX - w / 2, y: r.minY + pad * S * (1 - k), width: w, height: h), alpha: alpha)
}
func drawClipped(_ image: NSImage, in r: CGRect, radius: CGFloat, alpha: Double = 1) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
    draw(image, in: r, alpha: alpha)
    NSGraphicsContext.restoreGraphicsState()
}
func fill(_ r: CGRect, _ color: NSColor, radius: CGFloat = 0) {
    color.setFill()
    if radius > 0 { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() } else { NSBezierPath(rect: r).fill() }
}
func stroke(_ r: CGRect, _ color: NSColor, radius: CGFloat, width: CGFloat) {
    color.setStroke()
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    path.lineWidth = width
    path.stroke()
}
func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
    mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
}
func textWidth(_ s: String, _ f: NSFont) -> CGFloat { NSAttributedString(string: s, attributes: [.font: f]).size().width }
func text(_ s: String, _ f: NSFont, _ color: NSColor = .white, x: CGFloat, y: CGFloat, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color.withAlphaComponent(color.alphaComponent * CGFloat(alpha))])
        .draw(at: NSPoint(x: x, y: y))
}
func textC(_ s: String, _ f: NSFont, _ color: NSColor = .white, cx: CGFloat, y: CGFloat, alpha: Double = 1) {
    text(s, f, color, x: cx - textWidth(s, f) / 2, y: y, alpha: alpha)
}
func shadow(_ ctx: CGContext, blur: CGFloat = 40, y: CGFloat = 18, a: CGFloat = 0.4, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: NSColor.black.withAlphaComponent(a).cgColor)
    body()
    ctx.restoreGState()
}
func withAlpha(_ ctx: CGContext, _ a: Double, _ body: () -> Void) {
    guard a > 0.002 else { return }
    ctx.saveGState()
    ctx.setAlpha(CGFloat(min(a, 1)))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}
func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .semibold) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return nil }
    return NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
}

// Blurred copy of the secret card's preview (offscreen snapshots can't capture SwiftUI blur).
let blurredSecret: NSImage = {
    let src = px(shelfSecret)
    let crop = CGRect(x: 98 + 224, y: 171, width: 184, height: 116)
    guard let cg = shelfSecret.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let cropped = cg.cropping(to: CGRect(x: crop.minX, y: crop.minY, width: crop.width, height: crop.height)) else { return NSImage() }
    _ = src
    let ci = CIImage(cgImage: cropped).clampedToExtent().applyingGaussianBlur(sigma: 9).cropped(to: CIImage(cgImage: cropped).extent)
    let rep = NSCIImageRep(ciImage: ci)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
}()

// MARK: - Common pieces

func wallpaper(_ ctx: CGContext, t: Double) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let g = CGGradient(colorsSpace: space, colors: [rgb(0x15203A).cgColor, rgb(0x2E2A5C).cgColor, rgb(0x4A2F55).cgColor] as CFArray,
                       locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
    let glows: [(CGPoint, CGFloat, UInt32)] = [
        (CGPoint(x: 360 + 60 * sin(t * 0.25), y: 840), 620, 0x3F7FF0),
        (CGPoint(x: 1580 + 70 * cos(t * 0.2), y: 220), 680, 0xD97757),
        (CGPoint(x: 1050, y: 1000 + 40 * sin(t * 0.3)), 480, 0x8E6CF0),
    ]
    for (c, r, hex) in glows {
        let rg = CGGradient(colorsSpace: space, colors: [rgb(hex, 0.30).cgColor, rgb(hex, 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(rg, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
}

func menuBar(recording: Bool = false, stopHover: Bool = false) {
    fill(CGRect(x: 0, y: 0, width: W, height: menuBarHeight), rgb(0x000000, 0.30))
    if let apple = symbol("applelogo", size: 17, color: .white) { draw(apple, in: CGRect(x: 22, y: 8, width: apple.size.width, height: apple.size.height)) }
    text("Finder", font(15, .bold), x: 58, y: 8)
    var x: CGFloat = 132
    for item in ["File", "Edit", "View", "Go", "Window", "Help"] {
        text(item, font(15), x: x, y: 8)
        x += textWidth(item, font(15)) + 24
    }
    text("Mon 9:41 AM", font(15), x: W - 130, y: 8)
    if recording {
        let r = CGRect(x: W - 178, y: 6, width: 22, height: 22)
        if stopHover { fill(r.insetBy(dx: -4, dy: -1), rgb(0xFFFFFF, 0.2), radius: 5) }
        if let stop = symbol("stop.circle.fill", size: 16, color: .white) { draw(stop, in: CGRect(x: r.minX + 2, y: r.minY + 2, width: 18, height: 18)) }
    }
}

func caption(_ s: String, alpha: Double) {
    guard alpha > 0.002 else { return }
    let f = font(42, .semibold)
    let w = textWidth(s, f)
    let slide = CGFloat(1 - out(alpha)) * 14
    fill(CGRect(x: W / 2 - w / 2 - 36, y: H - 124 + slide, width: w + 72, height: 76), rgb(0x000000, 0.45 * CGFloat(alpha)), radius: 38)
    textC(s, f, cx: W / 2, y: H - 111 + slide, alpha: alpha)
}

func cursor(_ p: CGPoint, pressed: Bool, alpha: Double) {
    guard alpha > 0.002 else { return }
    let s: CGFloat = pressed ? 1.18 : 1.32
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 25), (6, 19.5), (10.5, 28.5), (14.5, 26.8), (10.2, 18), (18, 18)]
    let path = NSBezierPath()
    path.move(to: NSPoint(x: p.x, y: p.y))
    for q in pts.dropFirst() { path.line(to: NSPoint(x: p.x + q.0 * s, y: p.y + q.1 * s)) }
    path.close()
    NSColor.black.withAlphaComponent(CGFloat(alpha)).setFill(); path.fill()
    path.lineWidth = 2.2
    NSColor.white.withAlphaComponent(CGFloat(alpha)).setStroke(); path.stroke()
}

/// Pulsing ring that draws attention to a spot.
func ring(around r: CGRect, t: Double, start: Double, color: NSColor = rgb(0x4C8DF6), radius: CGFloat = 16) {
    let p = prog(t, start, start + 1.1)
    guard p > 0 && p < 1 else { return }
    let grow = CGFloat(out(p)) * 16
    stroke(r.insetBy(dx: -6 - grow, dy: -6 - grow), color.withAlphaComponent(CGFloat(1 - p)), radius: radius + grow, width: 4)
}

func keycaps(_ keys: [String], cy: CGFloat, t: Double, start: Double, end: Double) {
    let a = fade(t, start, end, 0.25)
    guard a > 0.002 else { return }
    let size: CGFloat = 92, gap: CGFloat = 20
    let total = CGFloat(keys.count) * size + CGFloat(keys.count - 1) * gap
    for (i, key) in keys.enumerated() {
        let pop = spring(prog(t, start + Double(i) * 0.12, start + Double(i) * 0.12 + 0.5))
        guard pop > 0 else { continue }
        let k = CGFloat(0.6 + 0.4 * pop)
        let s = size * k
        let x = W / 2 - total / 2 + CGFloat(i) * (size + gap) + (size - s) / 2
        let r = CGRect(x: x, y: cy - s / 2, width: max(s, textWidth(key, font(40 * k, .semibold)) + 36 * k), height: s)
        fill(r.offsetBy(dx: 0, dy: 6), rgb(0x000000, 0.35 * CGFloat(a)), radius: 20)
        fill(r, rgb(0xF4F4F6, CGFloat(a)), radius: 20)
        textC(key, font(40 * k, .semibold), rgb(0x1C1C1E), cx: r.midX, y: r.midY - 25 * k, alpha: a)
    }
}

/// A plain macOS-style window; `body` draws the content below the title bar.
func appWindow(_ ctx: CGContext, _ r: CGRect, title: String, dark: Bool = false, alpha: Double, body: (CGRect) -> Void) {
    withAlpha(ctx, alpha) {
        shadow(ctx) { fill(r, dark ? rgb(0x1E1E1E) : rgb(0xFFFFFF), radius: 14) }
        let bar = CGRect(x: r.minX, y: r.minY, width: r.width, height: 44)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).addClip()
        fill(bar, dark ? rgb(0x2C2C2E) : rgb(0xECECEF))
        NSGraphicsContext.restoreGraphicsState()
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            rgb(hex).setFill()
            NSBezierPath(ovalIn: CGRect(x: r.minX + 18 + CGFloat(i) * 22, y: r.minY + 15, width: 14, height: 14)).fill()
        }
        textC(title, font(16, .semibold), dark ? rgb(0xD1D1D6) : rgb(0x3A3A3C), cx: r.midX, y: r.minY + 12)
        body(CGRect(x: r.minX, y: r.minY + 44, width: r.width, height: r.height - 44))
    }
}

func titleCard(_ ctx: CGContext, t: Double, alpha: Double, start: Double) {
    guard alpha > 0.002 else { return }
    withAlpha(ctx, alpha) {
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0x0C111D).cgColor, rgb(0x1C1832).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
        let pop = spring(prog(t, start, start + 0.9))
        let size = 320 * CGFloat(0.72 + 0.28 * pop)
        draw(appIcon, in: CGRect(x: W / 2 - size / 2, y: 250 + (320 - size) / 2, width: size, height: size), alpha: min(1, pop * 1.5))
        let titleIn = out(prog(t, start + 0.55, start + 1.2))
        textC("Perch", font(128, .bold), cx: W / 2, y: 600 + CGFloat(1 - titleIn) * 30, alpha: titleIn)
    }
}

// MARK: - Scene timeline (absolute seconds)

struct Cue { let at: Double; let kind: Sound; var gain: Float = 1 }
enum Sound { case click, key, shutter, whoosh, pop, chime }
var cues: [Cue] = []
func sfx(_ at: Double, _ kind: Sound, _ gain: Float = 1) { cues.append(Cue(at: at, kind: kind, gain: gain)) }

let captions: [(String, Double, Double)] = [
    ("A shelf at the top of your Mac", 3.4, 7.4),
    ("Hover to open it", 7.6, 11.9),
    ("Screenshots land on the shelf automatically", 12.1, 16.4),
    ("Screen recordings too", 16.6, 20.4),
    ("Everything you copy is saved", 20.6, 24.4),
    ("Drag anything out, into any app", 24.6, 29.9),
    ("Select several, drag them all at once", 30.1, 35.4),
    ("Press Space to Quick Look", 35.6, 39.4),
    ("Find anything with ⌥⌘F", 39.6, 43.9),
    ("Fix favourites at the front, star the keepers", 44.1, 47.9),
    ("Passwords and API keys stay blurred", 48.1, 51.4),
    ("Right-click anything → Add to Perch", 51.6, 55.9),
    ("See every Claude Code session at a glance", 56.1, 60.9),
    ("Click a session to jump straight to it", 61.1, 65.4),
    ("Live plan usage, with reset timers", 65.6, 69.9),
    ("Notch, Floating or Orb", 70.2, 74.4),
    ("On the top, left or right edge", 74.6, 77.9),
    ("Or drag it anywhere", 78.1, 81.9),
    ("Dark or light, in your accent colour", 82.1, 86.4),
    ("Hides itself during full-screen video", 86.6, 90.9),
    ("Every shortcut, one key away", 91.1, 94.9),
]

// Sound cues
sfx(0.35, .whoosh, 0.7); sfx(0.45, .pop, 0.8)
sfx(3.5, .whoosh, 0.6)
sfx(9.0, .whoosh)
sfx(12.3, .key); sfx(12.42, .key); sfx(12.54, .key)
sfx(12.95, .click, 0.6); sfx(13.6, .shutter); sfx(14.0, .pop)
sfx(18.4, .click); sfx(18.75, .pop)
sfx(20.65, .whoosh, 0.5); sfx(21.2, .click, 0.6); sfx(22.0, .key); sfx(22.12, .key); sfx(22.5, .pop); sfx(23.6, .whoosh, 0.4)
sfx(24.7, .whoosh, 0.5); sfx(26.2, .click); sfx(26.5, .whoosh, 0.5); sfx(28.6, .click); sfx(28.7, .pop)
sfx(30.0, .whoosh, 0.4); sfx(30.9, .click); sfx(31.45, .key, 0.7); sfx(31.5, .click); sfx(32.0, .click); sfx(32.6, .click)
sfx(32.8, .whoosh, 0.5); sfx(34.2, .click); sfx(34.3, .pop)
sfx(35.6, .whoosh, 0.4); sfx(36.0, .key); sfx(36.2, .whoosh, 0.6); sfx(38.8, .key)
sfx(39.8, .key); sfx(39.92, .key); sfx(40.04, .key); sfx(40.9, .key); sfx(41.1, .key)
sfx(44.9, .click); sfx(45.5, .click)
sfx(51.6, .whoosh, 0.6); sfx(52.8, .click); sfx(54.3, .click); sfx(54.45, .pop)
sfx(56.2, .whoosh); sfx(57.5, .chime)
sfx(62.4, .click); sfx(62.6, .whoosh, 0.6)
sfx(65.5, .whoosh, 0.4); sfx(66.0, .whoosh, 0.5); sfx(69.2, .whoosh, 0.4)
sfx(70.4, .pop, 0.7); sfx(70.7, .pop, 0.7); sfx(71.0, .pop, 0.7)
sfx(74.6, .whoosh, 0.7)
sfx(79.0, .click); sfx(80.8, .click)
sfx(82.4, .whoosh, 0.6); sfx(84.0, .click, 0.6); sfx(85.2, .click, 0.6)
sfx(86.8, .whoosh, 0.5); sfx(87.6, .click); sfx(88.0, .whoosh)
sfx(91.0, .whoosh, 0.5); sfx(91.6, .key); sfx(91.9, .whoosh, 0.6)
sfx(95.1, .whoosh, 0.7); sfx(95.3, .pop, 0.8)

// MARK: - Frame

func renderFrame(_ ctx: CGContext, t: Double) {
    // Full-screen video moment: draw it over everything (menu bar hidden).
    let fullScreen = prog(t, 88.0, 88.6) * (1 - prog(t, 90.9, 91.3))

    // Camera zoom into the usage meters
    let zoom = inOut(prog(t, 66.0, 66.9)) * (1 - inOut(prog(t, 69.1, 69.9)))
    ctx.saveGState()
    if zoom > 0 {
        let focus = CGPoint(x: shelfRect.minX + 640 * S, y: shelfRect.minY + 425 * S)
        let k = 1 + 0.85 * CGFloat(zoom)
        let target = CGPoint(x: W / 2, y: H * 0.42)
        ctx.translateBy(x: lerp(focus.x, target.x, zoom), y: lerp(focus.y, target.y, zoom))
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -focus.x, y: -focus.y)
    }

    wallpaper(ctx, t: t)
    menuBar(recording: t > 16.8 && t < 18.5, stopHover: t > 18.2 && t < 18.5)

    var cur: CGPoint? = nil
    var pressed = false

    // ---------- Island (top centre) ----------
    if t >= 3.2 && t < 70.4 {
        let slide = out(prog(t, 3.4, 4.2))
        let open1 = spring(prog(t, 9.0, 9.7))        // pill → shelf
        let close = inOut(prog(t, 51.6, 52.1))        // shelf → pill (Services)
        let open2 = spring(prog(t, 56.2, 56.9))       // pill → Claude view
        let leave = inOut(prog(t, 70.0, 70.4))
        if t < 9.0 {
            draw(pill0, in: pillRect.offsetBy(dx: 0, dy: CGFloat(1 - slide) * -140), alpha: slide)
        } else if t < 51.6 {
            let k0 = pillRect.width / shelfRect.width
            if t < 9.8 { draw(pill0, rect: pillRect, scale: lerp(1, 1 / k0, open1), alpha: 1 - clamp(open1 * 2.2)) }
            let k = t < 9.8 ? lerp(k0, 1, open1) : 1
            let a = t < 9.8 ? clamp(open1 * 1.6) : 1
            // Shelf states, cross-faded in order
            let states: [(NSImage, Double)] = [(shelf0, 0), (shelf1, 13.9), (shelf2, 18.7), (shelf3, 22.5), (shelfSelect, 32.2),
                                               (shelf3, 35.0), (searchImg, 41.2), (shelfFixed, 44.0), (shelfSecret, 48.0)]
            for (i, s) in states.enumerated() {
                let fadeIn = s.1 == 0 ? 1 : prog(t, s.1, s.1 + 0.35)
                let next = i + 1 < states.count ? prog(t, states[i + 1].1, states[i + 1].1 + 0.35) : 0
                let alpha = fadeIn * (1 - next)
                if alpha > 0 { draw(s.0, rect: shelfRect, scale: k, alpha: a * alpha) }
            }
            // The secret card's preview, blurred, with a "Hidden" badge
            let secretA = prog(t, 48.0, 48.35)
            if secretA > 0 {
                let r = cardPreview(1)
                fill(r.insetBy(dx: -2, dy: -2), rgb(0x1C1C1E, CGFloat(secretA)), radius: 14 * S)
                drawClipped(blurredSecret, in: r, radius: 14 * S, alpha: secretA)
                let badge = CGRect(x: r.midX - 60, y: r.midY - 17, width: 120, height: 34)
                fill(badge, rgb(0x000000, 0.65 * CGFloat(secretA)), radius: 17)
                if let eye = symbol("eye.slash", size: 14, color: .white) { draw(eye, in: CGRect(x: badge.minX + 14, y: badge.minY + 9, width: eye.size.width, height: eye.size.height), alpha: secretA) }
                text("Hidden", font(16, .semibold), x: badge.minX + 42, y: badge.minY + 7, alpha: secretA)
                ring(around: cardRect(1), t: t, start: 48.5)
            }
        } else if t < 56.2 {
            let k0 = pillRect.width / shelfRect.width
            draw(shelfSecret, rect: shelfRect, scale: lerp(1, k0, close), alpha: 1 - clamp(close * 1.8))
            let bounce = 1 + 0.12 * CGFloat(sin(prog(t, 54.4, 54.9) * .pi))
            draw(pill, rect: pillRect, scale: bounce, alpha: clamp(close * 1.6))
        } else {
            let k0 = pillRect.width / shelfRect.width
            if t < 57.0 { draw(pill, rect: pillRect, scale: lerp(1, 1 / k0, open2), alpha: 1 - clamp(open2 * 2.2)) }
            let k = t < 57.0 ? lerp(k0, 1, open2) : 1
            draw(claudeImg, rect: shelfRect, scale: k * CGFloat(1 - 0.06 * leave), alpha: (t < 57.0 ? clamp(open2 * 1.6) : 1) * (1 - leave))
            // "Needs you" session pulse
            ring(around: cardRect(0), t: t, start: 57.5, color: rgb(0xF5B13A))
            ring(around: cardRect(0), t: t, start: 58.3, color: rgb(0xF5B13A))
        }
        // New-item highlight rings
        ring(around: cardRect(0), t: t, start: 14.2)
        ring(around: cardRect(0), t: t, start: 19.0)
        ring(around: cardRect(0), t: t, start: 22.8)
        ring(around: cardRect(0), t: t, start: 45.0)
    }

    // ---------- Scene 2: hover ----------
    if t >= 7.5 && t < 12.0 {
        let pillTarget = CGPoint(x: W / 2 + 10, y: pillRect.minY + pad * S + 14)
        cur = lerp(CGPoint(x: 1320, y: 760), pillTarget, inOut(prog(t, 7.6, 8.8)))
        if t > 10.0 { cur = lerp(pillTarget, CGPoint(x: 1300, y: 640), inOut(prog(t, 10.2, 11.5))) }
    }

    // ---------- Scene 3: ⌘⇧4 screenshot ----------
    keycaps(["⌘", "⇧", "4"], cy: 740, t: t, start: 12.3, end: 13.5)
    if t >= 12.9 && t < 13.65 {
        let p = inOut(prog(t, 12.95, 13.5))
        let a = CGPoint(x: 260, y: 640), b = lerp(a, CGPoint(x: 760, y: 940), p)
        let sel = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        fill(sel, rgb(0xFFFFFF, 0.12))
        stroke(sel, rgb(0xFFFFFF, 0.9), radius: 1, width: 1.5)
        cur = b
    }
    let flash = 1 - prog(t, 13.6, 14.05)
    if t >= 13.6 && flash > 0 { fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0xFFFFFF, 0.85 * CGFloat(flash))) }

    // ---------- Scene 4: screen recording ----------
    if t > 16.7 && t < 18.6 {
        let a = fade(t, 16.7, 18.6, 0.25)
        let hud = CGRect(x: W - 330, y: 46, width: 150, height: 40)
        fill(hud, rgb(0x000000, 0.6 * CGFloat(a)), radius: 20)
        let blink = 0.5 + 0.5 * cos(t * 6)
        rgb(0xFF3B30, CGFloat(a * (0.6 + 0.4 * blink))).setFill()
        NSBezierPath(ovalIn: CGRect(x: hud.minX + 16, y: hud.minY + 13, width: 14, height: 14)).fill()
        text(String(format: "Recording 0:%02d", Int((t - 16.7) * 2.2) + 1), font(16, .semibold, mono: true), x: hud.minX + 38, y: hud.minY + 10, alpha: a)
    }
    if t >= 16.6 && t < 20.4 {
        cur = lerp(CGPoint(x: 1300, y: 640), CGPoint(x: W - 167, y: 16), inOut(prog(t, 17.0, 18.2)))
        if t > 18.6 { cur = lerp(CGPoint(x: W - 167, y: 16), CGPoint(x: 1380, y: 700), inOut(prog(t, 18.8, 19.9))) }
        pressed = t > 18.35 && t < 18.5
    }

    // ---------- Scene 5: copy text ----------
    let noteA = fade(t, 20.6, 23.9, 0.35)
    if noteA > 0 {
        let r = CGRect(x: 560, y: 560 + CGFloat(1 - out(prog(t, 20.6, 21.0))) * 60, width: 800, height: 330)
        appWindow(ctx, r, title: "Notes", alpha: noteA) { body in
            let line1 = "Team sync"
            text(line1, font(26, .bold), rgb(0x1C1C1E), x: body.minX + 40, y: body.minY + 30)
            let sentence = "Lunch with the design team moved to 1 pm"
            let f = font(24)
            let sel = prog(t, 21.2, 21.8)
            let w = textWidth(sentence, f) * CGFloat(sel)
            if sel > 0 { fill(CGRect(x: body.minX + 38, y: body.minY + 90, width: w + 4, height: 34), rgb(0xB3D7FF), radius: 4) }
            text(sentence, f, rgb(0x1C1C1E), x: body.minX + 40, y: body.minY + 92)
            text("Ship the Perch launch post on Friday.", f, rgb(0x6E6E73), x: body.minX + 40, y: body.minY + 142)
        }
        if t >= 20.9 && t < 22.0 {
            cur = lerp(CGPoint(x: 600, y: 700), CGPoint(x: 1120, y: 700), inOut(prog(t, 21.2, 21.8)))
            pressed = t > 21.2 && t < 21.8
        }
    }
    keycaps(["⌘", "C"], cy: 470, t: t, start: 22.0, end: 23.0)

    // ---------- Scene 6: drag to chat ----------
    let chatA = fade(t, 24.7, 30.4, 0.4)
    let chatRect = CGRect(x: 1180 + CGFloat(1 - out(prog(t, 24.7, 25.2))) * 700, y: 600, width: 640, height: 360)
    if chatA > 0 {
        appWindow(ctx, chatRect, title: "Team chat", alpha: chatA) { body in
            fill(CGRect(x: body.minX + 22, y: body.minY + 22, width: 410, height: 50), rgb(0xE9E9EB), radius: 18)
            text("Can you send me the latest dashboard?", font(17), rgb(0x1C1C1E), x: body.minX + 40, y: body.minY + 36)
            let pop = spring(prog(t, 28.6, 29.2))
            if pop > 0 {
                let thumb = CGRect(x: body.maxX - 22 - 250 * CGFloat(0.7 + 0.3 * pop), y: body.minY + 90, width: 250 * CGFloat(0.7 + 0.3 * pop), height: 167 * CGFloat(0.7 + 0.3 * pop))
                drawClipped(dashboard, in: thumb, radius: 14, alpha: min(1, pop * 1.4))
                let bubble = CGRect(x: body.maxX - 22 - 140, y: body.minY + 266, width: 140, height: 34)
                fill(bubble, rgb(0x0A84FF, CGFloat(min(1, pop))), radius: 17)
                textC("Here it is", font(16, .medium), cx: bubble.midX, y: bubble.minY + 7, alpha: min(1, pop))
            }
        }
    }
    if t >= 24.9 && t < 30.0 {
        let card = center(cardPreview(2))
        let drop = CGPoint(x: chatRect.maxX - 150, y: chatRect.minY + 210)
        cur = lerp(CGPoint(x: 1380, y: 700), card, inOut(prog(t, 25.0, 26.0)))
        if t > 26.2 { cur = lerp(card, drop, inOut(prog(t, 26.4, 28.4))) }
        if t > 28.7 { cur = lerp(drop, CGPoint(x: 1100, y: 760), inOut(prog(t, 28.9, 29.9))) }
        pressed = t > 26.15 && t < 28.6
        if t > 26.2 && t < 28.65, let p = cur {
            let lift = out(prog(t, 26.2, 26.45))
            let r = CGRect(x: p.x - 85, y: p.y - 50, width: 180, height: 120)
            shadow(ctx, blur: 24, y: 14, a: 0.45) { drawClipped(dashboard, in: r, radius: 12, alpha: 0.95 * lift) }
        }
    }

    // ---------- Scene 7: multi-select + drag to a folder ----------
    let finderA = fade(t, 30.3, 35.9, 0.4)
    let finderRect = CGRect(x: 1160 + CGFloat(1 - out(prog(t, 30.3, 30.8))) * 700, y: 580, width: 660, height: 380)
    if finderA > 0 {
        appWindow(ctx, finderRect, title: "Project files", alpha: finderA) { body in
            fill(CGRect(x: body.minX, y: body.minY, width: 150, height: body.height), rgb(0xF2F2F5))
            for (i, s) in ["Recents", "Desktop", "Documents", "Downloads"].enumerated() {
                text(s, font(15), rgb(0x6E6E73), x: body.minX + 20, y: body.minY + 20 + CGFloat(i) * 32)
            }
            let landed = spring(prog(t, 34.2, 34.8))
            if landed > 0 {
                let items: [(NSImage?, String)] = [(symbol("doc.text.fill", size: 60, color: rgb(0x8E8E93)), "Lunch.txt"),
                                                   (sunset, "Screen Recording.mov"), (dashboard, "Screenshot.png")]
                for (i, item) in items.enumerated() {
                    let k = CGFloat(0.6 + 0.4 * landed)
                    let cell = CGRect(x: body.minX + 180 + CGFloat(i) * 160, y: body.minY + 40, width: 120 * k, height: 90 * k)
                    if let img = item.0 { drawClipped(img, in: cell, radius: 8, alpha: min(1, landed * 1.4)) }
                    textC(item.1, font(13), rgb(0x1C1C1E), cx: cell.midX, y: cell.maxY + 10, alpha: min(1, landed * 1.4))
                }
            }
        }
    }
    if t >= 30.4 && t < 35.4 {
        let c0 = center(cardPreview(0)), c1 = center(cardPreview(1)), c2 = center(cardPreview(2))
        let drop = CGPoint(x: finderRect.midX + 60, y: finderRect.midY + 20)
        cur = lerp(CGPoint(x: 1100, y: 760), c0, inOut(prog(t, 30.4, 30.8)))
        if t > 30.95 { cur = lerp(c0, c1, inOut(prog(t, 31.0, 31.4))) }
        if t > 31.55 { cur = lerp(c1, c2, inOut(prog(t, 31.6, 31.9))) }
        if t > 32.6 { cur = lerp(c2, drop, inOut(prog(t, 32.8, 34.0))) }
        if t > 34.3 { cur = lerp(drop, CGPoint(x: 1300, y: 780), inOut(prog(t, 34.5, 35.3))) }
        pressed = (t > 30.85 && t < 31.0) || (t > 31.45 && t < 31.6) || (t > 31.95 && t < 32.1) || (t > 32.6 && t < 34.2)
        // Selection outlines appear as each card is clicked (until the real selected state takes over)
        for (i, at) in [30.9, 31.5, 32.0].enumerated() where t > at && t < 32.3 {
            stroke(cardRect(i).insetBy(dx: 1, dy: 1), rgb(0x4C8DF6), radius: 20 * S, width: 4)
        }
        if t > 32.75 && t < 34.25, let p = cur {
            let lift = out(prog(t, 32.75, 33.0))
            for (i, img) in [loginThumb, sunset, dashboard].enumerated() {
                let r = CGRect(x: p.x - 80 + CGFloat(i) * 8, y: p.y - 46 - CGFloat(i) * 8, width: 160, height: 107)
                shadow(ctx, blur: 18, y: 10, a: 0.35) { drawClipped(img, in: r, radius: 10, alpha: 0.95 * lift) }
            }
            let badge = CGRect(x: p.x + 82, y: p.y - 74, width: 34, height: 34)
            rgb(0xFF3B30, CGFloat(lift)).setFill(); NSBezierPath(ovalIn: badge).fill()
            textC("3", font(19, .bold), cx: badge.midX, y: badge.minY + 6, alpha: lift)
        }
    }

    // ---------- Scene 8: Quick Look ----------
    keycaps(["Space"], cy: 760, t: t, start: 35.9, end: 36.9)
    let ql = spring(prog(t, 36.2, 36.75)) * (1 - inOut(prog(t, 38.8, 39.2)))
    if ql > 0.002 {
        let k = CGFloat(0.85 + 0.15 * ql)
        let r = CGRect(x: W / 2 - 420 * k, y: 300 + (1 - k) * 200, width: 840 * k, height: 600 * k)
        appWindow(ctx, r, title: "Screenshot 9.41.12 AM.png", dark: true, alpha: min(1, ql * 1.3)) { body in
            draw(dashboard, in: body.insetBy(dx: 24, dy: 24))
        }
    }

    // ---------- Scene 9: search ----------
    keycaps(["⌥", "⌘", "F"], cy: 760, t: t, start: 39.8, end: 41.3)
    if t >= 40.6 && t < 41.25 {
        // Typing "q3" into the search box (before the filtered state cross-fades in)
        let typed = t < 40.9 ? "" : (t < 41.1 ? "q" : "q3")
        let box = CGRect(x: shelfRect.minX + 910 * S, y: shelfRect.minY + 76 * S, width: 478 * S, height: 60 * S)
        fill(box, rgb(0x2A2A2C), radius: 16 * S)
        if let mag = symbol("magnifyingglass", size: 15, color: rgb(0x98989D)) { draw(mag, in: CGRect(x: box.minX + 14, y: box.minY + 8, width: mag.size.width, height: mag.size.height)) }
        text(typed + (Int(t * 4) % 2 == 0 ? "|" : ""), font(19), x: box.minX + 42, y: box.minY + 4)
    }

    // ---------- Scene 10: fix & star ----------
    if t >= 44.0 && t < 47.9 {
        let pin = CGPoint(x: cardRect(0).maxX - 70 * S, y: cardRect(0).minY + 30 * S)
        cur = lerp(CGPoint(x: 1300, y: 700), pin, inOut(prog(t, 44.2, 44.8)))
        if t > 45.0 { cur = lerp(pin, CGPoint(x: 1200, y: 720), inOut(prog(t, 45.8, 46.8))) }
        pressed = t > 44.85 && t < 45.0
    }

    // ---------- Scene 12: Services menu ----------
    let docA = fade(t, 52.0, 56.3, 0.4)
    let docRect = CGRect(x: 520, y: 330 + CGFloat(1 - out(prog(t, 52.0, 52.4))) * 60, width: 880, height: 420)
    if docA > 0 {
        appWindow(ctx, docRect, title: "Launch plan.txt", alpha: docA) { body in
            let f = font(24)
            text("Perch launch", font(28, .bold), rgb(0x1C1C1E), x: body.minX + 40, y: body.minY + 30)
            let quote = "“The shelf that keeps up with you.”"
            fill(CGRect(x: body.minX + 38, y: body.minY + 92, width: textWidth(quote, f) + 4, height: 34), rgb(0xB3D7FF), radius: 4)
            text(quote, f, rgb(0x1C1C1E), x: body.minX + 40, y: body.minY + 94)
            text("Post on LinkedIn with the intro video.", f, rgb(0x6E6E73), x: body.minX + 40, y: body.minY + 144)
        }
        // Context menu → Services → Add to Perch
        let menuA = prog(t, 52.85, 53.0) * (1 - prog(t, 54.3, 54.4))
        if menuA > 0 {
            let origin = CGPoint(x: docRect.minX + 400, y: docRect.minY + 170)
            let items = ["Look Up “The shelf…”", "Translate", "—", "Cut", "Copy", "Paste", "—", "Services"]
            var y = origin.y + 8
            let menu = CGRect(x: origin.x, y: origin.y, width: 280, height: 8 + CGFloat(items.count) * 30 + 8)
            withAlpha(ctx, menuA) {
                shadow(ctx, blur: 24, y: 10, a: 0.3) { fill(menu, rgb(0xF6F6F8), radius: 10) }
                for item in items {
                    if item == "—" { fill(CGRect(x: menu.minX + 12, y: y + 14, width: menu.width - 24, height: 1), rgb(0xD1D1D6)); y += 30; continue }
                    let hot = item == "Services" && t > 53.3
                    if hot { fill(CGRect(x: menu.minX + 6, y: y, width: menu.width - 12, height: 28), rgb(0x0A84FF), radius: 6) }
                    text(item, font(16), hot ? .white : rgb(0x1C1C1E), x: menu.minX + 18, y: y + 4)
                    if item == "Services" { text("›", font(18, .semibold), hot ? .white : rgb(0x8E8E93), x: menu.maxX - 26, y: y + 2) }
                    y += 30
                }
                if t > 53.3 {
                    let sub = CGRect(x: menu.maxX - 4, y: menu.maxY - 38 - 66, width: 240, height: 104)
                    shadow(ctx, blur: 24, y: 10, a: 0.3) { fill(sub, rgb(0xF6F6F8), radius: 10) }
                    let subItems = ["Add to Perch", "Make New Note", "Show in Finder"]
                    for (i, item) in subItems.enumerated() {
                        let row = CGRect(x: sub.minX + 6, y: sub.minY + 8 + CGFloat(i) * 30, width: sub.width - 12, height: 28)
                        let hot = i == 0 && t > 53.8
                        if hot { fill(row, rgb(0x0A84FF), radius: 6) }
                        text(item, font(16), hot ? .white : rgb(0x1C1C1E), x: row.minX + 12, y: row.minY + 4)
                    }
                }
            }
        }
        if t > 52.3 && t < 55.8 {
            let sel = CGPoint(x: docRect.minX + 400, y: docRect.minY + 170)
            let services = CGPoint(x: sel.x + 120, y: sel.y + 8 + 7 * 30 + 14)
            let add = CGPoint(x: sel.x + 330, y: services.y - 52)
            cur = lerp(CGPoint(x: 1300, y: 760), sel, inOut(prog(t, 52.3, 52.75)))
            if t > 53.0 { cur = lerp(sel, services, inOut(prog(t, 53.0, 53.3))) }
            if t > 53.4 { cur = lerp(services, add, inOut(prog(t, 53.45, 53.8))) }
            if t > 54.5 { cur = lerp(add, CGPoint(x: 1250, y: 800), inOut(prog(t, 54.6, 55.6))) }
            pressed = (t > 52.75 && t < 52.9) || (t > 54.2 && t < 54.35)
        }
    }

    // ---------- Scenes 13–14: Claude ----------
    if t >= 56.9 && t < 65.4 {
        let goTab = CGPoint(x: cardRect(0).midX, y: cardRect(0).minY + 222 * S)
        cur = lerp(CGPoint(x: 1250, y: 800), CGPoint(x: 1150, y: 640), inOut(prog(t, 57.0, 58.0)))
        if t > 61.1 { cur = lerp(CGPoint(x: 1150, y: 640), goTab, inOut(prog(t, 61.3, 62.2))) }
        if t > 62.6 { cur = lerp(goTab, CGPoint(x: 1500, y: 900), inOut(prog(t, 63.2, 64.4))) }
        pressed = t > 62.3 && t < 62.45
    }
    let termA = fade(t, 62.6, 65.9, 0.4)
    if termA > 0 {
        let r = CGRect(x: 460, y: 470 + CGFloat(1 - out(prog(t, 62.6, 63.1))) * 120, width: 1000, height: 420)
        appWindow(ctx, r, title: "api — claude", dark: true, alpha: termA) { body in
            let f = font(19, .regular, mono: true)
            let lines: [(String, UInt32)] = [
                ("~/code/api ❯ claude", 0xD1D1D6),
                ("✻ Refactoring the API client…", 0xD97757),
                ("  Updated 4 files, tests passing", 0x8E8E93),
                ("", 0xFFFFFF),
                ("⏺ Allow edits to src/client.ts?", 0xF5B13A),
                ("  ❯ 1. Yes      2. No", 0xD1D1D6),
            ]
            for (i, line) in lines.enumerated() { text(line.0, f, rgb(line.1), x: body.minX + 30, y: body.minY + 28 + CGFloat(i) * 38) }
        }
    }

    ctx.restoreGState() // end of camera zoom

    // ---------- Scene 16: styles in mini screens ----------
    let stylesA = fade(t, 70.3, 74.6, 0.4)
    if stylesA > 0 {
        let items: [(NSImage, String, Bool)] = [(styleNotch, "Notch", true), (pill, "Floating", false), (styleOrb, "Orb", false)]
        for (i, item) in items.enumerated() {
            let pop = spring(prog(t, 70.4 + Double(i) * 0.3, 71.1 + Double(i) * 0.3))
            guard pop > 0 else { continue }
            let k = CGFloat(0.8 + 0.2 * pop)
            let screen = CGRect(x: W / 2 - 290 * k + CGFloat(i - 1) * 620, y: 260 + (1 - k) * 100, width: 580 * k, height: 360 * k)
            withAlpha(ctx, min(1, pop) * stylesA) {
                shadow(ctx) { fill(screen, rgb(0x2A3A66), radius: 18) }
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: screen, xRadius: 18, yRadius: 18).addClip()
                let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                   colors: [rgb(0x2B3D73).cgColor, rgb(0x5A3A6E).cgColor] as CFArray, locations: [0, 1])!
                ctx.drawLinearGradient(g, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
                fill(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: 22 * k), rgb(0x000000, 0.28))
                let s = S * 1.05 * k
                let size = px(item.0)
                let top = item.2 ? screen.minY : screen.minY + 34 * k - pad * s
                draw(item.0, in: CGRect(x: screen.midX - size.width * s / 2, y: top, width: size.width * s, height: size.height * s))
                NSGraphicsContext.restoreGraphicsState()
                textC(item.1, font(32, .semibold), rgb(0xF2F2F7), cx: screen.midX, y: screen.maxY + 26)
            }
        }
    }

    // ---------- Scene 17: side panel ----------
    let sideA = fade(t, 74.6, 78.4, 0.4)
    if sideA > 0 {
        let s = S * 1.0
        let size = px(sideImg)
        let r = CGRect(x: -pad * s + CGFloat(1 - out(prog(t, 74.6, 75.2))) * -500, y: H / 2 - size.height * s / 2 + 10,
                       width: size.width * s, height: size.height * s)
        draw(sideImg, in: r, alpha: sideA)
    }

    // ---------- Scene 18: drag it anywhere ----------
    if t >= 78.2 && t < 82.8 {
        let a = fade(t, 78.2, 82.8, 0.4)
        let start = CGPoint(x: W / 2, y: pillRect.midY)
        let end = CGPoint(x: 1380, y: 640)
        let p = inOut(prog(t, 79.2, 80.6))
        let c = lerp(start, end, p)
        let r = CGRect(x: c.x - pillRect.width / 2, y: c.y - pillRect.height / 2, width: pillRect.width, height: pillRect.height)
        draw(pill, in: r, alpha: a)
        let grab = CGPoint(x: c.x + 20, y: c.y + 6)
        cur = t < 79.0 ? lerp(CGPoint(x: 1100, y: 760), CGPoint(x: start.x + 20, y: start.y + 6), inOut(prog(t, 78.3, 78.9))) : grab
        if t > 80.9 { cur = lerp(grab, CGPoint(x: 1600, y: 860), inOut(prog(t, 81.0, 81.8))) }
        pressed = t > 78.95 && t < 80.8
    }

    // ---------- Scene 19: themes ----------
    let themeA = fade(t, 82.3, 86.8, 0.4)
    if themeA > 0 {
        let looks: [(NSImage, Double)] = [(shelfLight, 82.3), (shelfOrange, 84.0), (shelfPurple, 85.2)]
        for (i, look) in looks.enumerated() {
            let inA = prog(t, look.1, look.1 + 0.35)
            let outA = i + 1 < looks.count ? prog(t, looks[i + 1].1, looks[i + 1].1 + 0.35) : 0
            draw(look.0, rect: shelfRect, scale: CGFloat(0.96 + 0.04 * out(inA)), alpha: themeA * inA * (1 - outA))
        }
    }

    // ---------- Scene 20: full-screen video ----------
    let playerA = fade(t, 86.8, 91.4, 0.4)
    if playerA > 0 || fullScreen > 0 {
        if t < 88.0 { draw(pill, in: pillRect, alpha: fade(t, 86.6, 88.6, 0.3)) }
        let small = CGRect(x: 560, y: 340, width: 800, height: 470)
        let r = CGRect(x: lerp(small.minX, 0, inOut(fullScreen)), y: lerp(small.minY, 0, inOut(fullScreen)),
                       width: lerp(small.width, W, inOut(fullScreen)), height: lerp(small.height, H, inOut(fullScreen)))
        withAlpha(ctx, max(playerA, fullScreen)) {
            shadow(ctx) { fill(r, rgb(0x000000), radius: lerp(14, 0, inOut(fullScreen))) }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: lerp(14, 0, inOut(fullScreen)), yRadius: lerp(14, 0, inOut(fullScreen))).addClip()
            let drift = CGFloat(t - 86.8) * 6
            draw(sunset, in: CGRect(x: r.minX - 40 - drift, y: r.minY - 20, width: r.width + 80, height: (r.width + 80) * 2 / 3))
            let bar = CGRect(x: r.minX + 40, y: r.maxY - 56, width: r.width - 80, height: 6)
            fill(bar, rgb(0xFFFFFF, 0.35), radius: 3)
            fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(prog(t, 87.6, 95)), height: 6), rgb(0xFFFFFF), radius: 3)
            let playing = t > 87.6
            if let icon = symbol(playing ? "pause.fill" : "play.fill", size: 22, color: .white) {
                draw(icon, in: CGRect(x: r.minX + 40, y: r.maxY - 100, width: icon.size.width, height: icon.size.height))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if t > 86.9 && t < 88.0 {
            cur = lerp(CGPoint(x: 1500, y: 860), CGPoint(x: 612, y: 718), inOut(prog(t, 86.9, 87.5)))
            pressed = t > 87.55 && t < 87.7
        }
    }

    // ---------- Scene 21: shortcuts ----------
    keycaps(["?"], cy: 820, t: t, start: 91.5, end: 92.5)
    let scA = fade(t, 91.9, 95.4, 0.4)
    if scA > 0 {
        let size = px(shortcutsImg)
        let k: CGFloat = 0.62
        let r = CGRect(x: W / 2 - size.width * k / 2, y: 120 + CGFloat(1 - out(prog(t, 91.9, 92.4))) * 80, width: size.width * k, height: size.height * k)
        appWindow(ctx, CGRect(x: r.minX, y: r.minY - 44, width: r.width, height: r.height + 44), title: "Perch Keyboard Shortcuts",
                  dark: true, alpha: scA) { body in drawClipped(shortcutsImg, in: body, radius: 0) }
    }

    // ---------- Cursor and captions ----------
    if let c = cur { cursor(c, pressed: pressed, alpha: fullScreen > 0.5 ? 0 : 1) }
    for c in captions { caption(c.0, alpha: fade(t, c.1, c.2, 0.3)) }

    // Opening and closing: just the logo and the name
    titleCard(ctx, t: t, alpha: 1 - prog(t, 2.7, 3.3), start: 0.2)
    titleCard(ctx, t: t, alpha: prog(t, 95.0, 95.6), start: 95.3)
}

// MARK: - Video

let tempVideo = FileManager.default.temporaryDirectory.appendingPathComponent("perch-video-\(UUID().uuidString).mp4")
let tempAudio = FileManager.default.temporaryDirectory.appendingPathComponent("perch-audio-\(UUID().uuidString).caf")

func writeVideo() {
    let writer = try! AVAssetWriter(outputURL: tempVideo, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let frames = Int(duration * Double(FPS))
    for f in 0..<frames {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(W), height: Int(H), bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        renderFrame(ctx, t: Double(f) / Double(FPS))
        NSGraphicsContext.restoreGraphicsState()
        CVPixelBufferUnlockBaseAddress(pb, [])
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
        if f % 300 == 0 { print("video \(f)/\(frames)") }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}

// MARK: - Music and sound effects (synthesised; no samples, no licences)

let SR = 48_000.0
let N = Int(duration * SR)
var L = [Float](repeating: 0, count: N)
var R = [Float](repeating: 0, count: N)
var rng = SystemRandomNumberGenerator()
func noise() -> Float { Float.random(in: -1...1, using: &rng) }
func midi(_ n: Double) -> Double { 440 * pow(2, (n - 69) / 12) }

func addMusic() {
    let bpm = 100.0, beat = 60 / bpm, bar = beat * 4
    // C – G – Am – F, with sevenths and ninths for warmth
    let chords: [[Double]] = [[48, 55, 59, 62, 64], [43, 50, 55, 59, 64], [45, 52, 55, 59, 60], [41, 48, 52, 57, 67]]
    let roots: [Double] = [36, 31, 33, 29]
    var padL = [Float](repeating: 0, count: N), padR = [Float](repeating: 0, count: N)
    let bars = Int(duration / bar) + 1
    for b in 0..<bars {
        let chord = chords[b % 4]
        let t0 = Double(b) * bar
        let start = Int(t0 * SR), length = Int((bar + 1.2) * SR)
        for (ni, note) in chord.enumerated() {
            let f = midi(note)
            for i in 0..<length {
                let idx = start + i
                guard idx < N else { break }
                let tt = Double(i) / SR
                let env = min(tt / 0.8, 1) * (tt > bar ? max(0, 1 - (tt - bar) / 1.2) : 1)
                let v = sin(2 * .pi * f * tt) + 0.5 * sin(2 * .pi * f * 1.003 * tt + 0.7) + 0.25 * sin(2 * .pi * f * 2.001 * tt)
                let s = Float(v * env * 0.022)
                let pan = Float(0.35 + 0.3 * Double(ni) / 4)
                padL[idx] += s * (1 - pan); padR[idx] += s * pan
            }
        }
        // Arpeggio (from bar 2), bass and drums (from bar 4), hats (from bar 6)
        for step in 0..<8 {
            let st = t0 + Double(step) * beat / 2
            if b >= 1 {
                let note = chord[1 + (step % 4)] + 12
                pluck(at: st, freq: midi(note), amp: 0.05, decay: 5.5, pan: step % 2 == 0 ? 0.35 : 0.65)
            }
            if b >= 6 && step % 2 == 1 { hat(at: st, amp: 0.022) }
        }
        if b >= 3 {
            for k in 0..<4 {
                pluck(at: t0 + Double(k) * beat, freq: midi(roots[b % 4]), amp: 0.11, decay: 3, pan: 0.5, harmonics: false)
                if k == 0 || k == 2 { kick(at: t0 + Double(k) * beat, amp: 0.22) }
                if b >= 5 && (k == 1 || k == 3) { clap(at: t0 + Double(k) * beat, amp: 0.05) }
            }
        }
    }
    // Simple stereo echo on the pad for space
    let dL = Int(0.31 * SR), dR = Int(0.37 * SR)
    for i in 0..<N {
        let eL = i >= dL ? padR[i - dL] * 0.35 : 0, eR = i >= dR ? padL[i - dR] * 0.35 : 0
        padL[i] += eL; padR[i] += eR
        L[i] += padL[i]; R[i] += padR[i]
    }
}

func pluck(at t: Double, freq: Double, amp: Double, decay: Double, pan: Float, harmonics: Bool = true) {
    let start = Int(t * SR), length = Int(1.2 * SR)
    for i in 0..<length {
        let idx = start + i
        guard idx < N else { break }
        let tt = Double(i) / SR
        var v = sin(2 * .pi * freq * tt)
        if harmonics { v += 0.3 * sin(2 * .pi * freq * 2 * tt) + 0.1 * sin(2 * .pi * freq * 3 * tt) }
        let env = min(tt / 0.004, 1) * exp(-tt * decay)
        let s = Float(v * env * amp)
        L[idx] += s * (1 - pan) * 2 * 0.5; R[idx] += s * pan * 2 * 0.5
    }
}
func kick(at t: Double, amp: Double) {
    let start = Int(t * SR), length = Int(0.35 * SR)
    var phase = 0.0
    for i in 0..<length {
        let idx = start + i
        guard idx < N else { break }
        let tt = Double(i) / SR
        phase += 2 * .pi * (45 + 90 * exp(-tt * 30)) / SR
        let s = Float(sin(phase) * exp(-tt * 9) * amp)
        L[idx] += s; R[idx] += s
    }
}
func hat(at t: Double, amp: Double) {
    let start = Int(t * SR), length = Int(0.06 * SR)
    var prev: Float = 0
    for i in 0..<length {
        let idx = start + i
        guard idx < N else { break }
        let n = noise(); let hp = n - prev; prev = n
        let s = hp * Float(exp(-Double(i) / SR * 70) * amp)
        L[idx] += s * 0.8; R[idx] += s
    }
}
func clap(at t: Double, amp: Double) {
    let start = Int(t * SR), length = Int(0.18 * SR)
    var lp: Float = 0
    for i in 0..<length {
        let idx = start + i
        guard idx < N else { break }
        lp += (noise() - lp) * 0.35
        let s = lp * Float(exp(-Double(i) / SR * 22) * amp)
        L[idx] += s; R[idx] += s
    }
}

func addEffects() {
    for cue in cues {
        let start = Int(cue.at * SR)
        let g = cue.gain
        func put(_ i: Int, _ s: Float, pan: Float = 0.5) {
            let idx = start + i
            guard idx >= 0 && idx < N else { return }
            L[idx] += s * (1 - pan) * 2 * 0.5 * g; R[idx] += s * pan * 2 * 0.5 * g
        }
        switch cue.kind {
        case .click: // crisp mouse click
            var prev: Float = 0
            for i in 0..<Int(0.03 * SR) {
                let tt = Double(i) / SR
                let n = noise(); let hp = n - prev * 0.6; prev = n
                put(i, Float(sin(2 * .pi * 2600 * tt) * exp(-tt * 260)) * 0.28 + hp * Float(exp(-tt * 400)) * 0.22)
            }
        case .key: // soft keyboard key, slightly varied
            let f = Double.random(in: 220...300)
            var lp: Float = 0
            for i in 0..<Int(0.06 * SR) {
                let tt = Double(i) / SR
                lp += (noise() - lp) * 0.5
                put(i, Float(sin(2 * .pi * f * tt) * exp(-tt * 70)) * 0.32 + lp * Float(exp(-tt * 160)) * 0.25, pan: 0.45)
            }
        case .shutter: // two-part camera shutter
            for (offset, amp) in [(0.0, 0.5), (0.07, 0.38)] {
                var lp: Float = 0
                for i in 0..<Int(0.09 * SR) {
                    let tt = Double(i) / SR
                    lp += (noise() - lp) * 0.6
                    put(i + Int(offset * SR), lp * Float(exp(-tt * 55) * amp))
                }
            }
        case .whoosh: // filtered noise sweep
            var lp: Float = 0
            let length = Int(0.55 * SR)
            for i in 0..<length {
                let p = Double(i) / Double(length)
                let cutoff = Float(0.02 + 0.25 * sin(p * .pi))
                lp += (noise() - lp) * cutoff
                put(i, lp * Float(sin(p * .pi) * 0.22), pan: Float(0.3 + 0.4 * p))
            }
        case .pop: // bubbly pop
            for i in 0..<Int(0.12 * SR) {
                let tt = Double(i) / SR
                let f = 520 + 700 * min(tt / 0.04, 1)
                put(i, Float(sin(2 * .pi * f * tt) * exp(-tt * 38) * 0.26))
            }
        case .chime: // two soft bell notes
            for (offset, note) in [(0.0, 84.0), (0.16, 88.0)] {
                for i in 0..<Int(1.4 * SR) {
                    let tt = Double(i) / SR
                    let f = midi(note)
                    put(i + Int(offset * SR), Float((sin(2 * .pi * f * tt) + 0.4 * sin(2 * .pi * f * 2.76 * tt)) * exp(-tt * 3.2) * 0.12))
                }
            }
        }
    }
}

func writeAudio() {
    addMusic()
    addEffects()
    // Fade in/out and gentle limiting
    for i in 0..<N {
        let t = Double(i) / SR
        let env = Float(min(t / 1.5, 1) * min((duration - t) / 3.5, 1))
        L[i] = tanhf(L[i] * env * 1.4) * 0.85
        R[i] = tanhf(R[i] * env * 1.4) * 0.85
    }
    let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
    let file = try! AVAudioFile(forWriting: tempAudio, settings: format.settings)
    let chunk = 48_000
    var offset = 0
    while offset < N {
        let n = min(chunk, N - offset)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        for i in 0..<n {
            buffer.floatChannelData![0][i] = L[offset + i]
            buffer.floatChannelData![1][i] = R[offset + i]
        }
        try! file.write(from: buffer)
        offset += n
    }
}

// MARK: - Mux

func mux() {
    let composition = AVMutableComposition()
    let videoAsset = AVURLAsset(url: tempVideo), audioAsset = AVURLAsset(url: tempAudio)
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))
    let vTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let aTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try! vTrack.insertTimeRange(range, of: videoAsset.tracks(withMediaType: .video)[0], at: .zero)
    try! aTrack.insertTimeRange(range, of: audioAsset.tracks(withMediaType: .audio)[0], at: .zero)
    try? FileManager.default.removeItem(at: finalURL)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    export.outputURL = finalURL
    export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    done.wait()
    if export.status != .completed { print("Export failed: \(export.error?.localizedDescription ?? "?")") }
}

writeVideo()
print("audio…")
writeAudio()
print("mux…")
mux()
try? FileManager.default.removeItem(at: tempVideo)
try? FileManager.default.removeItem(at: tempAudio)
print("Wrote \(finalURL.path)")

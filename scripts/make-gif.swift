// Builds the short looping GIF at the top of the README: hover to open, a screenshot lands, drag it into
// a chat, the Claude view and its activity heatmap, close. Drawn from the app's own views (sample data), like the intro video.
//
//   build/Perch.app/Contents/MacOS/Perch --render-video-states build/video-states
//   swiftc -O -o build/make-gif scripts/make-gif.swift
//   build/make-gif build/video-states docs/screenshots/perch.gif
import AppKit
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") }
let statesDir = URL(fileURLWithPath: args.first ?? "build/video-states")
let outURL = URL(fileURLWithPath: args.dropFirst().first ?? "docs/screenshots/perch.gif")

let W: CGFloat = 1000, H: CGFloat = 640
let FPS = 20
let duration = 17.2

// MARK: - Easing

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func inOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
func expoOut(_ p: Double) -> Double { p >= 1 ? 1 : 1 - pow(2, -10 * p) }
func spring(_ p: Double) -> Double { p <= 0 ? 0 : (p >= 1 ? 1 : 1 - exp(-7 * p) * cos(7 * p)) }
func fade(_ t: Double, _ a: Double, _ b: Double, _ f: Double = 0.3) -> Double { min(prog(t, a, a + f), 1 - prog(t, b - f, b)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }

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
let pill0 = load("pill-0.png"), pill1 = load("pill-1.png")
let shelf0 = load("shelf-0.png"), shelf1 = load("shelf-1.png"), claudeImg = load("claude.png")
let claudeCalendar = load("claude-calendar.png"), claudeHours = load("claude-hours.png")
let dashboard = load("drag-thumb.png")

let pad: CGFloat = 48            // transparent padding around the island images (px)
let k: CGFloat = 880 / (px(shelf0).width - 2 * pad) // image px → canvas points
let menuH: CGFloat = 28
let islandTop: CGFloat = menuH + 6

/// An island image placed centred under the menu bar.
func topRect(_ image: NSImage) -> CGRect {
    let s = px(image)
    return CGRect(x: W / 2 - s.width * k / 2, y: islandTop - pad * k, width: s.width * k, height: s.height * k)
}
let shelfRect = topRect(shelf0), pillRect = topRect(pill0)
func inShelf(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: shelfRect.minX + x * k, y: shelfRect.minY + y * k) }
func cardRect(_ i: Int) -> CGRect { CGRect(origin: inShelf(88 + 224 * CGFloat(i), 161), size: CGSize(width: 208 * k, height: 252 * k)) }
let previewCenter = inShelf(190, 229)
let claudeButton = inShelf(1430, 106)

// MARK: - Drawing helpers (top-left origin)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let white = rgb(0xF5F5F7), grey = rgb(0x9A9AA2), blueAccent = rgb(0x7AA7FF)
var ctx: CGContext!

func draw(_ image: NSImage, in r: CGRect, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    image.draw(in: r, from: .zero, operation: .sourceOver, fraction: CGFloat(min(alpha, 1)), respectFlipped: true,
               hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
}
func drawClipped(_ image: NSImage, in r: CGRect, radius: CGFloat, alpha: Double = 1) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
    draw(image, in: r, alpha: alpha)
    NSGraphicsContext.restoreGraphicsState()
}
func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
    c.setFill()
    if radius > 0 { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() } else { NSBezierPath(rect: r).fill() }
}
func stroke(_ r: CGRect, _ c: NSColor, radius: CGFloat, width: CGFloat = 1) {
    c.setStroke(); let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius); p.lineWidth = width; p.stroke()
}
func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: size, weight: weight) }
func width(_ s: String, _ f: NSFont) -> CGFloat { NSAttributedString(string: s, attributes: [.font: f]).size().width }
func text(_ s: String, _ f: NSFont, _ c: NSColor, x: CGFloat, y: CGFloat, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c.withAlphaComponent(c.alphaComponent * CGFloat(alpha))])
        .draw(at: NSPoint(x: x, y: y))
}
func shadow(blur: CGFloat = 30, y: CGFloat = 12, a: CGFloat = 0.5, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: NSColor.black.withAlphaComponent(a).cgColor)
    body()
    ctx.restoreGState()
}
func layer(_ a: Double, _ body: () -> Void) {
    guard a > 0.002 else { return }
    ctx.saveGState(); ctx.setAlpha(CGFloat(min(a, 1))); ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctx.endTransparencyLayer(); ctx.restoreGState()
}
func symbol(_ name: String, size: CGFloat, color: NSColor) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return nil }
    return NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
}
let apple = symbol("applelogo", size: 13, color: white)

/// A plain dark desktop (flat colours keep the GIF small and free of banding).
func desktop() {
    fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x14161F))
    fill(CGRect(x: 0, y: 0, width: W, height: menuH), rgb(0x0B0C11))
    if let apple { draw(apple, in: CGRect(x: 18, y: 7, width: apple.size.width, height: apple.size.height)) }
    text("Finder", font(13, .semibold), white, x: 44, y: 6)
    var x: CGFloat = 100
    for item in ["File", "Edit", "View", "Go", "Window"] { text(item, font(13), white, x: x, y: 6); x += width(item, font(13)) + 18 }
    text("Mon 9:41 AM", font(13), white, x: W - 100, y: 6)
}
func cursor(_ p: CGPoint, pressed: Bool) {
    let s: CGFloat = pressed ? 0.85 : 0.95
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 25), (6, 19.5), (10.5, 28.5), (14.5, 26.8), (10.2, 18), (18, 18)]
    let path = NSBezierPath(); path.move(to: p)
    for q in pts.dropFirst() { path.line(to: NSPoint(x: p.x + q.0 * s, y: p.y + q.1 * s)) }
    path.close()
    shadow(blur: 4, y: 2, a: 0.4) { NSColor.black.setFill(); path.fill() }
    path.lineWidth = 1.6; NSColor.white.setStroke(); path.stroke()
}
func keycaps(_ keys: [String], cx: CGFloat, cy: CGFloat, t: Double, start: Double, end: Double) {
    let a = fade(t, start, end, 0.2)
    guard a > 0.002 else { return }
    let f = font(17, .medium), h: CGFloat = 38, gap: CGFloat = 8
    let ws = keys.map { max(h, width($0, f) + 24) }
    var x = cx - (ws.reduce(0, +) + gap * CGFloat(keys.count - 1)) / 2
    for (i, key) in keys.enumerated() {
        let p = spring(prog(t, start + Double(i) * 0.07, start + Double(i) * 0.07 + 0.5))
        let r = CGRect(x: x, y: cy - h / 2 + CGFloat(1 - p) * 8, width: ws[i], height: h)
        layer(a * min(1, p * 1.5)) {
            fill(r, rgb(0x1E1F27), radius: 9); stroke(r, rgb(0x3A3B45), radius: 9)
            text(key, f, white, x: r.midX - width(key, f) / 2, y: r.midY - 11)
        }
        x += ws[i] + gap
    }
}
func appWindow(_ r: CGRect, title: String, alpha: Double, body: (CGRect) -> Void) {
    layer(alpha) {
        shadow(blur: 30, y: 14, a: 0.55) { fill(r, rgb(0x1C1C1F), radius: 10) }
        stroke(r, rgb(0xFFFFFF, 0.08), radius: 10)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
        fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 30), rgb(0x26262A))
        NSGraphicsContext.restoreGraphicsState()
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            rgb(hex).setFill(); NSBezierPath(ovalIn: CGRect(x: r.minX + 12 + CGFloat(i) * 16, y: r.minY + 10, width: 10, height: 10)).fill()
        }
        let f = font(12, .semibold)
        text(title, f, rgb(0xB0B0B6), x: r.midX - width(title, f) / 2, y: r.minY + 8)
        body(CGRect(x: r.minX, y: r.minY + 30, width: r.width, height: r.height - 30))
    }
}
/// A caption in the bottom-left corner, shown between `start` and `end`.
func caption(_ s: String, t: Double, start: Double, end: Double) {
    let a = fade(t, start, end, 0.25)
    guard a > 0.002 else { return }
    let rise = CGFloat(1 - expoOut(prog(t, start, start + 0.5))) * 8
    text(s, font(22, .semibold), white, x: 40, y: H - 56 + rise, alpha: a)
}

// MARK: - Timeline

let restCursor = CGPoint(x: 260, y: 470)
let pillPoint = CGPoint(x: W / 2 + 6, y: islandTop + 14)
let chat = CGRect(x: 470, y: 318, width: 490, height: 270)
let sidebarW: CGFloat = 132
/// The chat's message area (right of the sidebar, below the title bar).
var chatMain: CGRect { CGRect(x: chat.minX + sidebarW, y: chat.minY + 30, width: chat.width - sidebarW, height: chat.height - 30) }
let chatDrop = CGPoint(x: chat.minX + sidebarW + 120, y: chat.minY + 160)

func avatar(_ letter: String, _ color: NSColor, x: CGFloat, y: CGFloat) {
    color.setFill(); NSBezierPath(roundedRect: CGRect(x: x, y: y, width: 26, height: 26), xRadius: 7, yRadius: 7).fill()
    let f = font(13, .bold)
    text(letter, f, .white, x: x + 13 - width(letter, f) / 2, y: y + 5)
}

/// A small team-chat app: channels on the left, the conversation and a message box on the right.
func chatApp(t: Double, alpha: Double, offset: CGFloat) {
    let r = chat.offsetBy(dx: 0, dy: offset)
    appWindow(r, title: "Design team", alpha: alpha) { body in
        // Sidebar
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: CGRect(x: body.minX, y: body.minY - 10, width: body.width, height: body.height + 10), xRadius: 10, yRadius: 10).addClip()
        fill(CGRect(x: body.minX, y: body.minY, width: sidebarW, height: body.height), rgb(0x18181C))
        NSGraphicsContext.restoreGraphicsState()
        fill(CGRect(x: body.minX + sidebarW - 1, y: body.minY, width: 1, height: body.height), rgb(0x000000, 0.5))
        text("Design team", font(13, .bold), white, x: body.minX + 14, y: body.minY + 12)
        var y = body.minY + 44
        text("Channels", font(10.5, .semibold), grey, x: body.minX + 14, y: y); y += 20
        for (name, selected) in [("general", false), ("design", true), ("launch", false)] {
            if selected { fill(CGRect(x: body.minX + 6, y: y - 3, width: sidebarW - 12, height: 22), rgb(0x2F5BD3), radius: 5) }
            text("# \(name)", font(12.5, selected ? .semibold : .regular), selected ? .white : rgb(0xC4C4CA), x: body.minX + 14, y: y)
            y += 24
        }
        y += 8
        text("Direct messages", font(10.5, .semibold), grey, x: body.minX + 14, y: y); y += 20
        for (name, color) in [("Maya", rgb(0x34C759)), ("Sam", grey)] {
            color.setFill(); NSBezierPath(ovalIn: CGRect(x: body.minX + 15, y: y + 5, width: 7, height: 7)).fill()
            text(name, font(12.5), rgb(0xC4C4CA), x: body.minX + 28, y: y); y += 24
        }

        // Conversation
        let main = CGRect(x: body.minX + sidebarW, y: body.minY, width: body.width - sidebarW, height: body.height)
        text("# design", font(13, .bold), white, x: main.minX + 16, y: main.minY + 10)
        fill(CGRect(x: main.minX, y: main.minY + 36, width: main.width, height: 1), rgb(0xFFFFFF, 0.07))
        avatar("M", rgb(0xD9774F), x: main.minX + 16, y: main.minY + 50)
        text("Maya", font(12.5, .bold), white, x: main.minX + 52, y: main.minY + 48)
        text("9:40 AM", font(11), grey, x: main.minX + 52 + width("Maya", font(12.5, .bold)) + 8, y: main.minY + 49)
        text("Can you send me the dashboard?", font(13), rgb(0xDCDCE0), x: main.minX + 52, y: main.minY + 65)

        let landed = spring(prog(t, 6.3, 6.8))
        if landed > 0 {
            let a = min(1, landed * 1.4)
            let my = main.minY + 96 + CGFloat(1 - landed) * 10
            layer(a) {
                avatar("A", rgb(0x5B7CF0), x: main.minX + 16, y: my + 2)
                text("You", font(12.5, .bold), white, x: main.minX + 52, y: my)
                text("9:41 AM", font(11), grey, x: main.minX + 52 + width("You", font(12.5, .bold)) + 8, y: my + 1)
                let img = CGRect(x: main.minX + 52, y: my + 20, width: 112, height: 75)
                drawClipped(dashboard, in: img, radius: 7)
                stroke(img, rgb(0xFFFFFF, 0.1), radius: 7)
            }
        }

        // Message box
        let box = CGRect(x: main.minX + 14, y: main.maxY - 42, width: main.width - 28, height: 30)
        fill(box, rgb(0x232327), radius: 8); stroke(box, rgb(0xFFFFFF, 0.1), radius: 8)
        text("+", font(16, .medium), grey, x: box.minX + 10, y: box.minY + 4)
        text("Message #design", font(12.5), grey, x: box.minX + 28, y: box.minY + 7)

        // Drop highlight while the screenshot is over the conversation
        let over = prog(t, 5.75, 5.95) * (1 - prog(t, 6.25, 6.4))
        if over > 0.002 {
            let z = main.insetBy(dx: 8, dy: 8)
            fill(z, rgb(0x0A84FF, 0.13 * CGFloat(over)), radius: 8)
            stroke(z, rgb(0x0A84FF, 0.9 * CGFloat(over)), radius: 8, width: 2)
            let s = "Drop to share in #design", f = font(13, .semibold)
            let tag = CGRect(x: z.midX - width(s, f) / 2 - 12, y: z.maxY - 74, width: width(s, f) + 24, height: 26)
            fill(tag, rgb(0x0A84FF, 0.9 * CGFloat(over)), radius: 13)
            text(s, f, .white, x: tag.minX + 12, y: tag.minY + 5, alpha: over)
        }
    }
}

/// The cards slide right to make room and the new screenshot pops in at the front.
func screenshotLands(_ t: Double) {
    let strip = CGRect(origin: inShelf(80, 155), size: CGSize(width: (1532 - 80) * k, height: 264 * k))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: strip).addClip()
    fill(strip, rgb(0x000000))
    let shift = 224 * k * CGFloat(expoOut(prog(t, 2.95, 3.35)))
    NSBezierPath(rect: strip.offsetBy(dx: shift, dy: 0)).addClip() // only the cards move, not the shelf's edge
    draw(shelf0, in: shelfRect.offsetBy(dx: shift, dy: 0))
    NSGraphicsContext.restoreGraphicsState()
    let p = spring(prog(t, 3.3, 3.75))
    guard p > 0 else { return }
    let card = cardRect(0).insetBy(dx: -3, dy: -3)
    let sc = CGFloat(0.92 + 0.08 * p)
    let r = CGRect(x: card.midX - card.width * sc / 2, y: card.midY - card.height * sc / 2, width: card.width * sc, height: card.height * sc)
    let ik = shelf1.size.width / px(shelf1).width
    let from = CGRect(x: (88 - 3 / k) * ik, y: (px(shelf1).height - 161 - 252 - 3 / k) * ik, width: (208 + 6 / k) * ik, height: (252 + 6 / k) * ik)
    shelf1.draw(in: r, from: from, operation: .sourceOver, fraction: CGFloat(min(1, p * 1.6)), respectFlipped: true, hints: nil)
}

/// The heatmap part zooms in a little so the map is easier to read.
func zoom(_ t: Double) -> CGFloat { 1 + 0.12 * CGFloat(inOut(prog(t, 9.4, 10.0)) * (1 - inOut(prog(t, 13.0, 13.5)))) }
func zoomed(_ p: CGPoint, _ z: CGFloat) -> CGPoint { CGPoint(x: W / 2 + (p.x - W / 2) * z, y: islandTop + (p.y - islandTop) * z) }

// The screenshot scene: an analytics dashboard in a browser window, captured with ⌘⇧4.
let dashWindow = CGRect(x: 40, y: 318, width: 330, height: 250)
let dashImage = CGRect(x: dashWindow.minX, y: dashWindow.minY + 30, width: dashWindow.width, height: dashWindow.height - 30)
let selStart = CGPoint(x: dashImage.minX + 6, y: dashImage.minY + 6)
let selEnd = CGPoint(x: dashImage.maxX - 6, y: dashImage.maxY - 6)
/// Extra seconds the capture takes; the rest of the timeline runs this much later.
let captureTime = 1.7

func dashboardWindow(alpha: Double) {
    appWindow(dashWindow, title: "Analytics · Q3 dashboard", alpha: alpha) { body in
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: CGRect(x: body.minX, y: body.minY - 10, width: body.width, height: body.height + 10), xRadius: 10, yRadius: 10).addClip()
        draw(dashboard, in: body)
        NSGraphicsContext.restoreGraphicsState()
    }
}
func crosshair(_ p: CGPoint) {
    for (w, c) in [(CGFloat(3), NSColor.black.withAlphaComponent(0.6)), (1.2, NSColor.white)] {
        c.setStroke()
        let path = NSBezierPath(); path.lineWidth = w
        path.move(to: CGPoint(x: p.x - 11, y: p.y)); path.line(to: CGPoint(x: p.x + 11, y: p.y))
        path.move(to: CGPoint(x: p.x, y: p.y - 11)); path.line(to: CGPoint(x: p.x, y: p.y + 11))
        path.stroke()
    }
}

func frame(_ T: Double) {
    // `t` is the rest of the story's clock: it pauses while the screenshot is being taken.
    let landAt = 2.95
    let t = T <= landAt ? T : max(landAt, T - captureTime)
    desktop()

    let windowsOut = 1 - prog(t, 7.2, 7.7)
    dashboardWindow(alpha: windowsOut)

    // Island: pill → shelf → (screenshot) → Claude sessions → activity (calendar, hours) → pill
    let openAt = 1.25, closeAt = 13.6
    let open = spring(prog(t, openAt, openAt + 0.7))
    let close = inOut(prog(t, closeAt, closeAt + 0.5))
    if t >= openAt && t < closeAt + 0.5 {
        let p = t < closeAt ? open : 1 - close
        let s = lerp(pillRect.width / shelfRect.width, 1, p)
        let r = CGRect(x: W / 2 - shelfRect.width * s / 2, y: shelfRect.minY + pad * k * (1 - s),
                       width: shelfRect.width * s, height: shelfRect.height * s)
        let a = t < closeAt ? clamp(open * 1.8) : clamp((1 - close) * 1.8)
        let claude = prog(t, 7.75, 8.1)
        let calendar = prog(t, 9.15, 9.45), hours = prog(t, 11.75, 12.05)
        let landed = T >= landAt + captureTime
        let zoomAnchor = CGPoint(x: W / 2, y: islandTop)
        ctx.saveGState()
        ctx.translateBy(x: zoomAnchor.x, y: zoomAnchor.y); ctx.scaleBy(x: zoom(t), y: zoom(t)); ctx.translateBy(x: -zoomAnchor.x, y: -zoomAnchor.y)
        shadow {
            layer(a) {
                draw(shelf0, in: r, alpha: landed ? 0 : 1)
                draw(shelf1, in: r, alpha: (landed ? 1 : 0) * (1 - claude))
                if landed && t < 3.8 { screenshotLands(t) }
                draw(claudeImg, in: r, alpha: claude * (1 - calendar))
                draw(claudeCalendar, in: r, alpha: calendar * (1 - hours))
                draw(claudeHours, in: r, alpha: hours)
            }
        }
        ctx.restoreGState()
        let pillA = t < closeAt ? 1 - clamp(open * 3) : clamp(close * 3 - 1.2)
        draw(t < 5 ? pill0 : pill1, in: pillRect, alpha: pillA)
    } else {
        shadow(blur: 16, y: 6, a: 0.45) { draw(t < 5 ? pill0 : pill1, in: pillRect) }
    }

    // ⌘⇧4, drag a selection over the dashboard, flash, and the capture flies into the shelf
    keycaps(["⌘", "⇧", "4"], cx: 720, cy: 450, t: T, start: 2.6, end: 3.4)
    let dragP = inOut(prog(T, 3.2, 4.0))
    let selCorner = lerp(selStart, selEnd, dragP)
    if T > 3.15 && T < 4.05 {
        let sel = CGRect(x: selStart.x, y: selStart.y, width: selCorner.x - selStart.x, height: selCorner.y - selStart.y)
        fill(sel, rgb(0xFFFFFF, 0.12)); stroke(sel, rgb(0xFFFFFF, 0.9), radius: 0, width: 1)
        let label = "\(Int(sel.width * 2)) × \(Int(sel.height * 2))", f = font(11, .medium)
        let tag = CGRect(x: selCorner.x + 12, y: selCorner.y + 8, width: width(label, f) + 12, height: 18)
        fill(tag, rgb(0x000000, 0.65), radius: 4)
        text(label, f, .white, x: tag.minX + 6, y: tag.minY + 2)
    }
    if T > 4.05 && T < 4.4 { fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0xFFFFFF, 0.22 * CGFloat(1 - prog(T, 4.05, 4.4)))) }
    let arrive = landAt + captureTime + 0.35 // the cards have made room by then
    if T > 4.1 && T < arrive + 0.15 {
        let f = inOut(prog(T, 4.15, arrive))
        let from = CGRect(x: selStart.x, y: selStart.y, width: selEnd.x - selStart.x, height: selEnd.y - selStart.y)
        let to = CGRect(origin: inShelf(98, 171), size: CGSize(width: 184 * k, height: 116 * k))
        var r = CGRect(x: lerp(from.minX, to.minX, f), y: lerp(from.minY, to.minY, f),
                       width: lerp(from.width, to.width, f), height: lerp(from.height, to.height, f))
        r.origin.y -= CGFloat(sin(f * .pi)) * 30 // a slight arc
        shadow(blur: 20, y: 10, a: 0.5) { drawClipped(dashboard, in: r, radius: lerp(4, 8, f), alpha: 1 - prog(T, arrive, arrive + 0.15)) }
        stroke(r, rgb(0xFFFFFF, 0.5 * CGFloat(1 - f)), radius: lerp(4, 8, f))
    }

    let chatIn = expoOut(prog(t, 3.4, 4.1)) * windowsOut
    if chatIn > 0.002 { chatApp(t: t, alpha: chatIn, offset: CGFloat(1 - expoOut(prog(t, 3.4, 4.1))) * 40) }

    // Cursor
    let activityTab = inShelf(1222, 106), hoursTab = zoomed(inShelf(303, 176), 1.12)
    var c = restCursor
    var pressed = false
    if T < 1.25 { c = lerp(restCursor, pillPoint, inOut(prog(T, 0.3, 1.2))) }
    else if T < 3.15 { c = lerp(pillPoint, selStart, inOut(prog(T, 1.9, 2.6))) }
    else if T < 4.05 { c = selCorner; pressed = true }
    else if t < 5.0 { c = lerp(selEnd, previewCenter, inOut(prog(t, 3.9, 4.8))) }
    else if t < 6.4 { c = lerp(previewCenter, chatDrop, inOut(prog(t, 5.15, 6.2))); pressed = t > 5.0 && t < 6.3 }
    else if t < 8.0 { c = lerp(chatDrop, claudeButton, inOut(prog(t, 6.6, 7.6))); pressed = t > 7.65 && t < 7.8 }
    else if t < 9.3 { c = lerp(claudeButton, activityTab, inOut(prog(t, 8.2, 9.0))); pressed = t > 9.05 && t < 9.2 }
    else if t < 11.9 { c = lerp(activityTab, hoursTab, inOut(prog(t, 10.6, 11.6))); pressed = t > 11.65 && t < 11.8 }
    else { c = lerp(hoursTab, restCursor, inOut(prog(t, 13.3, 14.6))) }

    if t > 5.0 && t < 6.35 {
        let lift = expoOut(prog(t, 5.0, 5.3))
        shadow(blur: 16, y: 8, a: 0.5) {
            drawClipped(dashboard, in: CGRect(x: c.x - 52, y: c.y - 32, width: 112, height: 75), radius: 8, alpha: lift * 0.95)
        }
        if t > 5.75 {
            let b = CGRect(x: c.x + 50, y: c.y - 44, width: 22, height: 22)
            rgb(0x34C759).setFill(); NSBezierPath(ovalIn: b).fill()
            text("+", font(16, .bold), .white, x: b.midX - 5, y: b.minY + 1)
        }
    }
    if T > 2.95 && T < 4.1 { crosshair(c) } else { cursor(c, pressed: pressed) }

    let D = captureTime
    caption("Hover to open your shelf", t: T, start: 0.4, end: 2.4)
    caption("Take a screenshot… it lands on your shelf", t: T, start: 2.5, end: 4.6 + D)
    caption("Drag anything out, into any app", t: T, start: 4.7 + D, end: 7.4 + D)
    caption("Claude Code sessions, agents and usage", t: T, start: 7.6 + D, end: 9.4 + D)
    caption("Your Claude activity, by day or by hour", t: T, start: 9.5 + D, end: 13.5 + D)
    caption("Free and open source, for macOS 13+", t: T, start: 13.8 + D, end: 15.4 + D)
}

// MARK: - Render

let scale: CGFloat = 1
let pw = Int(W * scale), ph = Int(H * scale)
let frames = Int(duration * Double(FPS))
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.gif.identifier as CFString, frames, nil) else {
    fatalError("Can't write \(outURL.path)")
}
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(FPS),
                                                  kCGImagePropertyGIFUnclampedDelayTime: 1.0 / Double(FPS)]] as CFDictionary
for i in 0..<frames {
    autoreleasepool {
        ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: scale, y: -scale)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        frame(Double(i) / Double(FPS))
        NSGraphicsContext.current = nil
        CGImageDestinationAddImage(dest, ctx.makeImage()!, frameProps)
    }
}
guard CGImageDestinationFinalize(dest) else { fatalError("Couldn't finish the GIF") }
let size = (try? FileManager.default.attributesOfItem(atPath: outURL.path)[.size] as? Int) ?? 0
print("Wrote \(outURL.path) (\(frames) frames, \(size / 1024) KB)")

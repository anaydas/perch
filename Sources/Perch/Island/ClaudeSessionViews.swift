import AppKit
import SwiftUI

extension ClaudeSession.Status {
    var color: Color {
        switch self {
        case .waiting: return Color(red: 0.98, green: 0.69, blue: 0.20)
        case .working: return ClaudeLogo.orange
        case .idle: return Color.white.opacity(0.45)
        }
    }
}

extension ClaudeSession {
    var statusLabel: String {
        switch status {
        case .waiting: return "Needs you"
        case .working: return "Working"
        case .idle: return "Idle"
        }
    }
}

/// Claude's logo, loaded from the installed Claude app (not bundled), tinted Claude orange.
enum ClaudeLogo {
    static let orange = Color(red: 0.851, green: 0.467, blue: 0.341) // #D97757

    /// The app's menu bar icon; `image(forResource:)` picks up the @2x/@3x versions too.
    static let image: NSImage? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop"),
              let image = Bundle(url: url)?.image(forResource: "TrayIconTemplate") else { return nil }
        image.isTemplate = true
        return image
    }()

    /// Small static orange logo, for labels.
    @ViewBuilder
    static func markIcon(size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                .foregroundStyle(orange)
                .frame(width: size * 1.4, height: size * 1.4)
                .frame(width: size, height: size)
        } else {
            ClaudeMarkShape().fill(orange).frame(width: size, height: size)
        }
    }
}

/// Fallback starburst for when the Claude app isn't installed.
struct ClaudeMarkShape: Shape {
    var rays = 10

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let width = radius * 0.32
        var path = Path()
        for i in 0..<rays {
            let ray = Path(roundedRect: CGRect(x: -width / 2, y: -radius, width: width, height: radius),
                           cornerRadius: width / 2)
            let angle = CGFloat(i) / CGFloat(rays) * 2 * .pi
            path.addPath(ray, transform: CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle))
        }
        return path
    }
}

/// The mark, coloured and animated by status: spinning while working, pulsing while waiting.
struct ClaudeMarkView: View {
    let status: ClaudeSession.Status
    var size: CGFloat = 11

    var body: some View {
        Animated(status: status, size: size).id(status)
    }

    private struct Animated: View {
        let status: ClaudeSession.Status
        let size: CGFloat
        @State private var phase = false

        @ViewBuilder
        private var logo: some View {
            if let image = ClaudeLogo.image {
                // The icon has built-in padding, so draw it a bit larger than the slot.
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .foregroundStyle(ClaudeLogo.orange)
                    .frame(width: size * 1.4, height: size * 1.4)
                    .frame(width: size, height: size)
            } else {
                ClaudeMarkShape()
                    .fill(ClaudeLogo.orange)
                    .frame(width: size, height: size)
            }
        }

        var body: some View {
            logo
                .opacity(status == .idle ? 0.5 : 1)
                .rotationEffect(.degrees(status == .working && phase ? 360 : 0))
                .scaleEffect(status == .waiting && phase ? 1.2 : 1)
                .overlay(alignment: .topTrailing) {
                    if status == .waiting {
                        Circle()
                            .fill(ClaudeSession.Status.waiting.color)
                            .overlay(Circle().stroke(Color.black, lineWidth: 1))
                            .frame(width: size * 0.45, height: size * 0.45)
                            .offset(x: size * 0.15, y: -size * 0.15)
                    }
                }
                .onAppear {
                    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    switch status {
                    case .working:
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { phase = true }
                    case .waiting:
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { phase = true }
                    case .idle:
                        break
                    }
                }
        }
    }
}

/// Shown on the collapsed pill: the most urgent session's status, plus how many need you.
struct ClaudeIndicator: View {
    let sessions: [ClaudeSession]

    var body: some View {
        if let top = sessions.first {
            let waiting = sessions.filter { $0.status == .waiting }.count
            HStack(spacing: 2) {
                ClaudeMarkView(status: top.status, size: 11)
                if waiting > 1 {
                    Text("\(waiting)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(ClaudeSession.Status.waiting.color)
                }
            }
            .help(sessions.map { "\($0.title): \($0.statusLabel)" }.joined(separator: "\n"))
        }
    }
}

/// A running session, shown as a card the same size as a shelf card. Click to open it.
struct SessionCardView: View {
    let session: ClaudeSession
    let watcher: ClaudeSessionWatcher
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack {
                session.status.color.opacity(session.status == .idle ? 0.08 : 0.16)
                ClaudeMarkView(status: session.status, size: 24)
            }
            .frame(width: IslandMetrics.cardWidth - 12, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(session.title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(session.statusLabel)
                    .foregroundStyle(session.status.color)
                Spacer(minLength: 2)
                // App or terminal, as an icon (the words don't fit beside "Needs you").
                Image(systemName: session.source == .terminal ? "terminal" : "macwindow")
                    .foregroundStyle(.secondary)
                    .help(session.source == .terminal ? "Running in a terminal" : "Running in the Claude app")
            }
            .font(.system(size: 9.5))
            .lineLimit(1)

            Spacer(minLength: 0)

            Button { watcher.open(session) } label: {
                Label(session.source == .terminal ? "Go to tab" : "Open",
                      systemImage: session.source == .terminal ? "arrow.up.forward.app" : "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(session.status == .waiting ? ClaudeSession.Status.waiting.color.opacity(0.3)
                                                         : Color.white.opacity(hovering ? 0.18 : 0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: IslandMetrics.cardWidth, height: IslandMetrics.cardHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.11 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(session.status == .waiting ? ClaudeSession.Status.waiting.color.opacity(0.8)
                                                     : Color.white.opacity(0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .onTapGesture { watcher.open(session) }
        .help(helpText)
        .contextMenu {
            Button(session.source == .terminal ? "Go to Terminal Tab" : "Open in Claude") { watcher.open(session) }
            if session.source == .terminal {
                Button("Open a Copy in the Claude App") { watcher.openInClaudeApp(session) }
            }
        }
    }

    private var helpText: String {
        var lines = [session.title, session.cwd]
        if let reason = session.waitingFor { lines.append("Waiting: \(reason)") }
        return lines.joined(separator: "\n")
    }
}

/// Fixed bottom row: 5-hour and weekly plan usage, in Claude orange.
struct ClaudeUsageBar: View {
    let usage: ClaudeUsage
    /// Side panel: meters on top of each other instead of side by side.
    var stacked = false

    private var isStale: Bool { Date().timeIntervalSince(usage.updatedAt) > 3600 }

    private static let barWidth: CGFloat = 110

    var body: some View {
        // Re-render every 30s so the countdowns and timelines move.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    if let five = usage.fiveHour { meter("5-hour", five, now: context.date) }
                    if let week = usage.weekly { meter("Weekly", week, now: context.date) }
                    if isStale {
                        Text("as of \(Self.timeText(usage.updatedAt))")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 22) {
                    if let five = usage.fiveHour { meter("5-hour", five, now: context.date) }
                    if let week = usage.weekly { meter("Weekly", week, now: context.date) }
                    Spacer(minLength: 0)
                    if isStale {
                        Text("as of \(Self.timeText(usage.updatedAt))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.system(size: 10.5))
        .opacity(isStale ? 0.55 : 1)
        .help(helpText)
    }

    /// Label, orange usage bar and percentage, with the reset countdown underneath the bar.
    private func meter(_ label: String, _ window: ClaudeUsage.Window, now: Date) -> some View {
        // A window whose reset time has passed has started over.
        let didReset = window.resetsAt.map { $0 < now } ?? false
        let percent = didReset ? 0 : min(max(window.usedPercent, 0), 100)
        let width = Self.barWidth
        return HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 6) {
                ClaudeLogo.markIcon(size: 9)
                Text(label).foregroundStyle(.secondary)
            }
            .frame(height: 13)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(ClaudeLogo.orange)
                            .frame(width: max(percent > 0 ? 4 : 0, width * percent / 100))
                    }
                    .frame(width: width, height: 5)
                    Text("\(Int(percent.rounded()))%")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .frame(height: 13)
                if let resets = window.resetsAt, !didReset {
                    Text("Resets in \(Self.countdown(to: resets, now: now)) · \(Self.resetText(resets))")
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else if didReset {
                    Text("Reset")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var helpText: String {
        let source = usage.source == .statusLine
            ? "From the Claude Code status line (updates while a session runs)"
            : "From the Claude app's usage history (sampled occasionally)"
        return "\(source)\nUpdated \(Self.timeText(usage.updatedAt))"
    }

    private static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: date)
    }

    /// "2h 14m", "3d 4h", "12m".
    private static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(max(mins, 1))m"
    }

    private static func resetText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = date.timeIntervalSinceNow < 20 * 3600 ? "h:mm a" : "EEE h:mm a"
        return f.string(from: date)
    }
}

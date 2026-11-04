import AppKit
import SwiftUI

/// Heatmap shades: nothing, then four steps of Claude orange relative to the busiest cell shown.
private func shade(_ count: Int, max: Int) -> Color {
    guard count > 0, max > 0 else { return Color.primary.opacity(0.08) }
    let level = min(4, Int((Double(count) / Double(max) * 4).rounded(.up)))
    return ClaudeLogo.orange.opacity([0.3, 0.5, 0.75, 1][level - 1])
}

private let shortDate: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("EEE d MMM")
    return f
}()

private func replies(_ n: Int) -> String { n == 1 ? "1 reply" : "\(n.formatted()) replies" }

/// Footer: the last 30 days as small bars next to the usage meters. Click to open the Activity view.
struct ClaudeActivityStrip: View {
    let activity: ClaudeActivity
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let days = activity.dailyTotals(lastDays: 30)
        let peak = days.map(\.replies).max() ?? 0
        Button(action: open) {
            VStack(alignment: .trailing, spacing: 3) {
                Text("Last 30 days · \(replies(days.reduce(0) { $0 + $1.replies }))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(hovering ? .primary : .secondary)
                HStack(spacing: 2) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(shade(day.replies, max: peak))
                            .frame(width: 6, height: 18)
                            .help("\(shortDate.string(from: day.date)): \(replies(day.replies))")
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A pointing hand and a brighter label say it's clickable (no box around it).
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // Clicking it opens Activity, which removes the strip while the mouse is still on it.
        .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
        .help("Claude Code replies per day. Click for the full activity view.")
    }
}

enum ClaudeActivityMap: String, CaseIterable, Identifiable {
    case calendar, hours
    var id: Self { self }
    var label: String { self == .calendar ? "Calendar" : "Hours" }
}

/// The Activity view: one map (a calendar of the last weeks, or replies by weekday and hour),
/// with Calendar | Hours tabs above the map and the totals beside it, spanning the map's height.
struct ClaudeActivityView: View {
    let activity: ClaudeActivity
    @Binding var map: ClaudeActivityMap
    var stacked = false

    /// The side panel is narrow, so it shows fewer weeks.
    private var weeks: Int { stacked ? 16 : 26 }
    /// Both maps use the same square cells (the hours grid has to fit 24 columns in the side panel).
    private var cellSize: CGFloat { stacked ? 8 : 10 }
    private var cellGap: CGFloat { stacked ? 2 : 3 }
    /// Month names (or, for Hours, the hour labels underneath) plus seven rows of squares. Both maps
    /// are this tall, so the totals beside them line up with the top and bottom of either one.
    private var mapHeight: CGFloat { 11 + 3 + 7 * cellSize + 6 * cellGap }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Columns are weeks starting on Monday; the last column is this week.
        let weekdayIndex = (calendar.component(.weekday, from: today) + 5) % 7
        let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7 - weekdayIndex, to: today) ?? today
        let days = (0..<(weeks * 7)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let counts = days.map { $0 <= today ? activity.total(on: $0) : 0 }

        Group {
            if counts.allSatisfy({ $0 == 0 }) {
                empty
            } else if stacked {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            tabs
                            mapView(days: days, counts: counts, today: today, start: start)
                        }
                        stats(days: days, counts: counts, today: today)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        tabs
                        mapView(days: days, counts: counts, today: today, start: start)
                    }
                    Spacer(minLength: 0)
                    stats(days: days, counts: counts, today: today)
                        .padding(.top, Self.tabsHeight + 6) // level with the top of the map
                }
                .frame(height: IslandMetrics.cardHeight, alignment: .top)
            }
        }
    }

    static let tabsHeight: CGFloat = 18
    @Namespace private var underline

    /// Light underline tabs over the map (the heavier Sessions | Activity switch is at the top right).
    private var tabs: some View {
        HStack(spacing: 16) {
            ForEach(ClaudeActivityMap.allCases) { option in
                let selected = option == map
                Text(option.label)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(height: Self.tabsHeight - 2)
                    .overlay(alignment: .bottom) {
                        if selected {
                            Capsule()
                                .fill(ClaudeLogo.orange)
                                .frame(height: 2)
                                .offset(y: 2)
                                .matchedGeometryEffect(id: "underline", in: underline)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !selected else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { map = option }
                    }
            }
        }
        .frame(height: Self.tabsHeight, alignment: .top)
        .padding(.leading, 26) // over the first column of squares, past the day names
    }

    @ViewBuilder
    private func mapView(days: [Date], counts: [Int], today: Date, start: Date) -> some View {
        // Cross-fades when the map changes (the switch animates the change).
        Group {
            switch map {
            case .calendar: calendarGrid(days: days, counts: counts, today: today)
            case .hours: rhythmGrid(since: start)
            }
        }
        .frame(height: mapHeight, alignment: .top)
        .id(map)
        .transition(.opacity)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            ClaudeMarkView(status: .idle, size: 22)
            Text("No Claude Code activity yet. Replies from your Claude Code sessions show up here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandMetrics.cardHeight)
    }

    // MARK: - Calendar (A)

    private func calendarGrid(days: [Date], counts: [Int], today: Date) -> some View {
        let peak = counts.max() ?? 0
        let cell = cellSize, gap = cellGap
        let monthFormatter = DateFormatter()
        monthFormatter.setLocalizedDateFormatFromTemplate("MMM")
        return VStack(alignment: .leading, spacing: 3) {
            // Month names over the week where each month starts.
            HStack(spacing: gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    let monday = days[week * 7]
                    let newMonth = week == 0 || Calendar.current.component(.month, from: monday)
                        != Calendar.current.component(.month, from: days[(week - 1) * 7])
                    Text(newMonth ? monthFormatter.string(from: monday) : "")
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            .frame(height: 11)
            .padding(.leading, 26)
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(["Mon", "", "Wed", "", "Fri", "", ""][row]).frame(height: cell)
                    }
                }
                .frame(width: 22, alignment: .leading)
                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { row in
                                let index = week * 7 + row
                                let future = days[index] > today
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(future ? Color.clear : shade(counts[index], max: peak))
                                    .overlay(RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(days[index] == today ? ClaudeLogo.orange : .clear, lineWidth: 1))
                                    .frame(width: cell, height: cell)
                                    .help(future ? "" : "\(shortDate.string(from: days[index])): \(replies(counts[index]))")
                            }
                        }
                    }
                }
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }

    // MARK: - Rhythm (C)

    private func rhythmGrid(since start: Date) -> some View {
        let grid = activity.rhythm(since: start)
        let peak = grid.flatMap { $0 }.max() ?? 0
        let width = cellSize, height = cellSize, gap = cellGap
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { Text(names[$0]).frame(height: height) }
                }
                .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { day in
                        HStack(spacing: gap) {
                            ForEach(0..<24, id: \.self) { hour in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(shade(grid[day][hour], max: peak))
                                    .frame(width: width, height: height)
                                    .help("\(names[day]) \(Self.hourText(hour)): \(replies(grid[day][hour]))")
                            }
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach([0, 6, 12, 18], id: \.self) { hour in
                            Text(Self.hourText(hour)).frame(width: (width + gap) * 6, alignment: .leading)
                        }
                    }
                    .frame(height: 11)
                }
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.secondary)
    }

    private static func hourText(_ hour: Int) -> String {
        let suffix = hour < 12 ? "am" : "pm"
        let h = hour % 12 == 0 ? 12 : hour % 12
        return "\(h) \(suffix)"
    }

    // MARK: - Totals

    private func stats(days: [Date], counts: [Int], today: Date) -> some View {
        let total = counts.reduce(0, +)
        let active = counts.filter { $0 > 0 }.count
        let busiest = zip(days, counts).max { $0.1 < $1.1 }
        // Days in a row with replies, ending today (or yesterday, if today hasn't started yet).
        var streak = 0
        var day = activity.total(on: today) > 0 ? today : Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        while activity.total(on: day) > 0 {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        let busiestText = busiest.map { $0.1 > 0 ? "\(shortDate.string(from: $0.0)) · \($0.1.formatted())" : "–" } ?? "–"
        let streakText = streak == 1 ? "1 day" : "\(streak) days"
        if stacked {
            return AnyView(Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
                GridRow { stat("Replies, \(weeks) weeks", total.formatted()); stat("Active days", "\(active)") }
                GridRow { stat("Busiest day", busiestText); stat("Streak", streakText) }
            })
        }
        // Beside the map: the first row level with its top, the second with its bottom.
        return AnyView(HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                stat("Replies, \(weeks) weeks", total.formatted())
                Spacer(minLength: 0)
                stat("Busiest day", busiestText)
            }
            VStack(alignment: .leading, spacing: 0) {
                stat("Active days", "\(active)")
                Spacer(minLength: 0)
                stat("Streak", streakText)
            }
        }
        .frame(height: mapHeight))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }
}

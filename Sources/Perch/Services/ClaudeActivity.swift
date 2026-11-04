import Foundation

/// Claude Code replies per hour of each local day ("yyyy-MM-dd" → 24 counts), for the activity heatmap.
struct ClaudeActivity: Equatable {
    var days: [String: [Int]] = [:]

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { dayFormatter.string(from: date) }

    func total(on date: Date) -> Int { days[Self.key(date)]?.reduce(0, +) ?? 0 }

    /// The last `count` days, oldest first, ending today.
    func dailyTotals(lastDays count: Int, now: Date = Date()) -> [(date: Date, replies: Int)] {
        let today = Calendar.current.startOfDay(for: now)
        return (0..<count).reversed().compactMap { back in
            Calendar.current.date(byAdding: .day, value: -back, to: today).map { ($0, total(on: $0)) }
        }
    }

    /// Replies by weekday (0 = Monday) and hour, for days on or after `start`.
    func rhythm(since start: Date) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let first = Self.key(start)
        for (key, hours) in days where key >= first {
            guard let date = Self.dayFormatter.date(from: key) else { continue }
            let weekday = (Calendar.current.component(.weekday, from: date) + 5) % 7
            for (hour, n) in hours.prefix(24).enumerated() { grid[weekday][hour] += n }
        }
        return grid
    }
}

/// Counts Claude's replies in Claude Code's session logs (`~/.claude/projects/**/*.jsonl`, sub-agents
/// included). Files are read incrementally, so each pass only reads what was added since the last one.
/// Claude Code deletes old logs (after 30 days by default), so the daily totals are also saved in
/// Perch's own folder and kept after the logs are gone. Only used on the usage watcher's queue.
final class ClaudeActivityScanner {
    private struct FileState {
        var offset: UInt64 = 0
        var seenMessages = Set<String>()
        var counts: [String: [Int]] = [:]
    }

    private let projects: URL
    private let historyURL: URL
    private var files: [String: FileState] = [:]
    private var saved: [String: [Int]]

    private static let marker = Data("\"type\":\"assistant\"".utf8)
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(projects: URL, historyURL: URL) {
        self.projects = projects
        self.historyURL = historyURL
        saved = (try? Data(contentsOf: historyURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            .flatMap { $0["days"] as? [String: [Int]] } ?? [:]
    }

    func scan() -> ClaudeActivity {
        let fm = FileManager.default
        var present = Set<String>()
        if let walker = fm.enumerator(at: projects, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                present.insert(url.path)
                read(url)
            }
        }
        files = files.filter { present.contains($0.key) }

        // What the logs still hold, per day.
        var computed: [String: [Int]] = [:]
        for state in files.values {
            for (day, hours) in state.counts {
                var total = computed[day] ?? Array(repeating: 0, count: 24)
                for (hour, n) in hours.enumerated() { total[hour] += n }
                computed[day] = total
            }
        }
        // Logs only ever lose old days, so for each day the larger total is the right one.
        var merged = saved
        for (day, hours) in computed where hours.reduce(0, +) >= (saved[day]?.reduce(0, +) ?? 0) {
            merged[day] = hours
        }
        if merged != saved {
            saved = merged
            save()
        }
        return ClaudeActivity(days: merged)
    }

    private func read(_ url: URL) {
        var state = files[url.path] ?? FileState()
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        if size < state.offset { state = FileState() } // rewritten or truncated: start over
        guard size > state.offset, let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: state.offset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return }

        // Whole lines only; a half-written last line is read on the next pass.
        let complete = data[data.startIndex...lastNewline]
        var start = complete.startIndex
        while start < complete.endIndex {
            let end = complete[start...].firstIndex(of: 0x0A) ?? complete.endIndex
            let line = complete[start..<end]
            if line.range(of: Self.marker) != nil { count(line, into: &state) }
            start = complete.index(after: end)
        }
        state.offset += UInt64(complete.count)
        files[url.path] = state
    }

    /// One reply = one assistant message (Claude Code can log a message over several lines).
    private func count(_ line: Data, into state: inout FileState) {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let stamp = json["timestamp"] as? String,
              let date = Self.timestampFormatter.date(from: stamp) else { return }
        let message = json["message"] as? [String: Any]
        if message?["model"] as? String == "<synthetic>" { return } // error notices, not replies
        let id = message?["id"] as? String ?? json["uuid"] as? String ?? stamp
        guard state.seenMessages.insert(id).inserted else { return }
        let day = ClaudeActivity.key(date)
        let hour = Calendar.current.component(.hour, from: date)
        var hours = state.counts[day] ?? Array(repeating: 0, count: 24)
        hours[hour] += 1
        state.counts[day] = hours
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "days": saved], options: [.sortedKeys])
        else { return }
        try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: historyURL, options: .atomic)
    }
}

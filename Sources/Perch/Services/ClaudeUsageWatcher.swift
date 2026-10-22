import Foundation

/// Claude plan usage: the 5-hour and weekly limits, as a percentage used.
struct ClaudeUsage: Equatable {
    struct Window: Equatable {
        var usedPercent: Double
        var resetsAt: Date?
    }

    enum Source { case statusLine, claudeApp }

    var fiveHour: Window?
    var weekly: Window?
    var updatedAt: Date
    var source: Source

    /// 5-hour usage right now: 0 once its reset time has passed.
    var currentFiveHourPercent: Double? {
        guard let five = fiveHour else { return nil }
        if let resets = five.resetsAt, resets < Date() { return 0 }
        return five.usedPercent
    }
}

/// Reads usage saved by the Claude Code status line script (`~/.claude/perch/usage.json`,
/// live while a session runs), falling back to the Claude app's own usage history, which it
/// only samples now and then. Both formats are someone else's, so bad data is skipped quietly.
final class ClaudeUsageWatcher: ObservableObject {
    @Published private(set) var usage: ClaudeUsage?

    private let settings: AppSettings
    private let queue = DispatchQueue(label: "Perch.ClaudeUsage", qos: .utility)
    private var timer: Timer?

    private let statusLineFile: URL
    private let appHistoryFile: URL

    init(settings: AppSettings) {
        self.settings = settings
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        statusLineFile = configDir.appendingPathComponent("perch/usage.json")
        appHistoryFile = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// Sample usage for the README screenshots (the watcher isn't started then).
    func showSample(_ usage: ClaudeUsage) { self.usage = usage }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        guard settings.showClaude && settings.showClaudeUsage else {
            if usage != nil { usage = nil }
            return
        }
        let statusLineFile = statusLineFile, appHistoryFile = appHistoryFile
        queue.async { [weak self] in
            let candidates = [Self.readStatusLine(statusLineFile), Self.readAppHistory(appHistoryFile)].compactMap { $0 }
            let newest = candidates.max { $0.updatedAt < $1.updatedAt }
            DispatchQueue.main.async {
                guard let self, newest != self.usage else { return }
                self.usage = newest
            }
        }
    }

    private static func readStatusLine(_ url: URL) -> ClaudeUsage? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = json["updatedAt"] as? NSNumber else { return nil }

        func window(_ key: String) -> ClaudeUsage.Window? {
            guard let w = json[key] as? [String: Any],
                  let used = w["used_percentage"] as? NSNumber else { return nil }
            let resets = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return ClaudeUsage.Window(usedPercent: used.doubleValue, resetsAt: resets)
        }

        let usage = ClaudeUsage(fiveHour: window("five_hour"), weekly: window("seven_day"),
                                updatedAt: Date(timeIntervalSince1970: updated.doubleValue / 1000),
                                source: .statusLine)
        return usage.fiveHour == nil && usage.weekly == nil ? nil : usage
    }

    /// `{"samples": [{"t": ms, "u": {"fh": 5-hour %, "sd": 7-day %}}]}` (no reset times).
    private static func readAppHistory(_ url: URL) -> ClaudeUsage? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = json["samples"] as? [[String: Any]],
              let last = samples.max(by: { ($0["t"] as? NSNumber)?.doubleValue ?? 0 < ($1["t"] as? NSNumber)?.doubleValue ?? 0 }),
              let t = last["t"] as? NSNumber,
              let u = last["u"] as? [String: Any] else { return nil }
        let five = (u["fh"] as? NSNumber).map { ClaudeUsage.Window(usedPercent: $0.doubleValue, resetsAt: nil) }
        let week = (u["sd"] as? NSNumber).map { ClaudeUsage.Window(usedPercent: $0.doubleValue, resetsAt: nil) }
        guard five != nil || week != nil else { return nil }
        return ClaudeUsage(fiveHour: five, weekly: week,
                           updatedAt: Date(timeIntervalSince1970: t.doubleValue / 1000), source: .claudeApp)
    }
}

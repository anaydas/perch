import AppKit
import Combine
import Darwin

/// A running Claude Code session, from `~/.claude/sessions/<pid>.json`.
struct ClaudeSession: Identifiable, Equatable {
    enum Status: Int, Comparable {
        case waiting, working, idle
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    enum Source { case app, terminal }

    let id: String
    let pid: pid_t
    let title: String
    let cwd: String
    let status: Status
    /// Why it's waiting, e.g. "input needed" or "dialog open".
    let waitingFor: String?
    let source: Source
    /// `local_…` id of the Claude desktop session, used for the claude:// deep link.
    let hostSessionId: String?
    let statusUpdatedAt: Date
}

/// Watches the per-process status files Claude Code writes for each running session.
/// The format is undocumented, so anything unexpected is skipped quietly.
final class ClaudeSessionWatcher: ObservableObject {
    @Published private(set) var sessions: [ClaudeSession] = []

    /// Fires when a session starts waiting for you or finishes a turn.
    let needsAttention = PassthroughSubject<ClaudeSession, Never>()

    private let settings: AppSettings
    private let directory: URL
    private let queue = DispatchQueue(label: "Perch.ClaudeSessions", qos: .utility)
    private var timer: Timer?

    init(settings: AppSettings) {
        self.settings = settings
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        directory = configDir.appendingPathComponent("sessions", isDirectory: true)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    // MARK: - Opening a session

    func open(_ session: ClaudeSession) {
        switch session.source {
        case .app:
            guard let host = session.hostSessionId,
                  let url = URL(string: "claude://code/continue?session=\(host)") else { return }
            NSWorkspace.shared.open(url)
        case .terminal:
            TerminalFocuser.focus(pid: session.pid)
        }
    }

    /// Imports a terminal session into the Claude app (it becomes a separate copy there).
    func openInClaudeApp(_ session: ClaudeSession) {
        guard let url = URL(string: "claude://claude.ai/resume?session=\(session.id)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private func poll() {
        guard settings.showClaude && settings.showClaudeSessions else {
            if !sessions.isEmpty { sessions = [] }
            return
        }
        let directory = directory
        queue.async { [weak self] in
            let found = Self.readSessions(in: directory)
            DispatchQueue.main.async { self?.apply(found) }
        }
    }

    private func apply(_ found: [ClaudeSession]) {
        guard found != sessions else { return }
        let previous = Dictionary(sessions.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        sessions = found
        for session in found {
            guard let before = previous[session.id], before != session.status else { continue }
            if session.status == .waiting || (before == .working && session.status == .idle) {
                needsAttention.send(session)
            }
        }
    }

    private static func readSessions(in directory: URL) -> [ClaudeSession] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let sessions = files
            .filter { $0.pathExtension == "json" }
            .compactMap(parse)
        return sessions.sorted {
            $0.status != $1.status ? $0.status < $1.status : $0.statusUpdatedAt > $1.statusUpdatedAt
        }
    }

    private static func parse(_ url: URL) -> ClaudeSession? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pidNumber = json["pid"] as? NSNumber,
              let sessionId = json["sessionId"] as? String else { return nil }
        let pid = pid_t(truncating: pidNumber)
        guard isAlive(pid), json["spare"] as? Bool != true else { return nil }
        if let kind = json["kind"] as? String, kind != "interactive" { return nil }

        let entrypoint = json["entrypoint"] as? String ?? ""
        let hostSessionId = json["hostSessionId"] as? String
        let source: ClaudeSession.Source
        if entrypoint == "claude-desktop", hostSessionId?.hasPrefix("local_") == true {
            source = .app
        } else if entrypoint.hasPrefix("cli") {
            source = .terminal
        } else {
            return nil // SDK scripts and other hosts we can't jump to
        }

        let status: ClaudeSession.Status
        switch json["status"] as? String {
        case "busy": status = .working
        case "waiting": status = .waiting
        default: status = .idle
        }

        let cwd = json["cwd"] as? String ?? ""
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (name?.isEmpty == false ? name : nil) ?? (cwd as NSString).lastPathComponent
        let updated = (json["statusUpdatedAt"] as? NSNumber ?? json["updatedAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } ?? .distantPast

        return ClaudeSession(id: sessionId, pid: pid, title: title, cwd: cwd, status: status,
                             waitingFor: json["waitingFor"] as? String, source: source,
                             hostSessionId: hostSessionId, statusUpdatedAt: updated)
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}

/// Brings the terminal that runs a process to the front, and selects its exact tab
/// in Terminal and iTerm2 (via AppleScript, which macOS asks permission for once).
enum TerminalFocuser {
    private static let scriptQueue = DispatchQueue(label: "Perch.TerminalFocuser")

    static func focus(pid: pid_t) {
        let tty = ttyName(of: pid)
        guard let app = hostApp(of: pid) else {
            NSSound.beep() // e.g. inside tmux/screen, whose server isn't a child of the terminal
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])

        guard let tty, let script = selectTabScript(bundleID: app.bundleIdentifier, tty: "/dev/" + tty) else { return }
        // Off the main thread: the first run waits on the Automation permission prompt.
        scriptQueue.async {
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error { NSLog("Perch: could not select terminal tab: \(error)") }
        }
    }

    /// Walks up the process tree to the first regular (Dock) app, which is the terminal.
    private static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<32 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let info = processInfo(current) else { return nil }
            let parent = info.kp_eproc.e_ppid
            if parent <= 1 || parent == current { return nil }
            current = parent
        }
        return nil
    }

    private static func ttyName(of pid: pid_t) -> String? {
        guard let info = processInfo(pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        return String(cString: name)
    }

    private static func processInfo(_ pid: pid_t) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }

    private static func selectTabScript(bundleID: String?, tty: String) -> String? {
        switch bundleID {
        case "com.apple.Terminal":
            return """
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        case "com.googlecode.iterm2":
            return """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }
}

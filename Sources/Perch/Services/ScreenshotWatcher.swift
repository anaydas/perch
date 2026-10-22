import AppKit
import Darwin

/// Watches the folder macOS saves screenshots (and ⌘⇧5 screen recordings) to and pins new ones.
///
/// It watches the folder directly rather than asking Spotlight: Spotlight silently leaves
/// out files in protected folders (Desktop, Documents) unless the app already has access,
/// and a query never triggers the permission prompt. Listing the folder does, once.
final class ScreenshotWatcher {
    private let store: ShelfStore
    private let settings: AppSettings
    private let queue = DispatchQueue(label: "Perch.ScreenshotWatcher", qos: .utility)
    private let launchDate = Date()

    // Only touched on `queue`.
    private var folder: URL?
    private var source: DispatchSourceFileSystemObject?
    private var seenPaths = Set<String>()
    private var scanPending = false
    private var locationTimer: DispatchSourceTimer?

    init(store: ShelfStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        queue.async { self.watchCurrentLocation() }
        // Pick up a changed screenshot location (Screenshot app → Options → Save to).
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10)
        timer.setEventHandler { [weak self] in self?.watchCurrentLocation() }
        timer.resume()
        locationTimer = timer
    }

    // MARK: - Watching (on `queue`)

    /// Where screenshots are saved: `defaults read com.apple.screencapture location`, else Desktop.
    private static func screenshotFolder() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        defaults?.synchronize()
        if let location = defaults?.string(forKey: "location"), !location.isEmpty {
            let path = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func watchCurrentLocation() {
        let target = Self.screenshotFolder()
        guard target.standardizedFileURL != folder?.standardizedFileURL || source == nil else { return }
        source?.cancel()
        source = nil
        folder = target

        // Opening the folder is what raises the Desktop/Documents permission prompt (off the main thread).
        let fd = open(target.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Perch: can't watch screenshot folder \(target.path) (errno \(errno)); will retry.")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: queue)
        source.setEventHandler { [weak self] in self?.scheduleScan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        scan() // remember what's already there
    }

    /// Screenshots appear as a hidden temp file first, then get renamed; wait for things to settle.
    private func scheduleScan() {
        guard !scanPending else { return }
        scanPending = true
        queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.scanPending = false
            self?.scan()
        }
    }

    private func scan() {
        guard let folder else { return }
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }

        var found: [URL] = []
        for url in files where !seenPaths.contains(url.path) {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { continue }
            seenPaths.insert(url.path)
            guard let created = values.creationDate, created > launchDate,
                  Self.isScreenshot(url) else { continue }
            found.append(url)
        }
        guard !found.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for url in found {
                if ShelfStore.isVideoFile(url) {
                    // Recordings can be huge: reference them in place, like other files.
                    if self.settings.autoCatchRecordings { self.store.addFile(url) }
                } else if self.settings.autoCatchScreenshots {
                    self.store.addImage(from: url)
                }
            }
        }
    }

    /// macOS tags screenshots with this extended attribute, whatever their name or language.
    private static func isScreenshot(_ url: URL) -> Bool {
        let size = getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0)
        if size > 0 { return true }
        // Fallback for copies that lost the attribute: a name that starts like a screenshot or recording.
        let name = url.lastPathComponent.lowercased()
        if ShelfStore.isImageFile(url) { return name.hasPrefix("screenshot") || name.hasPrefix("screen shot") }
        if ShelfStore.isVideoFile(url) { return name.hasPrefix("screen recording") }
        return false
    }
}

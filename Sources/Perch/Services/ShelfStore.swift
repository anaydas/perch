import AVFoundation
import AppKit
import Combine
import CryptoKit
import QuickLookThumbnailing
import ImageIO
import UniformTypeIdentifiers

/// Owns the shelf items, their files on disk, and clipboard / drag-and-drop I/O.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    /// Fires whenever a new item lands on the shelf (used for the pulse + haptic).
    let itemAdded = PassthroughSubject<ShelfItem, Never>()

    /// Pasteboard changeCount right after our own copy, so clipboard history ignores it.
    private(set) var lastOwnChangeCount = -1

    /// Display order: fixed cards first (in the order they were fixed), then newest first.
    var ordered: [ShelfItem] {
        let fixed = items.filter(\.isFixed).sorted { $0.fixedAt! < $1.fixedAt! }
        let rest = items.filter { !$0.isFixed }.sorted { $0.createdAt > $1.createdAt }
        return fixed + rest
    }
    var pinned: [ShelfItem] { ordered.filter { !$0.isRecent } }
    var recent: [ShelfItem] { ordered.filter { $0.isRecent } }

    private let settings: AppSettings
    private let directory: URL
    private let filesDirectory: URL
    private let maxRecent = 30
    private var saveWork: DispatchWorkItem?
    private var expiryTimer: Timer?
    private let thumbnails = NSCache<NSString, NSImage>()
    /// Image encoding, hashing and file writes, kept off the main thread so drags stay smooth.
    private let ioQueue = DispatchQueue(label: "Perch.ShelfStore.io", qos: .userInitiated)

    /// A card is being dragged out of the shelf. While it is, the shelf doesn't show its
    /// drop area (that would replace the card being dragged mid-drag).
    @Published var isDraggingOut = false

    /// Size and icon of referenced files, read off the main thread.
    struct FileInfo {
        var size: Int64?
        var icon: NSImage?
        /// Finder-style preview of the content (video frame, PDF page…), when there is one.
        var thumbnail: NSImage?
        /// Length of a video, in seconds.
        var duration: Double?
    }
    @Published private(set) var fileInfo: [UUID: FileInfo] = [:]
    private var fileInfoRequested = Set<UUID>()

    /// `directory` is only passed when rendering the README screenshots (sample data in a temp folder).
    init(settings: AppSettings, directory customDirectory: URL? = nil) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = customDirectory ?? support.appendingPathComponent("Perch", isDirectory: true)
        // The app used to be called Notch Shelf: bring its items along on first launch.
        let oldDirectory = support.appendingPathComponent("NotchShelf", isDirectory: true)
        if customDirectory == nil,
           !FileManager.default.fileExists(atPath: directory.path),
           FileManager.default.fileExists(atPath: oldDirectory.path) {
            try? FileManager.default.moveItem(at: oldDirectory, to: directory)
        }
        filesDirectory = directory.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        load()
        backfillImageHashes()
        purgeExpired()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.purgeExpired()
        }
    }

    // MARK: - Adding

    /// `moveToFront`: an item that's already on the shelf moves to the front (copying it again).
    /// Drops pass `false`, so dragging a card out and back in changes nothing.
    func addText(_ text: String, recent: Bool = false, moveToFront: Bool = true) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Same text already here: never add it twice.
        if let index = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            if !recent { items[index].isRecent = false }
            if moveToFront { items[index].createdAt = Date() }
            scheduleSave()
            return
        }

        var item = ShelfItem(kind: .text, title: Self.title(forText: trimmed))
        item.text = text
        item.isRecent = recent
        item.isSensitive = SensitiveDetector.looksSensitive(text)
        insert(item)
    }

    func addImage(_ image: NSImage, title: String, recent: Bool = false, moveToFront: Bool = true) {
        // PNG encoding a large image is slow: do it off the main thread.
        ioQueue.async { [weak self] in
            guard let data = image.pngData() else { return }
            self?.storeImage(data: data, ext: "png", title: title, recent: recent, moveToFront: moveToFront)
        }
    }

    func addImage(from url: URL, recent: Bool = false, moveToFront: Bool = true) {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        // Read off the main thread: a privacy prompt for Desktop/Downloads would otherwise freeze the UI.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                self?.storeImage(data: data, ext: ext, title: title, recent: recent, moveToFront: moveToFront)
            }
        }
    }

    func addFile(_ url: URL, recent: Bool = false, moveToFront: Bool = true) {
        // Same file again: never add it twice.
        if let index = items.firstIndex(where: { $0.kind == .file && $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            if moveToFront { items[index].createdAt = Date() }
            if !recent { items[index].isRecent = false }
            scheduleSave()
            return
        }
        var item = ShelfItem(kind: .file, title: url.lastPathComponent)
        item.fileURL = url
        item.isRecent = recent
        insert(item)
    }

    /// Images are copied into the shelf; any other file is referenced in place.
    func add(url: URL, recent: Bool = false, moveToFront: Bool = true) {
        // One of the shelf's own stored images (a card dragged out and dropped back): already here.
        if isStoredFile(url) {
            if moveToFront, let index = items.firstIndex(where: { imageURL(for: $0)?.standardizedFileURL == url.standardizedFileURL }) {
                items[index].createdAt = Date()
                scheduleSave()
            }
            return
        }
        if Self.isImageFile(url) {
            addImage(from: url, recent: recent, moveToFront: moveToFront)
        } else {
            addFile(url, recent: recent, moveToFront: moveToFront)
        }
    }

    private func isStoredFile(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let stored = filesDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(stored + "/")
    }

    /// ⌥⌘V: pin whatever is currently on the clipboard.
    func pinCurrentClipboard() {
        add(from: NSPasteboard.general)
    }

    /// Adds what's on a pasteboard: files, else an image, else text. Used by ⌥⌘V and the
    /// "Add to Perch" service. Returns false if there was nothing it could use.
    @discardableResult
    func add(from pb: NSPasteboard) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            urls.forEach { add(url: $0) }
        } else if Self.hasImage(pb), let image = NSImage(pasteboard: pb) {
            addImage(image, title: "Clipboard image")
        } else if let string = pb.string(forType: .string),
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addText(string)
        } else {
            return false
        }
        return true
    }

    /// Handles anything dropped onto the island.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] data, _ in
                    var url: URL?
                    if let data = data as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let direct = data as? URL {
                        url = direct
                    }
                    guard let url else { return }
                    DispatchQueue.main.async { self?.add(url: url, moveToFront: false) }
                }
            } else if let type = provider.registeredTypeIdentifiers.compactMap(UTType.init).first(where: { $0.conforms(to: .image) }) {
                // Keep the image's own bytes (PNG, JPEG, HEIC…) instead of decoding and re-encoding it.
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, _ in
                    guard let data else { return }
                    self?.storeImage(data: data, ext: type.preferredFilenameExtension ?? "png",
                                     title: "Dropped image", recent: false, moveToFront: false)
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let image = object as? NSImage else { return }
                    self?.addImage(image, title: "Dropped image", moveToFront: false)
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let string = object as? NSString else { return }
                    DispatchQueue.main.async { self?.addText(string as String, moveToFront: false) }
                }
            }
        }
        return handled
    }

    // MARK: - Using items

    func copy(_ item: ShelfItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let url = imageURL(for: item), let image = NSImage(contentsOf: url) {
                pb.writeObjects([image, url as NSURL])
            }
        case .file:
            if let url = item.fileURL { pb.writeObjects([url as NSURL]) }
        }
        lastOwnChangeCount = pb.changeCount
    }

    /// Copies several items at once: files and images as file URLs, text joined by blank lines.
    func copy(items: [ShelfItem]) {
        guard items.count > 1 else { items.first.map(copy); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        let urls: [NSURL] = items.compactMap { item in
            switch item.kind {
            case .image: return imageURL(for: item) as NSURL?
            case .file: return item.fileURL as NSURL?
            case .text: return nil
            }
        }
        let text = items.filter { $0.kind == .text }.compactMap(\.text).joined(separator: "\n\n")
        var objects: [NSPasteboardWriting] = urls
        if !text.isEmpty { objects.append(text as NSString) }
        pb.writeObjects(objects)
        lastOwnChangeCount = pb.changeCount
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .text: copy(item)
        case .image: if let url = imageURL(for: item) { NSWorkspace.shared.open(url) }
        case .file: if let url = item.fileURL { NSWorkspace.shared.open(url) }
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        let url = item.kind == .image ? imageURL(for: item) : item.fileURL
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    func imageURL(for item: ShelfItem) -> URL? {
        item.storedPath.map { filesDirectory.appendingPathComponent($0) }
    }

    /// Small, cached thumbnail so the shelf stays fast with big screenshots.
    func thumbnail(for item: ShelfItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        let key = url.path as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 360,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails.setObject(image, forKey: key)
        return image
    }

    /// Touching a file in Desktop/Documents/Downloads can raise a privacy prompt that blocks
    /// the calling thread until it's answered, so never read file details while rendering.
    func info(for item: ShelfItem) -> FileInfo? {
        if let info = fileInfo[item.id] { return info }
        guard let url = item.fileURL, !fileInfoRequested.contains(item.id) else { return nil }
        fileInfoRequested.insert(item.id)
        let id = item.id
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var info = FileInfo()
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                info.size = (attributes[.size] as? NSNumber)?.int64Value
                info.icon = NSWorkspace.shared.icon(forFile: url.path)
            }
            let exists = info.size != nil
            DispatchQueue.main.async {
                self?.fileInfo[id] = info
                if exists { self?.loadPreview(for: id, url: url) }
            }
        }
        return nil
    }

    /// Fills in the content preview (and a video's length) once they're ready.
    private func loadPreview(for id: UUID, url: URL) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 240, height: 160),
                                                   scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            DispatchQueue.main.async { self?.fileInfo[id]?.thumbnail = image }
        }
        if Self.isVideoFile(url) {
            let setDuration: (Double) -> Void = { [weak self] seconds in
                DispatchQueue.main.async { self?.fileInfo[id]?.duration = seconds }
            }
            Task {
                guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return }
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return }
                setDuration(seconds)
            }
        }
    }

    // MARK: - Managing

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        fileInfo[item.id] = nil
        fileInfoRequested.remove(item.id)
        deleteFiles(of: item)
        scheduleSave()
    }

    func toggleStar(_ item: ShelfItem) {
        update(item) { $0.isStarred.toggle() }
    }

    /// Fixes a card at the front of the shelf, or releases it back into date order.
    func toggleFixed(_ item: ShelfItem) {
        update(item) { $0.fixedAt = $0.fixedAt == nil ? Date() : nil }
    }

    /// Moves a clipboard-history item onto the shelf proper.
    func pin(_ item: ShelfItem) {
        update(item) { $0.isRecent = false }
    }

    func clearRecent() {
        let removed = items.filter { $0.isRecent && !$0.isKept }
        items.removeAll { $0.isRecent && !$0.isKept }
        removed.forEach(deleteFiles(of:))
        scheduleSave()
    }

    /// Copies show on the shelf too, so this clears everything that isn't starred or fixed.
    func clearShelf() {
        let removed = items.filter { !$0.isKept }
        items.removeAll { !$0.isKept }
        removed.forEach(deleteFiles(of:))
        scheduleSave()
    }

    func purgeExpired() {
        let hours = settings.expiryHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let expired = items.filter { !$0.isKept && $0.createdAt < cutoff }
        guard !expired.isEmpty else { return }
        let ids = Set(expired.map(\.id))
        items.removeAll { ids.contains($0.id) }
        expired.forEach(deleteFiles(of:))
        scheduleSave()
    }

    // MARK: - Private

    private func insert(_ item: ShelfItem) {
        items.insert(item, at: 0)
        trimRecent()
        scheduleSave()
        itemAdded.send(item)
    }

    private func update(_ item: ShelfItem, _ change: (inout ShelfItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        change(&items[index])
        scheduleSave()
    }

    private func trimRecent() {
        let recents = items.filter { $0.isRecent && !$0.isKept }.sorted { $0.createdAt > $1.createdAt }
        guard recents.count > maxRecent else { return }
        let overflow = recents.suffix(recents.count - maxRecent)
        let ids = Set(overflow.map(\.id))
        items.removeAll { ids.contains($0.id) }
        overflow.forEach(deleteFiles(of:))
    }

    /// Hashing, writing and reading image properties happen on `ioQueue`; only the duplicate
    /// check and the insert touch `items` (main thread). Safe to call from any thread.
    private func storeImage(data: Data, ext: String, title: String, recent: Bool, moveToFront: Bool = true) {
        let filesDirectory = filesDirectory
        ioQueue.async { [weak self] in
            let hash = Self.hash(data)
            DispatchQueue.main.async {
                guard let self else { return }
                // Same image already on the shelf (same bytes): never store it twice.
                if let index = self.items.firstIndex(where: { $0.kind == .image && $0.contentHash == hash }) {
                    if moveToFront { self.items[index].createdAt = Date() }
                    if !recent { self.items[index].isRecent = false }
                    self.scheduleSave()
                    return
                }
                self.ioQueue.async {
                    // Each image gets its own folder so a dragged-out file keeps a readable name.
                    let id = UUID()
                    let relative = id.uuidString + "/" + Self.safeFileName(title) + "." + ext
                    let destination = filesDirectory.appendingPathComponent(relative)
                    do {
                        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: destination)
                    } catch {
                        NSLog("Perch: could not store image: \(error)")
                        return
                    }
                    var item = ShelfItem(id: id, kind: .image, title: title)
                    item.storedPath = relative
                    item.contentHash = hash
                    item.isRecent = recent
                    if let source = CGImageSourceCreateWithData(data as CFData, nil),
                       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                        item.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
                        item.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
                    }
                    DispatchQueue.main.async {
                        // The same image may have landed while this one was being written.
                        if self.items.contains(where: { $0.kind == .image && $0.contentHash == hash }) {
                            try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                            return
                        }
                        self.insert(item)
                    }
                }
            }
        }
    }

    private func deleteFiles(of item: ShelfItem) {
        guard let url = imageURL(for: item) else { return }
        thumbnails.removeObject(forKey: url.path as NSString)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private var indexURL: URL { directory.appendingPathComponent("items.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = decoded
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let snapshot = items
        let url = indexURL
        let work = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private static func title(forText text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }

    private static func safeFileName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let short = String(cleaned.prefix(60))
        return short.isEmpty ? "Image" : short
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Images stored before duplicate checks existed have no hash yet; work them out once.
    private func backfillImageHashes() {
        let missing = items.filter { $0.kind == .image && $0.contentHash == nil }
            .compactMap { item in imageURL(for: item).map { (item.id, $0) } }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let hashes = missing.compactMap { id, url in (try? Data(contentsOf: url)).map { (id, Self.hash($0)) } }
            DispatchQueue.main.async {
                guard let self else { return }
                for (id, hash) in hashes {
                    if let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].contentHash = hash }
                }
                self.scheduleSave()
            }
        }
    }

    static func isVideoFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    static func isImageFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    static func hasImage(_ pb: NSPasteboard) -> Bool {
        let types = pb.types ?? []
        return types.contains(.png) || types.contains(.tiff)
    }
}

extension NSImage {
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

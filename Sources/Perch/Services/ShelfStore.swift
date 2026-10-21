import AppKit
import Combine
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

    /// Size and icon of referenced files, read off the main thread.
    struct FileInfo {
        var size: Int64?
        var icon: NSImage?
    }
    @Published private(set) var fileInfo: [UUID: FileInfo] = [:]
    private var fileInfoRequested = Set<UUID>()

    init(settings: AppSettings) {
        self.settings = settings
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Perch", isDirectory: true)
        // The app used to be called Notch Shelf: bring its items along on first launch.
        let oldDirectory = support.appendingPathComponent("NotchShelf", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path),
           FileManager.default.fileExists(atPath: oldDirectory.path) {
            try? FileManager.default.moveItem(at: oldDirectory, to: directory)
        }
        filesDirectory = directory.appendingPathComponent("files", isDirectory: true)
        try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        load()
        purgeExpired()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.purgeExpired()
        }
    }

    // MARK: - Adding

    func addText(_ text: String, recent: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Same text already here: move it to the front (and promote it if pinned on purpose).
        if let index = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            var existing = items.remove(at: index)
            existing.createdAt = Date()
            if !recent { existing.isRecent = false }
            items.insert(existing, at: 0)
            scheduleSave()
            return
        }

        var item = ShelfItem(kind: .text, title: Self.title(forText: trimmed))
        item.text = text
        item.isRecent = recent
        item.isSensitive = SensitiveDetector.looksSensitive(text)
        insert(item)
    }

    func addImage(_ image: NSImage, title: String, recent: Bool = false) {
        guard let data = image.pngData() else { return }
        storeImage(data: data, ext: "png", title: title, recent: recent)
    }

    func addImage(from url: URL, recent: Bool = false) {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let title = url.deletingPathExtension().lastPathComponent
        // Read off the main thread: a privacy prompt for Desktop/Downloads would otherwise freeze the UI.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            DispatchQueue.main.async {
                self?.storeImage(data: data, ext: ext, title: title, recent: recent)
            }
        }
    }

    func addFile(_ url: URL, recent: Bool = false) {
        // Same file again: bring it to the front.
        if let index = items.firstIndex(where: { $0.kind == .file && $0.fileURL == url }) {
            items[index].createdAt = Date()
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
    func add(url: URL, recent: Bool = false) {
        if Self.isImageFile(url) {
            addImage(from: url, recent: recent)
        } else {
            addFile(url, recent: recent)
        }
    }

    /// ⌥⌘V: pin whatever is currently on the clipboard.
    func pinCurrentClipboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            urls.forEach { add(url: $0) }
        } else if Self.hasImage(pb), let image = NSImage(pasteboard: pb) {
            addImage(image, title: "Clipboard image")
        } else if let string = pb.string(forType: .string) {
            addText(string)
        }
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
                    DispatchQueue.main.async { self?.add(url: url) }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
                    guard let image = object as? NSImage else { return }
                    DispatchQueue.main.async { self?.addImage(image, title: "Dropped image") }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                    guard let string = object as? NSString else { return }
                    DispatchQueue.main.async { self?.addText(string as String) }
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

    /// What gets handed to other apps when a card is dragged out.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        case .image:
            if let url = imageURL(for: item), let provider = NSItemProvider(contentsOf: url) { return provider }
        case .file:
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
        }
        return NSItemProvider()
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
            DispatchQueue.main.async { self?.fileInfo[id] = info }
        }
        return nil
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

    private func storeImage(data: Data, ext: String, title: String, recent: Bool) {
        // Each image gets its own folder so a dragged-out file keeps a readable name.
        let id = UUID()
        let folder = id.uuidString
        let fileName = Self.safeFileName(title) + "." + ext
        let relative = folder + "/" + fileName
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
        item.isRecent = recent
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            item.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
            item.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
        }
        insert(item)
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

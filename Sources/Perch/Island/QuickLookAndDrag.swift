import AppKit
import Quartz

/// Feeds the selected shelf items to the system Quick Look panel (Space on a card).
final class QuickLookSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var urls: [URL] = []

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }

    /// The file Quick Look should show for an item. Text cards are written to a temporary
    /// .txt file, since Quick Look previews files.
    static func previewURL(for item: ShelfItem, store: ShelfStore) -> URL? {
        switch item.kind {
        case .image: return store.imageURL(for: item)
        case .file: return item.fileURL
        case .text:
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Perch Quick Look", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = item.title.replacingOccurrences(of: "/", with: "-").prefix(60)
            let url = folder.appendingPathComponent("\(name.isEmpty ? "Text" : String(name)).txt")
            try? (item.text ?? "").write(to: url, atomically: true, encoding: .utf8)
            return url
        }
    }
}

/// Source for dragging cards out: one card, or several selected ones at once.
final class MultiDragSource: NSObject, NSDraggingSource {
    var onEnd: () -> Void = {}

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnd()
    }

    /// One dragging item per shelf item: files and images as file URLs, text as text.
    static func draggingItems(for items: [ShelfItem], store: ShelfStore, at point: NSPoint) -> [NSDraggingItem] {
        items.enumerated().compactMap { index, item in
            let writer: NSPasteboardWriting?
            switch item.kind {
            case .image: writer = store.imageURL(for: item) as NSURL?
            case .file: writer = item.fileURL as NSURL?
            case .text: writer = (item.text ?? "") as NSString
            }
            guard let writer else { return nil }
            let dragging = NSDraggingItem(pasteboardWriter: writer)
            // A small fanned stack under the cursor; macOS adds the count badge.
            let offset = CGFloat(min(index, 4)) * 5
            let frame = NSRect(x: point.x - 32 + offset, y: point.y - 32 - offset, width: 64, height: 64)
            dragging.setDraggingFrame(frame, contents: dragImage(for: item, store: store))
            return dragging
        }
    }

    private static func dragImage(for item: ShelfItem, store: ShelfStore) -> NSImage {
        switch item.kind {
        case .image:
            if let thumb = store.thumbnail(for: item) { return thumb }
        case .file:
            if let info = store.info(for: item), let image = info.thumbnail ?? info.icon { return image }
        case .text:
            break
        }
        return NSImage(systemSymbolName: item.kind == .text ? "doc.text" : "doc", accessibilityDescription: nil) ?? NSImage()
    }
}

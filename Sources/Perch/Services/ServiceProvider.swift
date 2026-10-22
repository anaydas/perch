import AppKit

/// "Add to Perch" in the Services menu (right-click selected text, images or files in most
/// apps). Declared under NSServices in Info.plist; macOS calls `addToPerch` with the selection.
final class ServiceProvider: NSObject {
    private let store: ShelfStore

    init(store: ShelfStore) {
        self.store = store
    }

    @objc func addToPerch(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        if !store.add(from: pboard) {
            error.pointee = "Perch couldn't use this selection." as NSString
        }
    }
}

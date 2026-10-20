import AppKit

/// Uses Spotlight to notice new screenshots (wherever they are saved) and pins them.
final class ScreenshotWatcher: NSObject {
    private let store: ShelfStore
    private let settings: AppSettings
    private let query = NSMetadataQuery()
    private let launchDate = Date()
    private var seenPaths = Set<String>()

    init(store: ShelfStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        super.init()
    }

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )
        query.start()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        guard settings.autoCatchScreenshots else { return }
        let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        // A screenshot is sometimes reported as "changed" once its final name is written.
        let changed = notification.userInfo?[NSMetadataQueryUpdateChangedItemsKey] as? [NSMetadataItem] ?? []

        for item in added + changed {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seenPaths.contains(path) else { continue }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            guard created > launchDate, FileManager.default.fileExists(atPath: path) else { continue }
            seenPaths.insert(path)
            store.addImage(from: URL(fileURLWithPath: path))
        }
    }
}

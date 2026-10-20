import Foundation

enum ShelfItemKind: String, Codable {
    case text, image, file
}

struct ShelfItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ShelfItemKind
    var title: String
    var createdAt = Date()
    /// Starred items never expire.
    var isStarred = false
    /// Came from clipboard history rather than being pinned on purpose.
    var isRecent = false
    /// Text that matched a secret / card-number pattern.
    var isSensitive = false

    var text: String?
    /// Path of a stored image, relative to the store's files folder.
    var storedPath: String?
    /// Original location of a pinned file (files are referenced, not copied).
    var fileURL: URL?
    var pixelWidth: Int?
    var pixelHeight: Int?
}

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all, images, text, files, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .images: return "Images"
        case .text: return "Text"
        case .files: return "Files"
        case .recent: return "Recent"
        }
    }
}

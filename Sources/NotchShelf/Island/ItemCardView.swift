import AppKit
import SwiftUI

struct ItemCardView: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    @State private var copied = false
    @State private var revealed = false

    private var isHidden: Bool { item.isSensitive && settings.hideSensitive && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            preview
                .frame(width: IslandMetrics.cardWidth - 16, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            Text(meta)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: copy) {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(copied ? Color.accentColor : Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: IslandMetrics.cardWidth, height: IslandMetrics.cardHeight)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1)))
        .overlay(alignment: .topTrailing) { cornerControls.padding(4) }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrag { store.itemProvider(for: item) }
        .onTapGesture(count: 2) { store.open(item) }
        .contextMenu { menu }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                missing
            }
        case .text:
            Text(item.text ?? "")
                .font(looksLikeCode ? .system(size: 10, design: .monospaced) : .system(size: 10.5))
                .foregroundStyle(looksLikeCode ? Color(red: 0.56, green: 0.89, blue: 0.63) : Color.white.opacity(0.9))
                .lineLimit(6)
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(looksLikeCode ? Color.black.opacity(0.45) : Color.white.opacity(0.1))
                .blur(radius: isHidden ? 5 : 0)
                .overlay {
                    if isHidden {
                        Button { revealed = true } label: {
                            Label("Hidden", systemImage: "eye.slash")
                                .font(.system(size: 10.5, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .help("Looks like a secret. Click to reveal.")
                    }
                }
        case .file:
            ZStack {
                Color.white.opacity(0.1)
                if let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    missing
                }
            }
        }
    }

    private var missing: some View {
        Image(systemName: "questionmark.square.dashed")
            .font(.system(size: 22))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.1))
    }

    private var cornerControls: some View {
        HStack(spacing: 3) {
            if item.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            Button { store.remove(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Copy") { copy() }
        if item.kind != .text {
            Button("Open") { store.open(item) }
            Button("Show in Finder") { store.revealInFinder(item) }
        }
        if item.isRecent {
            Button("Pin to Shelf") { store.pin(item) }
        }
        Button(item.isStarred ? "Unstar" : "Star (never expires)") { store.toggleStar(item) }
        Divider()
        Button("Remove") { store.remove(item) }
    }

    // MARK: - Helpers

    private var looksLikeCode: Bool {
        guard let text = item.text else { return false }
        let markers = ["{", "}", "();", "=>", "curl ", "$ ", "func ", "class ", "import ", "SELECT ", "</"]
        return markers.contains { text.contains($0) }
    }

    private var meta: String {
        switch item.kind {
        case .image:
            let ext = (item.storedPath as NSString?)?.pathExtension.uppercased() ?? "IMG"
            if let w = item.pixelWidth, let h = item.pixelHeight { return "\(ext) · \(w)×\(h)" }
            return ext
        case .text:
            return "\(item.text?.count ?? 0) chars" + (item.isRecent ? " · copied" : "")
        case .file:
            guard let url = item.fileURL,
                  let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 else {
                return "File missing"
            }
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
    }

    private func copy() {
        store.copy(item)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}

import AppKit
import SwiftUI

struct ItemCardView: View {
    @Environment(\.islandAccent) private var accent
    let item: ShelfItem
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    @State private var copied = false
    @State private var revealed = false
    @State private var hovering = false

    private var isHidden: Bool { item.isSensitive && settings.hideSensitive && !revealed }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            preview
                .frame(width: IslandMetrics.cardWidth - 12, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(item.title)
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
            Text(meta)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: copy) {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(copied ? accent : Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: IslandMetrics.cardWidth, height: IslandMetrics.cardHeight)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(item.isFixed ? accent.opacity(0.8) : Color.primary.opacity(0.1)))
        .overlay(alignment: .topTrailing) { cornerControls.padding(3) }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
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
                .font(looksLikeCode ? .system(size: 8.5, design: .monospaced) : .system(size: 9.5))
                .foregroundStyle(looksLikeCode ? Color(red: 0.56, green: 0.89, blue: 0.63) : Color.primary.opacity(0.9))
                .lineLimit(4)
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(looksLikeCode ? Color(white: 0.1) : Color.primary.opacity(0.1))
                .blur(radius: isHidden ? 4 : 0)
                .overlay {
                    if isHidden {
                        Button { revealed = true } label: {
                            Label("Hidden", systemImage: "eye.slash")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .foregroundStyle(.white)
                                .background(Capsule().fill(Color.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .help("Looks like a secret. Click to reveal.")
                    }
                }
        case .file:
            ZStack {
                Color.primary.opacity(0.1)
                if let info = store.info(for: item) {
                    if let thumbnail = info.thumbnail {
                        // Real preview: a video frame, a PDF's first page, …
                        Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
                    } else if let icon = info.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 36, height: 36)
                    } else {
                        missing
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
            }
        }
    }

    private var missing: some View {
        Image(systemName: "questionmark.square.dashed")
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.1))
    }

    private var cornerControls: some View {
        HStack(spacing: 3) {
            if item.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.yellow)
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.6)))
            }
            // Fix button: always shown on fixed cards, on hover otherwise.
            if item.isFixed || hovering {
                Button { store.toggleFixed(item) } label: {
                    Image(systemName: item.isFixed ? "pin.fill" : "pin")
                        .font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(45))
                        .frame(width: 15, height: 15)
                        .foregroundStyle(.white)
                        .background(Circle().fill(item.isFixed ? accent : Color.black.opacity(0.6)))
                }
                .buttonStyle(.plain)
                .help(item.isFixed ? "Unfix position" : "Fix at the front")
            }
            Button { store.remove(item) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .frame(width: 15, height: 15)
                    .foregroundStyle(.white)
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
        Button(item.isFixed ? "Unfix Position" : "Fix at the Front") { store.toggleFixed(item) }
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
            guard let info = store.info(for: item) else { return "File" }
            guard let size = info.size else { return "File missing" }
            let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            if let duration = info.duration { return "\(Self.durationText(duration)) · \(sizeText)" }
            return sizeText
        }
    }

    private var isVideo: Bool { item.fileURL.map(ShelfStore.isVideoFile) ?? false }

    /// "0:42", "12:05", "1:02:03".
    private static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func copy() {
        store.copy(item)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}

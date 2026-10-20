import AppKit
import SwiftUI

/// The small island: recent items peeking out on the left, the count on the right,
/// and an empty gap where the hardware notch is.
struct CollapsedPillView: View {
    let notchWidth: CGFloat
    let items: [ShelfItem]
    @ObservedObject var store: ShelfStore
    let flashToken: Int
    @State private var bump = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: -6) {
                if items.isEmpty {
                    Image(systemName: "tray")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(items.prefix(3))) { item in
                    MiniThumb(item: item, store: store)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchWidth)

            HStack(spacing: 5) {
                if !items.isEmpty {
                    Text("\(items.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .scaleEffect(bump ? 1.12 : 1)
        .onChange(of: flashToken) { _ in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.4)) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { bump = false }
            }
        }
    }
}

private struct MiniThumb: View {
    let item: ShelfItem
    @ObservedObject var store: ShelfStore

    var body: some View {
        Group {
            if item.kind == .image, let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(item.kind == .file ? Color.orange : Color.gray)
            }
        }
        .frame(width: 16, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black, lineWidth: 1.5))
    }
}

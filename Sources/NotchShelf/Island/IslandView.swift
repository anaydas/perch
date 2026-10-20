import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    let actions: IslandActions

    private var expanded: Bool { model.isExpanded }
    private var ear: CGFloat { expanded ? IslandMetrics.earExpanded : IslandMetrics.earCollapsed }
    private var bottom: CGFloat { expanded ? IslandMetrics.bottomExpanded : IslandMetrics.bottomCollapsed }

    private var bodySize: CGSize {
        let notch = model.notchSize
        return expanded
            ? CGSize(width: IslandMetrics.expandedWidth, height: notch.height + IslandMetrics.expandedBodyHeight)
            : CGSize(width: notch.width + IslandMetrics.collapsedExtraWidth, height: notch.height)
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var island: some View {
        let shape = IslandShape(ear: ear, bottom: bottom)
        return ZStack(alignment: .top) {
            IslandBackgroundView(style: settings.background, shape: shape)
            content
                .padding(.horizontal, ear)
        }
        .frame(width: bodySize.width + ear * 2, height: bodySize.height)
        .clipShape(shape)
        .overlay(
            IslandOutlineView(
                shape: IslandShape(ear: ear, bottom: bottom, closed: false),
                outline: settings.outline,
                tint: settings.tint.color
            )
        )
        .shadow(color: .black.opacity(expanded ? 0.35 : 0), radius: 22, x: 0, y: 12)
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.plainText], isTargeted: $model.isDropTargeted) { providers in
            store.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedShelfView(model: model, store: store, settings: settings, actions: actions)
                .padding(.top, model.notchSize.height + 6)
                .transition(AnyTransition.opacity.animation(.easeOut(duration: 0.18).delay(0.1)))
        } else {
            CollapsedPillView(notchWidth: model.notchSize.width,
                              items: store.pinned,
                              store: store,
                              flashToken: model.flashToken)
                .frame(height: model.notchSize.height)
                .transition(AnyTransition.opacity.animation(.easeOut(duration: 0.12)))
        }
    }
}

/// Solid, transparent, or frosted-glass fill.
struct IslandBackgroundView: View {
    let style: IslandBackground
    let shape: IslandShape

    var body: some View {
        switch style {
        case .solid:
            shape.fill(Color.black)
        case .transparent:
            shape.fill(Color.black.opacity(0.55))
        case .glass:
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.black.opacity(0.3))
            }
        }
    }
}

/// Outline styles drawn along the same path as the island (top edge left open).
struct IslandOutlineView: View {
    let shape: IslandShape
    let outline: IslandOutline
    let tint: Color
    @State private var pulsing = false

    var body: some View {
        switch outline {
        case .none:
            Color.clear
        case .hairline:
            shape.stroke(Color.white.opacity(0.35), lineWidth: 1)
        case .accent:
            shape.stroke(tint, lineWidth: 1.5)
        case .glow:
            shape.stroke(tint, lineWidth: 1)
                .shadow(color: tint.opacity(0.85), radius: 7)
        case .double:
            ZStack {
                shape.stroke(tint, lineWidth: 5)
                shape.stroke(Color.black, lineWidth: 2).blendMode(.destinationOut)
            }
            .compositingGroup()
        case .pulse:
            shape.stroke(tint, lineWidth: 1)
                .shadow(color: tint, radius: pulsing ? 14 : 3)
                .onAppear {
                    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulsing = true }
                }
        }
    }
}

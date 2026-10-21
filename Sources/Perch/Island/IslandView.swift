import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var store: ShelfStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var claudeSessions: ClaudeSessionWatcher
    let claudeUsage: ClaudeUsageWatcher
    let actions: IslandActions

    private var layout: IslandLayout { model.layout }
    private var expanded: Bool { model.isExpanded }
    private var ear: CGFloat { layout.ear(expanded: expanded) }
    private var corner: CGFloat { layout.corner(expanded: expanded) }

    /// Where the island sits inside the panel: against the chosen edge, centred along it.
    private var alignment: Alignment {
        switch layout.position {
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private var edgePadding: EdgeInsets {
        let inset = layout.edgeInset
        switch layout.position {
        case .top: return EdgeInsets(top: inset, leading: 0, bottom: 0, trailing: 0)
        case .left: return EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: 0)
        case .right: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: inset)
        }
    }

    var body: some View {
        Group {
            if layout.isMovable {
                // Anywhere on screen: placed at its (possibly dragged) centre.
                let center = layout.floatingCenter(expanded: expanded, offset: model.dragOffset ?? .zero)
                island
                    .gesture(expanded ? nil : moveGesture)
                    .position(center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                island
                    .padding(edgePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// Drags the floating island; the open shelf uses the same gesture on its header.
    private var moveGesture: some Gesture {
        IslandMoveGesture.make(model: model, actions: actions)
    }

    private func shape(closed: Bool = true) -> IslandShape {
        IslandShape(ear: ear, bottom: corner, closed: closed, edge: layout.position, detached: !layout.isAttached)
    }

    private var island: some View {
        let outer = layout.outerSize(expanded: expanded)
        return ZStack {
            IslandBackgroundView(style: settings.background, shape: shape())
            content
                .padding(layout.isVertical ? .vertical : .horizontal, ear)
        }
        .frame(width: outer.width, height: outer.height)
        .clipShape(shape())
        .overlay(
            IslandOutlineView(
                shape: shape(closed: !layout.isAttached),
                outline: settings.outline,
                tint: settings.tint.color
            )
        )
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.plainText], isTargeted: $model.isDropTargeted) { providers in
            store.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var content: some View {
        if expanded {
            ExpandedShelfView(model: model, store: store, settings: settings,
                              claudeSessions: claudeSessions, claudeUsage: claudeUsage, actions: actions)
                .padding(.top, layout.contentLeadInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(AnyTransition.opacity.animation(.easeOut(duration: 0.12)))
        } else {
            CollapsedIslandView(layout: layout,
                                items: store.ordered,
                                store: store,
                                sessions: claudeSessions.sessions,
                                flashToken: model.flashToken)
                .transition(AnyTransition.opacity.animation(.easeOut(duration: 0.12)))
        }
    }
}

/// Drag-to-move for the floating island, shared by the collapsed capsule and the shelf header.
enum IslandMoveGesture {
    static func make(model: IslandViewModel, actions: IslandActions) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in model.dragOffset = value.translation }
            .onEnded { value in
                actions.moveFloating(value.translation)
                model.dragOffset = nil
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

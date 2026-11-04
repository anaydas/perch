import AppKit
import SwiftUI

/// A two-or-more option switch whose highlight slides to the chosen option (the system segmented
/// control jumps). The change is animated, so views that depend on it can cross-fade.
struct SlidingSwitch<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var small = false
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Text(option.label)
                    .font(.system(size: small ? 11 : 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: small ? 20 : 24)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: small ? 5 : 6)
                                .fill(Color.primary.opacity(0.16))
                                .matchedGeometryEffect(id: "highlight", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !selected else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { selection = option.value }
                    }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: small ? 7 : 8).fill(Color.primary.opacity(0.07)))
    }
}

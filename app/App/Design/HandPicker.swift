import SwiftUI

/// The hand-choosing rows shared by the Drawer (the whole shelf at once) and
/// the page's hand card (one Book). The sample line rendered in each face is
/// the real information; the small-caps name anchors it for VoiceOver and for
/// the faces that render small.
struct HandPickerList: View {
    /// Label of the leading "no re-dressing" row.
    let ownLabel: String
    /// Face previewed on that row — a Book's own hand. nil on the Drawer,
    /// where "own" means eight different hands at once.
    let ownHand: Hand?
    /// Currently chosen hand id; nil highlights nothing among the hands.
    let selection: String?
    /// Whether the leading "own" row is the current choice (distinct from
    /// `selection == nil`, which on a mixed shelf highlights nothing at all).
    let ownSelected: Bool
    let onSelect: (String?) -> Void
    @Environment(\.room) private var room

    private static let sample = "I will answer in kind."

    var body: some View {
        VStack(spacing: 0) {
            row(id: nil, name: ownLabel, sampleFont: ownHand.map { InkFont.hand($0.id, 19 * $0.scale) },
                selected: ownSelected, divider: true)
            ForEach(Array(Hand.all.enumerated()), id: \.element.id) { index, hand in
                row(id: hand.id, name: hand.name,
                    sampleFont: InkFont.hand(hand.id, 19 * hand.scale),
                    selected: selection == hand.id,
                    divider: index < Hand.all.count - 1)
            }
        }
    }

    private func row(
        id: String?, name: String, sampleFont: Font?, selected: Bool, divider: Bool
    ) -> some View {
        Button {
            if !selected { Feel.shared.tick() }
            onSelect(id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SmallCapsLabel(
                        text: name, size: 10.5, tracking: 1.8,
                        color: selected ? room.accent : room.dim
                    )
                    if let sampleFont {
                        Text(Self.sample)
                            .font(sampleFont)
                            .foregroundStyle(room.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("Each Book keeps the script it was bound with.")
                            .font(InkFont.bodyItalic(14))
                            .foregroundStyle(room.dim)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.candle)
                    .opacity(selected ? 1 : 0)
            }
            .padding(EdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(room.accent.opacity(0.1)).frame(height: 1)
            }
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

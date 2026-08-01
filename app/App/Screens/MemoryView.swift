import SwiftUI

/// "What the notebook remembers" — Plus feature. Memory entries as inked
/// marginalia; tear any out to make it forget. Free users see the bind
/// pitch. Off every navigation path for v1: cross-page memory (task D5) is
/// not built, so nothing writes notes and no screen may promise otherwise.
/// When the MemoryInjection store binds, this reads from it and returns to
/// the shelf's rooms.
struct MemoryView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room
    /// Empty until the real memory store binds — the notebook honestly
    /// remembers nothing, and the demo notes this once showed are gone.
    @State private var notes: [String] = []
    @State private var tearing: String?

    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(
                stops: [
                    .init(color: Ink.parchmentBright, location: 0),
                    .init(color: Ink.parchment, location: 0.46),
                    .init(color: Ink.parchmentDeep, location: 1),
                ],
                center: UnitPoint(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: 1300
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                parchmentNavBar
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("What the notebook remembers")
                            .font(InkFont.display(32))
                            .foregroundStyle(Ink.ink)
                            .multilineTextAlignment(.center)

                        if model.bound {
                            Text("Kept in the margins. Tear any note out to make it forget.")
                                .font(InkFont.bodyItalic(15))
                                .foregroundStyle(Color(hex: 0x7A6A4D))
                                .padding(.top, 6)

                            if notes.isEmpty {
                                Text("Nothing is kept in the margins yet — the notebook is only beginning to know you.")
                                    .font(InkFont.bodyItalic(17))
                                    .foregroundStyle(Color(hex: 0x7A6A4D))
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(6)
                                    .frame(maxWidth: 400)
                                    .padding(.top, 44)
                            } else {
                                VStack(spacing: 2) {
                                    ForEach(notes, id: \.self) { note in
                                        memoryRow(note)
                                    }
                                }
                                .padding(.top, 32)
                            }
                        } else {
                            freeState
                                .padding(.top, 40)
                        }
                    }
                    .frame(maxWidth: 600)
                    .padding(EdgeInsets(top: 40, leading: 56, bottom: 56, trailing: 56))
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var parchmentNavBar: some View {
        ZStack {
            SmallCapsLabel(text: "Memory", size: 12.5, tracking: 2.5, color: Color(hex: 0x8A7658))
            HStack {
                Button { model.go(.shelf) } label: {
                    HStack(spacing: 6) {
                        Text("‹").font(InkFont.body(15))
                        SmallCapsLabel(text: "the shelf", size: 11.5, tracking: 1.4, color: Ink.inkFaded)
                    }
                    .foregroundStyle(Ink.inkFaded)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 38)
                    .background(
                        Capsule()
                            .fill(Ink.ink.opacity(0.05))
                            .overlay(Capsule().stroke(Ink.ink.opacity(0.18), lineWidth: 1))
                    )
                }
                .buttonStyle(PressScaleStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color(hex: 0xF8F0DE, opacity: 0.82))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.ink.opacity(0.12)).frame(height: 1)
        }
    }

    private func memoryRow(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("❦")
                .font(InkFont.body(15))
                .foregroundStyle(Ink.wax)
                .padding(.top, 3)
            Text(note)
                .font(InkFont.body(17))
                .foregroundStyle(Ink.ink)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            if tearing == note {
                HStack(spacing: 8) {
                    Text("tear out?")
                        .font(InkFont.bodyItalic(13))
                        .foregroundStyle(Ink.dangerEmber)
                    tearButton("yes", destructive: true) {
                        withAnimation(.easeOut(duration: 0.35)) {
                            notes.removeAll { $0 == note }
                            tearing = nil
                        }
                    }
                    tearButton("no", destructive: false) {
                        withAnimation { tearing = nil }
                    }
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation { tearing = note }
                } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 15))
                        .foregroundStyle(Ink.ink.opacity(0.35))
                        // 34pt was under the 44pt minimum target, and this is
                        // the destructive control on the screen.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Named, so a row of identical "Tear out this memory" buttons
                // is not the only thing VoiceOver can tell apart.
                .accessibilityLabel("Tear out the memory: \(note)")
            }
        }
        .padding(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 4))
        .overlay(alignment: .bottom) {
            Line()
                .stroke(Ink.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
        }
    }

    private func tearButton(_ label: String, destructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(InkFont.body(13))
                .foregroundStyle(destructive ? Ink.dangerEmber : Ink.inkFaded)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(destructive ? Ink.dangerEmber.opacity(0.12) : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).stroke(
                                destructive ? Ink.dangerEmber.opacity(0.35) : Ink.ink.opacity(0.2),
                                lineWidth: 1
                            )
                        )
                )
        }
        .buttonStyle(PressScaleStyle())
    }

    private var freeState: some View {
        VStack(spacing: 0) {
            Text("The notebook remembers nothing yet. Bind it, and it will begin to keep what matters — the names, the threads, the way you like to be answered.")
                .font(InkFont.bodyItalic(18))
                .foregroundStyle(Color(hex: 0x7A6A4D))
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .frame(maxWidth: 400)
            WaxSealButton(
                label: "bind the notebook",
                diameter: 48,
                labelFont: InkFont.display(21)
            ) {
                model.go(.paywall)
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
    }
}

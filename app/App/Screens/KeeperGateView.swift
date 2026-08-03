import SwiftUI

/// The Keeper stays shut for everyone but you. Face ID (or passcode) through
/// the injected `KeeperAuthenticating` seam; in-fiction framing throughout.
/// The lock fails closed: nothing but a successful evaluation opens the Book.
struct KeeperGateView: View {
    @Bindable var model: AppModel
    let auth: any KeeperAuthenticating
    let archive: PageArchive
    @Environment(\.room) private var room
    @State private var refusal: KeeperAuthOutcome?
    @State private var asking = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                keeperCover
                    .padding(.bottom, 34)
                faceIDGlyph
                    .padding(.bottom, 22)

                Text("Only your hand may open this")
                    .font(InkFont.display(27))
                    .foregroundStyle(room.heading)
                Text("The Keeper stays shut for everyone but you.")
                    .font(InkFont.bodyItalic(15))
                    .foregroundStyle(room.dim)
                    .padding(.top, 6)

                Button(action: unlock) {
                    Text("Look to unlock")
                        .font(InkFont.body(16))
                        .kerning(0.6)
                        .foregroundStyle(room.heading)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 48)
                        .background(
                            Capsule()
                                .fill(room.accent.opacity(0.1))
                                .overlay(Capsule().stroke(room.accent.opacity(0.34), lineWidth: 1))
                        )
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 28)
                .disabled(asking)

                Button(action: unlock) {
                    Text("Use passcode instead")
                        .font(InkFont.body(13))
                        .foregroundStyle(Color(hex: 0x7A6A4D))
                        .frame(minHeight: 44)
                }
                .padding(.top, 2)
                .disabled(asking)

                if let refusal, let line = Self.refusalLine(refusal) {
                    Text(line)
                        .font(InkFont.bodyItalic(13))
                        .foregroundStyle(Ink.dangerEmber)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(56)

            Button { model.go(.shelf) } label: {
                HStack(spacing: 7) {
                    Text("‹")
                    SmallCapsLabel(text: "the shelf", size: 12, tracking: 1.4, color: room.accent)
                }
                .foregroundStyle(room.accent)
                .padding(.horizontal, 15)
                .frame(minHeight: 40)
                .background(
                    Capsule()
                        .fill(.white.opacity(0.04))
                        .overlay(Capsule().stroke(room.accent.opacity(0.2), lineWidth: 1))
                )
            }
            .buttonStyle(PressScaleStyle())
            .padding(22)
        }
    }

    private var keeperCover: some View {
        let keeper = Book.by(id: .keeper)
        return UnevenRoundedRectangle(
            topLeadingRadius: 5, bottomLeadingRadius: 5,
            bottomTrailingRadius: 7, topTrailingRadius: 7
        )
        .fill(
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x8A4F47), location: 0),
                    .init(color: keeper.accent, location: 0.32),
                    .init(color: Color(hex: 0x4C2722), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.24),
                    .init(color: .black.opacity(0.34), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .top) { LockGlyph().padding(.top, 16) }
        .overlay(
            Circle()
                .stroke(Ink.goldTitleTop.opacity(0.4), lineWidth: 1)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("K").font(InkFont.display(22)).foregroundStyle(Ink.goldTitleTop)
                )
        )
        .frame(width: 150, height: 212)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 5, bottomLeadingRadius: 5,
                bottomTrailingRadius: 7, topTrailingRadius: 7
            )
        )
        .shadow(color: .black.opacity(0.75), radius: 30, y: 22)
    }

    private var faceIDGlyph: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { corner in
                RoundedCorner()
                    .stroke(Ink.candleBright, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 16, height: 16)
                    .rotationEffect(.degrees(Double(corner) * 90))
                    .offset(
                        x: corner == 1 || corner == 2 ? 24 : -24,
                        y: corner >= 2 ? 24 : -24
                    )
            }
            Capsule().fill(Ink.candleBright).frame(width: 3, height: 10).offset(x: -10, y: -4)
            Capsule().fill(Ink.candleBright).frame(width: 3, height: 10).offset(x: 10, y: -4)
            SmileArc()
                .stroke(Ink.candleBright, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 18, height: 8)
                .offset(y: 11)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }

    /// Every outcome but `.granted` leaves the Book shut. The fiction may
    /// dead-end; the lock may not.
    static func refusalLine(_ outcome: KeeperAuthOutcome) -> String? {
        switch outcome {
        case .granted:
            return nil
        case .cancelled:
            // The reader chose to stop. Say almost nothing.
            return "The Keeper waits. Look again when you are ready."
        case .unavailable:
            return "This lock has no key cut for it yet. Set a passcode on this device, and the Keeper will learn your hand."
        case .lockedOut:
            return "The lock has closed itself against too many hands. Your device passcode will wake it."
        case .denied:
            return "The lock did not know your hand. Try once more."
        }
    }

    private func unlock() {
        guard !asking else { return }
        asking = true
        Task { @MainActor in
            let outcome = await auth.authenticate(reason: "The Keeper opens for your hand alone.")
            asking = false
            if outcome == .granted {
                Feel.shared.play(.unlock)
                granted()
            } else {
                Feel.shared.play(.refusal)
                withAnimation { refusal = outcome }
            }
        }
    }

    private func granted() {
        model.keeperUnlocked = true
        // The Keeper's pages come off disk only now, and only for as long as
        // the gate stands open.
        archive.unsealKeeper()
        // Open the Book that was actually asked for — AppModel.open(book:) set
        // activeBookID before it routed here. Hardcoding the Keeper would open
        // the wrong Book the moment a second one is marked `locked`.
        model.open(book: model.activeBook)
    }
}

private struct RoundedCorner: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: rect.maxY * 0.35))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX * 0.35, y: 0),
                control: .zero
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: 0))
        }
    }
}

private struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: 0),
                control: CGPoint(x: rect.midX, y: rect.maxY * 2)
            )
        }
    }
}

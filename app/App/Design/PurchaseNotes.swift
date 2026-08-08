import SwiftUI

/// Commerce feedback, rendered over whichever room started the purchase.
/// Every `PurchaseState` the model can hold has a face here: progress blocks
/// the seal from being pressed twice, failure and Ask-to-Buy get plain words
/// and a way out, success gets its receipt. A purchase that looks like
/// nothing happening is indistinguishable from a broken paywall — for the
/// user and for App Review alike.
struct PurchaseNoteOverlay: View {
    @Environment(\.room) private var room
    /// VoiceOver lands on the verdict when a note rises — paired with
    /// `.isModal` so the room behind the scrim stops existing for the rotor
    /// (audit H-7), matching the delete-confirm pattern.
    @AccessibilityFocusState private var noteFocused: Bool

    let state: PurchaseState
    var successTitle: String
    var successBody: String
    var successAction: String
    /// Dismisses failure / Ask-to-Buy notes (clears the purchase state).
    var onDismiss: () -> Void
    /// Where the success card's single button leads.
    var onSuccess: () -> Void

    var body: some View {
        notes
            // One hook for every room that sells: the paywall and the vials
            // both render this overlay, so the verdict pulse lives here and
            // nowhere per-screen. Deferred stays silent — Ask-to-Buy is a
            // pause, not a verdict.
            .onChange(of: state) { _, landed in
                switch landed {
                case .succeeded: Feel.shared.play(.purchaseSuccess)
                case .failed: Feel.shared.play(.purchaseFailed)
                default: break
                }
            }
    }

    @ViewBuilder
    private var notes: some View {
        switch state {
        case .idle:
            EmptyView()
        case .purchasing:
            scrim(dismissable: false) {
                VStack(spacing: 16) {
                    WaxSeal(diameter: 52)
                    Text("The seal takes to the wax…")
                        .font(InkFont.bodyItalic(16))
                        .foregroundStyle(Color(hex: 0xC9B48A))
                }
                .padding(36)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityFocused($noteFocused)
            }
        case .deferred:
            note(
                title: "The binding waits",
                body: "Your purchase is waiting for approval — Ask to Buy sends it to your family organizer first. The notebook binds itself the moment word arrives.",
                action: "very well", onTap: onDismiss
            )
        case .failed(let title, let message):
            // The state carries its own headline (audit L-10): "The seal
            // would not take" over a body saying the payment DID take —
            // delivery pending, delivery rejected — read as a contradiction.
            note(title: title, body: message, action: "very well", onTap: onDismiss)
        case .succeeded:
            note(title: successTitle, body: successBody, action: successAction, onTap: onSuccess)
        }
    }

    private func note(
        title: String, body: String, action: String, onTap: @escaping () -> Void
    ) -> some View {
        scrim(dismissable: false) {
            VStack(spacing: 0) {
                Text(title)
                    .font(InkFont.display(24))
                    .foregroundStyle(room.heading)
                    .accessibilityFocused($noteFocused)
                Text(body)
                    .font(InkFont.body(15))
                    // Theme-following (audit H-6): the hardcoded #B8A684 read
                    // at ~2:1 on the daylight card.
                    .foregroundStyle(room.text)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                Button(action: onTap) {
                    Text(action)
                        .font(InkFont.body(15))
                        .foregroundStyle(Ink.parchment)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(
                                    colors: [Color(hex: 0x9A4340), Ink.wax],
                                    startPoint: .top, endPoint: .bottom
                                ))
                        )
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [room.cardTop, room.cardBottom],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(room.accent.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
            )
            .padding(30)
        }
    }

    private func scrim(dismissable: Bool, @ViewBuilder content: () -> some View) -> some View {
        ZStack {
            Color(hex: 0x080503, opacity: 0.66).ignoresSafeArea()
            content()
        }
        .transition(.opacity)
        // A purchase verdict may not leave the room behind it swipe-reachable
        // (audit H-7): without .isModal a VoiceOver user could land on — and
        // activate — the paywall under the scrim.
        .accessibilityAddTraits(.isModal)
        .onAppear { noteFocused = true }
    }
}

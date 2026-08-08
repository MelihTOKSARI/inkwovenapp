import SwiftUI
import InkMoney

/// The credit wallet: moving-picture credits as wax-sealed vials.
///
/// Live as of Epic J — the modality the vials fund now works end to end, so the
/// shop comes out from behind the curtain. Prices and pack sizes are the ones
/// costed in `design/app-store-assets/credits.md` §3; the balance shown is the
/// server's, never a local tally.
///
/// Reachable two ways, because the shop is visited for two different reasons:
/// deliberately from the Drawer (this room), and mid-errand from a page whose
/// picture wants to move (`VialsSheet`). The second cannot be a room: RootView
/// rebuilds `PageView` on every navigation, so travelling to a shop would throw
/// away the reply and the offer the reader was trying to spend on.
struct VialsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Back to wherever the shop was opened from — the Drawer, not
                // the shelf, when that is where the reader came from.
                RoomNavBar(title: "The Vials") { model.closeVials() }
                ScrollView(showsIndicators: false) {
                    VialsShop(model: model)
                        .frame(maxWidth: 720)
                        .padding(EdgeInsets(top: 36, leading: 56, bottom: 60, trailing: 56))
                        .frame(maxWidth: .infinity)
                }
            }

            PurchaseNoteOverlay(
                state: model.purchaseState,
                successTitle: "Sealed and delivered",
                successBody: "The vials are yours — they wait, sealed, until a picture asks to move.",
                successAction: "very well",
                onDismiss: { model.clearPurchaseNote() },
                onSuccess: { model.clearPurchaseNote() }
            )
        }
    }
}

/// The shop's contents, independent of how they are presented.
struct VialsShop: View {
    @Bindable var model: AppModel
    /// Shown when the shop is opened because a picture is waiting on a vial —
    /// the errand needs a sentence the deliberate visit does not.
    var errandNote: String?
    /// Bound by a modal presentation (VialsSheet) so VoiceOver lands on the
    /// title when the sheet rises (audit H-7); the room presentation leaves
    /// it nil and keeps the nav bar's natural order.
    var titleFocus: AccessibilityFocusState<Bool>.Binding?
    @Environment(\.room) private var room

    /// No fallback literals (audit C-3): a hardcoded USD price is charged at
    /// a different amount in every other storefront, which is a misleading-
    /// price rejection. Until StoreKit answers, the buy button waits.
    private let packs: [String] = [ProductID.vialsSmall, ProductID.vialsMedium, ProductID.vialsLarge]

    var body: some View {
        VStack(spacing: 0) {
            title
            Text(errandNote ?? "Moving-picture credits, sealed in wax until you spend them.")
                .font(InkFont.bodyItalic(16))
                .foregroundStyle(room.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 6)

            balance
                .padding(.vertical, 34)

            HStack(alignment: .bottom, spacing: 16) {
                ForEach(Array(packs.enumerated()), id: \.offset) { index, pack in
                    packCard(productID: pack, big: index == 2, index: index)
                }
            }
            // Re-keyed on reachability (audit L-29): a shop opened on a dark
            // road used to show "—" forever, even after the way reopened.
            .task(id: offline) {
                await model.refreshWallet()
                // The launch price fetch can have failed; the shop re-asks.
                await model.refreshStore()
            }

            refundNote
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private var title: some View {
        let text = Text("The Vials")
            .font(InkFont.display(34))
            .foregroundStyle(room.heading)
        if let titleFocus {
            text.accessibilityFocused(titleFocus)
        } else {
            text
        }
    }

    /// Whether the road is dark. Read in `body`, so the shop re-renders the
    /// moment the way opens or closes (audit L-29).
    private var offline: Bool { Reachability.shared.isOffline }

    /// The purse, as the server reports it. While the read is in flight the
    /// count is a quiet placeholder rather than a zero — telling someone they
    /// have nothing when we simply have not asked yet is its own small lie.
    private var balance: some View {
        HStack(spacing: 22) {
            VialView(width: 46, height: 78, fill: model.vialBalance ?? 0 > 0 ? 0.55 : 0.12)
                .shadow(color: Ink.candle.opacity(0.12), radius: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.vialBalance.map(String.init) ?? "—")
                    .font(InkFont.display(44))
                    .foregroundStyle(room.heading)
                    .contentTransition(.numericText())
                SmallCapsLabel(text: balanceCaption, size: 12, tracking: 1.7, color: room.dim)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.vialBalance.map { "\($0) vials remain. \(balanceCaption)" }
            ?? (offline
                ? "The road is dark — the vials cannot be counted until the connection returns."
                : "Counting your vials."))
    }

    /// The free clips are named plainly: they are the reason a first-time
    /// reader never meets this room before they have seen what it buys.
    /// When the road is dark and the purse unread, the caption says why the
    /// count is a dash (audit L-29) — "—" forever explained nothing.
    private var balanceCaption: String {
        guard let free = model.freeClipsRemaining else {
            if offline, model.vialBalance == nil {
                return "the road is dark — the count waits"
            }
            return "moments remain"
        }
        if free > 0 {
            return free == 1 ? "moments remain · 1 gifted" : "moments remain · \(free) gifted"
        }
        return "moments remain"
    }

    private func packCard(productID: String, big: Bool, index: Int) -> some View {
        let count = ProductID.creditAmount(for: productID) ?? 0
        // The storefront's own string, or a waiting state — never a USD
        // literal (audit C-3). A buy button with no real price is disabled:
        // it could only answer productUnavailable.
        let price = model.storePrices[productID]
        return VStack(spacing: 0) {
            VialView(
                width: 22 + CGFloat(index) * 9,
                height: 46 + CGFloat(index) * 15,
                fill: 0.55
            )
            .frame(height: 84, alignment: .bottom)

            Text("\(count)")
                .font(InkFont.display(28))
                .foregroundStyle(room.heading)
                .padding(.top, 14)
            SmallCapsLabel(text: "moments", size: 11, tracking: 1.5, color: room.dim)
                .padding(.top, 4)
                .padding(.bottom, 18)

            Button {
                withAnimation { model.buyVials(productID) }
            } label: {
                Text(price.map { "Buy · \($0)" } ?? "Buy · —")
                    .font(InkFont.bodySemiBold(15))
                    .foregroundStyle(Color(hex: 0x2A1C0A))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Ink.candleBright, Ink.candle], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Ink.candle.opacity(price == nil ? 0 : 0.55), radius: 6, y: 4)
                    )
                    .opacity(price == nil ? 0.55 : 1)
            }
            .buttonStyle(PressScaleStyle())
            .disabled(price == nil)
            .accessibilityLabel(
                price.map { "Buy \(count) vials for \($0)" }
                    ?? "Buy \(count) vials. Waiting for the App Store to report the price."
            )
        }
        .padding(EdgeInsets(top: 26, leading: 16, bottom: 18, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                .shadow(color: big ? Ink.candle.opacity(0.45) : .clear, radius: 15, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(room.accent.opacity(big ? 0.5 : 0.18), lineWidth: 1)
        )
        .overlay(alignment: .top) {
            if big {
                SmallCapsLabel(text: "best value", size: 10, tracking: 1.4, color: Color(hex: 0x241A10))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Ink.candle))
                    .shadow(color: Ink.candle.opacity(0.6), radius: 4, y: 3)
                    .offset(y: -10)
            }
        }
    }

    private var refundNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("✦").font(InkFont.body(15)).foregroundStyle(Color(hex: 0x6B8A4E))
                // Ornament — VoiceOver spoke "four-pointed star" before the
                // refund promise (audit L-16).
                .accessibilityHidden(true)
            Text("If a picture fails to develop, its vial returns to you. You are never charged for a moment that did not arrive.")
                .font(InkFont.bodyItalic(14.5))
                .foregroundStyle(room.text)
                .lineSpacing(4)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Ink.successHerb.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Ink.successHerb.opacity(0.3), lineWidth: 1))
        )
    }
}

/// The shop as an errand, over the page rather than instead of it.
///
/// A reader who taps "fill the vials" is mid-sentence with a reply on the
/// facing page and a picture waiting to move. `RootView` rebuilds `PageView`
/// on every navigation, so sending them to the Vials *room* would discard the
/// reply, the verdict and the offer — they would buy a vial and come back to a
/// blank page with nothing to spend it on. Presented here it costs them
/// nothing: the page is still underneath, and the offer is still on it.
struct VialsSheet: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    @Environment(\.room) private var room
    /// VoiceOver lands on the shop's title when the errand rises — paired
    /// with `.isModal` so the page behind the scrim stops existing for the
    /// rotor (audit H-7), matching the delete-confirm pattern.
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityLabel("Close the vials")

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(room.dim)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.trailing, 6)

                ScrollView(showsIndicators: false) {
                    VialsShop(
                        model: model,
                        errandNote: "A picture is waiting to move. Fill the vials and it will.",
                        titleFocus: $titleFocused
                    )
                    .padding(EdgeInsets(top: 4, leading: 34, bottom: 34, trailing: 34))
                }
            }
            .frame(maxWidth: 720)
            .frame(maxHeight: 720)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(room.accent.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            )
            .padding(40)

            PurchaseNoteOverlay(
                state: model.purchaseState,
                successTitle: "Sealed and delivered",
                successBody: "The vials are yours. The picture on the page can move now.",
                successAction: "very well",
                onDismiss: { model.clearPurchaseNote() },
                // Dismissing the receipt closes the errand too: the reader came
                // here to buy one thing, and the page they left is the point.
                onSuccess: {
                    model.clearPurchaseNote()
                    onClose()
                }
            )
        }
        .transition(.opacity)
        // The errand covers the page entirely; without .isModal a VoiceOver
        // user could land on — and write into — the page behind the scrim
        // (audit H-7).
        .accessibilityAddTraits(.isModal)
        .onAppear { titleFocused = true }
    }
}

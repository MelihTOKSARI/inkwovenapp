import SwiftUI
import InkMoney

/// The credit wallet: moving-picture credits as wax-sealed vials.
///
/// Live as of Epic J — the modality the vials fund now works end to end, so the
/// shop comes out from behind the curtain. Prices and pack sizes are the ones
/// costed in `design/app-store-assets/credits.md` §3; the balance shown is the
/// server's, never a local tally.
struct VialsView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room

    /// Fallbacks are shown only until StoreKit answers with the storefront's
    /// own strings — a hardcoded USD price is charged differently everywhere
    /// else, which is a misleading-price rejection.
    private let packs: [(productID: String, fallback: String)] = [
        (ProductID.vialsSmall, "$4.99"),
        (ProductID.vialsMedium, "$10.99"),
        (ProductID.vialsLarge, "$24.99"),
    ]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                RoomNavBar(title: "The Vials") { model.go(.shelf) }
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("The Vials")
                            .font(InkFont.display(34))
                            .foregroundStyle(room.heading)
                        Text("Moving-picture credits, sealed in wax until you spend them.")
                            .font(InkFont.bodyItalic(16))
                            .foregroundStyle(room.dim)
                            .padding(.top, 6)

                        balance
                            .padding(.vertical, 34)

                        HStack(alignment: .bottom, spacing: 16) {
                            ForEach(Array(packs.enumerated()), id: \.offset) { index, pack in
                                packCard(pack: pack, big: index == 2, index: index)
                            }
                        }
                        .task { await model.refreshWallet() }

                        refundNote
                            .padding(.top, 24)
                    }
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
            ?? "Counting your vials.")
    }

    /// The free clips are named plainly: they are the reason a first-time
    /// reader never meets this room before they have seen what it buys.
    private var balanceCaption: String {
        guard let free = model.freeClipsRemaining else { return "moments remain" }
        if free > 0 {
            return free == 1 ? "moments remain · 1 gifted" : "moments remain · \(free) gifted"
        }
        return "moments remain"
    }

    private func packCard(
        pack: (productID: String, fallback: String), big: Bool, index: Int
    ) -> some View {
        let count = ProductID.creditAmount(for: pack.productID) ?? 0
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
                withAnimation { model.buyVials(pack.productID) }
            } label: {
                Text("Buy · \(model.displayPrice(for: pack.productID, fallback: pack.fallback))")
                    .font(InkFont.bodySemiBold(15))
                    .foregroundStyle(Color(hex: 0x2A1C0A))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Ink.candleBright, Ink.candle], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Ink.candle.opacity(0.55), radius: 6, y: 4)
                    )
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(
                "Buy \(count) vials for \(model.displayPrice(for: pack.productID, fallback: pack.fallback))"
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

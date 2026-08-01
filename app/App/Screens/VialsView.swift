import SwiftUI
import InkMoney

/// The credit wallet: moving-picture credits as wax-sealed vials.
/// Off the shelf for v1 — the moving-picture modality ships flag-off, so the
/// shop that funds it stays behind the curtain (PRD kill-switch rule). The
/// screen stays wired for the DEBUG routes and the modality's return.
struct VialsView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room

    private let packs: [(count: Int, productID: String, fallback: String)] = [
        (10, ProductID.credits10, "$4.99"),
        (30, ProductID.credits30, "$11.99"),
        (100, ProductID.credits100, "$29.99"),
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

    private var balance: some View {
        HStack(spacing: 22) {
            VialView(width: 46, height: 78, fill: 0.38)
                .shadow(color: Ink.candle.opacity(0.12), radius: 12)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(model.credits)")
                    .font(InkFont.display(44))
                    .foregroundStyle(room.heading)
                    .contentTransition(.numericText())
                SmallCapsLabel(
                    text: "moments remain · 1 gifted at binding",
                    size: 12, tracking: 1.7, color: room.dim
                )
            }
        }
    }

    private func packCard(
        pack: (count: Int, productID: String, fallback: String), big: Bool, index: Int
    ) -> some View {
        VStack(spacing: 0) {
            VialView(
                width: 22 + CGFloat(index) * 9,
                height: 46 + CGFloat(index) * 15,
                fill: 0.55
            )
            .frame(height: 84, alignment: .bottom)

            Text("\(pack.count)")
                .font(InkFont.display(28))
                .foregroundStyle(room.heading)
                .padding(.top, 14)
            SmallCapsLabel(text: "moments", size: 11, tracking: 1.5, color: room.dim)
                .padding(.top, 4)
                .padding(.bottom, 18)

            Button {
                withAnimation { model.buy(pack: pack.count) }
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

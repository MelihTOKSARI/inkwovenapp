import SwiftUI
import InkMoney

/// "Bind the notebook to you" — the in-fiction subscription page, backed by
/// the real StoreKit 2 store: storefront-localized prices, a working restore,
/// and the terms/privacy sheet App Review expects behind a paywall.
struct PaywallView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                RoomNavBar(title: "Binding", backLabel: "back") { model.go(.shelf) }
                ScrollView(showsIndicators: false) {
                    parchmentSheet
                        .frame(maxWidth: 540)
                        .padding(.top, 36)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 60)
                }
            }

            if model.showBindConfirm {
                confirmSheet
            }
            if model.showPolicies {
                PolicySheet { model.showPolicies = false }
            }
            PurchaseNoteOverlay(
                state: model.purchaseState,
                successTitle: "The binding holds",
                successBody: "The notebook is yours now — every page kept, and the ink never resting.",
                successAction: "to the shelf",
                onDismiss: { model.clearPurchaseNote() },
                onSuccess: {
                    model.clearPurchaseNote()
                    model.go(.shelf)
                }
            )
        }
    }

    private var parchmentSheet: some View {
        VStack(spacing: 0) {
            Text("Bind the notebook\nto you")
                .font(InkFont.display(34))
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("An unbound notebook forgets by morning. A bound one keeps every page, and never rests the ink.")
                .font(InkFont.bodyItalic(16))
                .foregroundStyle(Color(hex: 0x7A6A4D))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 400)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                benefit("Endless moments — the ink never has to rest.")
                benefit("Every page kept — nothing fades at thirty days.")
                benefit("Pictures develop freely, page after page.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 26)

            // Both plans in one view, period beside every price, and the
            // monthly saving stated outright: $4.99 looks smaller than $9.99
            // while costing 2.2× as much, and a reviewer who has to do that
            // arithmetic reads the layout as a dark pattern (3.1.2).
            HStack(spacing: 12) {
                planCard(
                    .weekly, name: "Seven nights",
                    price: model.displayPrice(for: ProductID.plusWeekly, fallback: "$4.99"),
                    period: "/wk", tag: "3-day free trial"
                )
                planCard(
                    .monthly, name: "One moon",
                    price: model.displayPrice(for: ProductID.plusMonthly, fallback: "$9.99"),
                    period: "/mo", tag: "save 54% · best"
                )
            }
            .padding(.bottom, 22)

            sealCTA

            // The trial's full terms, stated where the seal is pressed — not
            // only inside a tag on the plan card.
            Text(trialDisclosure)
                .font(InkFont.body(12.5))
                .foregroundStyle(Color(hex: 0x8A7658))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)

            HStack(spacing: 24) {
                linkText("Restore a binding") { model.restorePurchases() }
                linkText("Terms & privacy") { model.showPolicies = true }
            }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 44, leading: 46, bottom: 36, trailing: 46))
        .background(
            RadialGradient(
                stops: [
                    .init(color: Ink.parchmentBright, location: 0),
                    .init(color: Ink.parchment, location: 0.55),
                    .init(color: Ink.parchmentDeep, location: 1),
                ],
                center: UnitPoint(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: 700
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.7), radius: 40, y: 20)
            .shadow(color: Ink.candle.opacity(0.14), radius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(Ink.wax.opacity(0.12), lineWidth: 1)
        )
    }

    private var trialDisclosure: String {
        switch model.selectedPlan {
        case .weekly:
            "Free for 3 days, then \(model.displayPrice(for: ProductID.plusWeekly, fallback: "$4.99")) a week. Renews until cancelled in Settings."
        case .monthly:
            "\(model.displayPrice(for: ProductID.plusMonthly, fallback: "$9.99")) a month. Renews until cancelled in Settings."
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("❦").font(InkFont.body(17)).foregroundStyle(Ink.wax)
            Text(text)
                .font(InkFont.body(16))
                .foregroundStyle(Ink.ink)
                .lineSpacing(3)
        }
    }

    private func planCard(
        _ plan: AppModel.Plan, name: String, price: String, period: String, tag: String?
    ) -> some View {
        let selected = model.selectedPlan == plan
        return Button { model.selectedPlan = plan } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).font(InkFont.body(15)).foregroundStyle(Ink.ink)
                    Spacer()
                    Circle()
                        .strokeBorder(selected ? Ink.wax : Ink.ink.opacity(0.3), lineWidth: 2)
                        .background(
                            Circle().fill(selected ? Ink.wax : .white).padding(selected ? 5 : 2)
                        )
                        .frame(width: 20, height: 20)
                }
                (Text(price).font(InkFont.display(26)).foregroundStyle(Ink.ink)
                    + Text(period).font(InkFont.body(14)).foregroundStyle(Color(hex: 0x7A6A4D)))
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Ink.wax.opacity(0.1) : Color(hex: 0xFFFDF7))
                    .shadow(color: selected ? Ink.wax.opacity(0.55) : .clear, radius: 10, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Ink.wax : Ink.ink.opacity(0.2), lineWidth: 2)
            )
            .overlay(alignment: .topLeading) {
                if let tag {
                    SmallCapsLabel(text: tag, size: 10, tracking: 1.2, color: Ink.parchment)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Ink.wax))
                        .offset(x: 14, y: -9)
                }
            }
        }
        .buttonStyle(PressScaleStyle())
    }

    private var sealCTA: some View {
        Button { model.showBindConfirm = true } label: {
            HStack(spacing: 14) {
                WaxSeal(diameter: 44)
                Text("Press the seal to bind")
                    .font(InkFont.display(21))
                    .foregroundStyle(Ink.parchment)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Ink.wax, Ink.waxDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Ink.wax.opacity(0.6), radius: 13, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleStyle(scale: 0.985))
    }

    private func linkText(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(InkFont.body(13))
                .foregroundStyle(Ink.wax)
                .underline()
                .frame(minHeight: 44)
        }
    }

    // MARK: - Confirm

    private var confirmSheet: some View {
        ZStack {
            Color(hex: 0x080503, opacity: 0.66)
                .ignoresSafeArea()
                .onTapGesture { model.showBindConfirm = false }

            RoomCard(borderOpacity: 0.24) {
                VStack(spacing: 0) {
                    Text("Confirm the binding")
                        .font(InkFont.display(24))
                        .foregroundStyle(room.heading)
                    Text("\(trialDisclosure) Charged to your Apple account.")
                        .font(InkFont.body(15))
                        .foregroundStyle(Color(hex: 0xB8A684))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 10)
                        .padding(.bottom, 22)
                    HStack(spacing: 10) {
                        confirmButton("Not yet", prominent: false) {
                            model.showBindConfirm = false
                        }
                        confirmButton("Bind it", prominent: true) {
                            // The commitment press; the verdict pulse follows
                            // from PurchaseNoteOverlay when StoreKit answers.
                            model.confirmBind()
                        }
                    }
                }
                .padding(28)
            }
            .frame(maxWidth: 380)
            .padding(30)
        }
        .transition(.opacity)
    }

    private func confirmButton(_ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(InkFont.body(15))
                .foregroundStyle(prominent ? Ink.parchment : Color(hex: 0xC9B48A))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            prominent
                                ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x9A4340), Ink.wax], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color.white.opacity(0.05))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(prominent ? .clear : room.accent.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(PressScaleStyle())
    }
}

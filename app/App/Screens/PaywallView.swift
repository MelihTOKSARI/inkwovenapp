import SwiftUI
import InkMoney

/// "Bind the notebook to you" — the in-fiction subscription page, backed by
/// the real StoreKit 2 store: storefront-localized prices, a working restore,
/// and the terms/privacy sheet App Review expects behind a paywall.
struct PaywallView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room
    /// VoiceOver lands on the confirm question when the sheet rises (A-3).
    @AccessibilityFocusState private var confirmFocused: Bool

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
                // The palette's faded ink (audit M-17): #7A6A4D measured a
                // marginal 4.40:1 on the parchment; inkFaded holds 5.55.
                .foregroundStyle(Ink.inkFaded)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 400)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 12) {
                benefit("Endless moments — the ink never has to rest.")
                benefit("Every page kept — nothing fades at thirty days.")
                // Scoped to the one Book that develops (audit M-20): only
                // the Artist makes pictures, and Plus rests the bath after
                // eight in a day — "freely, page after page" promised more
                // than either.
                benefit("The Artist's pictures develop, day after day.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 26)

            // Both plans in one view, period beside every price, and the
            // monthly saving stated outright: $4.99 looks smaller than $9.99
            // while costing 2.2× as much, and a reviewer who has to do that
            // arithmetic reads the layout as a dark pattern (3.1.2).
            //
            // Prices are the storefront's own or a placeholder — never a USD
            // literal (audit C-3), and the trial tag appears only when THIS
            // Apple ID is actually eligible for the introductory offer (C-2).
            HStack(spacing: 12) {
                planCard(
                    .weekly, name: "Seven nights",
                    price: weeklyPrice ?? "—",
                    period: "/wk",
                    tag: model.weeklyTrialEligible == true ? "3-day free trial" : nil
                )
                planCard(
                    .monthly, name: "One moon",
                    price: monthlyPrice ?? "—",
                    period: "/mo", tag: monthlySavingsTag
                )
            }
            .padding(.bottom, 22)

            sealCTA

            if model.storeFetchFailed && !pricesReady {
                storefrontRetry
            } else {
                // The trial's full terms, stated where the seal is pressed —
                // not only inside a tag on the plan card.
                Text(trialDisclosure)
                    .font(InkFont.body(12.5))
                    // Small print in the palette's faded ink (audit M-17):
                    // #8A7658 at 12.5pt measured 3.65:1 on the parchment;
                    // inkFaded holds ≥4.5 across the whole sheet gradient.
                    .foregroundStyle(Ink.inkFaded)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 12)
            }

            HStack(spacing: 24) {
                linkText("Restore a binding") { model.restorePurchases() }
                linkText("Terms & privacy") { model.showPolicies = true }
            }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 44, leading: 46, bottom: 36, trailing: 46))
        // The launch fetch can have failed (offline launch, IAP records still
        // propagating) — re-ask the storefront every time the paywall opens.
        .task { await model.refreshStore() }
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

    private var weeklyPrice: String? { model.storePrices[ProductID.plusWeekly] }
    private var monthlyPrice: String? { model.storePrices[ProductID.plusMonthly] }
    /// The seal may not be pressed until the storefront has answered with
    /// real prices — a purchase sheet reached from a placeholder is exactly
    /// the productUnavailable dead end the audit describes (C-3).
    private var pricesReady: Bool { weeklyPrice != nil && monthlyPrice != nil }

    /// "save 54%" is arithmetic now, not copy (audit H-4): weekly annualised
    /// (52×) against monthly (12×), from the storefront's own decimals — a
    /// storefront whose ratio differs from the US one gets its own truth. No
    /// tag at all until both real prices are in hand, and none when the
    /// arithmetic cannot honestly call the moon the better bargain.
    private var monthlySavingsTag: String? {
        guard let weekly = model.storeAmounts[ProductID.plusWeekly],
              let monthly = model.storeAmounts[ProductID.plusMonthly],
              pricesReady, weekly > 0 else { return nil }
        let yearOfWeeks = NSDecimalNumber(decimal: weekly).doubleValue * 52
        let yearOfMoons = NSDecimalNumber(decimal: monthly).doubleValue * 12
        let saved = (yearOfWeeks - yearOfMoons) / yearOfWeeks
        guard saved >= 0.005 else { return nil }
        return "save \(Int((saved * 100).rounded()))% · best"
    }

    /// The storefront was asked and did not answer (audit L-13): the seal
    /// cannot be pressed, so the page says so and offers the asking again —
    /// "waking…" forever was indistinguishable from broken.
    private var storefrontRetry: some View {
        VStack(spacing: 12) {
            Text("The storefront did not answer — the road to it may be dark.")
                .font(InkFont.bodyItalic(14))
                .foregroundStyle(Ink.inkFaded)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                Task { await model.refreshStore() }
            } label: {
                Text("ask the storefront again")
                    .font(InkFont.body(14))
                    .foregroundStyle(Ink.inkFaded)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(
                        Capsule()
                            .fill(Ink.ink.opacity(0.06))
                            .overlay(Capsule().stroke(Ink.ink.opacity(0.18), lineWidth: 1))
                    )
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityHint("Asks the App Store for its prices again.")
        }
        .padding(.top, 14)
    }

    private var trialDisclosure: String {
        switch model.selectedPlan {
        case .weekly:
            guard let price = weeklyPrice else {
                return "Fetching your storefront's price — a moment."
            }
            // The trial clause appears only for an Apple ID that will
            // actually receive it (audit C-2).
            return model.weeklyTrialEligible == true
                ? "Free for 3 days, then \(price) a week. Renews until cancelled in Settings."
                : "\(price) a week. Renews until cancelled in Settings."
        case .monthly:
            guard let price = monthlyPrice else {
                return "Fetching your storefront's price — a moment."
            }
            return "\(price) a month. Renews until cancelled in Settings."
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // Ornament only — VoiceOver spoke "floral heart" before every
            // benefit line (audit A-7).
            Text("❦").font(InkFont.body(17)).foregroundStyle(Ink.wax)
                .accessibilityHidden(true)
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
        // Selection was expressed only visually (audit A-2): a VoiceOver
        // user could not tell which plan the seal was about to charge.
        // One element, the trait carrying selection, the value carrying
        // what this plan actually costs.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)\(tag.map { ". \($0)" } ?? "")")
        .accessibilityValue("\(price) \(period == "/wk" ? "a week" : "a month")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selected ? "The selected plan." : "Selects this plan.")
    }

    private var sealCTA: some View {
        Button { model.showBindConfirm = true } label: {
            HStack(spacing: 14) {
                WaxSeal(diameter: 44)
                Text(pricesReady ? "Press the seal to bind" : "The storefront is waking…")
                    .font(InkFont.display(21))
                    .foregroundStyle(Ink.parchment)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Ink.wax, Ink.waxDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: pricesReady ? Ink.wax.opacity(0.6) : .clear, radius: 13, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.14), lineWidth: 1)
            )
            .opacity(pricesReady ? 1 : 0.55)
        }
        .buttonStyle(PressScaleStyle(scale: 0.985))
        // No purchase path until real storefront prices exist (audit C-3) —
        // the sheet would only answer productUnavailable.
        .disabled(!pricesReady)
        .accessibilityHint(pricesReady
            ? "Opens the purchase confirmation."
            : "Waiting for the App Store to report prices.")
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
                        .accessibilityFocused($confirmFocused)
                    Text("\(trialDisclosure) Charged to your Apple account.")
                        .font(InkFont.body(15))
                        // Theme-following (audit H-6): the hardcoded #B8A684
                        // read at ~2:1 on the daylight card.
                        .foregroundStyle(room.text)
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
        // A purchase confirmation may not leave the paywall behind it
        // swipe-reachable (audit A-3).
        .accessibilityAddTraits(.isModal)
        .onAppear { confirmFocused = true }
    }

    private func confirmButton(_ label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(InkFont.body(15))
                // theme-following for the quiet option (audit H-6)
                .foregroundStyle(prominent ? Ink.parchment : room.text)
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

import SwiftUI
import StoreKit
import InkAnalytics

/// The Drawer: settings kept in the room's fiction. Hand, voice, options,
/// books & shelf curation, account.
struct DrawerView: View {
    @Bindable var model: AppModel
    let archive: PageArchive
    let analytics: Analytics
    /// "Delete all pages" must cover the unsent ones too (audit D-1): a
    /// draft is the user's ink as much as an archived page is.
    var drafts: (any PageDraftStoring)?
    @Environment(\.room) private var room

    /// A generated export, ready for the share sheet.
    private struct ExportItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    @State private var exportItem: ExportItem?
    /// Marginalia for the rare failures: nothing to export, a wipe that
    /// could not finish. Never a raw error string.
    @State private var drawerNote: String?
    /// The "Written in" row folds its nine choices away until asked.
    @State private var showHands = false
    /// The ritual's hour row folds its wheel away the same way.
    @State private var showRitualTime = false

    private let inkChoices: [UInt32] = [0x2E2418, 0x6B4A2B, 0x1F5A63, 0x7A2E2B]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                RoomNavBar(title: "The Drawer") { model.go(.shelf) }
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(spacing: 5) {
                            Text("The Drawer")
                                .font(InkFont.display(32))
                                .foregroundStyle(room.heading)
                            SmallCapsLabel(text: "Settings", size: 12, tracking: 3, color: room.dim)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 26)

                        section("The Hand") {
                            row("Ink colour", divider: true) { inkSwatches }
                            row("Left-handed mode") {
                                GoldToggle(isOn: model.leftHanded) { model.leftHanded.toggle() }
                            }
                        }

                        section("The Voice") {
                            row("Reply length", divider: true) {
                                SegmentedPills(
                                    options: AppModel.ReplyLength.allCases.map { ($0.rawValue, $0) },
                                    selection: model.replyLength
                                ) { model.replyLength = $0 }
                            }
                            handRow
                            if showHands {
                                shelfHandPicker
                            }
                            row("Pages fade after") {
                                Text("30 days").font(InkFont.body(15)).foregroundStyle(room.accent)
                            }
                        }

                        section("Options") {
                            row("Theme", divider: true) {
                                SegmentedPills(
                                    options: [("Candlelight", RoomVariant.candlelight), ("Daylight", .daylight)],
                                    selection: model.themeVariant
                                ) { choice in
                                    withAnimation(.easeInOut(duration: 0.4)) { model.themeVariant = choice }
                                }
                            }
                            row("Landscape layout", divider: true) {
                                SegmentedPills(
                                    options: [("Two-page", true), ("Single", false)],
                                    selection: model.spreadLayout
                                ) { model.spreadLayout = $0 }
                            }
                            // Only where the hardware can actually answer. No
                            // iPad has a Taptic Engine, so on the device this
                            // app is built for this switch did nothing at all
                            // — a settings row that claims a capability the
                            // device hasn't got is worse than no row.
                            //
                            // Deliberately its own row where it does appear,
                            // next to Reduce motion rather than folded into
                            // it: a haptic is not motion, and someone who
                            // wants the room still may still want to feel the
                            // reply land.
                            if Feel.isSupported {
                                row("A gentle pulse", divider: true) {
                                    GoldToggle(isOn: Feel.shared.hapticsEnabled) {
                                        Feel.shared.hapticsEnabled.toggle()
                                    }
                                    .accessibilityLabel("A gentle pulse")
                                    .accessibilityHint("Haptic feedback at the few moments the room marks.")
                                }
                            }
                            row("Reduce motion") {
                                GoldToggle(isOn: model.reduceMotionOverride) {
                                    model.reduceMotionOverride.toggle()
                                }
                            }
                        }

                        section("The Ritual") {
                            row("The evening ritual", divider: true) {
                                GoldToggle(isOn: model.ritualEffectivelyOn) { ritualToggleTapped() }
                                    .accessibilityLabel("The evening ritual")
                            }
                            if model.ritualAuthorization == .denied {
                                QuietBanner(
                                    text: "The device keeps its bell silenced — Settings can allow it again.",
                                    size: 13.5
                                )
                                .padding(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ritualTimeRow
                            if showRitualTime {
                                ritualTimePicker
                            }
                        }

                        booksAndShelf

                        // No account section: v1 has no sign-in of any kind —
                        // the notebook works anonymously, and a Sign in with
                        // Apple button with nothing behind it (task F4) may
                        // not ship as furniture.
                        section("The Pages") {
                            row("Export", divider: drawerNote != nil) {
                                HStack(spacing: 8) {
                                    exportButton("PDF") { try PageExporter.pdfFile(entries: archive.entries) }
                                    exportButton("Text") { try PageExporter.textFile(entries: archive.entries) }
                                }
                            }
                            if let note = drawerNote {
                                QuietBanner(text: note, size: 13.5)
                                    .padding(EdgeInsets(top: 0, leading: 18, bottom: 12, trailing: 18))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        section(nil) {
                            Button {
                                // A bound user gets StoreKit's manage sheet —
                                // the paywall is a place to buy, not cancel.
                                if model.bound {
                                    model.showManageSubs = true
                                } else {
                                    model.go(.paywall)
                                }
                            } label: {
                                HStack {
                                    Text("Subscription").font(InkFont.body(16)).foregroundStyle(room.text)
                                    Spacer()
                                    Text("\(model.bound ? "Manage" : "Bind the notebook") ›")
                                        .font(InkFont.body(15))
                                        .foregroundStyle(room.accent)
                                }
                                .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { hairline }
                            // The vials are a separate purse from the binding:
                            // the subscription buys ink and pictures, a vial
                            // buys one moving picture. Two rows, because
                            // conflating them is how someone pays twice for
                            // what they thought they already had.
                            Button { model.openVials(from: .drawer) } label: {
                                HStack {
                                    Text("The Vials").font(InkFont.body(16)).foregroundStyle(room.text)
                                    Spacer()
                                    Text("\(vialsSummary) ›")
                                        .font(InkFont.body(15))
                                        .foregroundStyle(room.accent)
                                }
                                .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) { hairline }
                            .accessibilityLabel("The Vials. \(vialsSummary)")
                            .accessibilityHint("Moving-picture credits.")
                            Button { model.showDeleteConfirm = true } label: {
                                HStack {
                                    Text("Delete all pages")
                                        .font(InkFont.bodyMedium(16))
                                        .foregroundStyle(Color(hex: 0xC0392B))
                                    Spacer()
                                    Text("›").foregroundStyle(Color(hex: 0xC0392B))
                                }
                                .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        VStack(spacing: 10) {
                            Text("Inkwoven writes fiction on your behalf with a spirit of ink — not a person, and not advice.")
                                .font(InkFont.bodyItalic(13))
                                .foregroundStyle(room.dim)
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                            Button { model.showPolicies = true } label: {
                                Text("Read the privacy note, terms & AI disclosure")
                                    .font(InkFont.body(13))
                                    .foregroundStyle(room.accent)
                                    .underline()
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            // Published contact (guideline 1.2): a person must
                            // be reachable without leaving the app to hunt.
                            Link(destination: SupportContact.mailURL) {
                                Text("Write to the binder")
                                    .font(InkFont.body(13))
                                    .foregroundStyle(room.accent)
                                    .underline()
                                    .frame(minHeight: 44)
                            }
                            .accessibilityLabel("Write to the binder")
                            .accessibilityHint("Opens an email to \(SupportContact.email).")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                    }
                    .frame(maxWidth: 600)
                    .padding(EdgeInsets(top: 32, leading: 44, bottom: 60, trailing: 44))
                    .frame(maxWidth: .infinity)
                }
            }

            if model.showDeleteConfirm {
                deleteConfirm
            }
            if model.showPolicies {
                PolicySheet { model.showPolicies = false }
            }
        }
        // So the vials row states a balance rather than an invitation to fill
        // a purse that is already full.
        .task { await model.refreshWallet() }
        .manageSubscriptionsSheet(isPresented: $model.showManageSubs)
        .sheet(item: $exportItem) { item in
            ShareSheet(items: [item.url])
        }
    }

    // MARK: - Section scaffolding

    private func section(_ title: String?, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                SmallCapsLabel(text: title, size: 11, tracking: 2.2, color: room.dim)
                    .padding(.leading, 4)
            }
            RoomCard {
                VStack(spacing: 0) { rows() }
            }
        }
        .padding(.bottom, 22)
    }

    private func row(
        _ label: String, divider: Bool = false, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Text(label).font(InkFont.body(16)).foregroundStyle(room.text)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
        .overlay(alignment: .bottom) {
            if divider { hairline }
        }
    }

    private var hairline: some View {
        Rectangle().fill(room.accent.opacity(0.1)).frame(height: 1)
    }

    /// What the row says before it is tapped. The free clips are named while
    /// they last — they are the reason a new reader has no business in the
    /// shop yet, and saying so is friendlier than showing them a zero.
    private var vialsSummary: String {
        guard let balance = model.vialBalance else { return "Fill the vials" }
        if let free = model.freeClipsRemaining, free > 0, balance == 0 {
            return free == 1 ? "1 gifted moment" : "\(free) gifted moments"
        }
        if balance == 0 { return "Fill the vials" }
        return balance == 1 ? "1 moment" : "\(balance) moments"
    }

    // MARK: - The Voice: script hand

    /// One hand for the whole shelf. A single Book re-dressed from its own
    /// page reads here as "a mixed shelf".
    private var handRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showHands.toggle() }
        } label: {
            HStack(spacing: 12) {
                Text("Written in").font(InkFont.body(16)).foregroundStyle(room.text)
                Spacer(minLength: 8)
                Text(shelfHandName)
                    .font(InkFont.body(15))
                    .foregroundStyle(room.accent)
                Text("›")
                    .font(InkFont.body(15))
                    .foregroundStyle(room.accent)
                    .rotationEffect(.degrees(showHands ? 90 : 0))
            }
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { hairline }
        .accessibilityLabel("Written in. \(shelfHandName)")
        .accessibilityHint(showHands ? "Closes the hand choices." : "Opens the hand choices.")
    }

    private var shelfHandName: String {
        switch model.shelfHand {
        case .own: return "Each Book's own"
        case .uniform(let id): return Hand.by(id: id)?.name ?? "Each Book's own"
        case .mixed: return "A mixed shelf"
        }
    }

    private var shelfHandPicker: some View {
        let uniform: String? = if case .uniform(let id) = model.shelfHand { id } else { nil }
        return HandPickerList(
            ownLabel: "Each Book's own",
            ownHand: nil,
            selection: uniform,
            ownSelected: model.shelfHand == .own
        ) { model.setAllHands($0) }
            .overlay(alignment: .bottom) { hairline }
    }

    // MARK: - The Ritual

    /// One tap, three meanings: flip the wish when the device allows it, walk
    /// to Settings when it does not, or make the one-and-only ask when the
    /// writer got here before their first answered page.
    private func ritualToggleTapped() {
        switch model.ritualAuthorization {
        case .granted:
            model.ritualEnabled.toggle()
            if !model.ritualEnabled {
                withAnimation(.easeInOut(duration: 0.25)) { showRitualTime = false }
            }
        case .denied:
            // The system prompt cannot be shown twice; the only way back on.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .notDetermined:
            Task {
                if let granted = await model.promptRitualIfNeeded() {
                    await analytics.track(.notificationPermissionAnswered(granted: granted))
                } else {
                    // Asked before but never resolved — re-read where we stand.
                    await model.rearmRitual()
                }
            }
        }
    }

    private var ritualTimeLabel: String {
        model.ritualTimeDate.formatted(date: .omitted, time: .shortened)
    }

    private var ritualTimeRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showRitualTime.toggle() }
        } label: {
            HStack(spacing: 12) {
                Text("At the hour of").font(InkFont.body(16)).foregroundStyle(room.text)
                Spacer(minLength: 8)
                Text(ritualTimeLabel)
                    .font(InkFont.body(15))
                    .foregroundStyle(room.accent)
                Text("›")
                    .font(InkFont.body(15))
                    .foregroundStyle(room.accent)
                    .rotationEffect(.degrees(showRitualTime ? 90 : 0))
            }
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.ritualEffectivelyOn)
        .opacity(model.ritualEffectivelyOn ? 1 : 0.45)
        .overlay(alignment: .bottom) {
            if showRitualTime { hairline }
        }
        .accessibilityLabel("At the hour of. \(ritualTimeLabel)")
        .accessibilityHint(showRitualTime ? "Closes the hour wheel." : "Opens the hour wheel.")
    }

    /// The first system picker in the room — an arbitrary hour needs a real
    /// wheel, not another row of pills. It follows the room's light so its
    /// digits stay legible on both papers.
    private var ritualTimePicker: some View {
        DatePicker(
            "The hour of the evening ritual",
            selection: Binding(
                get: { model.ritualTimeDate },
                set: { model.setRitualTime(from: $0) }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .environment(\.colorScheme, model.themeVariant == .daylight ? .light : .dark)
        .padding(.horizontal, 18)
    }

    // MARK: - The Hand

    private var inkSwatches: some View {
        HStack(spacing: 11) {
            ForEach(inkChoices, id: \.self) { hex in
                let selected = model.inkColorHex == hex
                Button { model.inkColorHex = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().stroke(
                                selected ? Ink.candle : .white.opacity(0.18),
                                lineWidth: selected ? 2 : 1
                            )
                            .padding(selected ? -3 : 0)
                        )
                        .frame(minWidth: 34, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ink colour")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// Generates the file on tap and hands it to the share sheet. The Keeper's
    /// pages never pass through here: `archive.entries` is the open shelf only.
    private func exportButton(_ label: String, generate: @escaping () throws -> URL) -> some View {
        Button {
            do {
                exportItem = ExportItem(url: try generate())
                drawerNote = nil
            } catch PageExporter.ExportError.nothingToExport {
                drawerNote = "There are no pages to carry out yet — the Keeper's stay behind their seal."
            } catch {
                drawerNote = "The pages would not gather this time. Try again in a moment."
            }
        } label: {
            Text(label)
                .font(InkFont.body(14))
                .foregroundStyle(room.accent)
                .padding(.horizontal, 15)
                .frame(minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(room.accent.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(room.accent.opacity(0.42), lineWidth: 1))
                )
        }
        .buttonStyle(PressScaleStyle(scale: 0.96))
        .accessibilityLabel("Export pages as \(label)")
    }

    // MARK: - Books & Shelf

    private var booksAndShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsLabel(text: "Books & Shelf", size: 11, tracking: 2.2, color: room.dim)
                Spacer()
                Text("\(Book.all.count - model.hiddenBooks.count) on the shelf · \(model.hiddenBooks.count) hidden")
                    .font(InkFont.body(12))
                    .foregroundStyle(room.dim)
            }
            .padding(.horizontal, 4)

            RoomCard {
                VStack(spacing: 0) {
                    ForEach(Array(Book.all.enumerated()), id: \.element.id) { index, book in
                        bookRow(book, divider: index < Book.all.count - 1)
                    }
                }
            }

            Text("Hidden books stay in your notebook — they only leave the shelf.")
                .font(InkFont.bodyItalic(13))
                .foregroundStyle(room.dim)
                .padding(.leading, 4)
        }
        .padding(.bottom, 22)
    }

    private func bookRow(_ book: Book, divider: Bool) -> some View {
        let hidden = model.hiddenBooks.contains(book.id)
        let state = hidden ? "Hidden from the shelf"
            : book.locked ? "Private · opens with Face ID"
            : book.suggested ? "Suggested tonight"
            : book.resting ? "Resting"
            : "On the shelf"
        return HStack(spacing: 14) {
            UnevenRoundedRectangle(
                topLeadingRadius: 2, bottomLeadingRadius: 2,
                bottomTrailingRadius: 3, topTrailingRadius: 3
            )
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: book.spineTop, location: 0),
                        .init(color: book.accent, location: 0.42),
                        .init(color: book.spineBottom, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 26, height: 34)
            .overlay(
                Text(book.monogram)
                    .font(InkFont.display(14))
                    .foregroundStyle(Ink.goldTitleTop)
            )
            .opacity(hidden ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.name)
                    .font(InkFont.body(16))
                    .foregroundStyle(room.text)
                    .opacity(hidden ? 0.6 : 1)
                Text(state)
                    .font(InkFont.bodyItalic(12.5))
                    .foregroundStyle(hidden ? room.dim : room.accent)
            }
            Spacer(minLength: 8)
            GoldToggle(isOn: !hidden) {
                withAnimation { model.toggleShelf(book: book) }
            }
            .accessibilityLabel("\(book.name) on the shelf")
        }
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        .overlay(alignment: .bottom) {
            if divider { hairline }
        }
    }

    // MARK: - Delete confirm

    private var deleteConfirm: some View {
        ZStack {
            Color(hex: 0x080503, opacity: 0.66)
                .ignoresSafeArea()
                .onTapGesture { model.showDeleteConfirm = false }

            VStack(spacing: 0) {
                Text("Delete every page?")
                    .font(InkFont.display(24))
                    .foregroundStyle(room.heading)
                Text("This tears out every page in every Book. The ink cannot be recovered.")
                    .font(InkFont.body(15))
                    .foregroundStyle(Color(hex: 0xB8A684))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.bottom, 22)
                HStack(spacing: 10) {
                    Button {
                        model.showDeleteConfirm = false
                    } label: {
                        Text("Keep them")
                            .font(InkFont.body(15))
                            .foregroundStyle(Color(hex: 0xC9B48A))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(room.accent.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .buttonStyle(PressScaleStyle())
                    Button {
                        let clean = archive.deleteAll()
                        // The unsent pages go with the archived ones — a
                        // draft left behind would resurrect on the next
                        // page visit after "delete all" promised otherwise.
                        drafts?.deleteAll()
                        model.revisit = nil
                        model.showDeleteConfirm = false
                        drawerNote = clean
                            ? nil
                            : "Some pages resisted the tearing. Open the Drawer and try once more."
                    } label: {
                        Text("Delete all")
                            .font(InkFont.body(15))
                            .foregroundStyle(Ink.parchment)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Color(hex: 0xA3453A), Ink.dangerEmber], startPoint: .top, endPoint: .bottom))
                            )
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(28)
            .frame(maxWidth: 380)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ink.dangerEmber.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
            )
            .padding(30)
        }
        .transition(.opacity)
    }
}

/// UIActivityViewController, contained in a SwiftUI sheet so the iPad
/// popover-anchor requirement is satisfied by the sheet itself.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

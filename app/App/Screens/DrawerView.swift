import SwiftUI
import AuthenticationServices

/// The Drawer: settings kept in the room's fiction. Hand, voice, options,
/// books & shelf curation, ritual & account.
struct DrawerView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room

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
                            row("Reduce motion") {
                                GoldToggle(isOn: model.reduceMotionOverride) {
                                    model.reduceMotionOverride.toggle()
                                }
                            }
                        }

                        booksAndShelf

                        section("Ritual & Account") {
                            row("Quiet hours", divider: true) {
                                Text("10pm – 8am").font(InkFont.body(15)).foregroundStyle(room.dim)
                            }
                            SignInWithAppleButton(.signIn) { _ in } onCompletion: { _ in
                                // Optional account upgrade (task F4) binds here.
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 44)
                            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
                            .overlay(alignment: .bottom) { hairline }
                            row("Export") {
                                HStack(spacing: 8) {
                                    exportButton("PDF")
                                    exportButton("Text")
                                }
                            }
                        }

                        section(nil) {
                            Button { model.go(.paywall) } label: {
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

                        Text("Inkwoven writes fiction on your behalf with a spirit of ink — not a person, and not advice. Read the privacy note and AI disclosure any time.")
                            .font(InkFont.bodyItalic(13))
                            .foregroundStyle(room.dim)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
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

    private func exportButton(_ label: String) -> some View {
        Button {
            // PDF/text export (task E2) binds here.
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
                        // InkData wipe (task E3) binds here.
                        model.showDeleteConfirm = false
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

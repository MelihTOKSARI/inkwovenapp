import SwiftUI

/// The content shop: covers, inks, papers, and new hands. Purchases bind
/// to StoreKit later; try-on is real — the notebook beside the shelves
/// wears whatever is previewed, so the buyer never loses the context.
struct BinderyView: View {
    @Bindable var model: AppModel
    @Environment(\.room) private var room
    @State private var category = "Covers"
    @State private var tryOn = TryOn()

    struct Item: Identifiable, Equatable {
        let name: String
        let price: String
        let toneHex: UInt32
        let owned: Bool
        /// Book packs bring their own hand; other wares leave these nil.
        var hand: String?
        var handScale: CGFloat = 1
        var line: String?
        var id: String { name }
    }

    /// What the preview notebook is currently wearing, one slot per shelf.
    /// A pack replaces the whole binding, so pack and cover are exclusive.
    struct TryOn: Equatable {
        var cover: Item?
        var ink: Item?
        var paper: Item?
        var pack: Item?

        var isEmpty: Bool {
            cover == nil && ink == nil && paper == nil && pack == nil
        }
    }

    private static let catalog: [(name: String, items: [Item])] = [
        ("Covers", [
            Item(name: "Midnight Calf", price: "$2.99", toneHex: 0x2B2F3D, owned: false),
            Item(name: "Foxed Vellum", price: "$2.99", toneHex: 0xC9B489, owned: true),
            Item(name: "Sea-Green Buckram", price: "$2.99", toneHex: 0x3C5B52, owned: false),
            Item(name: "Oxblood Morocco", price: "$3.99", toneHex: 0x5C211F, owned: false),
        ]),
        ("Inks", [
            Item(name: "Iron Gall", price: "Free", toneHex: 0x2E2418, owned: true),
            Item(name: "Sepia Walnut", price: "$0.99", toneHex: 0x6B4A2B, owned: false),
            Item(name: "Peacock", price: "$0.99", toneHex: 0x1F5A63, owned: false),
            Item(name: "Oxblood", price: "$0.99", toneHex: 0x7A2E2B, owned: false),
        ]),
        ("Papers", [
            Item(name: "Winter Laid", price: "$1.99", toneHex: 0xEEF0E8, owned: false),
            Item(name: "Autumn Foxed", price: "$1.99", toneHex: 0xE7D3AC, owned: false),
            Item(name: "Spring Deckle", price: "$1.99", toneHex: 0xF3EAD6, owned: false),
        ]),
        ("Book Packs", [
            Item(name: "The Cartographer", price: "$4.99", toneHex: 0x4A6B6E, owned: false,
                 hand: "Fondamento-Regular", handScale: 1.05,
                 line: "North of the salt marsh, the road forgets itself."),
            Item(name: "The Confessor", price: "$4.99", toneHex: 0x6E3B34, owned: false,
                 hand: "HomemadeApple-Regular", handScale: 1.0,
                 line: "Tell me only what the night should keep."),
            Item(name: "The Botanist", price: "$4.99", toneHex: 0x5A6B3A, owned: false,
                 hand: "Caveat-Regular", handScale: 1.15,
                 line: "The foxglove opened a day early this year."),
        ]),
    ]

    private var items: [Item] {
        Self.catalog.first { $0.name == category }?.items ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            RoomNavBar(title: "The Bindery") { model.go(.shelf) }
            GeometryReader { geo in
                if geo.size.width >= 860 {
                    HStack(spacing: 0) {
                        catalogScroll
                        Rectangle()
                            .fill(room.accent.opacity(0.14))
                            .frame(width: 1)
                        previewPane
                            .frame(width: min(400, geo.size.width * 0.36))
                    }
                } else {
                    VStack(spacing: 0) {
                        compactPreview
                        Rectangle()
                            .fill(room.accent.opacity(0.14))
                            .frame(height: 1)
                        catalogScroll
                    }
                }
            }
        }
    }

    // MARK: - Catalog

    private var catalogScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Text("The Bindery")
                    .font(InkFont.display(34))
                    .foregroundStyle(room.heading)
                Text("Covers, inks, papers and new hands. Try any on the notebook before it is yours.")
                    .font(InkFont.bodyItalic(16))
                    .foregroundStyle(room.dim)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                categoryChips
                    .padding(.top, 28)
                    .padding(.bottom, 26)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 210), spacing: 20)],
                    spacing: 20
                ) {
                    ForEach(items) { item in
                        itemCard(item)
                    }
                }
            }
            .frame(maxWidth: 840)
            .padding(EdgeInsets(top: 36, leading: 48, bottom: 60, trailing: 48))
            .frame(maxWidth: .infinity)
        }
    }

    private var categoryChips: some View {
        HStack(spacing: 10) {
            ForEach(Self.catalog, id: \.name) { cat in
                let selected = cat.name == category
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { category = cat.name }
                } label: {
                    Text(cat.name)
                        .font(selected ? InkFont.bodySemiBold(13.5) : InkFont.body(13.5))
                        .kerning(0.8)
                        .foregroundStyle(selected ? Color(hex: 0x241A10) : room.text)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(
                            Capsule()
                                .fill(selected ? Ink.candle : .clear)
                                .overlay(
                                    Capsule().stroke(
                                        selected ? Ink.candle : room.accent.opacity(0.38),
                                        lineWidth: 1
                                    )
                                )
                        )
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    private func itemCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Color(hex: item.toneHex)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.16), location: 0),
                        .init(color: .clear, location: 0.44),
                        .init(color: .black.opacity(0.3), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                HStack {
                    LinearGradient(colors: [.black.opacity(0.42), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                    Spacer()
                }
                if item.owned {
                    SmallCapsLabel(text: "owned", size: 10, tracking: 1.1, color: Color(hex: 0xEEF3E6))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Ink.successHerb.opacity(0.92)))
                        .padding(10)
                }
            }
            .aspectRatio(4 / 5, contentMode: .fit)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(InkFont.display(20))
                    .foregroundStyle(room.heading)
                    .lineLimit(2)
                HStack {
                    Text(item.price)
                        .font(InkFont.display(18))
                        .foregroundStyle(room.heading)
                    Spacer()
                    previewButton(item)
                }
                .padding(.top, 14)
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
        }
        .background(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).stroke(room.accent.opacity(0.16), lineWidth: 1)
        )
    }

    private func previewButton(_ item: Item) -> some View {
        let trying = slotItem(for: category) == item
        return Button {
            togglePreview(item)
        } label: {
            SmallCapsLabel(
                text: trying ? "trying" : "preview", size: 11.5, tracking: 1,
                color: trying ? Color(hex: 0x241A10) : room.accent
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(trying ? Ink.candle : .clear)
                    .overlay(
                        Capsule().stroke(
                            trying ? Ink.candle : room.accent.opacity(0.42),
                            lineWidth: 1
                        )
                    )
            )
            // snap the label swap: the ambient try-on animation otherwise
            // morphs PREVIEW↔TRYING glyphs into each other
            .transaction { $0.animation = nil }
        }
        .buttonStyle(PressScaleStyle())
    }

    // MARK: - Try-on state

    private func slotItem(for category: String) -> Item? {
        switch category {
        case "Covers": tryOn.cover
        case "Inks": tryOn.ink
        case "Papers": tryOn.paper
        case "Book Packs": tryOn.pack
        default: nil
        }
    }

    private func togglePreview(_ item: Item) {
        withAnimation(.easeInOut(duration: 0.35)) {
            switch category {
            case "Covers":
                tryOn.cover = tryOn.cover == item ? nil : item
                if tryOn.cover != nil { tryOn.pack = nil }
            case "Inks":
                tryOn.ink = tryOn.ink == item ? nil : item
            case "Papers":
                tryOn.paper = tryOn.paper == item ? nil : item
            case "Book Packs":
                tryOn.pack = tryOn.pack == item ? nil : item
                if tryOn.pack != nil { tryOn.cover = nil }
            default:
                break
            }
        }
    }

    // MARK: - Preview notebook

    private var previewBook: Book { model.activeBook }

    private var coverToneHex: UInt32 {
        tryOn.pack?.toneHex ?? tryOn.cover?.toneHex ?? previewBook.accentHex
    }

    private var paperToneHex: UInt32 {
        tryOn.paper?.toneHex ?? previewBook.paperHex
    }

    private var previewInk: Color {
        tryOn.ink.map { Color(hex: $0.toneHex) } ?? previewBook.ink
    }

    private var previewTitle: String {
        tryOn.pack?.name ?? previewBook.name
    }

    private var previewLine: String {
        tryOn.pack?.line ?? previewBook.opener
    }

    private func previewHandFont(_ base: CGFloat) -> Font {
        if let pack = tryOn.pack, let hand = pack.hand {
            InkFont.hand(hand, base * pack.handScale)
        } else {
            previewBook.handFont(base)
        }
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            SmallCapsLabel(text: "on the notebook", size: 12, tracking: 2.2, color: room.dim)
                .padding(.bottom, 22)
            notebookPreview
                .frame(maxWidth: 310)
            tryingCaption
                .padding(.top, 22)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 40, leading: 30, bottom: 30, trailing: 30))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var compactPreview: some View {
        HStack(alignment: .top, spacing: 22) {
            notebookPreview
                .frame(height: 200)
            VStack(alignment: .leading, spacing: 12) {
                SmallCapsLabel(text: "on the notebook", size: 11, tracking: 2, color: room.dim)
                tryingCaption
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 18, leading: 28, bottom: 18, trailing: 28))
    }

    private var notebookPreview: some View {
        ZStack {
            // the binding
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .mix(coverToneHex, 0.88, 0xFFFFFF), location: 0),
                            .init(color: Color(hex: coverToneHex), location: 0.3),
                            .init(color: .mix(coverToneHex, 0.78, 0x000000), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.14), location: 0),
                            .init(color: .black.opacity(0.06), location: 0.22),
                            .init(color: .black.opacity(0.32), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

            // the page it opens to
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .mix(paperToneHex, 0.96, 0xFFFFFF), location: 0),
                            .init(color: Color(hex: paperToneHex), location: 0.5),
                            .init(color: .mix(paperToneHex, 0.86, 0x6B5A43), location: 1),
                        ],
                        center: UnitPoint(x: 0.2, y: 0),
                        startRadius: 0,
                        endRadius: 480
                    )
                )
                .overlay(alignment: .leading) {
                    // page curvature at the spine
                    LinearGradient(colors: [.black.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .overlay(alignment: .topLeading) { previewPage }
                .padding(EdgeInsets(top: 12, leading: 24, bottom: 12, trailing: 12))
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
        .animation(.easeInOut(duration: 0.35), value: tryOn)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("bindery-preview")
        .accessibilityLabel("Preview notebook: \(previewTitle)")
    }

    private var previewPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallCapsLabel(text: previewTitle, size: 9.5, tracking: 2, color: previewInk.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            LinearGradient(colors: [previewInk.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
                .padding(.top, 7)

            Text(previewLine)
                .font(previewHandFont(19))
                .foregroundStyle(previewInk)
                .opacity(0.92)
                .lineSpacing(4)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .padding(.top, 14)

            Spacer(minLength: 8)

            Line()
                .stroke(previewInk.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(height: 1)
            Text("and I wrote back at once…")
                .font(InkFont.hand("Caveat-Regular", 17))
                .foregroundStyle(previewInk.opacity(0.55))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 16, leading: 22, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Caption under the preview

    private var triedSlots: [(slot: String, item: Item)] {
        var slots: [(String, Item)] = []
        if let cover = tryOn.cover { slots.append(("cover", cover)) }
        if let ink = tryOn.ink { slots.append(("ink", ink)) }
        if let paper = tryOn.paper { slots.append(("paper", paper)) }
        if let pack = tryOn.pack { slots.append(("book", pack)) }
        return slots
    }

    @ViewBuilder
    private var tryingCaption: some View {
        if tryOn.isEmpty {
            Text("Tap preview on any ware and the notebook tries it on, right here.")
                .font(InkFont.bodyItalic(13.5))
                .foregroundStyle(room.dim)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(triedSlots, id: \.slot) { entry in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color(hex: entry.item.toneHex))
                            .overlay(Circle().stroke(room.accent.opacity(0.35), lineWidth: 1))
                            .frame(width: 11, height: 11)
                        SmallCapsLabel(text: entry.slot, size: 9.5, tracking: 1.4, color: room.dim)
                        Text(entry.item.name)
                            .font(InkFont.body(13.5))
                            .foregroundStyle(room.text)
                            .lineLimit(1)
                    }
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { tryOn = TryOn() }
                } label: {
                    SmallCapsLabel(text: "return to your notebook", size: 10.5, tracking: 1.2, color: room.accent)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Capsule().stroke(room.accent.opacity(0.38), lineWidth: 1))
                }
                .buttonStyle(PressScaleStyle())
                .padding(.top, 4)
            }
        }
    }
}

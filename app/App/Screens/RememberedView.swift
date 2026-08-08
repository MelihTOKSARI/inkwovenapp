import SwiftUI
import InkAnalytics
import InkMoney

/// Per-Book timeline of filled pages, read straight from the PageArchive.
/// Each card is a real archived exchange: your ink above the Book's reply.
/// Free tier: pages older than thirty days are ghosted behind the fade line.
struct RememberedView: View {
    @Bindable var model: AppModel
    let archive: PageArchive
    let analytics: Analytics
    @Environment(\.room) private var room
    @State private var query = ""


    private var archived: [PageArchive.Entry] {
        let all = archive.entries(for: model.activeBookID)
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.replyText.localizedCaseInsensitiveContains(trimmed)
                || ($0.typedText?.localizedCaseInsensitiveContains(trimmed) ?? false)
                || Self.dateLabel($0.createdAt).localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func isGhosted(_ entry: PageArchive.Entry) -> Bool {
        !model.bound && Date.now.timeIntervalSince(entry.createdAt) > PageArchive.freeFadeAfter
    }

    var body: some View {
        VStack(spacing: 0) {
            RoomNavBar(title: "Remembered", backLabel: model.backLabel) { model.back() }

            // The head of the room stands still; only the pages scroll.
            VStack(spacing: 0) {
                Text(model.activeBook.name)
                    .font(InkFont.display(32))
                    .foregroundStyle(room.heading)
                Text("Every page you have filled here.")
                    .font(InkFont.bodyItalic(15))
                    .foregroundStyle(room.dim)
                    .padding(.top, 4)

                searchPill
                    .padding(.top, 26)
            }
            .frame(maxWidth: 760)
            .padding(EdgeInsets(top: 36, leading: 56, bottom: 0, trailing: 56))
            .frame(maxWidth: .infinity)

            ScrollView(showsIndicators: false) {
                Group {
                    if archived.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 210), spacing: 18)],
                            spacing: 18
                        ) {
                            ForEach(archived) { entry in
                                archivedCard(entry)
                            }
                        }
                    }
                }
                .frame(maxWidth: 760)
                .padding(EdgeInsets(top: 26, leading: 56, bottom: 60, trailing: 56))
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(room.dim)
            TextField(
                "",
                text: $query,
                prompt: Text("search the pages")
                    .font(InkFont.bodyItalic(15))
                    .foregroundStyle(room.dim)
            )
            .font(InkFont.bodyItalic(15))
            .foregroundStyle(room.heading)
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(room.dim)
                        // A ~20pt glyph was the whole target (audit M-16);
                        // the pill's own height now carries the 44.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: 420)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.04))
                .overlay(Capsule().stroke(room.accent.opacity(0.2), lineWidth: 1))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: query.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(room.dim)
            Text(
                query.isEmpty
                    ? "No pages yet. What you write here returns when the Book answers."
                    : "Nothing in these pages matches “\(query)”."
            )
            .font(InkFont.bodyItalic(15))
            .foregroundStyle(room.dim)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 420)
        .padding(.top, 40)
    }

    /// A real archived exchange: the user's own ink above the Book's reply.
    /// Tapping reopens it on the page; a ghosted page asks to bind first.
    private func archivedCard(_ entry: PageArchive.Entry) -> some View {
        let book = model.activeBook
        let ghosted = isGhosted(entry)
        return Button {
            if ghosted {
                // The funnel counts every road to the paywall, not just the
                // send gate's (audit: paywall-shown undercount).
                Task { await analytics.track(.paywallShown(trigger: PaywallTrigger.archive.rawValue)) }
                model.go(.paywall)
            } else {
                model.revisit = entry
                model.go(.page)
            }
        } label: {
            cardFace(entry, book: book, ghosted: ghosted)
        }
        .buttonStyle(PressScaleStyle())
        // The label used to be the date alone, so every card in the grid
        // announced an identically-shaped string and nothing else — there
        // was no way to find a page without opening each one in turn.
        .accessibilityLabel(spoken(entry, book: book, ghosted: ghosted))
        .accessibilityHint(ghosted
            ? "Bind the notebook to keep this page."
            : "Reopens this exchange on the page.")
    }

    /// The card's contents, spoken. Handwriting has no transcript anywhere in
    /// the schema, so an ink page is named rather than invented.
    private func spoken(_ entry: PageArchive.Entry, book: Book, ghosted: Bool) -> String {
        var parts = ["\(Self.dateLabel(entry.createdAt))."]
        if ghosted { parts.append("Faded at thirty days.") }
        if let typed = entry.typedText, !typed.isEmpty {
            parts.append("You wrote: \(typed).")
        } else if entry.strokeData.isEmpty == false {
            parts.append("Your handwritten page.")
        }
        if !entry.replyText.isEmpty {
            parts.append("\(book.name) answered: \(entry.replyText)")
        }
        return parts.joined(separator: " ")
    }

    private func cardFace(_ entry: PageArchive.Entry, book: Book, ghosted: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 10) {
                SmallCapsLabel(text: Self.dateLabel(entry.createdAt), size: 11, tracking: 1.5, color: Ink.inkFaded)
                    .padding(.top, 6)
                if let ink = InkThumbnail.image(for: entry) {
                    Image(uiImage: ink)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 84, alignment: .leading)
                        .accessibilityLabel(InkThumbnail.label)
                } else if let typed = entry.typedText, !typed.isEmpty {
                    Text(typed)
                        .font(InkFont.bodyItalic(14))
                        .foregroundStyle(Ink.inkFaded)
                        .opacity(ghosted ? 0.5 : 1)
                        .lineLimit(2)
                }
                if !entry.replyText.isEmpty {
                    Text(entry.replyText)
                        .font(book.handFont(book.handScale > 1.5 ? 15 : 19))
                        .foregroundStyle(book.ink)
                        .opacity(ghosted ? 0.42 : 0.92)
                        .lineSpacing(4)
                        .lineLimit(3)
                }
            }
            .padding(.leading, 20)
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 44, trailing: 18))
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
        .background(
            RadialGradient(
                stops: [
                    .init(color: Ink.parchmentBright, location: 0),
                    .init(color: Ink.parchment, location: 0.6),
                    .init(color: Ink.parchmentDeep, location: 1),
                ],
                center: UnitPoint(x: 0.3, y: 0),
                startRadius: 0,
                endRadius: 260
            )
        )
        .overlay(alignment: .topTrailing) {
            // ribbon marker
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 2,
                bottomTrailingRadius: 2, topTrailingRadius: 0
            )
            .fill(book.accent)
            .frame(width: 9, height: 28)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
            .padding(.trailing, 16)
        }
        .overlay {
            if ghosted {
                fadedOverlay
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .shadow(color: .black.opacity(0.6), radius: 12, y: 10)
    }

    private static func dateLabel(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated)).uppercased()
        return "\(day) \(month)"
    }

    /// Veil over a ghosted card. The card itself is the button (→ paywall);
    /// this is only the dressing.
    private var fadedOverlay: some View {
        VStack(spacing: 8) {
            LockGlyph(
                color: Color(hex: 0x8A6B4F),
                bodyColor: LinearGradient(
                    colors: [Color(hex: 0x8A6B4F), Color(hex: 0x8A6B4F)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            Text("faded at thirty days · bind to keep")
                .font(InkFont.bodyItalic(13))
                .foregroundStyle(Ink.inkFaded)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Ink.parchment.opacity(0.1), Ink.parchmentDeep.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )
        )
        // The fade is already spoken by the card's own label.
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// The Book's memory of this conversation: every earlier exchange, the
/// writer's page (ink or typed) above the Book's reply. Oldest first, so the
/// newest words wait at the foot of the page.
///
/// Each row is one accessibility element. Read as separate children it came
/// out as a date, then silence where the handwriting is, then a reply with no
/// indication of who wrote what.
struct PageHistoryThread: View {
    let entries: [PageArchive.Entry]
    let book: Book

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 30) {
            ForEach(entries) { entry in
                row(entry)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(spoken(entry))
            }
        }
        .accessibilityIdentifier("history-thread")
    }

    @ViewBuilder
    private func row(_ entry: PageArchive.Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallCapsLabel(
                text: Self.threadDateLabel(entry.createdAt),
                size: 10, tracking: 1.6, color: Ink.inkFaded.opacity(0.7)
            )
            if let typed = entry.typedText, !typed.isEmpty {
                Text(typed)
                    .font(InkFont.bodyItalic(16))
                    .foregroundStyle(Ink.inkFaded)
                    .lineSpacing(4)
            } else if let ink = InkThumbnail.image(for: entry) {
                Image(uiImage: ink)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 110, alignment: .leading)
                    .opacity(0.85)
                    .accessibilityLabel(InkThumbnail.label)
            }
            if !entry.replyText.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    Rectangle()
                        .fill(Ink.ink.opacity(0.14))
                        .frame(width: 2)
                    Text(entry.replyText)
                        .font(book.handFont(20))
                        .foregroundStyle(book.ink.opacity(0.85))
                        .lineSpacing(6)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Who wrote what, spoken. Handwriting has no transcript anywhere in the
    /// schema, so the writer's half is named rather than invented.
    private func spoken(_ entry: PageArchive.Entry) -> String {
        var parts = ["\(Self.threadDateLabel(entry.createdAt))."]
        if let typed = entry.typedText, !typed.isEmpty {
            parts.append("You wrote: \(typed).")
        } else {
            parts.append("Your handwritten page.")
        }
        if !entry.replyText.isEmpty {
            parts.append("\(book.name) answered: \(entry.replyText)")
        }
        return parts.joined(separator: " ")
    }

    private static func threadDateLabel(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated)).lowercased()
        return "\(day) \(month)"
    }
}

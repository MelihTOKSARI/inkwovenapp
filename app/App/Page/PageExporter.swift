import Foundation
import PencilKit
import UIKit
import InkCore

/// Task F5's export half: the Remembered Pages archive as a shareable file.
/// Reads only what the caller hands it — the Drawer passes the open shelf's
/// entries, so the Keeper's pages never leave through here while sealed.
@MainActor
enum PageExporter {
    enum ExportError: Error {
        case nothingToExport
    }

    /// Plain-text journal, oldest page first. Handwriting cannot become text
    /// on this path (no recognition ships in v1), so an inked page is noted
    /// as such rather than silently dropped.
    static func textFile(entries: [PageArchive.Entry]) throws -> URL {
        guard !entries.isEmpty else { throw ExportError.nothingToExport }
        var lines: [String] = [
            "Inkwoven — Remembered Pages",
            "Exported \(Self.stamp.string(from: .now))",
        ]
        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            lines.append("")
            lines.append(String(repeating: "—", count: 34))
            lines.append("\(bookName(entry)) · \(Self.stamp.string(from: entry.createdAt))")
            if let typed = entry.typedText, !typed.isEmpty {
                lines.append("You wrote: \(typed)")
            } else {
                lines.append("[a page written by hand]")
            }
            lines.append("The page answered: \(entry.replyText)")
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Inkwoven Pages.txt")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// One archived exchange per PDF page: the handwriting as it was inked,
    /// the reply beneath it.
    static func pdfFile(entries: [PageArchive.Entry]) throws -> URL {
        guard !entries.isEmpty else { throw ExportError.nothingToExport }
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 56
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Inkwoven Pages.pdf")
        try renderer.writePDF(to: url) { ctx in
            for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
                ctx.beginPage()
                var y = margin
                y = draw(
                    "\(bookName(entry)) · \(Self.stamp.string(from: entry.createdAt))",
                    font: font("CormorantGaramond-SemiBold", 18, fallbackWeight: .semibold),
                    color: .init(white: 0.15, alpha: 1),
                    at: y, width: contentWidth, margin: margin
                )
                y += 14

                if let drawing = try? PKDrawing(data: entry.strokeData),
                   !drawing.bounds.isEmpty {
                    let image = drawing.image(from: drawing.bounds, scale: 2)
                    let scale = min(contentWidth / image.size.width, 300 / image.size.height, 1)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(origin: CGPoint(x: margin, y: y), size: size))
                    y += size.height + 18
                } else if let typed = entry.typedText, !typed.isEmpty {
                    y = draw(
                        typed,
                        font: font("EBGaramond-Italic", 14, fallbackWeight: .regular),
                        color: .init(white: 0.25, alpha: 1),
                        at: y, width: contentWidth, margin: margin
                    )
                    y += 18
                }

                _ = draw(
                    entry.replyText,
                    font: font("EBGaramond-Regular", 13, fallbackWeight: .regular),
                    color: .init(white: 0.1, alpha: 1),
                    at: y, width: contentWidth, margin: margin
                )
            }
        }
        return url
    }

    // MARK: - Drawing helpers

    private static func draw(
        _ text: String, font: UIFont, color: UIColor,
        at y: CGFloat, width: CGFloat, margin: CGFloat
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        attributed.draw(
            with: CGRect(x: margin, y: y, width: width, height: ceil(bounds.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        )
        return y + ceil(bounds.height)
    }

    private static func font(_ name: String, _ size: CGFloat, fallbackWeight: UIFont.Weight) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: fallbackWeight)
    }

    private static func bookName(_ entry: PageArchive.Entry) -> String {
        Book.by(id: BookID(rawValue: entry.bookID)).name
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

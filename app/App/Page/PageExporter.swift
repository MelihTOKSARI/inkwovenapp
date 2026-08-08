import Foundation
import PencilKit
import UIKit
import InkCore

/// Task F5's export half: the Remembered Pages archive as a shareable file.
/// Reads only what the caller hands it — the Drawer passes the open shelf's
/// entries, so the Keeper's pages never leave through here while sealed.
/// Deliberately unisolated: the render is pure value-in, file-out work
/// (UIGraphicsPDFRenderer and PKDrawing rasterization are thread-safe), so a
/// long journal can gather off the main actor (audit L-31).
enum PageExporter {
    enum ExportError: Error {
        case nothingToExport
    }

    /// Exports live in their own directory under `tmp/` so they can be swept
    /// as a set (audit C-6): a plaintext copy of the whole journal used to be
    /// written to `tmp/` at the OS default protection class, left there
    /// indefinitely, and missed entirely by "delete all pages".
    private static var exportDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "ink-exports", directoryHint: .isDirectory)
    }

    /// Prepares the export directory, clearing anything a previous share left
    /// behind, and returns the URL to write to. Protection matches the
    /// archive's own: `.completeUnlessOpen`, not the tmp default.
    private static func prepare(_ filename: String) throws -> URL {
        let directory = exportDirectory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        // One export at a time: the previous file is the user's journal in
        // plaintext and has no reason to outlive the share sheet.
        purge()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
        )
        return directory.appending(path: filename)
    }

    /// Deletes every exported file. Called before each export, after a share
    /// sheet closes, and by "delete all pages" — which promised the ink was
    /// gone while a full plaintext copy sat in `tmp/` (audit C-6).
    static func purge() {
        try? FileManager.default.removeItem(at: exportDirectory)
    }

    /// Plain-text journal, oldest page first. Handwriting cannot become text
    /// on this path (no recognition ships in v1), so an inked page is noted
    /// as such rather than silently dropped.
    static func textFile(entries: [PageArchive.Entry]) throws -> URL {
        guard !entries.isEmpty else { throw ExportError.nothingToExport }
        let stamp = makeStamp()
        var lines: [String] = [
            "Inkwoven — Remembered Pages",
            "Exported \(stamp.string(from: .now))",
        ]
        for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
            lines.append("")
            lines.append(String(repeating: "—", count: 34))
            lines.append("\(bookName(entry)) · \(stamp.string(from: entry.createdAt))")
            if let typed = entry.typedText, !typed.isEmpty {
                lines.append("You wrote: \(typed)")
            } else {
                lines.append("[a page written by hand]")
            }
            lines.append("The page answered: \(entry.replyText)")
        }
        let url = try prepare("Inkwoven Pages.txt")
        try lines.joined(separator: "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
        )
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
        let url = try prepare("Inkwoven Pages.pdf")
        let stamp = makeStamp()
        try renderer.writePDF(to: url) { ctx in
            for entry in entries.sorted(by: { $0.createdAt < $1.createdAt }) {
                ctx.beginPage()
                var y = margin
                y = draw(
                    "\(bookName(entry)) · \(stamp.string(from: entry.createdAt))",
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
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path
        )
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

    /// A formatter per export, not a shared static: `DateFormatter` is not
    /// Sendable, and an export happens rarely enough that the setup cost is
    /// nothing next to the render.
    private static func makeStamp() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }
}

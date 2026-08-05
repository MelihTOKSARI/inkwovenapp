import UIKit
import InkCore

/// The typed hand, rendered into the same snapshot the ink path sends: the
/// server only ever sees a picture of a page, whichever hand wrote it. Keeps
/// the whole exchange pipeline (digest dedupe, gating, billing, crisis
/// interception) identical for keys and pencil.
@MainActor
enum TypedInkRasterizer {
    static func payload(text: String, pageWidth: CGFloat) -> SnapshotPayload? {
        let font = UIFont(name: "Caveat-Regular", size: 30) ?? .systemFont(ofSize: 30)
        let inset: CGFloat = 24
        let width = min(max(pageWidth, 320), 1024)
        let textWidth = width - inset * 2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
        ]
        let measured = (text as NSString).boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        let size = CGSize(width: width, height: ceil(measured.height) + inset * 2)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(
                in: CGRect(x: inset, y: inset, width: textWidth, height: ceil(measured.height)),
                withAttributes: attributes
            )
        }
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        return SnapshotPayload(
            imageData: data,
            digest: SnapshotProcessor.digest(of: data),
            cropRect: CGRect(origin: .zero, size: size),
            pixelSize: size,
            typed: true
        )
    }
}

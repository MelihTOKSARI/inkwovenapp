import SwiftUI
import PencilKit

/// The app's one ink-preview rasterization. It lived byte-for-byte in both
/// PageView and RememberedView, and both called it straight from a `ForEach`
/// body — a full PKDrawing deserialize plus a CPU raster per visible row, on
/// the main actor, on every re-render. One home, and the result is kept.
@MainActor
enum InkThumbnail {
    private static let cache = NSCache<NSUUID, UIImage>()

    static func image(for entry: PageArchive.Entry) -> UIImage? {
        let key = entry.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let drawing = try? PKDrawing(data: entry.strokeData),
              !drawing.strokes.isEmpty else { return nil }
        let image = drawing.image(from: drawing.bounds.insetBy(dx: -12, dy: -12), scale: 1)
        // An archived entry is immutable, so the raster can never go stale.
        cache.setObject(image, forKey: key)
        return image
    }

    /// Delete-all calls this so the rasters go with the pages (audit L-30):
    /// a cache of images of ink the user just destroyed has no business
    /// outliving it.
    static func removeAll() {
        cache.removeAllObjects()
    }

    /// What VoiceOver says in place of the picture. There is no transcript of
    /// handwriting anywhere in the schema (Vision OCR is unbuilt), so the
    /// honest label names the artifact rather than inventing its contents.
    static let label = "Your handwritten page"
}

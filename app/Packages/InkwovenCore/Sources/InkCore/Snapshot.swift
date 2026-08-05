import Foundation
import CoreGraphics
// CryptoKit is an allowed exception to InkCore's Foundation/CoreGraphics-only
// rule: it is a platform framework with no UI and no I/O, used solely for the
// SHA-256 snapshot digest below. Hashing is export-exempt, so it does not
// change the app's encryption declaration.
import CryptoKit

/// Pure geometry for the snapshot pipeline (task B4): crop to the strokes
/// added since the last exchange, then downscale hard. Rasterization itself is
/// injected (PencilKit lives in the app shell, never in InkCore).
public enum SnapshotPlanner {
    /// Union of new-stroke bounds, padded, clamped to the canvas.
    /// Returns nil when there is no new ink to send.
    public static func cropRect(
        newStrokeBounds: [CGRect],
        canvasBounds: CGRect,
        padding: CGFloat = 24
    ) -> CGRect? {
        let union = newStrokeBounds
            .filter { !$0.isNull && !$0.isEmpty }
            .reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return nil }
        let padded = union.insetBy(dx: -padding, dy: -padding)
        let clamped = padded.intersection(canvasBounds)
        guard !clamped.isNull, !clamped.isEmpty else { return nil }
        return clamped
    }

    /// Downscale so the long edge is ≤ `maxLongEdge`, preserving aspect ratio.
    public static func targetPixelSize(for crop: CGSize, maxLongEdge: CGFloat = 1024) -> CGSize {
        let longEdge = max(crop.width, crop.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return crop }
        let scale = maxLongEdge / longEdge
        return CGSize(width: (crop.width * scale).rounded(), height: (crop.height * scale).rounded())
    }
}

public struct SnapshotPayload: Equatable, Sendable {
    public var imageData: Data
    public var digest: String
    public var cropRect: CGRect
    public var pixelSize: CGSize
    /// True when the typed hand wrote the page — the snapshot is a rendering
    /// of words, not a sketch. The proxy develops those from the description
    /// instead of running img2img on a picture of text, which repainted the
    /// same page of words every time.
    public var typed: Bool

    public init(
        imageData: Data, digest: String, cropRect: CGRect, pixelSize: CGSize, typed: Bool = false
    ) {
        self.imageData = imageData
        self.digest = digest
        self.cropRect = cropRect
        self.pixelSize = pixelSize
        self.typed = typed
    }
}

/// Implemented in the app shell over PencilKit (`PKDrawing.image(from:scale:)`
/// → grayscale + contrast normalize → JPEG q0.7).
public protocol DrawingRasterizing: Sendable {
    func rasterize(cropRect: CGRect, targetPixelSize: CGSize) throws -> Data
}

public enum SnapshotResult: Equatable, Sendable {
    /// Digest matches the previous exchange — nothing new was written; skip
    /// the send entirely (dedupes re-rolls, never bills a duplicate).
    case skipDuplicate(digest: String)
    case send(SnapshotPayload)
}

public enum SnapshotError: Error, Equatable {
    case noNewInk
}

public struct SnapshotProcessor: Sendable {
    private let rasterizer: any DrawingRasterizing
    private let maxLongEdge: CGFloat

    public init(rasterizer: any DrawingRasterizing, maxLongEdge: CGFloat = 1024) {
        self.rasterizer = rasterizer
        self.maxLongEdge = maxLongEdge
    }

    public func process(
        newStrokeBounds: [CGRect],
        canvasBounds: CGRect,
        previousDigest: String?
    ) throws -> SnapshotResult {
        guard let crop = SnapshotPlanner.cropRect(newStrokeBounds: newStrokeBounds, canvasBounds: canvasBounds) else {
            throw SnapshotError.noNewInk
        }
        let target = SnapshotPlanner.targetPixelSize(for: crop.size, maxLongEdge: maxLongEdge)
        let data = try rasterizer.rasterize(cropRect: crop, targetPixelSize: target)
        let digest = Self.digest(of: data)
        if digest == previousDigest {
            return .skipDuplicate(digest: digest)
        }
        return .send(SnapshotPayload(imageData: data, digest: digest, cropRect: crop, pixelSize: target))
    }

    public static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

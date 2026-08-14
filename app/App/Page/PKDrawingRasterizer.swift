import UIKit
import PencilKit
import CoreImage
import InkCore

enum RasterizeError: Error {
    case renderFailed
}

/// Live `DrawingRasterizing` over PencilKit (task B4's app-shell half):
/// render the crop on white paper, grayscale + contrast normalize for the
/// vision model, JPEG q0.7.
/// @unchecked: PKDrawing is a value type; the struct is immutable after init.
struct PKDrawingRasterizer: DrawingRasterizing, @unchecked Sendable {
    let drawing: PKDrawing

    /// One shared context on purpose: CIContext builds and caches GPU state at
    /// init, so making a fresh one per rasterize would cost far more than the
    /// filter it runs. `nonisolated(unsafe)` rather than a computed property
    /// because Core Image documents a context as safe to share across threads —
    /// the 6.1 compiler simply has no annotation to read that from.
    private nonisolated(unsafe) static let ciContext = CIContext()

    func rasterize(cropRect: CGRect, targetPixelSize: CGSize) throws -> Data {
        let scale = max(targetPixelSize.width / max(cropRect.width, 1), 0.01)
        let inkImage = drawing.image(from: cropRect, scale: scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let composed = UIGraphicsImageRenderer(size: targetPixelSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetPixelSize))
            inkImage.draw(in: CGRect(origin: .zero, size: targetPixelSize))
        }

        guard let normalized = Self.normalize(composed),
              let jpeg = normalized.jpegData(compressionQuality: 0.7) else {
            throw RasterizeError.renderFailed
        }
        return jpeg
    }

    private static func normalize(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey) // grayscale
        filter?.setValue(1.15, forKey: kCIInputContrastKey)  // lift faint strokes
        guard let output = filter?.outputImage,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

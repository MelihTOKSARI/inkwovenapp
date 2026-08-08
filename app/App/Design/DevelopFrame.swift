import SwiftUI
import UIKit
import ImageIO

/// Darkroom-style progressive reveal of the developed picture. While the
/// image is still in the bath (or on a failed load) the frame shows the
/// design's woven placeholder.
struct DevelopFrame: View {
    let book: Book
    let step: Int
    let isMoving: Bool
    var imageURL: URL?
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var pan = false
    /// The developed plate, held downsampled (audit L-34). AsyncImage used to
    /// decode fal's full-resolution delivery for a frame that never exceeds
    /// ~420pt; CGImageSource now builds a plate-sized thumbnail off the main
    /// actor instead, with the same phases AsyncImage gave — the weave while
    /// it soaks, the weave if the load fails, the picture when it lands.
    @State private var developedPlate: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            plate
                .scaleEffect(isMoving && !reduceMotion ? (pan ? 1.09 : 1.04) : 1)
                .offset(x: isMoving && !reduceMotion ? (pan ? -6 : 0) : 0)
                .blur(radius: blur)
                .brightness(brightness)
                .saturation(saturation)
                .inkAnimation(.easeInOut(duration: 1.1), value: step, reduce: reduceMotion)

            Color(hex: 0x0D0906).opacity(veil)
                .inkAnimation(.easeInOut(duration: 1.1), value: step, reduce: reduceMotion)

            if isMoving {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Ink.dangerEmber)
                        .frame(width: 6, height: 6)
                        .shadow(color: Ink.dangerEmber, radius: 3)
                    SmallCapsLabel(text: "living", size: 10, tracking: 1.4, color: Ink.parchment)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: 0x0D0906, opacity: 0.55)))
                .padding(10)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Ink.ink.opacity(0.9), lineWidth: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .inset(by: 6)
                .strokeBorder(Ink.candle.opacity(0.15), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        .onAppear { startPanIfMoving() }
        .onChange(of: isMoving) { startPanIfMoving() }
        .task(id: imageURL) {
            developedPlate = nil
            guard let imageURL else { return }
            developedPlate = await Self.downsampledPlate(from: imageURL)
        }
        // The darkroom is otherwise silent: a plate that only reads as blur
        // and brightness has nothing to say to VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenState)
    }

    /// Where the picture is in the bath, in the room's own words.
    private var spokenState: String {
        if imageURL == nil {
            return "A picture is developing from your page."
        }
        return isMoving
            ? "The developed picture from your page, living — it drifts on its own."
            : "The developed picture from your page."
    }

    /// The picture in the frame: the real developed image once fal delivers
    /// it, the woven gradient while it soaks (and if the load fails).
    @ViewBuilder
    private var plate: some View {
        if let developedPlate {
            // Overlay on a clear base: fill the frame without letting
            // the image's own size inflate the 4:3 layout.
            Color.clear.overlay(
                Image(uiImage: developedPlate).resizable().scaledToFill()
            )
        } else {
            placeholderWeave
        }
    }

    /// ≈2× the frame's largest point dimension — the frame caps near 420pt —
    /// so the plate stays crisp on a 2× display without the bath holding the
    /// whole negative (audit L-34).
    private nonisolated static let maxPlatePixels = 840

    /// Fetch and decode at plate size, off the main actor. Anything that is
    /// not an image (an error page, a truncated body) simply fails the guard
    /// and leaves the weave in the frame, exactly as AsyncImage's failure
    /// phase did.
    private nonisolated static func downsampledPlate(from url: URL) async -> UIImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        let open: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, open as CFDictionary) else {
            return nil
        }
        let thumbnail: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPlatePixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }

    private var placeholderWeave: some View {
        LinearGradient(
            colors: [book.accent, .mix(book.accentHex, 0.72, 0x000000), book.accent],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// The slow Ken-Burns drift of a living picture. Starts in an explicit
    /// transaction; the moving state usually arrives after appear.
    private func startPanIfMoving() {
        guard isMoving, !reduceMotion, !pan else { return }
        withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
            pan = true
        }
    }

    private var blur: CGFloat { [18, 9, 3, 0][min(step, 3)] }
    private var brightness: Double { [-0.5, -0.35, -0.12, 0][min(step, 3)] }
    private var saturation: Double { [0.2, 0.4, 0.7, 1][min(step, 3)] }
    private var veil: Double { [0.72, 0.5, 0.24, 0][min(step, 3)] }
}

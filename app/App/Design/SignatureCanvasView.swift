import SwiftUI
import PencilKit

/// The flyleaf's ONE signature field (task H1, revised): pen-first, and the
/// same field takes the keyboard when no pencil is about — never two inputs.
/// Ink publishes the PKDrawing archive; keys publish the typed name; the
/// shell treats either as "signed" after its settle window.
struct SignatureCanvasView: UIViewRepresentable {
    @Binding var drawingData: Data?
    @Binding var typedName: String
    /// Re-renders the surface when the pen state flips (also what triggers
    /// updateUIView — PenPresence is read by the parent).
    var pencilActive: Bool
    /// The keyboard may rise on its own (no pencil, intro streamed, unsealed).
    var wantsKeys: Bool
    var onReturn: () -> Void = {}
    var inkColor: UIColor = UIColor(Ink.ink)

    func makeUIView(context: Context) -> HybridInkSurface {
        let surface = HybridInkSurface()
        surface.bottomAligned = true
        surface.singleLine = true

        let canvas = surface.canvas
        // Parchment flyleaf is always light; keep PencilKit from inverting
        // the ink under system dark mode (same trap as InkCanvasView).
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 3)
        canvas.delegate = context.coordinator
        if let data = drawingData, let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }

        let text = surface.textView
        // Scaled with Dynamic Type (same reasoning as InkCanvasView): the
        // flyleaf is the first thing a low-vision writer has to read and use.
        let base = UIFont(name: "Caveat-Regular", size: 26) ?? .systemFont(ofSize: 26)
        text.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        text.adjustsFontForContentSizeCategory = true
        text.textColor = inkColor
        text.tintColor = inkColor
        text.autocapitalizationType = .words
        text.returnKeyType = .done
        text.isScrollEnabled = false
        text.accessibilityIdentifier = "signature-keys"
        text.accessibilityLabel = "Your name, typed"
        text.accessibilityHint = "Type your name, then Done. The flyleaf seals once the writing rests."

        canvas.isAccessibilityElement = true
        canvas.accessibilityTraits = [.allowsDirectInteraction]
        canvas.accessibilityLabel = "The signature line"
        canvas.accessibilityHint = "Sign with pencil or finger. The flyleaf seals once the ink rests."

        surface.onTypedChange = { [coordinator = context.coordinator] name in
            coordinator.parent.typedName = name
        }
        surface.onReturn = { [coordinator = context.coordinator] in
            coordinator.parent.onReturn()
        }
        return surface
    }

    func updateUIView(_ surface: HybridInkSurface, context: Context) {
        context.coordinator.parent = self
        surface.apply(pencilActive: pencilActive)
        surface.setWantsKeys(wantsKeys)
        // "Begin again": the shell cleared the stored signature; wipe both hands.
        if drawingData == nil, !surface.canvas.drawing.strokes.isEmpty {
            surface.canvas.drawing = PKDrawing()
        }
        if surface.textView.text != typedName {
            surface.textView.text = typedName
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignatureCanvasView

        init(_ parent: SignatureCanvasView) { self.parent = parent }

        nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                let drawing = canvasView.drawing
                // No `withAnimation` here: PencilKit fires this continuously
                // through a stroke, and wrapping a Data assignment opened an
                // animation transaction per callback. The flyleaf animates
                // the states derived from it (OnboardingView animates on
                // `hasInk`), which is where the beat belongs.
                parent.drawingData = drawing.strokes.isEmpty ? nil : drawing.dataRepresentation()
            }
        }
    }
}

import SwiftUI
import PencilKit

/// PencilKit canvas (task B1): pressure ink, palm rejection via PencilKit,
/// finger drawing everywhere — Pencil recommended, never required, and
/// nothing gates on Pencil detection.
struct InkCanvasView: UIViewRepresentable {
    let interactor: PageInteractor

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas
        interactor.attach(canvas: canvas)
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(interactor: interactor)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let interactor: PageInteractor
        weak var canvas: PKCanvasView?
        private var strokeCount = 0

        init(interactor: PageInteractor) {
            self.interactor = interactor
        }

        nonisolated func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated { interactor.strokeBegan() }
        }

        nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                // Fires on every mutation; only a grown stroke count is a
                // finished stroke (undo/clear also land here).
                let count = canvasView.drawing.strokes.count
                defer { strokeCount = count }
                guard count > strokeCount else { return }
                interactor.strokeEnded()
            }
        }
    }
}

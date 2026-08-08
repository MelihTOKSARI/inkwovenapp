import SwiftUI
import PencilKit

/// The page's ONE writing surface (task B1, revised): pressure ink, palm
/// rejection via PencilKit, and — when no pencil is about — the same surface
/// hosts the keyboard's text instead of offering a second input. Pencil
/// recommended, never required; nothing gates on Pencil detection. Tool tray
/// (task B5) drives the eraser through `interactor.eraserOn`; Apple Pencil
/// double-tap toggles it too.
struct InkCanvasView: UIViewRepresentable {
    let interactor: PageInteractor
    /// Re-renders the surface when the pen state flips (also what triggers
    /// updateUIView — PenPresence is read by the parent).
    var pencilActive: Bool
    var inkColor: UIColor = .black
    /// Extra top inset for the typed hand, so keyboard text starts below
    /// whatever chrome (the opener line) overlays the top of the surface.
    /// Ink is unaffected — the pen may write anywhere, including over it.
    var typedTopInset: CGFloat = 0

    func makeUIView(context: Context) -> HybridInkSurface {
        let surface = HybridInkSurface()

        let canvas = surface.canvas
        // The page is always light parchment, whatever the system appearance.
        // Without this, PencilKit's dark-mode handling inverts dark inks to
        // near-parchment pale — invisible strokes while writing.
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: inkColor, width: 4)
        canvas.delegate = context.coordinator
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        canvas.addInteraction(pencil)

        // The typed hand writes in the user's script (Caveat — the same hand
        // as the starter hints), absorbed by the same exchange pipeline.
        // Scaled through UIFontMetrics: every SwiftUI label in the room grows
        // with Dynamic Type, and the one surface the writer actually types
        // into must not be the single thing that stays at 28pt script.
        let text = surface.textView
        let base = UIFont(name: "Caveat-Regular", size: 28) ?? .systemFont(ofSize: 28)
        text.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: base)
        text.adjustsFontForContentSizeCategory = true
        text.textColor = inkColor
        text.tintColor = inkColor
        text.autocapitalizationType = .sentences
        text.accessibilityIdentifier = "typed-canvas"
        // Without a label VoiceOver reaches the field and says nothing about
        // what it is for — and on a pencil-less iPad this field IS the page.
        text.accessibilityLabel = "The typed hand"
        text.accessibilityHint = "Write your page here. Rest, and it sends on its own."

        // PencilKit exposes no element for the drawing surface, so the ink
        // hand was simply absent from the accessibility tree. Direct
        // interaction is the correct trait for a canvas: it hands raw touches
        // to the app so a VoiceOver user can still draw.
        canvas.isAccessibilityElement = true
        canvas.accessibilityTraits = [.allowsDirectInteraction]
        canvas.accessibilityLabel = "The ink hand"
        canvas.accessibilityHint = "Write with pencil or finger. Rest, and the page sends on its own."
        text.textContainerInset.top = 8 + typedTopInset
        context.coordinator.typedTopInset = typedTopInset
        surface.onTypedChange = { [interactor] typed in
            interactor.typedDraft = typed
            interactor.typedDraftChanged()
        }

        context.coordinator.canvas = canvas
        context.coordinator.inkColor = inkColor
        // Attach rehydrates the draft — or restores a pending revisit — and
        // both write observable page state, which must not happen inside
        // this view-update pass (audit L-7). One beat later, outside it.
        Task { @MainActor in
            interactor.attach(canvas: canvas)
        }
        return surface
    }

    func updateUIView(_ surface: HybridInkSurface, context: Context) {
        // Pen-first: the page never summons the keyboard on its own. With no
        // pencil about, a deliberate finger tap on the page focuses the text
        // layer and raises the keys; the first pencil touch flips to ink.
        surface.apply(pencilActive: pencilActive)
        // Absorption (or turn-page) cleared the draft; the field follows.
        if surface.textView.text != interactor.typedDraft {
            surface.textView.text = interactor.typedDraft
        }
        if context.coordinator.typedTopInset != typedTopInset {
            context.coordinator.typedTopInset = typedTopInset
            surface.textView.textContainerInset.top = 8 + typedTopInset
        }
        // Only touch the tool when it actually changes — reassigning it
        // mid-stroke cancels the stroke PencilKit is drawing.
        let eraserOn = interactor.eraserOn
        guard context.coordinator.inkColor != inkColor
            || context.coordinator.eraserOn != eraserOn else { return }
        context.coordinator.inkColor = inkColor
        context.coordinator.eraserOn = eraserOn
        surface.canvas.tool = eraserOn
            ? PKEraserTool(.vector)
            : PKInkingTool(.pen, color: inkColor, width: 4)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(interactor: interactor)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        let interactor: PageInteractor
        weak var canvas: PKCanvasView?
        var inkColor: UIColor?
        var eraserOn = false
        var typedTopInset: CGFloat = 0
        private var strokeCount = 0
        /// Tool uses currently down on the canvas — the abort check below
        /// stands aside while any touch is still writing.
        private var activeToolUses = 0

        init(interactor: PageInteractor) {
            self.interactor = interactor
        }

        nonisolated func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                activeToolUses += 1
                interactor.strokeBegan()
            }
        }

        nonisolated func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                activeToolUses = max(0, activeToolUses - 1)
                // A committed stroke reports drawingDidChange just AFTER this
                // callback, so check on the next beat: a tool use that grew
                // nothing — an eraser touch on empty paper, a cancelled
                // stroke, an erase that only removed ink — must not leave
                // the page stranded at the `.inking` that pen-down promoted.
                // A newer touch still down owns the page; the check yields.
                let before = canvasView.drawing.strokes.count
                Task { @MainActor [weak canvasView] in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard let canvasView,
                          self.activeToolUses == 0,
                          canvasView.drawing.strokes.count <= before else { return }
                    self.interactor.strokeAborted()
                }
            }
        }

        nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                // Fires on every mutation; only a grown stroke count is a
                // finished stroke (undo/erase/clear also land here). Every
                // mutation refreshes the draft though — an erase or an undo
                // must not resurrect on the next launch (audit D-1).
                interactor.canvasContentChanged()
                let count = canvasView.drawing.strokes.count
                defer { strokeCount = count }
                guard count > strokeCount else { return }
                interactor.strokeEnded()
            }
        }

        nonisolated func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            MainActor.assumeIsolated { interactor.eraserOn.toggle() }
        }
    }
}

import SwiftUI

/// Inkwell/blotter cluster, riding the header rail (task B5). Dormant while
/// the pen moves. Cancel-send keeps a reserved slot (opacity, not insertion)
/// so its arrival never shifts the neighboring buttons.
struct PageToolTray: View {
    let interactor: PageInteractor
    /// Cancel is only meaningful while a send is pending, and only after the
    /// rest has held for a beat — the page decides that, not the tray.
    let showCancelSend: Bool
    /// Opens the hand card — the page owns the card, the tray only rings it.
    let onHand: () -> Void
    @Environment(\.reduceInkMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            trayButton("arrow.uturn.backward", label: "Undo") { interactor.undo() }
            trayButton("arrow.uturn.forward", label: "Redo") { interactor.redo() }
            trayButton("eraser", label: "Eraser", active: interactor.eraserOn) {
                interactor.eraserOn.toggle()
            }
            trayButton("hourglass", label: "Hold — the page waits", active: interactor.isHeld) {
                interactor.toggleHold()
            }
            trayButton("book.pages", label: "Turn the page") {
                interactor.turnPage()
            }
            trayButton("signature", label: "The hand it writes in") { onHand() }
            trayButton("xmark", label: "Cancel send") { interactor.cancelSend() }
                .opacity(showCancelSend ? 1 : 0)
                .allowsHitTesting(showCancelSend)
                .accessibilityHidden(!showCancelSend)
        }
        .opacity(interactor.status == .inking ? 0.14 : 0.8)
        .inkAnimation(
            .easeOut(duration: 0.4), value: interactor.status == .inking, reduce: reduceMotion
        )
        .inkAnimation(.easeOut(duration: 0.25), value: showCancelSend, reduce: reduceMotion)
        .accessibilityIdentifier("tool-tray")
    }

    private func trayButton(
        _ symbol: String, label: String, active: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(active ? Ink.parchment : Ink.inkFaded)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(active ? Ink.inkFaded : Ink.ink.opacity(0.05))
                        .overlay(Circle().stroke(Ink.ink.opacity(0.2), lineWidth: 1))
                )
                // The shape must come AFTER the sizing frame (audit A-4): a
                // Circle declared on the 38pt glyph capped every tool's hit
                // target at 38pt while Components.swift claimed 44.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        // The eraser and the hold are modes, not one-shot commands: without
        // this VoiceOver reads "Eraser" identically whether it is armed.
        .accessibilityAddTraits(active ? AccessibilityTraits.isSelected : [])
    }
}

import SwiftUI
import UIKit
import CoreHaptics

/// The room's sense of touch. Every haptic in the app passes through here,
/// named for the moment it marks — never for the hardware that renders it —
/// so a call site reads as intent (`Feel.shared.play(.replyArrived)`) and the
/// texture of each moment is tuned in exactly one place.
///
/// **This is a budget, not a coverage problem.** Inkwoven is a quiet
/// candlelit room, and the whole value of a felt moment is that there are so
/// few of them. Six exist, listed below, plus a selection tick in the two
/// places that are genuinely choices (the hand picker, the Drawer's controls).
/// Adding a seventh should feel like it needs an argument.
///
/// Three silences are load-bearing rather than incidental:
///
/// - **Nothing while the pen is on the page.** The Pencil already has real
///   feedback against glass; a haptic competing with it breaks the illusion
///   instantly. No stroke, undo, redo or eraser feedback, ever.
/// - **Nothing in the crisis flow.** Someone in distress does not need the
///   phone buzzing at them.
/// - **Nothing on navigation, the tool tray, streamed chunks, or launch.**
///   Those are all visible on screen; a haptic adds no information.
///
/// One writer-facing switch lives in the Drawer ("A gentle pulse"), default
/// on, deliberately separate from Reduce Motion — haptics are not motion, and
/// someone who dislikes animation may still want to feel the reply land.
/// `UIFeedbackGenerator` already honours the system haptics setting, so
/// nothing here tries to detect or mirror it.
@Observable
@MainActor
final class Feel {
    static let shared = Feel()

    /// The moments the room marks. Add here, texture below — call sites never
    /// compose their own patterns.
    enum Event {
        /// THE REPLY ARRIVES. The most important one in the app: the only
        /// event that happens while the writer's attention is probably
        /// elsewhere. Fires only for an exchange sent in this visit —
        /// revisits and archive restores stay silent.
        case replyArrived
        /// THE SEND COMMITS ON STILLNESS. The page leaves after 2s of pen-down
        /// stillness, an irreversible-ish thing triggered by doing nothing
        /// against a deadline nobody can perceive. Now the ONLY signal that it
        /// passed besides the ink going under — the margin no longer counts
        /// the window down, so this tap and the sink carry the whole moment.
        case sendCommitted
        /// THE KEEPER'S LOCK OPENS. Rare, and the one moment the app says
        /// "I recognise you."
        case unlock
        /// A BOOK COMES OFF THE SHELF — the cover actually opening, not the
        /// peek that precedes it.
        case bookOpen
        /// A QUIET REFUSAL: a declined page, a cooldown. The room turning you
        /// away gently, never reporting a fault.
        case refusal
        /// A PURCHASE VERDICT. Ask-to-Buy is a pause, not a verdict, and stays
        /// silent.
        case purchaseSuccess
        case purchaseFailed
        /// A choice was made: a hand picked, a toggle thrown, a pill chosen.
        case tick
    }

    /// Whether this device can render a haptic at all.
    ///
    /// **No iPad has a Taptic Engine.** Every generator below is a silent
    /// no-op there — which mattered because Inkwoven is iPad-first, so the
    /// whole of this file does nothing on the device most writers hold. The
    /// Apple Pencil Pro can buzz, but only through `UICanvasFeedbackGenerator`
    /// during pencil-on-canvas interaction, and not one of the moments above
    /// is that: the pen is lifted or absent for all six.
    ///
    /// This exists so the Drawer can stop offering a switch that cannot do
    /// anything. Hardware capability only — whether the writer has turned
    /// system haptics off is the OS's business, and `UIFeedbackGenerator`
    /// already honours it.
    nonisolated static let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "ink.haptics") }
    }

    private let defaults: UserDefaults

    // Kept alive so repeated moments stay low-latency; UIKit no-ops them on
    // hardware without a Taptic Engine.
    private let softTap = UIImpactFeedbackGenerator(style: .soft)
    private let rigidTap = UIImpactFeedbackGenerator(style: .rigid)
    private let verdict = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hapticsEnabled = defaults.object(forKey: "ink.haptics") as? Bool ?? true
    }

    func play(_ event: Event) {
        guard Self.isSupported, hapticsEnabled else { return }
        pulse(event)
    }

    /// Sugar for the one event call sites reach for constantly.
    func tick() { play(.tick) }

    // MARK: - Texture

    /// Built from the stock generators on purpose. `CHHapticEngine` would buy
    /// finer grain at the price of lifecycle tending — it stops on every
    /// backgrounding — and every moment here is short enough that two
    /// well-timed taps already read as one gesture.
    private func pulse(_ event: Event) {
        switch event {
        case .replyArrived:
            // Two soft beats, the second a little stronger: an arrival, not an
            // alert. The rise is what makes it read as something coming TO
            // you rather than a notification firing AT you.
            softTap.impactOccurred(intensity: 0.55)
            secondBeat(after: 130, intensity: 0.85)

        case .sendCommitted:
            // The sharpest thing in the app, and a single tap — the writer did
            // not touch anything, so the feedback has to be unambiguous rather
            // than decorative.
            rigidTap.impactOccurred(intensity: 1.0)
            // The reply follows this within seconds and is the moment that
            // matters most; warm its generator now, while we are already here.
            softTap.prepare()

        case .unlock:
            // Firm and crisp, distinct from the soft settle used for ordinary
            // confirmations. The seal giving way.
            rigidTap.impactOccurred(intensity: 0.9)

        case .bookOpen:
            // A settle, not a click: the cover coming to rest open.
            softTap.impactOccurred(intensity: 0.75)

        case .refusal:
            // Deliberately NOT `UINotificationFeedbackGenerator.warning`,
            // which is a two-part buzz that reads as a fault report. A quiet
            // no is one soft, low tap and nothing more.
            softTap.impactOccurred(intensity: 0.45)

        case .purchaseSuccess:
            verdict.notificationOccurred(.success)

        case .purchaseFailed:
            verdict.notificationOccurred(.error)

        case .tick:
            selection.selectionChanged()
        }
    }

    /// The trailing half of the reply's two-part texture. The intensity
    /// crosses into the `Task` as a plain Sendable scalar, so strict
    /// concurrency has no escaping capture to weigh up.
    private func secondBeat(after milliseconds: Int, intensity: CGFloat) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            softTap.impactOccurred(intensity: intensity)
        }
    }
}

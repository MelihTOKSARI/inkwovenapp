import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Answers one question for the shell: is a pencil in play? Pen-first, keys
/// as fallback — when no pencil has touched the glass, the keyboard steps in
/// for writing; a pencil touch flips the session to ink. Nothing *gates* on
/// the pencil — finger ink works everywhere — this only decides which hand
/// is offered first.
///
/// The observation is PER SESSION, deliberately (audit A-1): it used to be
/// persisted "for good", so one pencil touch — anyone's, ever, including a
/// stranger trying a display iPad — permanently disabled the keyboard, and a
/// VoiceOver user or a writer with a tremor could never type again. Two
/// overrides beat the observation: the writer's own "write with the keys"
/// choice in the Drawer (persisted — favoring the keyboard is the safe
/// direction to remember), and VoiceOver running, because a direct-interaction
/// canvas over a dead keyboard is an app a VoiceOver user cannot write in.
@Observable
@MainActor
final class PenPresence {
    static let shared = PenPresence()

    /// A pencil has touched the glass this session.
    private(set) var pencilActive: Bool

    /// The writer's explicit preference from the Drawer: keys stay available
    /// whatever the pencil does.
    var keysPreferred: Bool {
        didSet { defaults.set(keysPreferred, forKey: "ink.keysPreferred") }
    }

    /// VoiceOver, mirrored into observable state (audit M-18): the static
    /// `UIAccessibility.isVoiceOverRunning` read is a snapshot the surfaces
    /// never re-take, so a curtain raised mid-session would have left them
    /// on a canvas a VoiceOver user cannot write in.
    private(set) var voiceOverRunning: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read but never written in production: the UITest pencil scenarios
        // inject `ink.pencilSeen` through the argument domain, which the
        // startup scrub cannot reach. A pre-fix build DID persist this key;
        // AppModel removes that legacy value from the plist at launch (audit
        // M-12), so an upgrader's old touch cannot re-latch the lockout.
        // Production launches start pencil-quiet and observe the session's
        // touches.
        pencilActive = defaults.bool(forKey: "ink.pencilSeen")
        keysPreferred = defaults.bool(forKey: "ink.keysPreferred")
        voiceOverRunning = UIAccessibility.isVoiceOverRunning
        NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue (`queue: .main`), which is the
            // main actor — the assume is a statement of fact, not a hope.
            MainActor.assumeIsolated {
                self?.voiceOverRunning = UIAccessibility.isVoiceOverRunning
            }
        }
    }

    /// What the writing surfaces honor.
    var pencilPreferred: Bool {
        pencilActive && !keysPreferred && !voiceOverRunning
    }

    func note(_ type: UITouch.TouchType) {
        guard type == .pencil, !pencilActive else { return }
        // Session memory only — never written to disk (audit A-1).
        pencilActive = true
    }

    /// Attach to any canvas that should report which hand touches it.
    func observe(_ view: UIView) {
        let observer = TouchTypeObserver { [weak self] type in self?.note(type) }
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        view.addGestureRecognizer(observer)
    }
}

/// Reads the touch type on the way past and immediately fails, so PencilKit's
/// own recognizers never feel it.
private final class TouchTypeObserver: UIGestureRecognizer {
    private let onTouch: (UITouch.TouchType) -> Void

    init(onTouch: @escaping (UITouch.TouchType) -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let type = touches.first?.type { onTouch(type) }
        state = .failed
    }
}

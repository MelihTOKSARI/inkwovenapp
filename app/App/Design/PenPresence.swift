import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Answers one question for the shell: is a pencil in play? Pen-first, keys
/// as fallback — when no pencil has ever touched the glass (a simulator, an
/// iPad without one), the keyboard steps in for writing; the moment a pencil
/// touch lands anywhere, the app goes ink-only and remembers it across
/// launches. Nothing *gates* on the pencil — finger ink works everywhere —
/// this only decides which hand is offered first.
@Observable
@MainActor
final class PenPresence {
    static let shared = PenPresence()

    private(set) var pencilActive: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pencilActive = defaults.bool(forKey: "ink.pencilSeen")
    }

    func note(_ type: UITouch.TouchType) {
        guard type == .pencil, !pencilActive else { return }
        pencilActive = true
        defaults.set(true, forKey: "ink.pencilSeen")
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

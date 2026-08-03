import SwiftUI
import UIKit
import AVFoundation

/// The room's sense of touch and hearing. Every haptic and every sound in
/// the app passes through here, named for the moment it marks — never for
/// the hardware that renders it — so a call site reads as intent
/// (`Feel.shared.play(.sealPress)`) and the texture of each moment is tuned
/// in exactly one place.
///
/// Two writer-facing switches live in the Drawer ("A gentle pulse", "Quiet
/// sounds"); both default on. Sounds ride the `.ambient` category: they mix
/// under whatever the writer is listening to and fall silent with the ring
/// switch, the same posture `MovingPicture` takes for its clips. Writing
/// itself is deliberately unfelt — the pen on the page is the sensation —
/// and the Crisis room stays entirely still: no pulse, no chime, nothing
/// but the words.
@Observable
@MainActor
final class Feel {
    static let shared = Feel()

    /// The moments the room marks. Add here, texture below — call sites
    /// never compose their own patterns.
    enum Event {
        /// A Book comes off the shelf; its cover settles open.
        case bookOpen
        /// TURN PAGE — the manual archive-and-clear.
        case pageTurn
        /// The page absorbs the ink and the exchange leaves for the Book —
        /// also the press of any wax seal (binding included).
        case sealPress
        /// The Book's reply has fully arrived on the facing page.
        case replyArrived
        /// The Keeper's lock recognises the hand.
        case unlock
        /// A quiet no: a declined page, a cooldown. Gentler than an error —
        /// the room refuses softly.
        case refusal
        /// A verified purchase landed.
        case purchaseSuccess
        /// The seal would not take.
        case purchaseFailed
        /// Small selections: toggles, pills, choosing a hand.
        case tick
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "ink.haptics") }
    }
    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: "ink.sounds") }
    }

    private let defaults: UserDefaults

    // Kept alive so repeated moments stay low-latency; UIKit no-ops them on
    // hardware without a Taptic Engine.
    private let softTap = UIImpactFeedbackGenerator(style: .soft)
    private let lightTap = UIImpactFeedbackGenerator(style: .light)
    private let rigidTap = UIImpactFeedbackGenerator(style: .rigid)
    private let verdict = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private var players: [String: AVAudioPlayer] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hapticsEnabled = defaults.object(forKey: "ink.haptics") as? Bool ?? true
        soundsEnabled = defaults.object(forKey: "ink.sounds") as? Bool ?? true
        // Ambient before anything plays: the room's sounds sit UNDER the
        // writer's own listening and never take the audio route from it.
        // (MovingPicture sets the same category; agreeing here means neither
        // ever interrupts the other.)
        try? AVAudioSession.sharedInstance().setCategory(
            .ambient, mode: .default, options: [.mixWithOthers]
        )
        preloadSounds()
    }

    func play(_ event: Event) {
        if hapticsEnabled { pulse(event) }
        if soundsEnabled { sound(event) }
    }

    /// Sugar for the most common moment.
    func tick() { play(.tick) }

    // MARK: - Touch

    /// The textures. Layered from the stock generators on purpose: a
    /// CHHapticEngine would buy finer grain at the price of lifecycle
    /// tending (it stops on every backgrounding), and these moments are
    /// short enough that two well-timed taps read as one gesture.
    private func pulse(_ event: Event) {
        switch event {
        case .bookOpen:
            softTap.impactOccurred(intensity: 0.8)
            secondBeat(after: 90, .light, intensity: 0.5)
        case .pageTurn:
            lightTap.impactOccurred(intensity: 0.6)
        case .sealPress:
            rigidTap.impactOccurred(intensity: 1.0)
            secondBeat(after: 110, .soft, intensity: 0.7)
        case .replyArrived:
            softTap.impactOccurred(intensity: 0.55)
            secondBeat(after: 130, .soft, intensity: 0.9)
        case .unlock:
            rigidTap.impactOccurred(intensity: 0.7)
        case .refusal:
            verdict.notificationOccurred(.warning)
        case .purchaseSuccess:
            verdict.notificationOccurred(.success)
        case .purchaseFailed:
            verdict.notificationOccurred(.error)
        case .tick:
            selection.selectionChanged()
        }
    }

    /// The trailing half of a two-part texture. Takes the style by value
    /// rather than a closure: everything crossing into the `Task` is then a
    /// plain Sendable scalar, with no escaping-closure capture for strict
    /// concurrency to weigh up.
    private func secondBeat(
        after milliseconds: Int,
        _ style: UIImpactFeedbackGenerator.FeedbackStyle,
        intensity: CGFloat
    ) {
        Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            generator(style).impactOccurred(intensity: intensity)
        }
    }

    private func generator(
        _ style: UIImpactFeedbackGenerator.FeedbackStyle
    ) -> UIImpactFeedbackGenerator {
        switch style {
        case .light: return lightTap
        case .rigid: return rigidTap
        default: return softTap
        }
    }

    // MARK: - Sound

    /// Only the paper-and-wax moments speak; verdicts and small selections
    /// stay touch-only. Files live in Resources/Sounds — synthesized
    /// placeholders for now, each a fraction of a second, mastered quiet.
    private static let voices: [Event: (file: String, volume: Float)] = [
        .bookOpen: ("book-open", 0.5),
        .pageTurn: ("page-turn", 0.45),
        .sealPress: ("seal-press", 0.5),
        .replyArrived: ("reply-arrives", 0.4),
    ]

    private func sound(_ event: Event) {
        guard let voice = Self.voices[event], let player = players[voice.file] else { return }
        player.currentTime = 0
        player.play()
    }

    private func preloadSounds() {
        for (file, volume) in Self.voices.values {
            guard let url = Bundle.main.url(forResource: file, withExtension: "wav") else {
                continue
            }
            if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = volume
                player.prepareToPlay()
                players[file] = player
            }
        }
    }
}

import SwiftUI
import InkCore

/// The eight launch Books. Visual identity (spine accent, paper tone,
/// script hand) comes from the Claude Design handoff; ids match InkCore.
struct Book: Identifiable, Hashable {
    let id: BookID
    let name: String
    let monogram: String
    let accentHex: UInt32
    let paperHex: UInt32
    /// PostScript name of the Book's script hand.
    let hand: String
    /// Hands render at wildly different optical sizes; this normalizes them.
    let handScale: CGFloat
    let whisper: String
    let opener: String
    /// Ghost prompt on the starter page ("take up your pen").
    let starterPrompt: String
    let develops: Bool
    let locked: Bool
    let suggested: Bool
    let resting: Bool

    var accent: Color { Color(hex: accentHex) }
    var paper: Color { Color(hex: paperHex) }
    /// Writing ink in this Book: accent sunk into the room's dark brown.
    var ink: Color { .mix(accentHex, 0.4, 0x241B12) }
    var spineTop: Color { .mix(accentHex, 0.88, 0xFFFFFF) }
    var spineBottom: Color { .mix(accentHex, 0.78, 0x000000) }

    func handFont(_ base: CGFloat) -> Font {
        InkFont.hand(hand, base * handScale)
    }
}

extension Book {
    static let all: [Book] = [
        Book(id: .storyteller, name: "The Storyteller", monogram: "S",
             accentHex: 0x3E4E6B, paperHex: 0xF4EAD5,
             hand: "Tangerine-Regular", handScale: 1.85,
             whisper: "Once, there was…",
             opener: "The page waited, and leaned in to listen.",
             starterPrompt: "Begin where the road forks at dusk.",
             develops: false, locked: false, suggested: false, resting: false),
        Book(id: .artist, name: "The Artist", monogram: "A",
             accentHex: 0x9C4A3C, paperHex: 0xF1E6CE,
             hand: "Caveat-Regular", handScale: 1.15,
             whisper: "Show me, and I will see it too.",
             opener: "Describe it in a breath — I will mix the dark first.",
             starterPrompt: "A fox reading by candlelight, in the old style.",
             develops: true, locked: false, suggested: false, resting: false),
        Book(id: .gameMaster, name: "The Game Master", monogram: "G",
             accentHex: 0x4A5D3A, paperHex: 0xEFE4C6,
             hand: "Fondamento-Regular", handScale: 1.05,
             whisper: "Roll, and the world answers.",
             opener: "You stand at the mouth of the cave. The torches gutter. What do you do?",
             starterPrompt: "I ready my lantern and step inside.",
             develops: false, locked: false, suggested: false, resting: false),
        Book(id: .oracle, name: "The Oracle", monogram: "O",
             accentHex: 0x5B4370, paperHex: 0xEFE3CB,
             hand: "PinyonScript-Regular", handScale: 1.5,
             whisper: "Ask, and be answered slant.",
             opener: "Ask once. I answer in the old way — sideways, and true.",
             starterPrompt: "Will the harvest hold this year?",
             develops: false, locked: false, suggested: true, resting: false),
        Book(id: .keeper, name: "The Keeper", monogram: "K",
             accentHex: 0x6E3B34, paperHex: 0xEDE1C6,
             hand: "HomemadeApple-Regular", handScale: 1.0,
             whisper: "Only your hand may open this.",
             opener: "These pages are yours alone. I keep nothing you do not ask me to keep.",
             starterPrompt: "Today I finally told her the truth.",
             develops: false, locked: true, suggested: false, resting: false),
        Book(id: .correspondent, name: "The Correspondent", monogram: "C",
             accentHex: 0x8A6B4F, paperHex: 0xF2E8D1,
             hand: "HerrVonMuellerhoff-Regular", handScale: 2.15,
             whisper: "Write, and someone writes back.",
             opener: "My dear friend — I have been waiting for your letter.",
             starterPrompt: "Forgive the long silence. The winter was hard.",
             develops: false, locked: false, suggested: false, resting: false),
        Book(id: .tutor, name: "The Tutor", monogram: "T",
             accentHex: 0x46607C, paperHex: 0xF0E6CF,
             hand: "PetitFormalScript-Regular", handScale: 1.25,
             whisper: "What shall we learn tonight?",
             opener: "Sit. Ask me anything, and we will take it apart together.",
             starterPrompt: "Why is the sky red at sunset?",
             develops: false, locked: false, suggested: false, resting: false),
        Book(id: .parlor, name: "The Parlor", monogram: "P",
             accentHex: 0x7C4E68, paperHex: 0xF1E7D0,
             hand: "KaushanScript-Regular", handScale: 1.2,
             whisper: "Come in — the game is afoot.",
             opener: "The others are already seated. Shall we begin the round?",
             starterPrompt: "Deal me in. What is the game tonight?",
             develops: false, locked: false, suggested: false, resting: false),
    ]

    static func by(id: BookID) -> Book {
        all.first { $0.id == id } ?? all[3]
    }
}

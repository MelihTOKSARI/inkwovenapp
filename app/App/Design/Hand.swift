import SwiftUI

/// The eight script hands the room can write in — one per launch Book, every
/// face shipped in the bundle (UIAppFonts in project.yml). A Book wears its
/// own hand by default; the writer may re-dress a single Book from its page,
/// or the whole shelf from the Drawer. AppModel owns that choice.
struct Hand: Identifiable, Hashable {
    /// PostScript name, exactly as UIFont resolves it.
    let id: String
    /// What the room calls it.
    let name: String
    /// Hands render at wildly different optical sizes; this normalizes them
    /// (the same corrections the Book presets carry).
    let scale: CGFloat
}

extension Hand {
    static let all: [Hand] = [
        Hand(id: "Caveat-Regular", name: "The Quick Hand", scale: 1.15),
        Hand(id: "Tangerine-Regular", name: "The Flourished Hand", scale: 1.85),
        Hand(id: "Fondamento-Regular", name: "The Chancery Hand", scale: 1.05),
        Hand(id: "PinyonScript-Regular", name: "The Copperplate Hand", scale: 1.5),
        Hand(id: "HomemadeApple-Regular", name: "The Honest Hand", scale: 1.0),
        Hand(id: "HerrVonMuellerhoff-Regular", name: "The Spencerian Hand", scale: 2.15),
        Hand(id: "PetitFormalScript-Regular", name: "The Formal Hand", scale: 1.25),
        Hand(id: "KaushanScript-Regular", name: "The Brush Hand", scale: 1.2),
    ]

    static func by(id: String) -> Hand? {
        all.first { $0.id == id }
    }
}

extension Book {
    /// This Book re-dressed in another hand — name, paper and ink unchanged.
    func wearing(_ hand: Hand) -> Book {
        Book(
            id: id, name: name, monogram: monogram,
            accentHex: accentHex, paperHex: paperHex,
            hand: hand.id, handScale: hand.scale,
            whisper: whisper, opener: opener, starterPrompt: starterPrompt,
            develops: develops, locked: locked, suggested: suggested, resting: resting
        )
    }
}

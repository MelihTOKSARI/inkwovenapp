import Foundation
import InkCore
import PencilKit
import UIKit
import Vision

/// The writer's own Book, as the app holds it: the six answers of the binding
/// conversation plus the two refinements the bookplate adds later. Persisted
/// as JSON under `ink.customBinding`; nil means the blank book stands on the
/// shelf unbound. The name's ink strokes ride separately (`ink.customNameInk`)
/// so the spine can wear the writer's actual hand.
struct CustomBinding: Codable, Equatable {
    var you = ""
    var me = ""
    var place = ""
    var temper = ""
    var tongue = ""
    var fact = ""
    var length = ""
    var never = ""
    var boundAt = Date.now

    /// The palette the binding may take — the eight Book accents; the dye is
    /// drawn from the writer's own words so two bindings rarely match.
    private static let palette: [UInt32] = [
        0x5B4370, 0x3E4E6B, 0x46607C, 0x4A5D3A, 0x8A6B4F, 0x7C4E68, 0x6E3B34, 0x9C4A3C,
    ]

    var accentHex: UInt32 {
        var h: UInt32 = 0
        for byte in (place + temper).utf8 { h = h &* 31 &+ UInt32(byte) }
        return Self.palette[Int(h % UInt32(Self.palette.count))]
    }

    /// The spine's title. "The Unnamed" is the design's fallback, not an
    /// error state — an unnamed book is still a bound one.
    var displayName: String {
        me.isEmpty ? "The Unnamed" : me
    }

    /// The ring's letter: the first letter of the name, articles dropped —
    /// "The Night Kitchen" wears N, not T.
    var monogram: String {
        var name = displayName.lowercased()
        for article in ["the ", "a ", "an "] where name.hasPrefix(article) {
            name.removeFirst(article.count)
        }
        return name.first.map { String($0).uppercased() } ?? "·"
    }

    /// The card under the spine, in the design's own wording.
    var card: String {
        switch (temper.isEmpty, place.isEmpty) {
        case (false, false): "\(temper), from \(place)"
        case (false, true): temper
        case (true, false): "from \(place)"
        case (true, true): "a book in your own hand"
        }
    }

    var opener: String {
        let name = you.isEmpty ? "friend" : you
        return "I am bound, \(name), and I answer only you. Write."
    }

    /// The binding as it travels: empty answers stay off the wire so the
    /// proxy's fallbacks — not empty strings — fill the gaps.
    var wireCard: BindingCard {
        func field(_ s: String) -> String? { s.isEmpty ? nil : s }
        return BindingCard(
            you: field(you), me: field(me), place: field(place), temper: field(temper),
            tongue: field(tongue), fact: field(fact), length: field(length), never: field(never)
        )
    }
}

extension Book {
    /// The blank leather the unwritten book wears — warm, unfinished, never
    /// reading as locked or missing.
    static let blankLeatherHex: UInt32 = 0x71634F

    /// The writer's own Book as the shelf draws it: blank until bound, then
    /// dressed in the binding's dye and name.
    static func custom(_ binding: CustomBinding?) -> Book {
        if let binding {
            Book(
                id: .custom, name: binding.displayName, monogram: binding.monogram,
                accentHex: binding.accentHex, paperHex: 0xF2E8D1,
                hand: "Caveat-Regular", handScale: 1.15,
                whisper: binding.card,
                opener: binding.opener,
                starterPrompt: "Ask me what you would ask no one else.",
                develops: false, locked: false, suggested: false, resting: false,
                blank: false
            )
        } else {
            Book(
                id: .custom, name: "", monogram: "",
                accentHex: blankLeatherHex, paperHex: 0xF2E8D1,
                hand: "Caveat-Regular", handScale: 1.15,
                whisper: "a book that answers however you ask it to",
                opener: "",
                starterPrompt: "",
                develops: false, locked: false, suggested: false, resting: false,
                blank: true
            )
        }
    }
}

/// On-device transcription of a drawn binding answer. The answers must reach
/// the proxy as text; the same Vision engine the Remembered search uses reads
/// them here, so nothing leaves the device and nothing spends a moment.
enum BindingInkReader {
    static func transcribe(_ drawingData: Data) async -> String {
        guard let drawing = try? PKDrawing(data: drawingData),
              !drawing.strokes.isEmpty
        else { return "" }
        let bounds = drawing.bounds.insetBy(dx: -24, dy: -24)
        let inked = drawing.image(from: bounds, scale: 2)
        // Vision wants ink on paper, not ink on nothing: flatten onto white
        // before asking it to read.
        let flattened = UIGraphicsImageRenderer(size: inked.size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: inked.size))
            inked.draw(at: .zero)
        }
        guard let cgImage = flattened.cgImage else { return "" }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage)
            guard (try? handler.perform([request])) != nil else { return "" }
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

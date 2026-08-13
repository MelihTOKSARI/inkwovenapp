import Foundation

/// Identity of a Book. Definitions (prompt, hand, ink, paper, modality policy,
/// model routing) live server-side; the client only ever holds the ID and the
/// user's per-Book state.
public struct BookID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }

    public static let oracle = BookID("oracle")
    public static let keeper = BookID("keeper")
    public static let storyteller = BookID("storyteller")
    public static let artist = BookID("artist")
    public static let gameMaster = BookID("gm")
    public static let correspondent = BookID("correspondent")
    public static let tutor = BookID("tutor")
    public static let parlor = BookID("parlor")
    /// The writer's own Book — bound in the app, promptless on the server
    /// until each page carries its binding. Not on the launch shelf: it
    /// arrives, blank, once the writer has learned the loop.
    public static let custom = BookID("custom")

    public static let launchShelf: [BookID] = [
        .oracle, .keeper, .storyteller, .artist, .gameMaster, .correspondent, .tutor, .parlor,
    ]
}

/// The writer's own Book, as its binding travels the wire: structured voice
/// fields the proxy composes into a prompt. Deliberately not a free-form
/// prompt — every field is one short line, capped again server-side.
public struct BindingCard: Equatable, Sendable, Codable {
    /// What the Book calls the writer.
    public var you: String?
    /// What the writer calls the Book — the spine's title.
    public var me: String?
    /// Place and era; they colour the voice.
    public var place: String?
    /// Kind, honest, or the writer's own word for it.
    public var temper: String?
    /// The language every reply arrives in.
    public var tongue: String?
    /// The one thing the Book knows about the writer.
    public var fact: String?
    /// How long its replies run.
    public var length: String?
    /// A standing refusal, in the writer's words.
    public var never: String?

    enum CodingKeys: String, CodingKey {
        case you, me, place = "where", temper, tongue, fact, length, never
    }

    public init(
        you: String? = nil, me: String? = nil, place: String? = nil, temper: String? = nil,
        tongue: String? = nil, fact: String? = nil, length: String? = nil, never: String? = nil
    ) {
        self.you = you
        self.me = me
        self.place = place
        self.temper = temper
        self.tongue = tongue
        self.fact = fact
        self.length = length
        self.never = never
    }
}

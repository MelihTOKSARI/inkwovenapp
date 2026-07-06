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

    public static let launchShelf: [BookID] = [
        .oracle, .keeper, .storyteller, .artist, .gameMaster, .correspondent, .tutor, .parlor,
    ]
}

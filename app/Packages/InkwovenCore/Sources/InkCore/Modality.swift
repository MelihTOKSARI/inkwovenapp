import Foundation

/// The three grammars of the paper engine.
public enum Modality: String, Codable, Sendable, CaseIterable {
    case ink
    case image
    case video
}

/// What a materialized reply is. `assetRef` is an opaque reference to a local
/// asset (file name / CKAsset key), resolved by the shell.
///
/// `creditTxID` is optional because a missing credit link is a NORMAL state,
/// not a corruption: CloudKit mirroring requires every attribute optional, so a
/// partially-synced video reply legitimately arrives without one. It must stay
/// visibly absent — inventing an id here would break `Equatable` reflexivity
/// and mint a transaction the ledger has never heard of, stranding the refund.
public enum ReplyKind: Equatable, Sendable, Codable {
    case ink(text: String)
    case image(assetRef: String)
    case video(assetRef: String, creditTxID: UUID?)

    public var modality: Modality {
        switch self {
        case .ink: .ink
        case .image: .image
        case .video: .video
        }
    }
}

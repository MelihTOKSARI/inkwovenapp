import Foundation

/// The three grammars of the paper engine.
public enum Modality: String, Codable, Sendable, CaseIterable {
    case ink
    case image
    case video
}

/// What a materialized reply is. `assetRef` is an opaque reference to a local
/// asset (file name / CKAsset key), resolved by the shell.
public enum ReplyKind: Equatable, Sendable, Codable {
    case ink(text: String)
    case image(assetRef: String)
    case video(assetRef: String, creditTxID: UUID)

    public var modality: Modality {
        switch self {
        case .ink: .ink
        case .image: .image
        case .video: .video
        }
    }
}

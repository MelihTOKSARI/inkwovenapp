import Foundation
import SwiftData
import InkCore

// CloudKit-ready SwiftData models (task A2): every attribute has a default,
// no unique constraints, relationships optional — the private-database
// mirroring rules. Conflict policy: last-writer-wins per Page; replies are
// append-only and merge by id.

@Model
public final class Notebook {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var coverID: String = "default"
    @Relationship(deleteRule: .cascade, inverse: \BookState.notebook)
    public var books: [BookState]? = []

    public init(id: UUID = UUID(), createdAt: Date = Date(), coverID: String = "default") {
        self.id = id
        self.createdAt = createdAt
        self.coverID = coverID
    }
}

/// Per-user state of a Book. The Book definition itself (prompt, hand, paper,
/// modality policy, model routing) is server-side and never persisted here.
@Model
public final class BookState {
    public var bookID: String = ""
    public var lastOpenedAt: Date?
    /// Keeper is always locked; others opt in.
    public var isLocked: Bool = false
    public var notebook: Notebook?
    @Relationship(deleteRule: .cascade, inverse: \Page.book)
    public var pages: [Page]? = []
    @Relationship(deleteRule: .cascade, inverse: \MemoryEntry.book)
    public var memory: [MemoryEntry]? = []

    public init(bookID: BookID, isLocked: Bool = false) {
        self.bookID = bookID.rawValue
        self.isLocked = isLocked || bookID == .keeper
    }
}

@Model
public final class Page {
    public var id: UUID = UUID()
    public var bookID: String = ""
    public var createdAt: Date = Date()
    /// PKDrawing archive (`PKDrawing.dataRepresentation()`).
    public var strokeData: Data = Data()
    /// Dedupe key from the snapshot pipeline.
    public var snapshotDigest: String = ""
    /// Vision OCR result — the on-device handwriting search index (task D2).
    public var searchText: String?
    public var book: BookState?
    @Relationship(deleteRule: .cascade, inverse: \Reply.page)
    public var replies: [Reply]? = []

    public init(bookID: BookID, strokeData: Data = Data(), snapshotDigest: String = "") {
        self.bookID = bookID.rawValue
        self.strokeData = strokeData
        self.snapshotDigest = snapshotDigest
    }
}

@Model
public final class Reply {
    public var id: UUID = UUID()
    public var kindRaw: String = "ink"
    public var text: String?
    /// Local asset reference for image/video replies.
    public var assetRef: String?
    public var creditTxID: UUID?
    public var modelID: String = ""
    public var latencyMS: Int = 0
    public var createdAt: Date = Date()
    public var page: Page?

    public init(kind: ReplyKind, modelID: String, latencyMS: Int, createdAt: Date = Date()) {
        self.modelID = modelID
        self.latencyMS = latencyMS
        self.createdAt = createdAt
        self.kind = kind
    }

    /// Enum façade over the flat storage (SwiftData + CloudKit can't persist
    /// associated values directly).
    public var kind: ReplyKind {
        get {
            switch kindRaw {
            case "image":
                return .image(assetRef: assetRef ?? "")
            case "video":
                // A nil creditTxID stays nil. Fabricating one here made `kind`
                // non-deterministic (reply.kind != reply.kind) and, via the
                // setter round-trip below, persisted a transaction id matching
                // no ledger entry — so the refund path could never find the
                // reservation to release.
                return .video(assetRef: assetRef ?? "", creditTxID: creditTxID)
            default:
                return .ink(text: text ?? "")
            }
        }
        set {
            switch newValue {
            case .ink(let inkText):
                kindRaw = "ink"; text = inkText; assetRef = nil; creditTxID = nil
            case .image(let ref):
                kindRaw = "image"; assetRef = ref; text = nil; creditTxID = nil
            case .video(let ref, let txID):
                kindRaw = "video"; assetRef = ref; creditTxID = txID; text = nil
            }
        }
    }
}

/// Cross-page memory (Plus). `tornOut` entries stay on disk as tombstones so
/// sync can't resurrect them, but they never re-enter context (InkCore.
/// MemoryInjection filters them) and never leave the device.
@Model
public final class MemoryEntry {
    public var bookID: String = ""
    public var summary: String = ""
    public var updatedAt: Date = Date()
    public var tornOut: Bool = false
    public var book: BookState?

    public init(bookID: BookID, summary: String, updatedAt: Date = Date()) {
        self.bookID = bookID.rawValue
        self.summary = summary
        self.updatedAt = updatedAt
    }

    public var asSummary: MemorySummary {
        MemorySummary(bookID: BookID(bookID), summary: summary, updatedAt: updatedAt, tornOut: tornOut)
    }
}

/// Local mirror of wallet history for offline display; the proxy's ledger is
/// authoritative (idempotency keys on reserve/settle/release).
@Model
public final class CreditTransaction {
    public var id: UUID = UUID()
    public var delta: Int = 0
    public var reasonRaw: String = ""
    public var at: Date = Date()

    public init(id: UUID = UUID(), delta: Int, reasonRaw: String, at: Date = Date()) {
        self.id = id
        self.delta = delta
        self.reasonRaw = reasonRaw
        self.at = at
    }
}

public enum InkStore {
    /// Computed, not a stored `static let`: `Schema` is not `Sendable` under
    /// the 6.1 SDK, so a stored global trips strict-concurrency checking there
    /// while compiling clean on 6.3. Building it per call costs nothing — it is
    /// read once, at container creation — and keeps one source that both
    /// toolchains accept without an unsafe opt-out.
    public static var schema: Schema {
        Schema([
            Notebook.self, BookState.self, Page.self, Reply.self, MemoryEntry.self, CreditTransaction.self,
        ])
    }

    /// In-memory for tests; on-device the app shell configures CloudKit
    /// mirroring (private database) on this same schema.
    public static func container(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}

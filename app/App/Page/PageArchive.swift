import Foundation
import OSLog
import PencilKit
import InkCore

/// Where a finished exchange's strokes rest (task B3's archive half).
/// Minimal local store until InkData/CloudKit binds: PKDrawing archives +
/// reply text as JSON in Application Support. PageInteractor writes it on
/// `.exchangeComplete`; RememberedView reads it.
protocol PageArchiving: AnyObject {
    @MainActor @discardableResult
    func archive(book: BookID, drawing: PKDrawing, typedText: String?, replyText: String) -> UUID
}

/// The Keeper's pages live in their own file and are read off disk only while
/// the gate stands open — the lock has to cover the data, not just the route
/// to it.
@Observable
@MainActor
final class PageArchive: PageArchiving {
    struct Entry: Identifiable, Codable, Equatable {
        let id: UUID
        let bookID: String
        let createdAt: Date
        /// PKDrawing archive — mirrors `Page.strokeData` in the InkData schema.
        let strokeData: Data
        /// The typed hand's page, when the keyboard wrote it instead of ink.
        /// Optional so pre-existing archives still decode.
        var typedText: String?
        let replyText: String
    }

    /// Every Book but the Keeper.
    private(set) var entries: [Entry] = []
    /// When any page last archived — a date and nothing else. The Keeper's
    /// writes count without breaking the seal: the evening ritual has to stay
    /// silent on a day the user wrote, whichever Book kept the page, and the
    /// sealed store cannot be scanned for that answer.
    private(set) var lastWrittenAt: Date?
    /// The Keeper's pages, resident only between `unsealKeeper()` and
    /// `sealKeeper()`. While the gate is shut they are not in memory to hand
    /// out, to dump, or to leak into a crash report.
    private var keeperEntries: [Entry] = []
    private(set) var keeperUnsealed = false

    private let directory: URL
    private let openFileURL: URL
    private let keeperFileURL: URL
    private let lastWrittenURL: URL
    /// A store that exists but could not be read is not an empty store. These
    /// hold writes back so the next page never overwrites something still
    /// recoverable.
    private var openWritesBlocked = false
    private var keeperWritesBlocked = false

    private static let log = Logger(subsystem: "com.empath.inkwoven", category: "archive")

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.directory = dir
        openFileURL = dir.appending(path: "remembered-pages.json")
        keeperFileURL = dir.appending(path: "keeper-pages.json")
        lastWrittenURL = dir.appending(path: "last-written.json")
        if let data = try? Data(contentsOf: lastWrittenURL) {
            lastWrittenAt = try? JSONDecoder().decode(Date.self, from: data)
        }
        switch Self.load(from: openFileURL) {
        case .loaded(let loaded): entries = loaded
        case .absent: break
        case .blocked: openWritesBlocked = true
        }
        migrateKeeperPagesIfNeeded()
    }

    @discardableResult
    func archive(book: BookID, drawing: PKDrawing, typedText: String?, replyText: String) -> UUID {
        let entry = Entry(
            id: UUID(), bookID: book.rawValue, createdAt: .now,
            strokeData: drawing.dataRepresentation(), typedText: typedText, replyText: replyText
        )
        if book == .keeper {
            // A completed exchange can land after the gate has shut (the user
            // backgrounded the app mid-answer). The page must still be saved,
            // but the seal may not be left open behind it: `entries(for:)`
            // keys off `keeperUnsealed`, so a latched unseal would hand the
            // Keeper's pages out while the lock reads as closed.
            let wasSealed = !keeperUnsealed
            if wasSealed { unsealKeeper() }
            keeperEntries.insert(entry, at: 0)
            persist(keeperEntries, to: keeperFileURL, blocked: keeperWritesBlocked)
            if wasSealed { sealKeeper() }
        } else {
            entries.insert(entry, at: 0)
            persist(entries, to: openFileURL, blocked: openWritesBlocked)
        }
        recordWrite(at: entry.createdAt)
        return entry.id
    }

    /// The timestamp bypasses the write-holds deliberately: even when a store
    /// is blocked the page was still written tonight, and the ritual must not
    /// ring over it.
    private func recordWrite(at date: Date) {
        lastWrittenAt = date
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            try JSONEncoder().encode(date)
                .write(to: lastWrittenURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            Self.log.error("last-written stamp failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func entries(for book: BookID) -> [Entry] {
        if book == .keeper {
            return keeperUnsealed ? keeperEntries : []
        }
        return entries.filter { $0.bookID == book.rawValue }
    }

    /// "Delete all pages." Tears out every page in every Book: the open
    /// shelf's store, the Keeper's file (without unsealing it — the bytes go,
    /// the contents are never read), and any quarantined corrupt store, which
    /// is still the user's ink. The write-holds clear only when every file is
    /// verifiably gone; a partial wipe keeps them, and the caller must say so
    /// rather than let the dialog's promise stand broken.
    @discardableResult
    func deleteAll() -> Bool {
        entries.removeAll()
        keeperEntries.removeAll()
        lastWrittenAt = nil

        let fm = FileManager.default
        var targets = [openFileURL, keeperFileURL, lastWrittenURL]
        if let siblings = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            targets += siblings.filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("remembered-pages.json.corrupt-")
                    || name.hasPrefix("keeper-pages.json.corrupt-")
            }
        }
        var allRemoved = true
        for url in targets where fm.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                try fm.removeItem(at: url)
            } catch {
                Self.log.error("delete-all could not remove a store: \(error.localizedDescription, privacy: .public)")
                allRemoved = false
            }
        }
        if allRemoved {
            openWritesBlocked = false
            keeperWritesBlocked = false
        }
        return allRemoved
    }

    // MARK: - The Keeper's seal

    /// Called once the gate has opened. Reads the Keeper's file for the first
    /// time this session.
    func unsealKeeper() {
        guard !keeperUnsealed else { return }
        switch Self.load(from: keeperFileURL) {
        case .loaded(let loaded): keeperEntries = loaded
        case .absent: keeperEntries = []
        case .blocked:
            keeperEntries = []
            keeperWritesBlocked = true
        }
        keeperUnsealed = true
    }

    /// Called when the Keeper re-locks — on backgrounding, and on any route
    /// away that closes the gate. The pages leave memory with it.
    func sealKeeper() {
        keeperEntries.removeAll()
        keeperWritesBlocked = false
        keeperUnsealed = false
    }

    // MARK: - Disk

    private static func defaultDirectory() -> URL {
        do {
            return try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
        } catch {
            // Documented as possibly empty / failing; a lost archive beats a
            // launch crash, since PageArchive is built during App init.
            log.error("application support unavailable: \(error.localizedDescription, privacy: .public)")
            return URL.applicationSupportDirectory
        }
    }

    private enum LoadResult {
        case loaded([Entry])
        case absent
        /// Present but unreadable — file protection before first unlock, a
        /// permissions problem, a truncated read.
        case blocked
    }

    private static func load(from url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return .absent
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.error("archive unreadable: \(error.localizedDescription, privacy: .public)")
            return .blocked
        }
        do {
            return .loaded(try JSONDecoder().decode([Entry].self, from: data))
        } catch {
            // The whole journal is one JSON array, so a single bad byte used
            // to take every page with it (audit D-7). Try to salvage the
            // entries that still decode before giving up: decode the array
            // leniently, keeping what survives.
            if let salvaged = salvage(data), !salvaged.isEmpty {
                log.error("archive partly corrupt; salvaged \(salvaged.count, privacy: .public) pages")
                quarantine(url) // the original stays recoverable
                return .loaded(salvaged)
            }
            // Nothing decodable: move it aside before anything writes over it,
            // so a corrupt store is recoverable instead of silently replaced
            // by the next page. Only the error's type is logged — never the
            // bytes, which are the user's pages.
            log.error("archive corrupt, quarantining: \(String(describing: type(of: error)), privacy: .public)")
            quarantine(url)
            return .absent
        }
    }

    /// Decodes an array element-wise, dropping only what cannot be read. One
    /// truncated entry costs the user that entry, not their whole journal.
    private static func salvage(_ data: Data) -> [Entry]? {
        // `[FailableEntry]` decodes the outer array even when members fail;
        // a malformed OUTER array still throws, which is the real total loss
        // and falls through to quarantine.
        struct FailableEntry: Decodable {
            let entry: Entry?
            init(from decoder: Decoder) throws {
                entry = try? Entry(from: decoder)
            }
        }
        guard let wrapped = try? JSONDecoder().decode([FailableEntry].self, from: data) else {
            return nil
        }
        return wrapped.compactMap(\.entry)
    }

    private static func quarantine(_ url: URL) {
        let stamp = Int(Date.now.timeIntervalSince1970)
        do {
            try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt-\(stamp)"))
        } catch {
            log.error("quarantine failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    private func persist(_ snapshot: [Entry], to url: URL, blocked: Bool) -> Bool {
        guard !blocked else {
            Self.log.error("archive write held back: the existing store could not be read")
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            // `.completeUnlessOpen`, not `.complete`: completeExchange can
            // archive from a task that lands after the screen has locked, and
            // `.complete` would fail that write outright — losing the page the
            // user just wrote. This class still leaves the file unreadable at
            // rest to anything that cannot open it before the lock, which is
            // the guarantee the Keeper's UI has been making all along.
            try JSONEncoder().encode(snapshot)
                .write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            if url == keeperFileURL { excludeFromBackup(url) }
            return true
        } catch {
            Self.log.error("archive write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The Keeper's file only. A protected file in a backup is still restorable
    /// and readable on the restoring device, which is the whole exposure. The
    /// shared archive stays in backup deliberately — losing an ordinary
    /// journal on device migration is real harm, and that is a product call.
    private func excludeFromBackup(_ url: URL) {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try target.setResourceValues(values)
        } catch {
            Self.log.error("backup exclusion failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Earlier builds kept every Book in one unprotected file. Move the
    /// Keeper's pages into their own store on the first launch after the
    /// split, so the lock covers what is already on disk. Runs only while the
    /// Keeper's file does not yet exist, so it never needs to read it — the
    /// seal stays shut through migration.
    private func migrateKeeperPagesIfNeeded() {
        guard !FileManager.default.fileExists(atPath: keeperFileURL.path(percentEncoded: false)) else {
            // Even with the sealed store present, a PARTIAL earlier migration
            // can have left Keeper pages in the open array (audit C-7): the
            // sealed write succeeded, the open rewrite did not. The Drawer's
            // export reads `entries` directly, so a stray sealed page would
            // walk straight out through a share sheet. Drop them from memory
            // unconditionally — they are already in the sealed store.
            dropStrayKeeperPages()
            return
        }
        let strays = entries.filter { $0.bookID == BookID.keeper.rawValue }
        guard !strays.isEmpty else { return }
        // Write the new store first: only once it is safely on disk do the
        // pages leave the old one.
        guard persist(strays, to: keeperFileURL, blocked: false) else {
            Self.log.error("keeper migration deferred: could not write the sealed store")
            return
        }
        let remaining = entries.filter { $0.bookID != BookID.keeper.rawValue }
        entries = remaining
        // The in-memory array is corrected FIRST and unconditionally: a failed
        // rewrite of the open file must not leave sealed pages readable
        // through `entries` for the whole session. The next successful write
        // fixes the file; until then the pages simply live in the sealed
        // store, where they belong.
        if !persist(remaining, to: openFileURL, blocked: openWritesBlocked) {
            Self.log.error("keeper migration: sealed store written, open store rewrite deferred")
        }
    }

    /// Removes any Keeper page still standing in the open array. The sealed
    /// store is the authority for those; `entries` must never carry one.
    private func dropStrayKeeperPages() {
        let remaining = entries.filter { $0.bookID != BookID.keeper.rawValue }
        guard remaining.count != entries.count else { return }
        Self.log.error("open store carried sealed pages; dropping them from memory")
        entries = remaining
        _ = persist(remaining, to: openFileURL, blocked: openWritesBlocked)
    }
}

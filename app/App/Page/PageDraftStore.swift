import Foundation
import OSLog
import PencilKit
import InkCore

/// One page's unsent work, exactly as it stands: the live drawing, the typed
/// draft, and how many strokes are already accounted for (restored by a
/// revisit or absorbed by a completed exchange) — rehydrating must not let
/// those read as unsent, or a relaunch re-sends an archived page.
struct PageDraft: Codable, Equatable {
    var strokeData: Data
    var typedText: String
    var accountedStrokeCount: Int
}

/// Where unsent ink rests between launches (audit T9/D-1). Before this store
/// existed a page lived only in RAM until an exchange completed: a jetsam, a
/// Book switch, a tap on the shelf, or a crisis interception destroyed it.
protocol PageDraftStoring: AnyObject {
    @MainActor func load(book: BookID) -> PageDraft?
    @MainActor func save(_ draft: PageDraft, book: BookID)
    @MainActor func clear(book: BookID)
    /// "Delete all pages" covers the unsent ones too.
    @MainActor func deleteAll()
}

/// One file per Book in Application Support, written with the same protection
/// class as the archive (`.completeUnlessOpen` — a draft can be saved from a
/// scene-phase change racing the lock screen). The Keeper's draft follows the
/// Keeper's rules: excluded from backup like its sealed store, and only ever
/// rehydrated behind the gate — `RootView`'s structural lock means a Keeper
/// `PageView` (and therefore `attach(canvas:)`) cannot exist while sealed.
@MainActor
final class PageDraftStore: PageDraftStoring {
    private let directory: URL
    private static let log = Logger(subsystem: "com.empath.inkwoven", category: "draft")

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    func load(book: BookID) -> PageDraft? {
        let url = fileURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let draft = try? JSONDecoder().decode(PageDraft.self, from: data) else {
            // A draft is seconds-old work, not an archive: an unreadable one
            // has nothing recoverable in it, and leaving it poisons every
            // future rehydrate. Clear it rather than quarantine it.
            Self.log.error("draft unreadable; clearing")
            clear(book: book)
            return nil
        }
        return draft
    }

    func save(_ draft: PageDraft, book: BookID) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            let url = fileURL(for: book)
            try JSONEncoder().encode(draft)
                .write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
            // The Keeper's unsent ink is as sealed as its finished pages: a
            // protected file in a backup is still restorable and readable on
            // the restoring device.
            if book == .keeper { excludeFromBackup(url) }
        } catch {
            Self.log.error("draft write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func clear(book: BookID) {
        let url = fileURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.log.error("draft clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func deleteAll() {
        let fm = FileManager.default
        guard let siblings = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in siblings where url.lastPathComponent.hasPrefix("page-draft-") {
            try? fm.removeItem(at: url)
        }
    }

    private func fileURL(for book: BookID) -> URL {
        directory.appending(path: "page-draft-\(book.rawValue).json")
    }

    private static func defaultDirectory() -> URL {
        do {
            return try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            )
        } catch {
            log.error("application support unavailable: \(error.localizedDescription, privacy: .public)")
            return URL.applicationSupportDirectory
        }
    }

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
}

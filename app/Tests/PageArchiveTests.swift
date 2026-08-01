import Testing
import Foundation
import PencilKit
import InkCore
@testable import Inkwoven

/// The Keeper's lock has to cover the data, not just the route to it: sealed
/// pages are neither handed out nor resident, and the store on disk is
/// protected, quarantined rather than clobbered when unreadable, and never
/// crashes on a missing directory.
@MainActor
@Suite("Page archive")
struct PageArchiveTests {
    private func scratchDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "page-archive-\(UUID().uuidString)")
    }

    private func oneStroke() -> PKDrawing {
        let points = (0..<6).map { i in
            PKStrokePoint(
                location: CGPoint(x: 40 + CGFloat(i) * 10, y: 90),
                timeOffset: Double(i) * 0.02,
                size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: points, creationDate: .now)
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    // MARK: - The seal

    @Test("a sealed Keeper hands out nothing, even for pages it holds")
    func sealedKeeperReturnsNothing() throws {
        let dir = scratchDirectory()
        let archive = PageArchive(directory: dir)
        archive.unsealKeeper()
        archive.archive(book: .keeper, drawing: oneStroke(), typedText: nil, replyText: "kept")

        #expect(archive.entries(for: .keeper).count == 1)

        archive.sealKeeper()

        #expect(archive.keeperUnsealed == false)
        #expect(archive.entries(for: .keeper).isEmpty, "sealed means the pages are not in memory to hand out")
    }

    @Test("a fresh archive starts sealed — Keeper pages are not read at launch")
    func launchesSealed() throws {
        let dir = scratchDirectory()
        let first = PageArchive(directory: dir)
        first.unsealKeeper()
        first.archive(book: .keeper, drawing: oneStroke(), typedText: nil, replyText: "kept")

        let second = PageArchive(directory: dir)

        #expect(second.keeperUnsealed == false)
        #expect(second.entries.isEmpty, "the Keeper's pages never enter the shared, always-resident array")
        #expect(second.entries(for: .keeper).isEmpty)

        second.unsealKeeper()
        #expect(second.entries(for: .keeper).count == 1)
        #expect(second.entries(for: .keeper).first?.replyText == "kept")
    }

    @Test("open Books are unaffected by the seal")
    func openBooksIgnoreTheSeal() throws {
        let archive = PageArchive(directory: scratchDirectory())
        archive.archive(book: .oracle, drawing: oneStroke(), typedText: nil, replyText: "slant")
        archive.sealKeeper()

        #expect(archive.entries(for: .oracle).count == 1)
    }

    @Test("the Keeper's pages are written to their own file, not the shared one")
    func keeperHasItsOwnFile() throws {
        let dir = scratchDirectory()
        let archive = PageArchive(directory: dir)
        archive.archive(book: .oracle, drawing: oneStroke(), typedText: nil, replyText: "slant")
        archive.unsealKeeper()
        archive.archive(book: .keeper, drawing: oneStroke(), typedText: nil, replyText: "kept")

        let shared = try Data(contentsOf: dir.appending(path: "remembered-pages.json"))
        let sealed = try Data(contentsOf: dir.appending(path: "keeper-pages.json"))
        let sharedEntries = try JSONDecoder().decode([PageArchive.Entry].self, from: shared)

        #expect(sharedEntries.count == 1)
        #expect(sharedEntries.first?.bookID == BookID.oracle.rawValue)
        #expect(sealed.isEmpty == false)
    }

    // MARK: - Migration

    @Test("legacy single-file archives move their Keeper pages into the sealed store")
    func migratesLegacyKeeperPages() throws {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let legacy = [
            PageArchive.Entry(
                id: UUID(), bookID: BookID.keeper.rawValue, createdAt: .now,
                strokeData: oneStroke().dataRepresentation(), typedText: nil, replyText: "kept"
            ),
            PageArchive.Entry(
                id: UUID(), bookID: BookID.oracle.rawValue, createdAt: .now,
                strokeData: oneStroke().dataRepresentation(), typedText: nil, replyText: "slant"
            ),
        ]
        try JSONEncoder().encode(legacy).write(to: dir.appending(path: "remembered-pages.json"))

        let archive = PageArchive(directory: dir)

        #expect(archive.entries.count == 1, "the Keeper's page left the shared, always-resident array")
        #expect(archive.entries(for: .oracle).count == 1)
        #expect(archive.entries(for: .keeper).isEmpty, "and it is sealed, not merely moved")

        archive.unsealKeeper()
        #expect(archive.entries(for: .keeper).count == 1)
    }

    // MARK: - Files

    @Test("both stores carry a file protection class")
    func storesAreProtected() throws {
        let dir = scratchDirectory()
        let archive = PageArchive(directory: dir)
        archive.archive(book: .oracle, drawing: oneStroke(), typedText: nil, replyText: "slant")
        archive.unsealKeeper()
        archive.archive(book: .keeper, drawing: oneStroke(), typedText: nil, replyText: "kept")

        for name in ["remembered-pages.json", "keeper-pages.json"] {
            let path = dir.appending(path: name).path(percentEncoded: false)
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            // Data protection is a device feature; the simulator reports no
            // class at all. Assert the class we asked for whenever one is
            // reported, rather than pinning a test to the host filesystem.
            guard let protection = attributes[.protectionKey] as? FileProtectionType else { continue }
            #expect(
                protection == .completeUnlessOpen,
                "\(name) must not sit at the default class — that is readable after first unlock"
            )
        }
    }

    @Test("the Keeper's store is excluded from backup")
    func keeperStoreIsNotBackedUp() throws {
        let dir = scratchDirectory()
        let archive = PageArchive(directory: dir)
        archive.unsealKeeper()
        archive.archive(book: .keeper, drawing: oneStroke(), typedText: nil, replyText: "kept")

        let values = try dir.appending(path: "keeper-pages.json")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("a corrupt store is quarantined, not overwritten by the next page")
    func corruptStoreIsQuarantined() throws {
        let dir = scratchDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appending(path: "remembered-pages.json")
        try Data("{ this was once a journal".utf8).write(to: fileURL)

        let archive = PageArchive(directory: dir)
        archive.archive(book: .oracle, drawing: oneStroke(), typedText: nil, replyText: "slant")

        let quarantined = try FileManager.default
            .contentsOfDirectory(atPath: dir.path(percentEncoded: false))
            .filter { $0.contains("corrupt-") }
        #expect(quarantined.count == 1, "the unreadable journal is moved aside, never destroyed")
        #expect(archive.entries.count == 1)
    }

    @Test("a missing store is simply an empty archive")
    func missingStoreIsEmpty() throws {
        let archive = PageArchive(directory: scratchDirectory())
        #expect(archive.entries.isEmpty)
        #expect(archive.entries(for: .oracle).isEmpty)
    }
}

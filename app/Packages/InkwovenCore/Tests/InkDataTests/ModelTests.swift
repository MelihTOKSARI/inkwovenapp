import Foundation
import Testing
import SwiftData
import InkCore
@testable import InkData

@Suite("SwiftData models (task A2)", .serialized)
@MainActor
struct ModelTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try InkStore.container(inMemory: true))
    }

    @Test("notebook → book → page → replies roundtrip")
    func fullGraphRoundtrip() throws {
        let context = try makeContext()

        let notebook = Notebook()
        let keeper = BookState(bookID: .keeper)
        let page = Page(bookID: .keeper, strokeData: Data([0x01]), snapshotDigest: "abc")
        let reply = Reply(kind: .ink(text: "The page remembers."), modelID: "flash-lite", latencyMS: 1200)
        context.insert(notebook)
        notebook.books = [keeper]
        keeper.pages = [page]
        page.replies = [reply]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Notebook>())
        #expect(fetched.count == 1)
        let fetchedPage = try #require(fetched.first?.books?.first?.pages?.first)
        #expect(fetchedPage.snapshotDigest == "abc")
        #expect(fetchedPage.replies?.first?.kind == .ink(text: "The page remembers."))
    }

    @Test("the Keeper is always locked, whatever the caller says")
    func keeperAlwaysLocked() {
        #expect(BookState(bookID: .keeper, isLocked: false).isLocked)
        #expect(!BookState(bookID: .oracle, isLocked: false).isLocked)
    }

    @Test("reply kind façade roundtrips all three modalities")
    func replyKindRoundtrip() {
        let txID = UUID()
        let ink = Reply(kind: .ink(text: "hello"), modelID: "m", latencyMS: 1)
        let image = Reply(kind: .image(assetRef: "img-1.jpg"), modelID: "m", latencyMS: 1)
        let video = Reply(kind: .video(assetRef: "clip-1.mp4", creditTxID: txID), modelID: "m", latencyMS: 1)

        #expect(ink.kind == .ink(text: "hello"))
        #expect(image.kind == .image(assetRef: "img-1.jpg"))
        #expect(video.kind == .video(assetRef: "clip-1.mp4", creditTxID: txID))
        #expect(video.kind.modality == .video)
    }

    @Test("kind is deterministic: a video reply with no credit link reads the same twice")
    func kindIsStableWithoutCreditLink() {
        let video = Reply(kind: .video(assetRef: "clip-1.mp4", creditTxID: nil), modelID: "m", latencyMS: 1)

        // Previously this getter minted a fresh UUID each read, so a value
        // was not even equal to itself.
        #expect(video.kind == video.kind, "Equatable must be reflexive")
        #expect(video.kind == .video(assetRef: "clip-1.mp4", creditTxID: nil))
        #expect(video.creditTxID == nil, "a missing transaction stays visibly missing")
    }

    @Test("assigning kind back to itself never invents a transaction id")
    func kindRoundTripDoesNotFabricate() {
        let video = Reply(kind: .video(assetRef: "clip-1.mp4", creditTxID: nil), modelID: "m", latencyMS: 1)
        video.kind = video.kind

        #expect(video.creditTxID == nil,
                "a fabricated id would persist a transaction matching no ledger entry, stranding the refund")
        #expect(video.kindRaw == "video")
    }

    @Test("torn-out memory persists as a tombstone but never re-enters context")
    func tornMemoryTombstone() throws {
        let context = try makeContext()
        let gm = BookState(bookID: .gameMaster)
        context.insert(gm)
        let kept = MemoryEntry(bookID: .gameMaster, summary: "The party owes the ferryman")
        let torn = MemoryEntry(bookID: .gameMaster, summary: "erase me")
        torn.tornOut = true
        gm.memory = [kept, torn]
        try context.save()

        let entries = try context.fetch(FetchDescriptor<MemoryEntry>())
        #expect(entries.count == 2, "the tombstone survives so sync can't resurrect the memory")

        let injected = MemoryInjection.summaries(
            for: .gameMaster,
            from: entries.map(\.asSummary),
            memoryEnabled: true
        )
        #expect(injected == ["The party owes the ferryman"])
    }

    @Test("pages are searchable once OCR fills searchText")
    func searchTextQuery() throws {
        let context = try makeContext()
        let page = Page(bookID: .keeper)
        page.searchText = "today I planted rosemary"
        context.insert(page)
        let other = Page(bookID: .keeper)
        other.searchText = "long day at work"
        context.insert(other)
        try context.save()

        let hits = try context.fetch(FetchDescriptor<Page>(
            predicate: #Predicate { $0.searchText?.contains("rosemary") == true }
        ))
        #expect(hits.count == 1)
    }
}

import Foundation
import Testing
@testable import InkCore

@Suite("Cross-page memory injection (task D5)")
struct MemoryInjectionTests {
    let now = Date()

    private func entry(_ book: BookID, _ text: String, ageDays: Double, tornOut: Bool = false) -> MemorySummary {
        MemorySummary(bookID: book, summary: text, updatedAt: now.addingTimeInterval(-ageDays * 86_400), tornOut: tornOut)
    }

    @Test("torn-out memories never reappear")
    func tornOutNeverReappears() {
        let entries = [
            entry(.keeper, "Worries about the move", ageDays: 1),
            entry(.keeper, "The torn-out secret", ageDays: 2, tornOut: true),
            entry(.keeper, "Started running again", ageDays: 3),
        ]
        let injected = MemoryInjection.summaries(for: .keeper, from: entries, memoryEnabled: true)
        #expect(injected == ["Worries about the move", "Started running again"])
    }

    @Test("memory is Plus-only: disabled → nothing injected")
    func disabledInjectsNothing() {
        let entries = [entry(.keeper, "anything", ageDays: 1)]
        #expect(MemoryInjection.summaries(for: .keeper, from: entries, memoryEnabled: false).isEmpty)
    }

    @Test("memories are scoped per Book")
    func scopedPerBook() {
        let entries = [
            entry(.keeper, "diary theme", ageDays: 1),
            entry(.gameMaster, "campaign: the sunken keep", ageDays: 1),
        ]
        #expect(MemoryInjection.summaries(for: .gameMaster, from: entries, memoryEnabled: true) == ["campaign: the sunken keep"])
    }

    @Test("most recent first, capped at limit")
    func recencyAndLimit() {
        let entries = (1...8).map { entry(.keeper, "m\($0)", ageDays: Double($0)) }
        let injected = MemoryInjection.summaries(for: .keeper, from: entries, memoryEnabled: true, limit: 3)
        #expect(injected == ["m1", "m2", "m3"])
    }
}

import Foundation
import Testing
import InkCore
@testable import InkAnalytics

private final class SpySink: AnalyticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _tracked: [(name: String, parameters: [String: AnalyticsValue])] = []

    func track(name: String, parameters: [String: AnalyticsValue]) {
        lock.lock(); defer { lock.unlock() }
        _tracked.append((name, parameters))
    }

    var tracked: [(name: String, parameters: [String: AnalyticsValue])] {
        lock.lock(); defer { lock.unlock() }
        return _tracked
    }
}

@Suite("Analytics schema (task A3)")
struct AnalyticsTests {
    @Test("event names are the snake_case wire constants")
    func eventNames() {
        #expect(AnalyticsEvent.install.name == "install")
        #expect(AnalyticsEvent.firstStroke.name == "first_stroke")
        #expect(AnalyticsEvent.pageAnswered(book: .oracle, modality: .ink, ttfsMS: 900).name == "page_answered")
        #expect(AnalyticsEvent.secondBookOpened(book: .artist).name == "second_book_opened")
        #expect(AnalyticsEvent.cooldownHit(seconds: 60).name == "cooldown_hit")
        #expect(AnalyticsEvent.memoryTorn(book: .keeper).name == "memory_torn")
        #expect(AnalyticsEvent.crisisFlow(book: .gameMaster).name == "crisis_flow")
    }

    @Test("page_answered carries book, modality, and ttfs_ms for the latency instrument")
    func pageAnsweredParameters() {
        let params = AnalyticsEvent.pageAnswered(book: .storyteller, modality: .image, ttfsMS: 3200).parameters
        #expect(params["book"] == .string("storyteller"))
        #expect(params["modality"] == .string("image"))
        #expect(params["ttfs_ms"] == .int(3200))
    }

    @Test("facade forwards to the sink")
    func facadeForwards() async {
        let sink = SpySink()
        let analytics = Analytics(sink: sink)
        await analytics.track(.paywallShown(trigger: "moments"))
        #expect(sink.tracked.count == 1)
        #expect(sink.tracked.first?.name == "paywall_shown")
        #expect(sink.tracked.first?.parameters["trigger"] == .string("moments"))
    }
}

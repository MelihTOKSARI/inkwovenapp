import Foundation
import Testing
@testable import InkNet

@Suite("SSEParser")
struct SSEParserTests {
    private func parse(_ raw: String) -> [ServerSentEvent] {
        var parser = SSEParser()
        return parser.consume(Data(raw.utf8))
    }

    @Test("single event with event name and data")
    func singleEvent() {
        let events = parse("event: ink_delta\ndata: {\"text\":\"hi\"}\n\n")
        #expect(events == [ServerSentEvent(event: "ink_delta", data: "{\"text\":\"hi\"}")])
    }

    @Test("multiple events split across arbitrary byte boundaries")
    func chunkedDelivery() {
        let raw = "event: a\ndata: 1\n\nevent: b\ndata: 2\n\n"
        var parser = SSEParser()
        var events: [ServerSentEvent] = []
        // Feed one byte at a time — worst-case network fragmentation.
        for byte in Data(raw.utf8) {
            if let e = parser.consume(byte: byte) { events.append(e) }
        }
        #expect(events.map(\.event) == ["a", "b"])
        #expect(events.map(\.data) == ["1", "2"])
    }

    @Test("multi-line data joins with newline")
    func multiLineData() {
        let events = parse("data: line1\ndata: line2\n\n")
        #expect(events == [ServerSentEvent(event: nil, data: "line1\nline2")])
    }

    @Test("CRLF line endings and comments are tolerated")
    func crlfAndComments() {
        let events = parse(": keep-alive\r\nevent: x\r\ndata: y\r\n\r\n")
        #expect(events == [ServerSentEvent(event: "x", data: "y")])
    }

    @Test("blank line without pending data dispatches nothing")
    func emptyDispatch() {
        #expect(parse("\n\n\n").isEmpty)
    }

    @Test("event id is captured")
    func idCaptured() {
        let events = parse("id: 42\ndata: d\n\n")
        #expect(events.first?.id == "42")
    }

    @Test("keep-alive comments between events are dropped without disturbing them")
    func keepAliveBetweenEvents() {
        let events = parse("event: a\ndata: 1\n\n: ping\n\nevent: b\ndata: 2\n\n")
        #expect(events.map(\.event) == ["a", "b"])
    }

    @Test("EOF flush recovers an event whose terminating blank line never arrived")
    func flushWithoutBlankLine() {
        var parser = SSEParser()
        let events = parser.consume(Data("event: done\ndata: {\"modelID\":\"m\"}\n".utf8))
        #expect(events.isEmpty)
        #expect(parser.flush() == ServerSentEvent(event: "done", data: "{\"modelID\":\"m\"}"))
    }

    @Test("EOF flush recovers a trailing line that never got its newline")
    func flushMidLine() {
        var parser = SSEParser()
        #expect(parser.consume(Data("event: done\ndata: {\"a\":1}".utf8)).isEmpty)
        #expect(parser.flush() == ServerSentEvent(event: "done", data: "{\"a\":1}"))
    }

    @Test("EOF flush drops a trailing CR and still recovers the line")
    func flushMidLineCRLF() {
        var parser = SSEParser()
        _ = parser.consume(Data("event: done\r\ndata: x\r".utf8))
        #expect(parser.flush() == ServerSentEvent(event: "done", data: "x"))
    }

    @Test("flush yields nothing when the stream ended cleanly, and never double-dispatches")
    func flushIsIdempotent() {
        var parser = SSEParser()
        #expect(parser.consume(Data("event: a\ndata: 1\n\n".utf8)).count == 1)
        #expect(parser.flush() == nil)
        #expect(parser.flush() == nil)
    }

    @Test("CRLF split across two consume batches parses as one event")
    func crlfSplitAcrossBatches() {
        var parser = SSEParser()
        var events = parser.consume(Data("event: x\r\ndata: y\r".utf8))
        events += parser.consume(Data("\n\r\n".utf8))
        #expect(events == [ServerSentEvent(event: "x", data: "y")])
    }

    @Test("multi-line data survives an EOF flush")
    func flushMultiLineData() {
        var parser = SSEParser()
        _ = parser.consume(Data("data: line1\ndata: line2".utf8))
        #expect(parser.flush() == ServerSentEvent(event: nil, data: "line1\nline2"))
    }
}

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
}

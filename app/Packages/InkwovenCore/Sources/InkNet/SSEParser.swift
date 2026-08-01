import Foundation

public struct ServerSentEvent: Equatable, Sendable {
    public var event: String?
    public var data: String
    public var id: String?

    public init(event: String? = nil, data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental SSE parser fed raw bytes (we deliberately do not use
/// `AsyncLineSequence` — the blank line that delimits SSE events must be seen).
/// Handles `event:`/`data:`/`id:` fields, multi-line data, CRLF, and comments.
public struct SSEParser: Sendable {
    private var lineBuffer: [UInt8] = []
    private var currentEvent: String?
    private var currentData: [String] = []
    private var currentID: String?

    public init() {}

    public mutating func consume(_ data: Data) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []
        for byte in data {
            if let event = consume(byte: byte) {
                events.append(event)
            }
        }
        return events
    }

    public mutating func consume(byte: UInt8) -> ServerSentEvent? {
        guard byte == UInt8(ascii: "\n") else {
            lineBuffer.append(byte)
            return nil
        }
        if lineBuffer.last == UInt8(ascii: "\r") {
            lineBuffer.removeLast()
        }
        let line = String(decoding: lineBuffer, as: UTF8.self)
        lineBuffer.removeAll(keepingCapacity: true)
        return consume(line: line)
    }

    /// Drains a partial event at end-of-stream, including a trailing line that
    /// never got its newline. The SSE spec says pending data MUST be discarded
    /// at EOF; we deliberately deviate. The proxy writes the final `done` frame
    /// in one `write`, but that is not one TCP segment — if the edge resets
    /// after the payload and before the blank line, spec behaviour would throw
    /// away a reply the reader already watched land on the page.
    public mutating func flush() -> ServerSentEvent? {
        if !lineBuffer.isEmpty {
            if lineBuffer.last == UInt8(ascii: "\r") {
                lineBuffer.removeLast()
            }
            let line = String(decoding: lineBuffer, as: UTF8.self)
            lineBuffer.removeAll(keepingCapacity: true)
            if let event = consume(line: line) { return event }
        }
        return dispatch()
    }

    private mutating func consume(line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") { return nil } // comment / keep-alive

        let field: Substring
        let value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            var v = line[line.index(after: colon)...]
            if v.hasPrefix(" ") { v = v.dropFirst() }
            value = v
        } else {
            field = line[...]
            value = ""
        }

        switch field {
        case "event": currentEvent = String(value)
        case "data": currentData.append(String(value))
        case "id": currentID = String(value)
        default: break // per spec: ignore unknown fields (incl. "retry" for now)
        }
        return nil
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            currentEvent = nil
            currentData = []
            currentID = nil
        }
        guard !currentData.isEmpty else { return nil }
        return ServerSentEvent(event: currentEvent, data: currentData.joined(separator: "\n"), id: currentID)
    }
}

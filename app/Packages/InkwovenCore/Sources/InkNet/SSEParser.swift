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
/// Handles `event:`/`data:`/`id:` fields, multi-line data, comments, and all
/// three spec line terminators: LF, CRLF, and a lone CR.
public struct SSEParser: Sendable {
    private var lineBuffer: [UInt8] = []
    /// The previous byte was a CR that already ended its line — the LF of a
    /// CRLF pair, should one follow, is part of that terminator and must be
    /// swallowed rather than read as an empty line (audit L-4).
    private var pendingCR = false
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
        if pendingCR {
            pendingCR = false
            // The tail of a CRLF; its line was dispatched at the CR.
            if byte == UInt8(ascii: "\n") { return nil }
        }
        switch byte {
        case UInt8(ascii: "\n"):
            return endLine()
        case UInt8(ascii: "\r"):
            // A CR ends the line NOW — waiting to see whether an LF follows
            // would hold a complete event hostage to the next segment.
            pendingCR = true
            return endLine()
        default:
            lineBuffer.append(byte)
            return nil
        }
    }

    private mutating func endLine() -> ServerSentEvent? {
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
        pendingCR = false
        if !lineBuffer.isEmpty {
            if let event = endLine() { return event }
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

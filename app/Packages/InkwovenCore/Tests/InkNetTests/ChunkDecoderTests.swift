import Foundation
import Testing
import InkCore
@testable import InkNet

@Suite("ChunkDecoder")
struct ChunkDecoderTests {
    @Test("ink delta decodes")
    func inkDelta() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(event: "ink_delta", data: #"{"text":"The page stirs"}"#))
        #expect(chunk == .inkDelta("The page stirs"))
    }

    @Test("image intent, preview, final decode")
    func imageChunks() throws {
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "image_intent", data: #"{"id":"img-1","expectsPreview":true}"#))
                == .imageIntent(ImageJob(id: "img-1", expectsPreview: true)))

        let bytes = Data([0x01, 0x02, 0x03])
        let preview = ChunkDecoder.decode(ServerSentEvent(event: "image_preview", data: #"{"base64":"\#(bytes.base64EncodedString())"}"#))
        #expect(preview == .imagePreview(bytes))

        let url = try #require(URL(string: "https://assets.inkwoven.app/img-1.jpg"))
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "image_final", data: #"{"url":"\#(url.absoluteString)"}"#))
                == .imageFinal(url))
    }

    @Test("crisis decodes with resources")
    func crisis() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(
            event: "crisis",
            data: #"{"message":"You matter.","resources":[{"name":"988 Lifeline","contact":"988"}]}"#
        ))
        #expect(chunk == .crisis(CrisisPayload(message: "You matter.",
                                               resources: [.init(name: "988 Lifeline", contact: "988")])))
    }

    @Test("done decodes usage")
    func done() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(
            event: "done",
            data: #"{"modelID":"flash-lite","inputTokens":100,"outputTokens":50}"#
        ))
        #expect(chunk == .done(Usage(modelID: "flash-lite", inputTokens: 100, outputTokens: 50)))
    }

    @Test("crisis fails CLOSED — every malformed body still surfaces the card", arguments: [
        #"{"message":"Please talk to someone."}"#,   // resources omitted (empty region lookup)
        #"{"message":"x","resources":null}"#,        // resources null
        #"{"msg":"x","resources":[]}"#,              // message renamed
        #"{"message":"","resources":[]}"#,           // message blank
        "not json",                                  // body unparseable entirely
        "",                                          // body empty
    ])
    func crisisFailsClosed(body: String) throws {
        let chunk = ChunkDecoder.decode(ServerSentEvent(event: "crisis", data: body))
        let payload = try #require({ if case .crisis(let p) = chunk { p } else { nil } }())
        #expect(payload == ChunkDecoder.safeCrisisFallback)
        #expect(!payload.message.isEmpty)
    }

    @Test("a well-formed crisis payload is passed through untouched")
    func crisisPassthrough() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(
            event: "crisis",
            data: #"{"message":"You matter.","resources":[{"name":"Telefonseelsorge","contact":"0800 111 0 111"}]}"#
        ))
        #expect(chunk == .crisis(CrisisPayload(message: "You matter.",
                                               resources: [.init(name: "Telefonseelsorge", contact: "0800 111 0 111")])))
    }

    @Test("unknown event kinds are dropped, not fatal — forward compatibility")
    func unknownDropped() {
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "scent_intent", data: #"{"smell":"petrichor"}"#)) == nil)
    }

    @Test("malformed payload for a known kind is dropped, not fatal")
    func malformedDropped() {
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "ink_delta", data: "not json")) == nil)
    }

    @Test("image_error decodes — the server's terminal event for a failed develop")
    func imageErrorDecodes() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(
            event: "image_error",
            data: #"{"id":"img-1","reason":"develop_failed"}"#
        ))
        #expect(chunk == .imageFailed(ImageFailure(id: "img-1", reason: "develop_failed")))
    }

    @Test("image_error without a reason still decodes — only the id is required")
    func imageErrorReasonOptional() {
        let chunk = ChunkDecoder.decode(ServerSentEvent(event: "image_error", data: #"{"id":"img-2"}"#))
        #expect(chunk == .imageFailed(ImageFailure(id: "img-2")))
    }
}

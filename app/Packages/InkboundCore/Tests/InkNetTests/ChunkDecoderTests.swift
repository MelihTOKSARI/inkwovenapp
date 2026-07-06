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

        let url = try #require(URL(string: "https://assets.inkbound.app/img-1.jpg"))
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

    @Test("unknown event kinds are dropped, not fatal — forward compatibility")
    func unknownDropped() {
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "scent_intent", data: #"{"smell":"petrichor"}"#)) == nil)
    }

    @Test("malformed payload for a known kind is dropped, not fatal")
    func malformedDropped() {
        #expect(ChunkDecoder.decode(ServerSentEvent(event: "ink_delta", data: "not json")) == nil)
    }
}

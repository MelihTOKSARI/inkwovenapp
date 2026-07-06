import Foundation
import InkCore

/// Maps wire events to `ReplyChunk`s. Unknown event names decode to nil and
/// are dropped — forward compatibility with post-launch Book drops.
public enum ChunkDecoder {
    static let decoder = JSONDecoder()

    public static func decode(_ event: ServerSentEvent) -> ReplyChunk? {
        let data = Data(event.data.utf8)
        do {
            switch event.event {
            case "ink_delta":
                return .inkDelta(try decoder.decode(InkDeltaBody.self, from: data).text)
            case "image_intent":
                return .imageIntent(try decoder.decode(ImageJob.self, from: data))
            case "video_intent":
                return .videoIntent(try decoder.decode(VideoJob.self, from: data))
            case "image_preview":
                let body = try decoder.decode(Base64Body.self, from: data)
                guard let bytes = Data(base64Encoded: body.base64) else { return nil }
                return .imagePreview(bytes)
            case "image_final":
                guard let url = URL(string: try decoder.decode(URLBody.self, from: data).url) else { return nil }
                return .imageFinal(url)
            case "video_final":
                guard let url = URL(string: try decoder.decode(URLBody.self, from: data).url) else { return nil }
                return .videoFinal(url)
            case "crisis":
                return .crisis(try decoder.decode(CrisisPayload.self, from: data))
            case "done":
                return .done(try decoder.decode(Usage.self, from: data))
            default:
                return nil
            }
        } catch {
            // A malformed known chunk is dropped rather than killing the
            // stream; the exchange still terminates via `done` or transport EOF.
            return nil
        }
    }

    struct InkDeltaBody: Codable { var text: String }
    struct Base64Body: Codable { var base64: String }
    struct URLBody: Codable { var url: String }
}

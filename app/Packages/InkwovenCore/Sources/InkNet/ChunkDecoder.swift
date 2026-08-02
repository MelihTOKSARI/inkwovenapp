import Foundation
import InkCore

/// Maps wire events to `ReplyChunk`s. Unknown event names decode to nil and
/// are dropped — forward compatibility with post-launch Book drops.
public enum ChunkDecoder {
    /// Shared deliberately rather than allocated per chunk: `decode` runs once
    /// per ink delta on the TTFS-critical path. `JSONDecoder` is `Sendable`, so
    /// concurrent exchanges may decode against one instance — but only while it
    /// is never reconfigured, so it is `private` and every site that needs a
    /// strategy (see `ProxyClient.preupload`) makes its own local decoder.
    private static let decoder = JSONDecoder()

    /// The verdict is the one chunk carrying a date (`expiresAt`), so it needs
    /// the ISO-8601 strategy. Separate instance rather than reconfiguring the
    /// shared one, which several exchanges may be decoding against at once.
    private static let verdictDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Shown when the wire payload cannot be trusted. Unbranded, region-neutral,
    /// and safe to render verbatim; `CrisisView` supplies its own resources, so
    /// an empty list costs the reader nothing.
    static let safeCrisisFallback = CrisisPayload(
        message: "Let us set the story down for a moment. If you are thinking of hurting yourself, please reach out to someone who can help right now — you deserve that.",
        resources: []
    )

    public static func decode(_ event: ServerSentEvent) -> ReplyChunk? {
        let data = Data(event.data.utf8)

        // Safety fails CLOSED, and only safety does. An event *named* `crisis`
        // always surfaces the crisis card, even if its body is malformed,
        // truncated, or missing `resources` because a region lookup came back
        // empty. Dropping it would leave the fiction streaming through a
        // self-harm disclosure — so this arm never reaches the catch below.
        if event.event == "crisis" {
            let payload = (try? decoder.decode(CrisisPayload.self, from: data)) ?? safeCrisisFallback
            return .crisis(payload.message.isEmpty ? safeCrisisFallback : payload)
        }

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
            case "image_error":
                // Terminal counterpart to `image_intent`. Dropping it as an
                // unknown event would leave the develop slot spinning for the
                // rest of the exchange.
                return .imageFailed(try decoder.decode(ImageFailure.self, from: data))
            case "video_final":
                guard let url = URL(string: try decoder.decode(URLBody.self, from: data).url) else { return nil }
                return .videoFinal(url)
            case "video_error":
                // Terminal counterpart to `video_intent`. Dropping it as an
                // unknown event would leave the reader watching a clip develop
                // that is never coming, with their credit still held.
                return .videoFailed(try decoder.decode(VideoFailure.self, from: data))
            case "verdict":
                // Advisory only — it can never start a generation, so a
                // malformed one is safely dropped by the catch below.
                return .verdict(try verdictDecoder.decode(ConvertibilityVerdict.self, from: data))
            case "done":
                return .done(try decoder.decode(Usage.self, from: data))
            default:
                return nil
            }
        } catch {
            // A malformed known chunk is dropped rather than killing the
            // stream; the exchange still terminates via `done` or transport EOF.
            // `crisis` is handled above and never lands here.
            return nil
        }
    }

    struct InkDeltaBody: Codable { var text: String }
    struct Base64Body: Codable { var base64: String }
    struct URLBody: Codable { var url: String }
}

import SwiftUI
import InkCore
import InkNet
import InkSafety
import InkAnalytics

/// Definition-of-core-done harness: runs one echo-mode exchange against the
/// local proxy and streams the reply, reporting time-to-first-stroke. Not a
/// product screen — the Claude Design page view replaces it.
struct EchoExchangeView: View {
    let di: AppDI
    @State private var streamedText = ""
    @State private var status = "idle"
    @State private var ttfs: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inkbound — core harness").font(.headline)
            Text("status: \(status)").monospaced()
            if let ttfs {
                Text("time_to_first_stroke: \(ttfs) ms").monospaced()
            }
            ScrollView {
                Text(streamedText).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Run echo exchange") {
                Task { await runExchange() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func runExchange() async {
        streamedText = ""
        ttfs = nil
        status = "sending"
        var timer = ExchangeTimer()
        var assembler = ReplyAssembler()

        let payload = SnapshotPayload(
            imageData: Data("placeholder".utf8),
            digest: SnapshotProcessor.digest(of: Data("placeholder".utf8)),
            cropRect: .zero,
            pixelSize: .zero
        )
        let stream = CrisisInterceptor.intercept(
            di.proxy.exchange(payload: payload, book: .oracle, context: PageContext())
        )
        do {
            for try await chunk in stream {
                if let ms = timer.markFirstChunk() {
                    ttfs = ms
                }
                for output in assembler.consume(chunk) {
                    switch output {
                    case .appendInk(let delta):
                        streamedText += delta
                    case .completed:
                        status = "answered"
                        if let ttfs {
                            await di.analytics.track(.pageAnswered(book: .oracle, modality: .ink, ttfsMS: ttfs))
                        }
                    case .crisis:
                        status = "crisis (preempted)"
                    default:
                        break
                    }
                }
            }
        } catch let error as ProxyError {
            status = "declined: \(DeclineMapper.map(error))"
        } catch {
            status = "failed: \(error)"
        }
    }
}

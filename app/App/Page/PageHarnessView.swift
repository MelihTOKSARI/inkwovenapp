import SwiftUI
import InkCore

/// Core-done harness: a real page. Write with finger or Pencil, rest the pen
/// ~3s, watch the echo reply stream back. Placeholder chrome — the Claude
/// Design page view replaces this while binding to the same PageInteractor.
struct PageHarnessView: View {
    @State private var interactor: PageInteractor

    init(di: AppDI) {
        // Ephemeral accounting: a dev harness must never spend the user's real
        // daily allowance.
        _interactor = State(initialValue: PageInteractor(
            proxy: di.proxy, analytics: di.analytics, entitlements: .ephemeral()
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            InkCanvasView(interactor: interactor, pencilActive: PenPresence.shared.pencilActive)
                .background(Color(red: 0.98, green: 0.96, blue: 0.91)) // placeholder parchment
                .accessibilityElement()
                .accessibilityIdentifier("ink-canvas")
            replyPane
        }
    }

    private var statusBar: some View {
        HStack {
            Text("The Oracle — core harness").font(.headline)
            Spacer()
            Text(statusLabel).monospaced().font(.caption)
                .accessibilityIdentifier("status-label")
            if let ttfs = interactor.ttfsMS {
                Text("ttfs \(ttfs)ms").monospaced().font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var replyPane: some View {
        ScrollView {
            Text(interactor.streamedText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .accessibilityIdentifier("reply-pane")
        }
        .frame(maxHeight: 220)
        .background(.quaternary.opacity(0.3))
    }

    private var statusLabel: String {
        switch interactor.status {
        case .idle: "idle"
        case .inking: "inking"
        case .resting: "resting…"
        case .sending: "the page drinks the ink"
        case .answering: "answering"
        case .answered: "answered"
        case .held: "the page waits"
        case .paywall(let trigger): "paywall: \(trigger.rawValue)"
        case .cooldown(let seconds): "the ink must rest (\(Int(seconds))s)"
        case .declined(let reason): reason
        case .crisis: "crisis flow"
        }
    }
}

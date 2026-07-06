import Foundation

/// Darkroom development state machine (task C4): preview-first — the low-res
/// preview starts developing immediately while the full-res generates. Pure
/// transitions; the view layer draws the stages.
public struct DevelopFrameDriver: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case awaitingPreview
        case developingPreview
        case developingFinal
        case settled
        case failed
    }

    /// Staged development the fiction shows: edges bloom first, then midtones,
    /// then detail.
    public enum Stage: Equatable, Sendable, CaseIterable {
        case edges
        case midtones
        case detail

        public static func at(progress: Double) -> Stage {
            switch progress {
            case ..<0.34: .edges
            case ..<0.67: .midtones
            default: .detail
            }
        }
    }

    public enum Event: Equatable, Sendable {
        case previewArrived(Data)
        case finalArrived(URL)
        case finalRenderCompleted
        case failed
    }

    public enum Output: Equatable, Sendable {
        case beginPreviewDevelop(Data)
        case beginFinalDevelop(URL)
        case settle
        /// Shell tears the slot down in-fiction and, when the job was
        /// credit-backed, releases the reservation upstream.
        case fail
    }

    public private(set) var phase: Phase = .awaitingPreview

    public init() {}

    @discardableResult
    public mutating func handle(_ event: Event) -> [Output] {
        switch (phase, event) {
        case (.awaitingPreview, .previewArrived(let data)):
            phase = .developingPreview
            return [.beginPreviewDevelop(data)]

        // Full-res can land without a preview (fast generation, or the
        // preview was dropped) — never block on it.
        case (.awaitingPreview, .finalArrived(let url)), (.developingPreview, .finalArrived(let url)):
            phase = .developingFinal
            return [.beginFinalDevelop(url)]

        // A late preview never regresses the final.
        case (.developingFinal, .previewArrived), (.settled, .previewArrived):
            return []

        case (.developingFinal, .finalRenderCompleted):
            phase = .settled
            return [.settle]

        case (.awaitingPreview, .failed), (.developingPreview, .failed), (.developingFinal, .failed):
            phase = .failed
            return [.fail]

        default:
            return []
        }
    }
}

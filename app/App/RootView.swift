import SwiftUI
import InkCore

/// The design view tree. Every screen lives in the candlelit room; theme
/// and reduce-motion resolve here and flow down the environment.
struct RootView: View {
    let di: AppDI
    @State private var model = AppModel()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            model.theme.roomBackground.ignoresSafeArea()

            switch model.screen {
            case .onboarding:
                OnboardingView(model: model).transition(.opacity)
            case .shelf:
                ShelfView(model: model).transition(.opacity)
            case .page:
                // Structural gate. AppModel reads the review/UITest launch args
                // (`-ink.startScreen page -ink.startBook keeper`) in every
                // build and assigns `screen` directly, never through
                // open(book:) — so the lock cannot live only there. No route
                // may put a locked Book on screen without passing through it.
                if model.activeBook.locked && !model.keeperUnlocked {
                    keeperGate
                } else {
                    PageView(model: model, di: di)
                        .id(model.activeBookID)
                        .transition(.opacity)
                }
            case .remembered:
                RememberedView(model: model, archive: di.archive).transition(.opacity)
            case .memory:
                MemoryView(model: model).transition(.opacity)
            case .paywall:
                PaywallView(model: model).transition(.opacity)
            case .wallet:
                VialsView(model: model).transition(.opacity)
            case .bindery:
                BinderyView(model: model).transition(.opacity)
            case .drawer:
                DrawerView(model: model).transition(.opacity)
            case .keeperGate:
                keeperGate
            case .crisis:
                CrisisView(model: model).transition(.opacity)
            }

            // The app-switcher snapshot is written to disk at .inactive, and it
            // would carry the open Keeper page in legible plaintext. Draw the
            // empty room over it.
            if model.keeperUnlocked && scenePhase != .active {
                model.theme.roomBackground.ignoresSafeArea()
            }
        }
        .environment(\.room, model.theme)
        .environment(\.reduceInkMotion, systemReduceMotion || model.reduceMotionOverride)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { relockKeeper() }
        }
    }

    private var keeperGate: some View {
        KeeperGateView(model: model, auth: di.keeperAuth, archive: di.archive)
            .transition(.opacity)
    }

    /// One unlock buys one visit. Backgrounding the app re-seals the Keeper —
    /// its pages leave memory, and the next look has to earn them again.
    /// Assigns `screen` directly rather than going through `go(_:)`: an
    /// animation would still be running while the snapshot is taken.
    private func relockKeeper() {
        guard model.keeperUnlocked else { return }
        model.keeperUnlocked = false
        di.archive.sealKeeper()
        if model.revisit?.bookID == BookID.keeper.rawValue { model.revisit = nil }
        if model.activeBook.locked && (model.screen == .page || model.screen == .remembered) {
            model.screen = .shelf
        }
    }
}

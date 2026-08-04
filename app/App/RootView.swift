import SwiftUI
import InkCore

/// The design view tree. Every screen lives in the candlelit room; theme
/// and reduce-motion resolve here and flow down the environment.
struct RootView: View {
    let di: AppDI
    @State private var model: AppModel
    /// The launch veil (Design/LaunchGlow.swift): true exactly once per
    /// process, so foreground-resume never replays the ceremony.
    @State private var launchVeil = LaunchGlowView.shouldShow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(di: AppDI) {
        self.di = di
        // The wallet reader was never bound, so `AppModel.wallet` stayed nil
        // and every room that shows a balance showed a placeholder forever.
        _model = State(initialValue: AppModel(
            walletReader: di.wallet, ritual: di.ritual, ritualDiary: di.archive
        ))
    }

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
                DrawerView(model: model, archive: di.archive, analytics: di.analytics, drafts: di.drafts)
                    .transition(.opacity)
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

            // Topmost: the cold-launch veil. Its first frame matches the
            // system launch screen, so the app appears to light itself. The
            // room is already built underneath — the veil only ever draws on
            // top, and never delays initialization.
            if launchVeil {
                LaunchGlowView {
                    // The lift is the veil's own final beat, so its duration
                    // comes from the same place as the rest of the sequence.
                    let lift = systemReduceMotion || model.reduceMotionOverride
                        ? LaunchGlowView.Beat.reducedLift
                        : LaunchGlowView.Beat.lift
                    withAnimation(.easeOut(duration: lift)) { launchVeil = false }
                }
                .zIndex(2)
                .transition(.opacity)
            }
        }
        .environment(\.room, model.theme)
        .environment(\.reduceInkMotion, systemReduceMotion || model.reduceMotionOverride)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { relockKeeper() }
            // Every return to the room re-arms the week of evening reminders
            // (and re-reads authorization — the writer may have visited
            // Settings while away).
            if phase == .active {
                model.scheduleRitualRearm()
                // Cap and cooldown knobs are server-tunable; re-read them so a
                // change ships without a release. Failure keeps the defaults.
                Task { await LiveCommerce.refreshGateConfig() }
            }
        }
        .onChange(of: di.archive.lastWrittenAt) { _, _ in
            // A page written today — any Book, the Keeper included — keeps
            // tonight silent the moment it lands, not on the next foreground.
            model.scheduleRitualRearm()
        }
        .task { model.scheduleRitualRearm() }
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
        // A pending report holds a full entry the same way revisit does; a
        // sealed Keeper page may not wait in memory behind a closed lock.
        if model.reportTarget?.bookID == BookID.keeper.rawValue { model.reportTarget = nil }
        if model.activeBook.locked && (model.screen == .page || model.screen == .remembered) {
            model.screen = .shelf
        }
    }
}

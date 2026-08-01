import Foundation

/// Sample content carried over from the Claude Design handoff so each screen
/// has something to show before the real engines bind. This is the ONLY
/// place demo flows live — when an integration lands, swap the screen's read
/// to the real source and delete the matching entry here.
///
/// Integration seams:
/// - `memoryNotes`     → InkCore MemoryInjection store
/// - `developScript`   → InkRender progress callbacks (real develop stages)
///
/// Not demo (already real): PageView's write → rest → absorb → answer loop
/// runs through PageInteractor and the echo proxy; RememberedView reads the
/// PageArchive directly; KeeperGate uses LocalAuthentication; commerce stubs
/// sit behind AppModel's marked seams.
enum DemoContent {
    /// MemoryView's marginalia until the MemoryInjection store binds.
    static let memoryNotes = [
        "You take your tea without sugar, but with honey in winter.",
        "Your sister’s name is Removed at your request.",
        "You are writing toward something you have not named yet.",
        "You prefer to be answered slant, not straight.",
    ]

    /// PageView's darkroom reveal pacing until InkRender streams real
    /// develop progress: (seconds to wait, develop step to reach).
    static let developScript: [(delay: Double, step: Int)] = [(0.9, 1), (1.0, 2), (1.2, 3)]
}

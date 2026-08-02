import SwiftUI
import AVFoundation
import AVKit
import InkCore
import InkNet
import InkRender

/// The moving picture: the offer, the wait, the clip on the page, and the fall
/// into it (tasks J3–J6).
///
/// The rule that shapes every view here: **the page offers, the reader acts.**
/// Nothing in this file starts a generation on its own — `requestVideo()` is
/// reachable only from a tap, and the Keeper's pages need a second one.

// MARK: - The offer (task J3)

/// "Make this move", in the register of the tool tray — the notebook offering,
/// not a call to action. Appears only on a positive verdict, and says what the
/// tap will spend before it commits.
struct MovingPictureOffer: View {
    let book: Book
    /// What the next clip costs, as the server reported it. Nil while unknown.
    let wallet: WalletView?
    let isOffline: Bool
    let onRequest: () -> Void

    @Environment(\.room) private var room
    @Environment(\.reduceInkMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onRequest) {
                HStack(spacing: 11) {
                    VialView(width: 15, height: 30, fill: available ? 0.55 : 0.12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("let this one move")
                            .font(InkFont.bodyItalic(16))
                            .foregroundStyle(available ? Ink.wax : Ink.inkFaded)
                        Text(costLine)
                            .font(InkFont.body(12))
                            .foregroundStyle(Ink.inkFaded)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .background(
                    Capsule()
                        .fill(Ink.ink.opacity(0.05))
                        .overlay(Capsule().stroke(Ink.ink.opacity(available ? 0.2 : 0.1), lineWidth: 1))
                )
            }
            .buttonStyle(PressScaleStyle(scale: 0.96))
            .disabled(!available)
            .accessibilityLabel("Let this reply move")
            .accessibilityHint(spokenHint)
        }
        .transition(InkMotion.arrival(.inkSurface, reduce: reduceMotion))
    }

    /// Offline is a disabled affordance with a reason, never a dead button.
    private var available: Bool {
        !isOffline && (wallet?.canAffordClip ?? true)
    }

    /// Honest before the tap: which purse this comes out of, in the room's
    /// own words. Unknown stays quiet rather than guessing.
    private var costLine: String {
        if isOffline { return "the road is dark" }
        guard let wallet else { return "one vial" }
        if wallet.nextClipIsFree {
            return wallet.freeClipsRemaining == 1
                ? "your last gifted moment"
                : "one of \(wallet.freeClipsRemaining) gifted moments"
        }
        if wallet.available > 0 {
            return wallet.available == 1 ? "your last vial" : "one of \(wallet.available) vials"
        }
        return "the vials are empty"
    }

    private var spokenHint: String {
        if isOffline {
            return "The road is dark — a moving picture cannot be made until the connection returns."
        }
        if wallet?.canAffordClip == false {
            return "The vials are empty. Visit the vials to fill them."
        }
        return "Spends \(costLine). The picture takes a moment to develop."
    }
}

// MARK: - Keeper consent (task J6)

/// The Keeper is sealed behind the reader's face; making one of its pages move
/// sends that page to a third party. Explicit, separate consent before the
/// FIRST Keeper clip — remembered afterwards, never a silent tap.
///
/// Same treatment as the report sheet: name exactly what leaves the device,
/// and transmit nothing until the reader says so.
struct KeeperClipConsent: View {
    let onCancel: () -> Void
    let onAgree: () -> Void

    @Environment(\.room) private var room

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityLabel("Close without making a moving picture")

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    LockGlyph()
                    Text("Out from behind the seal")
                        .font(InkFont.display(22))
                        .foregroundStyle(room.heading)
                }
                .padding(.bottom, 10)

                Text("The Keeper's pages stay on this device, behind your face. To make this one move, the words of this reply must travel to the workshop that paints it — a service outside this notebook. The picture comes back to you and is kept here.")
                    .font(InkFont.body(15))
                    .foregroundStyle(room.text)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Your strokes, your other pages, and your name never travel. Nothing leaves this device until you press the seal, and this is asked once.")
                    .font(InkFont.bodyItalic(14))
                    .foregroundStyle(room.dim)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                HStack(spacing: 18) {
                    Button(action: onCancel) {
                        Text("keep it sealed")
                            .font(InkFont.body(15))
                            .foregroundStyle(Ink.inkFaded)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())

                    WaxSealButton(label: "let it move", diameter: 38, labelFont: InkFont.bodyItalic(15)) {
                        onAgree()
                    }
                }
                .padding(.top, 22)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(EdgeInsets(top: 26, leading: 26, bottom: 22, trailing: 26))
            .frame(maxWidth: 520)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [room.cardTop, room.cardBottom], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(room.accent.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
            )
            .padding(40)
        }
        .transition(.opacity)
    }
}

// MARK: - The wait (task J4)

/// The picture developing. Seconds, not milliseconds — so the wait is theatre,
/// not a spinner: the plate darkens and clears the way the darkroom does.
struct MovingPictureDeveloping: View {
    let book: Book
    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DevelopFrame(book: book, step: step, isMoving: false, imageURL: nil)
                .frame(maxWidth: 420)
            Text("the picture is learning to move…")
                .font(InkFont.bodyItalic(13))
                .foregroundStyle(Ink.inkFaded)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A moving picture is developing from this reply.")
        .task {
            guard !reduceMotion else {
                step = 2
                return
            }
            // Drifts to the edge of legibility and waits there; the clip's own
            // arrival is what finishes the reveal.
            for (delay, next) in [(1.2, 1), (2.4, 2)] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 1.4)) { step = next }
            }
        }
    }
}

// MARK: - The clip on the page (task J5)

/// The finished clip, blooming in its frame on the paper. Tapping it is the
/// moment: the picture expands past the page to fill the screen.
struct MovingPictureFrame: View {
    let url: URL
    let book: Book
    let onOpen: () -> Void

    @Environment(\.reduceInkMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                ClipLoopView(url: url)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Ink.ink.opacity(0.9), lineWidth: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .inset(by: 6)
                            .strokeBorder(Ink.candle.opacity(0.15), lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.985))
            .accessibilityLabel("The moving picture from your page")
            .accessibilityHint("Opens it full screen.")

            Text("tap to fall in")
                .font(InkFont.bodyItalic(13))
                .foregroundStyle(Ink.inkFaded)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .transition(InkMotion.arrival(.inkSurface, reduce: reduceMotion))
    }
}

// MARK: - Immersive playback (task J5)

/// Identity for `fullScreenCover(item:)`. A `URL` is not `Identifiable`, and a
/// retroactive conformance on a stdlib type is a landmine for every other file
/// in the app — so the wrapper stays local to the one presentation that needs it.
struct ImmersiveClip: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

/// The clip past the page: full screen, looping, no chrome, no controls, no
/// scrubber. Tap or swipe down to come back.
///
/// The expansion reads as going THROUGH the page rather than a modal sliding
/// up — the frame grows and the paper falls away behind it. Reduce Motion gets
/// a cross-fade instead, which is the same arrival without the travel.
struct ImmersiveClipView: View {
    let url: URL
    let onDismiss: () -> Void

    @Environment(\.reduceInkMotion) private var reduceMotion
    @State private var entered = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(entered ? 1 : 0)

            ClipLoopView(url: url)
                .ignoresSafeArea()
                // Through the page: the clip arrives already large and settles,
                // rather than sliding in from an edge.
                .scaleEffect(entered ? 1 : (reduceMotion ? 1 : 0.82))
                .opacity(entered ? 1 : 0)
                .offset(y: dragOffset)
                .scaleEffect(dragScale)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Downward only — an upward drag is not a dismissal.
                    dragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 120 || value.predictedEndTranslation.height > 260 {
                        dismiss()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The moving picture, full screen and looping.")
        .accessibilityHint("Tap or swipe down to return to the page.")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.55)) { entered = true }
        }
        .statusBarHidden()
    }

    /// The picture shrinks slightly as it is pulled down — the page taking it
    /// back rather than the clip being thrown away.
    private var dragScale: CGFloat {
        guard dragOffset > 0 else { return 1 }
        return max(0.85, 1 - dragOffset / 1600)
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: reduceMotion ? 0.2 : 0.35)) {
            entered = false
            dragOffset = 0
        }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 200 : 350))
            onDismiss()
        }
    }
}

// MARK: - The looping player

/// Seamless looping playback of a clip already on disk.
///
/// Two things matter here beyond "it plays":
///
/// 1. **The reader's music keeps playing.** The clips are silent, so there is
///    no excuse for interrupting anything: the session category is `.ambient`,
///    which mixes rather than taking the audio route. A default `AVPlayer`
///    would stop whatever the reader was listening to.
/// 2. **No streaming.** The clip is downloaded whole and then looped locally
///    (`AVPlayerLooper`), per the `VideoLoopDriver` design — a five-second loop
///    that re-buffers on every pass is not a living page.
struct ClipLoopView: View {
    let url: URL
    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if let localURL {
                LoopingPlayerLayer(url: localURL)
                    .transition(.opacity)
            }
        }
        .task(id: url) {
            failed = false
            localURL = nil
            do {
                localURL = try await ClipCache.shared.localCopy(of: url)
            } catch {
                failed = true
            }
        }
    }
}

/// AVPlayerLooper needs a queue player and a UIView-hosted layer; SwiftUI's
/// VideoPlayer would bring transport controls, which is exactly the chrome
/// this feature is defined by not having.
private struct LoopingPlayerLayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ view: LoopingPlayerUIView, context: Context) {
        view.retarget(url)
    }

    static func dismantleUIView(_ view: LoopingPlayerUIView, coordinator: ()) {
        view.stop()
    }
}

final class LoopingPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private var looper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    private var sourceURL: URL?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        (layer as? AVPlayerLayer)?.videoGravity = .resizeAspectFill
        retarget(url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func retarget(_ url: URL) {
        guard url != sourceURL else { return }
        sourceURL = url
        stop()
        // Ambient: silent clips must never take the audio route from whatever
        // the reader is listening to. Set before the player starts, because a
        // category change mid-playback is what actually ducks other audio.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        // No stalling recovery theatre on a local file; play straight through.
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        (layer as? AVPlayerLayer)?.player = player
        queuePlayer = player
        player.play()
    }

    func stop() {
        queuePlayer?.pause()
        looper?.disableLooping()
        looper = nil
        queuePlayer = nil
        (layer as? AVPlayerLayer)?.player = nil
    }
}

/// Downloads a clip once and keeps it in caches, so reopening a page replays
/// from disk instead of re-fetching a URL that will eventually expire.
actor ClipCache {
    static let shared = ClipCache()

    private var inFlight: [URL: Task<URL, Error>] = [:]

    func localCopy(of remote: URL) async throws -> URL {
        if remote.isFileURL { return remote }
        let destination = Self.cacheURL(for: remote)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        if let existing = inFlight[remote] { return try await existing.value }

        let task = Task<URL, Error> {
            let (temp, response) = try await URLSession.shared.download(from: remote)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw ProxyError.server(status: http.statusCode)
            }
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            // A half-written file from a previous attempt must never be played.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            return destination
        }
        inFlight[remote] = task
        defer { inFlight[remote] = nil }
        return try await task.value
    }

    private static func cacheURL(for remote: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // Hash the whole URL: fal's paths repeat, and the query is what makes
        // one clip distinct from another.
        let name = String(UInt64(bitPattern: Int64(remote.absoluteString.hashValue)), radix: 16)
        return caches.appending(path: "clips/\(name).mp4")
    }
}

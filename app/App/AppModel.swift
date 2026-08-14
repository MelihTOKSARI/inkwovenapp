import SwiftUI
import InkCore
import InkMoney
import InkNet

/// The wallet read, as the rooms need it. `ProxyClient` is the live conformer;
/// keeping it a protocol is what lets a preview run with no purse at all.
protocol WalletReading: Sendable {
    func wallet() async throws -> WalletView
}

extension ProxyClient: WalletReading {}

/// Where a purchase attempt stands. `deferred` is Ask-to-Buy / SCA: the
/// transaction exists, nothing is owned yet, and the room must not behave as
/// though it were.
enum PurchaseState: Equatable {
    case idle
    case purchasing
    case deferred
    /// Headline and body travel together (audit L-10): the overlay used to
    /// stamp "The seal would not take" over bodies that said the payment DID
    /// take — delivery-pending and delivery-rejected now carry titles that
    /// agree with their own words.
    case failed(title: String, message: String)
    case succeeded
}

enum AppScreen: Hashable {
    case onboarding
    case shelf
    case page
    /// The binding conversation — the blank book asking who it should be.
    case binding
    case remembered
    case memory
    case paywall
    case wallet
    case bindery
    case drawer
    case keeperGate
    case crisis
}

/// UI state + navigation for the design layer. Engine state stays in
/// PageInteractor / the InkwovenCore packages; this holds only what the
/// room needs to draw itself.
@Observable
@MainActor
final class AppModel {
    private let defaults: UserDefaults

    var screen: AppScreen
    var activeBookID: BookID = .oracle
    /// Book currently "peeked" on the shelf (first tap).
    var focusedBookID: BookID?
    var firstRun: Bool
    /// A remembered exchange chosen for revisit — PageView consumes it on
    /// appear and restores it onto the canvas.
    var revisit: PageArchive.Entry?

    var themeVariant: RoomVariant {
        didSet { defaults.set(themeVariant.rawValue, forKey: "ink.theme") }
    }
    /// Landscape shows a two-page spread when true, single page when false.
    var spreadLayout: Bool {
        didSet { defaults.set(spreadLayout, forKey: "ink.spread") }
    }
    var reduceMotionOverride: Bool {
        didSet { defaults.set(reduceMotionOverride, forKey: "ink.reduceMotion") }
    }

    // Commerce. Neither entitlement nor balance is stored here — see `bound`
    // and `wallet`. The vial count used to live in UserDefaults, where the
    // argument domain could set it and a refund could never take it back.
    /// The server's wallet, as last read. Nil until the proxy answers; the
    /// shop shows its waiting state rather than inventing a number.
    private(set) var wallet: WalletView?
    /// Tier as the last verified receipt reports it. Written only by the
    /// entitlement stream, never by a button.
    private(set) var tier: Tier = .free
    /// "Bound" is now a reading of `Transaction.currentEntitlements`, not a
    /// persisted flag. The flag it replaces was set by `confirmBind()` with no
    /// purchase behind it, survived a refund forever, and could be forged with
    /// `-ink.bound YES` because the argument domain is in the standard suite's
    /// search list.
    var bound: Bool { tier == .plus }
    private(set) var purchaseState: PurchaseState = .idle
    /// Localized storefront prices keyed by product id, filled once StoreKit
    /// answers. Hardcoded USD literals are charged at a different amount in
    /// every other storefront.
    private(set) var storePrices: [String: String] = [:]
    /// The raw decimals behind `storePrices`, for arithmetic only (audit H-4):
    /// the paywall's savings tag is computed from these, never parsed back out
    /// of a localized string — and never rendered directly.
    private(set) var storeAmounts: [String: Decimal] = [:]
    /// True once a store refresh has COMPLETED without prices for the plans
    /// the paywall sells (audit L-13) — the difference between "still waking"
    /// and "did not answer", which is the difference between waiting quietly
    /// and offering a retry.
    private(set) var storeFetchFailed = false
    /// Whether the weekly trial is open to THIS Apple ID (audit C-2). Nil
    /// until StoreKit answers; the paywall shows trial copy only on `true` —
    /// a returning subscriber promised "free for 3 days" is charged at once.
    private(set) var weeklyTrialEligible: Bool?
    /// Monthly pre-selected: it is the value plan (54% less than weekly
    /// annualised), and pre-selecting the cheap-looking weekly is the framing
    /// App Review reads as a dark pattern (3.1.2).
    var selectedPlan: Plan = .monthly
    var showBindConfirm = false
    /// The terms/privacy/AI-disclosure sheet, reachable from the paywall and
    /// the Drawer. App Review requires both documents behind a working link.
    var showPolicies = false
    /// StoreKit's manage-subscriptions sheet, presented from the Drawer for a
    /// bound user — the paywall is a place to buy, not to cancel.
    var showManageSubs = false

    // Drawer
    var hiddenBooks: Set<BookID> {
        didSet { defaults.set(hiddenBooks.map(\.rawValue), forKey: "ink.hiddenBooks") }
    }

    // MARK: - Arrivals (the shelf that grows)

    /// Books that have arrived on the shelf. A fresh notebook starts with
    /// three; the rest arrive between sessions as the writer uses it. Staged
    /// ARRIVAL, never a lock: nothing is ever shown closed or priced, and any
    /// Book can be brought over from the Drawer at any moment.
    private(set) var arrivedBooks: Set<BookID> {
        didSet { defaults.set(arrivedBooks.map(\.rawValue), forKey: "ink.arrivedBooks") }
    }
    /// Books the writer has completed at least one exchange in — the signal
    /// that the loop has been learned. Written by the page on `.answered`.
    private(set) var answeredBooks: Set<BookID> {
        didSet { defaults.set(answeredBooks.map(\.rawValue), forKey: "ink.answeredBooks") }
    }
    /// Total answered pages, ever. Arrivals require writing since the last
    /// arrival; a raw count is the cheapest durable way to know "since".
    private(set) var answeredCount: Int {
        didSet { defaults.set(answeredCount, forKey: "ink.answeredCount") }
    }
    /// The day (yyyy-MM-dd) of the last arrival — seeded to install day so
    /// nothing arrives during the very first session. One book per night.
    private var lastArrivalDay: String {
        didSet { defaults.set(lastArrivalDay, forKey: "ink.arrivalDay") }
    }
    private var answeredAtLastArrival: Int {
        didSet { defaults.set(answeredAtLastArrival, forKey: "ink.answeredAtArrival") }
    }

    /// A fresh shelf: the three Books whose verbs need no setup — ask, draw,
    /// tell the day — and the blank book beside them, waiting to be bound.
    /// Everything else asks the writer to supply a premise, a hero, a
    /// problem or an addressee, which is exactly the cliff this staging
    /// removes.
    static let firstShelf: Set<BookID> = [.oracle, .artist, .keeper, .custom]

    /// The order the rest arrive in, easiest verb first.
    static let arrivalOrder: [BookID] = [
        .storyteller, .gameMaster, .tutor, .correspondent, .parlor,
    ]

    // MARK: - The writer's own Book

    /// The binding, once the conversation completes; nil while the blank
    /// book stands unbound. JSON in defaults — the whole thing is eight
    /// short strings and a date.
    private(set) var customBinding: CustomBinding? {
        didSet {
            if let binding = customBinding, let data = try? JSONEncoder().encode(binding) {
                defaults.set(data, forKey: "ink.customBinding")
            } else {
                defaults.removeObject(forKey: "ink.customBinding")
            }
        }
    }
    /// The name's own strokes, when it was written in ink — the spine wears
    /// them instead of our gilt. Every other answer keeps only its text.
    private(set) var customNameInk: Data? {
        didSet { defaults.set(customNameInk, forKey: "ink.customNameInk") }
    }
    /// Mid-conversation answers, held so leaving the binding and coming back
    /// resumes where the page left off. Session-only on purpose: an
    /// abandoned half-binding should not survive a relaunch as a ghost.
    var bindingDraft: [BindingAnswer] = []

    struct BindingAnswer: Equatable {
        var text = ""
        var drawingData: Data?
        var skipped = false
    }
    /// Re-dressings: the hand a Book writes in instead of its own. Absent
    /// means the Book keeps the script it was bound with. The Drawer's
    /// shelf-wide choice writes every Book at once (`setAllHands`); there is
    /// deliberately no second, global layer to reason about.
    var bookHands: [BookID: String] {
        didSet {
            defaults.set(
                Dictionary(uniqueKeysWithValues: bookHands.map { ($0.key.rawValue, $0.value) }),
                forKey: "ink.bookHands"
            )
        }
    }
    var inkColorHex: UInt32 {
        didSet { defaults.set(Int(inkColorHex), forKey: "ink.inkColor") }
    }
    var leftHanded: Bool {
        didSet { defaults.set(leftHanded, forKey: "ink.leftHanded") }
    }
    var showDeleteConfirm = false
    /// The completed reply under report (guideline 1.2): set by a long-press
    /// on a reply, cleared on dismiss or send. Presence drives the report
    /// sheet overlay the way `showPolicies` drives the policy sheet.
    var reportTarget: PageArchive.Entry?

    // The evening ritual. Off until the writer grants notifications after
    // their first answered page; never required for the app to function.
    var ritualEnabled: Bool {
        didSet {
            defaults.set(ritualEnabled, forKey: "ink.ritualEnabled")
            scheduleRitualRearm()
        }
    }
    var ritualHour: Int {
        didSet {
            defaults.set(ritualHour, forKey: "ink.ritualHour")
            scheduleRitualRearm()
        }
    }
    var ritualMinute: Int {
        didSet {
            defaults.set(ritualMinute, forKey: "ink.ritualMinute")
            scheduleRitualRearm()
        }
    }
    /// The system prompt can be shown once, ever — re-triggering it does
    /// nothing. Recorded only after the dialog actually resolves (audit
    /// M-11): latching before the answer meant a process death mid-prompt
    /// left authorization `.notDetermined` behind a flag that said "asked",
    /// and the Drawer's toggle went permanently dead.
    private(set) var ritualAsked: Bool {
        didSet { defaults.set(ritualAsked, forKey: "ink.ritualAsked") }
    }
    private(set) var ritualAuthorization: RitualAuthorization = .notDetermined
    /// The Book whose voice the ritual speaks in — the last one actually
    /// opened to its page. BookState.lastOpenedAt in the InkData schema is
    /// this fact's future home, but that layer is dormant at runtime, so the
    /// defaults key is the record.
    private(set) var lastOpenedBookID: BookID? {
        didSet { defaults.set(lastOpenedBookID?.rawValue, forKey: "ink.lastOpenedBook") }
    }

    /// The Keeper's one-time consent to send a sealed page out for a moving
    /// picture (task J6). Asked once, remembered after — but only ever set by
    /// the reader agreeing on the consent card, never by a tap elsewhere.
    private(set) var keeperClipConsentGranted: Bool {
        didSet { defaults.set(keeperClipConsentGranted, forKey: "ink.keeperClipConsent") }
    }

    func grantKeeperClipConsent() {
        keeperClipConsentGranted = true
    }

    var keeperUnlocked = false
    var signedName: String {
        didSet { defaults.set(signedName, forKey: "ink.signedName") }
    }
    /// PKDrawing archive of the flyleaf signature — pen-first onboarding
    /// (task H1); the name is written in ink, never typed.
    var signatureData: Data? {
        didSet { defaults.set(signatureData, forKey: "ink.signature") }
    }

    enum Plan: String {
        case weekly, monthly

        var productID: String { self == .weekly ? ProductID.plusWeekly : ProductID.plusMonthly }
        var label: String { self == .weekly ? "seven nights" : "one moon" }
    }

    init(
        defaults: UserDefaults = .standard,
        purchases: any PurchaseServicing = LiveCommerce.purchases,
        walletReader: (any WalletReading)? = nil,
        ritual: RitualScheduler? = nil,
        ritualDiary: (any RitualDiary)? = nil
    ) {
        self.defaults = defaults
        self.purchases = purchases
        self.walletReader = walletReader
        self.ritual = ritual
        self.ritualDiary = ritualDiary
        // The review/UITest affordances stay, but only in Debug. They read the
        // whole search list — argument domain AND the persistent plist, which
        // rides along in an unencrypted device backup — and `-ink.startScreen
        // page -ink.startBook keeper` assigns `screen` directly, never passing
        // through `open(book:)` where the Keeper's lock is enforced. In a
        // Release build that is a Face ID gate anyone can walk around.
        #if DEBUG
        // `-ink.resetOnboarding YES` wipes the flyleaf so onboarding runs
        // fresh (a Data key can't be cleared through the argument domain).
        if defaults.bool(forKey: "ink.resetOnboarding") {
            defaults.removeObject(forKey: "ink.signature")
            defaults.removeObject(forKey: "ink.signedName")
            defaults.removeObject(forKey: "ink.seenOnboarding")
        }
        #endif
        let seenOnboarding = defaults.bool(forKey: "ink.seenOnboarding")
        firstRun = !seenOnboarding
        screen = seenOnboarding ? .shelf : .onboarding
        #if DEBUG
        // `-ink.startScreen paywall` etc. jumps straight to a screen (the
        // handoff console's nav, as launch args).
        if let start = defaults.string(forKey: "ink.startScreen") {
            let routes: [String: AppScreen] = [
                "onboarding": .onboarding, "shelf": .shelf, "page": .page,
                "remembered": .remembered, "memory": .memory, "paywall": .paywall,
                "wallet": .wallet, "bindery": .bindery, "drawer": .drawer,
                "keeperGate": .keeperGate, "crisis": .crisis,
            ]
            if let target = routes[start] { screen = target }
        }
        if let startBook = defaults.string(forKey: "ink.startBook") {
            activeBookID = BookID(rawValue: startBook)
        }
        #endif
        themeVariant = RoomVariant(rawValue: defaults.string(forKey: "ink.theme") ?? "") ?? .candlelight
        spreadLayout = defaults.object(forKey: "ink.spread") as? Bool ?? true
        reduceMotionOverride = defaults.bool(forKey: "ink.reduceMotion")
        hiddenBooks = Set((defaults.stringArray(forKey: "ink.hiddenBooks") ?? []).map { BookID(rawValue: $0) })
        // Arrivals. A notebook that predates staging keeps every book it
        // already had — arrival may only ever ADD to a shelf, never empty one.
        if let stored = defaults.stringArray(forKey: "ink.arrivedBooks") {
            arrivedBooks = Set(stored.map { BookID(rawValue: $0) })
        } else if seenOnboarding {
            // An existing notebook keeps all eight — and the blank book
            // arrives with the update, the same gift new writers earn.
            arrivedBooks = Set(Book.all.map(\.id)).union([.custom])
        } else {
            arrivedBooks = Self.firstShelf
        }
        customBinding = defaults.data(forKey: "ink.customBinding")
            .flatMap { try? JSONDecoder().decode(CustomBinding.self, from: $0) }
        customNameInk = defaults.data(forKey: "ink.customNameInk")
        answeredBooks = Set((defaults.stringArray(forKey: "ink.answeredBooks") ?? []).map { BookID(rawValue: $0) })
        answeredCount = defaults.object(forKey: "ink.answeredCount") as? Int ?? 0
        // Seeded to today on first run: the first night must pass before the
        // first arrival, or a book appears mid-first-session with no night in
        // between.
        lastArrivalDay = defaults.string(forKey: "ink.arrivalDay") ?? Self.dayStamp(.now)
        answeredAtLastArrival = defaults.object(forKey: "ink.answeredAtArrival") as? Int ?? 0
        // Unknown faces (a renamed hand, a forged plist) fall back silently
        // to the Book's own rather than to San Francisco.
        let storedHands = defaults.dictionary(forKey: "ink.bookHands") as? [String: String] ?? [:]
        bookHands = Dictionary(uniqueKeysWithValues: storedHands.compactMap { key, value in
            Hand.by(id: value) != nil ? (BookID(key), value) : nil
        })
        // A trapping conversion here crashes inside `init`, i.e. on every
        // launch with no way back: `as? Int` succeeds for a negative NSNumber,
        // and the argument domain can supply one.
        inkColorHex = UInt32(exactly: defaults.object(forKey: "ink.inkColor") as? Int ?? 0x2E2418)
            ?? 0x2E2418
        leftHanded = defaults.bool(forKey: "ink.leftHanded")
        ritualEnabled = defaults.bool(forKey: "ink.ritualEnabled")
        // Out-of-range hours (the argument domain, a forged plist) fall back
        // to eight in the evening rather than to a night that never comes.
        let storedHour = defaults.object(forKey: "ink.ritualHour") as? Int
        ritualHour = storedHour.flatMap { (0...23).contains($0) ? $0 : nil } ?? 20
        let storedMinute = defaults.object(forKey: "ink.ritualMinute") as? Int
        ritualMinute = storedMinute.flatMap { (0...59).contains($0) ? $0 : nil } ?? 0
        ritualAsked = defaults.bool(forKey: "ink.ritualAsked")
        // Only a Book the shelf actually carries may speak the ritual.
        let storedVoice = defaults.string(forKey: "ink.lastOpenedBook").map { BookID(rawValue: $0) }
        lastOpenedBookID = storedVoice.flatMap { id in
            id == .custom || Book.all.contains { $0.id == id } ? id : nil
        }
        keeperClipConsentGranted = defaults.bool(forKey: "ink.keeperClipConsent")
        signedName = defaults.string(forKey: "ink.signedName") ?? ""
        signatureData = defaults.data(forKey: "ink.signature")
        // The old forgeable entitlement flag: remove it so nothing can revive
        // it, and so a device carrying `ink.bound = YES` loses it on this run.
        defaults.removeObject(forKey: "ink.bound")
        // Same for the local vial count, which the argument domain could set
        // and which no refund could ever claw back. The wallet is the server's.
        defaults.removeObject(forKey: "ink.credits")
        // And the pencil observation a pre-fix build persisted (audit M-12):
        // left in the plist it would re-latch the old for-good keyboard
        // lockout (A-1) the moment an upgrader launched. This runs before any
        // surface wakes PenPresence, and the UITest `-ink.pencilSeen YES`
        // injection rides the argument domain, which removeObject cannot touch.
        defaults.removeObject(forKey: "ink.pencilSeen")
        // And the reply-length choice (audit H-10): the control was a dead
        // switch — nothing downstream ever read it — so the row is gone until
        // the engine honors it, and the persisted key goes with it.
        defaults.removeObject(forKey: "ink.replyLength")
        observeCommerce()
        // A launch is a wake: if a night has passed and pages were written,
        // the shelf is different this morning than it was.
        arrivalsOnWake()
    }

    deinit {
        // The streams end with their model (audit L-17): the for-await loops
        // in `observeCommerce` hold `self` weakly, so the last reference dying
        // actually reaches here — and this puts the tasks down rather than
        // leaving them parked forever on streams that never finish.
        entitlementTask?.cancel()
        grantTask?.cancel()
        ritualTask?.cancel()
        purchaseWatchdog?.cancel()
    }

    // MARK: - Commerce

    private let purchases: any PurchaseServicing
    /// Reads the server-side balance. Optional so previews and the harness can
    /// run with no network — they show the waiting state, never a fake purse.
    private let walletReader: (any WalletReading)?
    // `nonisolated(unsafe)` so a nonisolated `deinit` can cancel them (audit
    // L-17); every write happens on the main actor, and by the time deinit
    // runs no other reference exists to race with.
    @ObservationIgnored nonisolated(unsafe) private var entitlementTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var grantTask: Task<Void, Never>?
    /// Resolves a hung `.purchasing` scrim (audit L-15) — see
    /// `setPurchaseState`. `nonisolated(unsafe)` for the same deinit reason
    /// as the commerce tasks above.
    @ObservationIgnored nonisolated(unsafe) private var purchaseWatchdog: Task<Void, Never>?

    // Titles and bodies agree with each other (audit L-10): a payment still
    // in the post is not a seal that "would not take".
    private static let purchaseFailure = PurchaseState.failed(
        title: "The seal would not take",
        message: "Nothing was charged. Try once more in a moment."
    )
    private static let deliveryPending = PurchaseState.failed(
        title: "Paid, and in the post",
        message: "The vials are paid for but still in the post. They will arrive when the road clears — open the app again in a moment."
    )
    private static let deliveryRejected = PurchaseState.failed(
        title: "Sealed, but undelivered",
        message: "The purchase went through, but the vials could not be delivered to this notebook. Write to the binder from the Drawer — nothing is lost."
    )
    // The restore's endings, told apart (audit M-7).
    private static let restoreEmpty = PurchaseState.failed(
        title: "No binding was found",
        message: "The App Store keeps no binding for this Apple ID. If the notebook was bound under another, sign in with that hand and restore again."
    )
    private static let restoreOffline = PurchaseState.failed(
        title: "The road is dark",
        message: "The App Store could not be reached. Try the restore again when the way opens."
    )
    private static let restoreFailure = PurchaseState.failed(
        title: "The restore would not take",
        message: "Nothing has changed. Try again in a moment."
    )
    /// The watchdog's verdict (audit L-15) — honest about not knowing.
    private static let storefrontSilent = PurchaseState.failed(
        title: "The storefront did not answer",
        message: "No word has come from the App Store. If the purchase went through, it will land on its own — nothing is lost. Otherwise, try again in a moment."
    )

    private func observeCommerce() {
        // Every capture below is weak (audit L-17): these loops run for the
        // life of the streams, and a strong `self` would make any AppModel
        // that ever armed them immortal.
        entitlementTask = Task { [purchases, weak self] in
            // Armed before `start()` so the reconcile it performs is seen.
            for await snapshot in purchases.snapshots() {
                guard let self else { return }
                self.tier = snapshot.tier
            }
        }
        grantTask = Task { [purchases, weak self] in
            // A delivered purchase means the SERVER's balance changed; re-read
            // it rather than adding up what the client thinks it bought.
            for await _ in purchases.creditGrants() {
                guard let self else { return }
                await self.refreshWallet()
            }
        }
        Task { [purchases, weak self] in
            await purchases.start()
            await self?.refreshStore()
            await self?.refreshWallet()
        }
    }

    /// Re-reads the server wallet. Failure leaves the last known value standing
    /// — the shop says what it last knew rather than flashing an empty purse.
    func refreshWallet() async {
        guard let walletReader else { return }
        if let view = try? await walletReader.wallet() { wallet = view }
    }

    /// Re-reads prices and trial eligibility from StoreKit (audit C-2/C-3).
    /// This used to run once inside a fire-and-forget launch task: an offline
    /// launch left `storePrices` empty for the whole session, every surface
    /// fell back to a hardcoded USD literal, and pressing the seal met
    /// `productUnavailable`. Now the paywall re-asks on appear and RootView
    /// re-asks on every foreground; failures keep the last known values.
    /// One batched wire call for all five products (audit L-11), and
    /// `storeFetchFailed` tells the paywall when the storefront has still not
    /// answered for the plans it sells (audit L-13).
    func refreshStore() async {
        let ids = [ProductID.plusWeekly, ProductID.plusMonthly] + ProductID.consumables.sorted()
        let quotes = await purchases.products(for: ids)
        for (id, quote) in quotes {
            storePrices[id] = quote.display
            storeAmounts[id] = quote.amount
        }
        if let eligible = await purchases.isEligibleForIntroOffer(ProductID.plusWeekly) {
            weeklyTrialEligible = eligible
        }
        storeFetchFailed = storePrices[ProductID.plusWeekly] == nil
            || storePrices[ProductID.plusMonthly] == nil
    }

    /// The binding room opened. Called once per presentation from the room's own
    /// `.task`, never from `body` — a second call is a second impression, and a
    /// paywall that reports itself twice halves its own measured conversion.
    func notePaywallShown() async {
        await purchases.notePaywallImpression("inkwoven_binding_v1")
    }

    func clearPurchaseNote() {
        setPurchaseState(.idle)
    }

    /// Every purchase-state write passes through here so the watchdog's clock
    /// matches the scrim exactly (audit L-15): `.purchasing` arms it, any
    /// verdict stands it down. The watchdog resolves a StoreKit call that
    /// never answers into an honest note rather than a room bricked until
    /// force-quit — WITHOUT cancelling the purchase task, so a late answer
    /// still runs the normal paths and overwrites the verdict truthfully.
    private func setPurchaseState(_ next: PurchaseState) {
        purchaseWatchdog?.cancel()
        purchaseState = next
        guard next == .purchasing else { return }
        purchaseWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            // Only a still-hung purchase gets the silent-storefront note; a
            // verdict that landed while the watchdog slept stands untouched.
            guard self.purchaseState == .purchasing else { return }
            self.purchaseState = Self.storefrontSilent
        }
    }

    var theme: RoomTheme {
        themeVariant == .daylight ? .daylight : .candlelight
    }

    var activeBook: Book { book(activeBookID) }

    var visibleBooks: [Book] {
        var books = Book.all.filter { arrivedBooks.contains($0.id) && !hiddenBooks.contains($0.id) }
        if arrivedBooks.contains(.custom) && !hiddenBooks.contains(.custom) {
            // The writer's own book stands at the warm end of the row, blank
            // until it is bound.
            books.append(Book.custom(customBinding))
        }
        return books
    }

    // MARK: - Arrivals

    private static func dayStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// The page completed an exchange — the only signal arrivals listen to.
    func noteAnswered(_ id: BookID) {
        answeredBooks.insert(id)
        answeredCount += 1
    }

    /// A night passes. Called on launch and on every return to the
    /// foreground: if today is a new day AND the writer has answered a page
    /// since the last arrival, one more book stands on the ledge — quietly,
    /// with no badge and no announcement. The card under its spine does the
    /// telling when the writer notices.
    func arrivalsOnWake() {
        let today = Self.dayStamp(.now)
        guard lastArrivalDay != today,
              answeredCount > answeredAtLastArrival,
              let next = Self.arrivalOrder.first(where: { !arrivedBooks.contains($0) })
        else { return }
        arrivedBooks.insert(next)
        lastArrivalDay = today
        answeredAtLastArrival = answeredCount
    }

    /// The Drawer's override: any book, brought to the shelf right now. The
    /// staging is a pace, never a wall.
    func bringToShelf(_ id: BookID) {
        arrivedBooks.insert(id)
        hiddenBooks.remove(id)
    }

    // MARK: - Binding the writer's own Book

    /// The conversation finished: the book takes its dye and its name. The
    /// draft dies here — it has become the binding.
    func bind(_ binding: CustomBinding, nameInk: Data?) {
        customBinding = binding
        customNameInk = nameInk
        bindingDraft = []
    }

    /// One bookplate line, rewritten. Empty strings are honest values —
    /// writing nothing over a line clears it back to the proxy's fallback.
    func amendBinding(_ change: (inout CustomBinding) -> Void) {
        guard var binding = customBinding else { return }
        change(&binding)
        customBinding = binding
    }

    /// The seal broken: the plate lifts away and the blank book returns.
    /// The book's PAGES survive — only the voice is unbound.
    func unbindCustomBook() {
        customBinding = nil
        customNameInk = nil
        bindingDraft = []
    }

    /// A rewritten name retires the drawn one — the spine may not carry
    /// strokes that spell a different word than the plate.
    func clearCustomNameInk() {
        customNameInk = nil
    }

    // MARK: - Hands

    /// The Book as it currently dresses: its preset identity, wearing the
    /// writer's chosen hand when one is set. The writer's own Book has no
    /// preset — it dresses from the binding.
    func book(_ id: BookID) -> Book {
        let preset = id == .custom ? Book.custom(customBinding) : Book.by(id: id)
        guard let choice = bookHands[id], let hand = Hand.by(id: choice),
              hand.id != preset.hand
        else { return preset }
        return preset.wearing(hand)
    }

    /// One Book's choice, from its page. nil restores the Book's own hand.
    func setHand(_ handID: String?, for id: BookID) {
        if let handID {
            bookHands[id] = handID
        } else {
            bookHands.removeValue(forKey: id)
        }
    }

    /// The Drawer's shelf-wide stroke: dress every Book at once (nil sends
    /// every Book back to its own script). Overwrites per-Book choices —
    /// "the whole shelf writes in this" must mean the whole shelf.
    func setAllHands(_ handID: String?) {
        if let handID {
            bookHands = Dictionary(uniqueKeysWithValues: Book.all.map { ($0.id, handID) })
        } else {
            bookHands = [:]
        }
    }

    /// What the Drawer's row reports about the shelf as a whole.
    enum ShelfHand: Equatable {
        case own, uniform(String), mixed
    }

    var shelfHand: ShelfHand {
        let choices = Set(Book.all.map { bookHands[$0.id] })
        if choices.isEmpty || choices == [nil] { return .own }
        if choices.count == 1, let id = choices.first ?? nil { return .uniform(id) }
        return .mixed
    }

    // MARK: - The evening ritual

    private let ritual: RitualScheduler?
    private let ritualDiary: (any RitualDiary)?
    /// The re-arm in flight, held so tests can await it instead of polling.
    /// `nonisolated(unsafe)` for the same reason as the commerce tasks: the
    /// nonisolated `deinit` must be able to cancel it, and all writes stay
    /// on the main actor.
    @ObservationIgnored nonisolated(unsafe) private(set) var ritualTask: Task<Void, Never>?

    /// The voice on tonight's notification: the Book last opened, or the
    /// Keeper for a writer with no history yet.
    var ritualVoice: BookID { lastOpenedBookID ?? .keeper }

    /// What the Drawer's toggle shows. The wish and the permission both have
    /// to hold — a toggle reading "on" while the device blocks delivery would
    /// be a lie.
    var ritualEffectivelyOn: Bool {
        ritualEnabled && ritualAuthorization == .granted
    }

    var ritualTimeDate: Date {
        Calendar.current.date(bySettingHour: ritualHour, minute: ritualMinute, second: 0, of: .now) ?? .now
    }

    func setRitualTime(from date: Date, calendar: Calendar = .current) {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        ritualHour = time.hour ?? 20
        ritualMinute = time.minute ?? 0
    }

    /// A prompt already on screen; the flag never persists this state, so a
    /// death mid-dialog leaves the question askable (audit M-11).
    private var ritualAskInFlight = false

    /// The value moment — called after the first answered page, mirroring how
    /// the paywall waits. Asks the system exactly once; the ask is recorded
    /// only when the dialog actually resolves, and a recorded ask whose
    /// authorization still reads `.notDetermined` (a death mid-prompt, or a
    /// pre-fix build that latched early) counts as never asked. A grant turns
    /// the ritual on, a denial leaves it silently off. Returns nil when there
    /// was nothing to ask, so the caller knows whether an answer happened.
    func promptRitualIfNeeded() async -> Bool? {
        guard let ritual, !ritualAskInFlight else { return nil }
        if ritualAsked {
            // Marked asked, yet the device still holds the question open —
            // the system will happily show its dialog, so let it.
            ritualAuthorization = await ritual.authorization()
            guard ritualAuthorization == .notDetermined else { return nil }
        }
        ritualAskInFlight = true
        defer { ritualAskInFlight = false }
        let granted = await ritual.requestAuthorization()
        ritualAsked = true
        ritualAuthorization = granted ? .granted : .denied
        if granted {
            ritualEnabled = true
        }
        return granted
    }

    /// Fire-and-track re-arm for synchronous call sites (didSets, scene
    /// changes). The task replaces any previous one; last write wins — and
    /// the predecessor is cancelled first (audit L-21), so two re-arms can
    /// never interleave their cancel-then-schedule halves and double a night.
    func scheduleRitualRearm() {
        guard ritual != nil else { return }
        ritualTask?.cancel()
        ritualTask = Task { await rearmRitual() }
    }

    /// Replace the pending week with the next one: refresh where authorization
    /// stands, then either lay out the nights or clear the queue. Runs on
    /// every foreground and after every archived page, so tonight's request
    /// disappears the moment a page is written.
    func rearmRitual(now: Date = .now, calendar: Calendar = .current) async {
        guard let ritual else { return }
        ritualAuthorization = await ritual.authorization()
        // A re-arm superseded while it awaited (audit L-21) stands down here
        // rather than racing its replacement over the pending queue. Outside
        // a cancelled task this is always false, so direct calls still run.
        guard !Task.isCancelled else { return }
        guard ritualAsked, ritualEnabled, ritualAuthorization == .granted else {
            await ritual.cancelAll()
            return
        }
        await ritual.schedule(RitualPlanner.plan(
            now: now,
            calendar: calendar,
            hour: ritualHour,
            minute: ritualMinute,
            voice: ritualVoice,
            lastWrittenAt: ritualDiary?.lastWrittenAt
        ))
    }

    // MARK: - Navigation

    /// **The way back.** Every forward move records where it came from, so a
    /// screen reachable from four places returns to whichever one was actually
    /// used. Screens used to hardcode their own exit — almost all of them to
    /// `.shelf` — which meant hitting the daily limit mid-page and binding the
    /// notebook dropped you on the shelf instead of back on the page you were
    /// still writing. The Vials had already solved this privately with a
    /// `vialsReturn` field; this is that idea, once, for every screen.
    private var trail: [AppScreen] = []

    /// Screens with nothing behind them: arriving at one IS arriving home, and
    /// whatever led there stops being a way back.
    private static let roots: Set<AppScreen> = [.shelf, .onboarding]

    func go(_ target: AppScreen) {
        if target != screen {
            if Self.roots.contains(target) {
                trail.removeAll()
            } else if let already = trail.firstIndex(of: target) {
                // Walking to a screen that is already behind you is a return,
                // not a deeper push — otherwise page → paywall → page →
                // paywall grows a trail no amount of backing out exhausts.
                trail.removeSubrange(already...)
            } else {
                trail.append(screen)
            }
        }
        withAnimation(.easeInOut(duration: 0.35)) {
            screen = target
        }
        if target != .shelf { focusedBookID = nil }
    }

    /// One step back, to wherever this screen was opened from. An empty trail
    /// means a root — or a debug launch argument that dropped us mid-app — and
    /// the shelf is the floor under both.
    func back() {
        let destination = trail.popLast() ?? .shelf
        withAnimation(.easeInOut(duration: 0.35)) {
            screen = destination
        }
        if destination != .shelf { focusedBookID = nil }
    }

    /// What the back pill should SAY — the name of the place it actually
    /// returns to. Labels and destinations were written separately and drifted
    /// apart (a paywall pill reading "back" that always landed on the shelf);
    /// deriving both from one trail makes a pill that lies impossible.
    var backLabel: String {
        switch trail.last {
        case .page: activeBook.name
        case .binding: "the binding"
        case .remembered: "remembered"
        case .memory: "the memory"
        case .drawer: "the drawer"
        case .bindery: "the bindery"
        case .wallet: "the vials"
        case .paywall: "the binding"
        case .keeperGate, .crisis, .onboarding: "back"
        case .shelf, nil: "the shelf"
        }
    }

    /// Hard reset to the shelf with the trail cut — the Keeper relocking, and
    /// anything else that ejects a reader rather than letting them leave.
    /// Deliberately unanimated: `relockKeeper` runs while the app-switcher
    /// snapshot is being taken, and a transition would be caught mid-flight.
    func evictToShelf() {
        trail.removeAll()
        screen = .shelf
        focusedBookID = nil
    }

    func open(book: Book) {
        activeBookID = book.id
        focusedBookID = nil
        if book.blank {
            // The unwritten book opens onto its own first question, not a
            // page — binding IS this book's first visit.
            go(.binding)
        } else if book.locked && !keeperUnlocked {
            go(.keeperGate)
        } else {
            // Recorded only when the page actually opens — a Book that turned
            // the visitor away at the gate never becomes the ritual's voice.
            lastOpenedBookID = book.id
            go(.page)
        }
    }

    /// A ritual notification was tapped (audit L-18): walk to that Book's
    /// page through the same door a shelf tap uses. The Keeper still meets
    /// its gate — `open(book:)` is where the lock lives, and this path adds
    /// no way around it. A Book the shelf no longer carries, or a tap landing
    /// mid-onboarding, is quietly ignored.
    func openFromRitual(_ id: BookID) {
        guard screen != .onboarding,
              id == .custom || Book.all.contains(where: { $0.id == id })
        else { return }
        open(book: book(id))
    }

    /// First tap peeks (whisper), second tap opens — mirrors the shelf's
    /// hover behaviour on touch.
    func tap(book: Book) {
        if focusedBookID == book.id {
            open(book: book)
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                focusedBookID = book.id
            }
        }
    }

    func finishOnboarding() {
        defaults.set(true, forKey: "ink.seenOnboarding")
        go(.shelf)
    }

    // MARK: - Buying

    /// "Press the seal to bind." A real StoreKit 2 purchase. The seal used to
    /// set `bound = true` and walk on — an unpaid entitlement, and an
    /// automatic 3.1.1 rejection for showing a price with no payment sheet.
    /// Nothing here grants anything: the tier moves only when a verified
    /// receipt reaches the entitlement stream.
    func confirmBind() {
        showBindConfirm = false
        setPurchaseState(.purchasing)
        let productID = selectedPlan.productID
        Task { [purchases] in
            do {
                switch try await purchases.purchase(productID) {
                case .success:
                    // Stay on the paywall: the success card is the receipt the
                    // user sees, and its dismissal walks back to the shelf.
                    // (The Memory screen this used to open showed demo notes —
                    // cross-page memory is not a v1 feature.)
                    self.setPurchaseState(.succeeded)
                case .pending:
                    // Ask to Buy / SCA: the transaction is real, the
                    // entitlement is not. Opening Memory here is how a minor
                    // ends up with Plus nobody approved.
                    self.setPurchaseState(.deferred)
                case .cancelled:
                    self.setPurchaseState(.idle)
                }
            } catch {
                self.setPurchaseState(Self.purchaseFailure)
            }
        }
    }

    /// A vial pack, by product id. The credits land in the SERVER's wallet when
    /// the transaction verifies and the proxy accepts it — never here. This was
    /// once `credits += pack` behind a button labelled with a price.
    func buyVials(_ productID: String) {
        // One purchase at a time (audit L-14): two rapid taps used to start
        // two StoreKit tasks before the scrim could rise to block the second.
        guard purchaseState != .purchasing else { return }
        guard ProductID.consumables.contains(productID) else {
            setPurchaseState(Self.purchaseFailure)
            return
        }
        setPurchaseState(.purchasing)
        Task { [purchases] in
            do {
                switch try await purchases.purchase(productID) {
                case .success:
                    self.setPurchaseState(.succeeded)
                    await self.refreshWallet()
                case .pending: self.setPurchaseState(.deferred)
                case .cancelled: self.setPurchaseState(.idle)
                }
            } catch CommerceError.deliveryPending {
                // Paid, but the wallet has not been credited yet. The
                // transaction stays open, so StoreKit redelivers it — say so
                // honestly rather than claiming a failure that lost the money.
                self.setPurchaseState(Self.deliveryPending)
            } catch CommerceError.deliveryRejected {
                // The server refused the receipt terminally (audit M-4): the
                // transaction is finished so it can never loop, and the way
                // forward is a human, not a retry.
                self.setPurchaseState(Self.deliveryRejected)
            } catch {
                self.setPurchaseState(Self.purchaseFailure)
            }
        }
    }

    /// "Restore a binding." App Review requires a working restore on any
    /// auto-renewable subscription, and it is the only way back for a user who
    /// reinstalled or changed device. The endings are told apart (audit M-7):
    /// a binding found, an empty-handed sync, a sheet the user closed
    /// themselves (silent), a dark road, and a real failure each get their own
    /// words — the old flow ended a successful-but-empty sync in silence and
    /// blamed "no binding" for airplane mode.
    func restorePurchases() {
        guard purchaseState != .purchasing else { return }
        setPurchaseState(.purchasing)
        Task { [purchases] in
            do {
                // The verdict rides the return value, settled inside the
                // store before it answers — never a race against the
                // entitlement stream reaching `bound` first.
                let found = try await purchases.restore()
                self.setPurchaseState(found ? .succeeded : Self.restoreEmpty)
            } catch CommerceError.cancelled {
                self.setPurchaseState(.idle)
            } catch CommerceError.offline {
                self.setPurchaseState(Self.restoreOffline)
            } catch {
                self.setPurchaseState(Self.restoreFailure)
            }
        }
    }

    /// What the shop shows on the shelf. Nil while the wallet is still being
    /// read — the room says "counting" rather than "none".
    var vialBalance: Int? { wallet?.available }
    var freeClipsRemaining: Int? { wallet?.freeClipsRemaining }

    func toggleShelf(book: Book) {
        if hiddenBooks.contains(book.id) {
            hiddenBooks.remove(book.id)
        } else {
            hiddenBooks.insert(book.id)
        }
    }
}

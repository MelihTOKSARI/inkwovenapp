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
    case failed(String)
    case succeeded
}

enum AppScreen: Hashable {
    case onboarding
    case shelf
    case page
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
    var replyLength: ReplyLength {
        didSet { defaults.set(replyLength.rawValue, forKey: "ink.replyLength") }
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
    /// nothing. This flag is what makes the ask honest about that.
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

    enum ReplyLength: String, CaseIterable {
        case terse = "Terse", measured = "Measured", full = "Full"
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
        replyLength = ReplyLength(rawValue: defaults.string(forKey: "ink.replyLength") ?? "") ?? .measured
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
            Book.all.contains { $0.id == id } ? id : nil
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
        observeCommerce()
    }

    // MARK: - Commerce

    private let purchases: any PurchaseServicing
    /// Reads the server-side balance. Optional so previews and the harness can
    /// run with no network — they show the waiting state, never a fake purse.
    private let walletReader: (any WalletReading)?
    private var entitlementTask: Task<Void, Never>?
    private var grantTask: Task<Void, Never>?

    private static let purchaseFailure = "The seal would not take. Nothing was charged."
    private static let restoreFailure = "No binding was found for this hand."
    private static let deliveryPending =
        "The vials are paid for but still in the post. They will arrive when the road clears — open the app again in a moment."

    private func observeCommerce() {
        entitlementTask = Task { [purchases] in
            // Armed before `start()` so the reconcile it performs is seen.
            for await snapshot in purchases.snapshots() {
                self.tier = snapshot.tier
            }
        }
        grantTask = Task { [purchases] in
            // A delivered purchase means the SERVER's balance changed; re-read
            // it rather than adding up what the client thinks it bought.
            for await _ in purchases.creditGrants() {
                await self.refreshWallet()
            }
        }
        Task { [purchases] in
            await purchases.start()
            await self.refreshStore()
            await self.refreshWallet()
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
    func refreshStore() async {
        let ids = [ProductID.plusWeekly, ProductID.plusMonthly] + ProductID.consumables.sorted()
        for id in ids {
            if let price = await purchases.displayPrice(for: id) { storePrices[id] = price }
        }
        if let eligible = await purchases.isEligibleForIntroOffer(ProductID.plusWeekly) {
            weeklyTrialEligible = eligible
        }
    }

    func clearPurchaseNote() {
        purchaseState = .idle
    }

    var theme: RoomTheme {
        themeVariant == .daylight ? .daylight : .candlelight
    }

    var activeBook: Book { book(activeBookID) }

    var visibleBooks: [Book] { Book.all.filter { !hiddenBooks.contains($0.id) } }

    // MARK: - Hands

    /// The Book as it currently dresses: its preset identity, wearing the
    /// writer's chosen hand when one is set.
    func book(_ id: BookID) -> Book {
        let preset = Book.by(id: id)
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
    private(set) var ritualTask: Task<Void, Never>?

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

    /// The value moment — called after the first answered page, mirroring how
    /// the paywall waits. Asks the system exactly once, ever; a grant turns
    /// the ritual on, a denial leaves it silently off. Returns nil when there
    /// was nothing to ask, so the caller knows whether an answer happened.
    func promptRitualIfNeeded() async -> Bool? {
        guard let ritual, !ritualAsked else { return nil }
        ritualAsked = true
        let granted = await ritual.requestAuthorization()
        ritualAuthorization = granted ? .granted : .denied
        if granted {
            ritualEnabled = true
        }
        return granted
    }

    /// Fire-and-track re-arm for synchronous call sites (didSets, scene
    /// changes). The task replaces any previous one; last write wins.
    func scheduleRitualRearm() {
        guard ritual != nil else { return }
        ritualTask = Task { await rearmRitual() }
    }

    /// Replace the pending week with the next one: refresh where authorization
    /// stands, then either lay out the nights or clear the queue. Runs on
    /// every foreground and after every archived page, so tonight's request
    /// disappears the moment a page is written.
    func rearmRitual(now: Date = .now, calendar: Calendar = .current) async {
        guard let ritual else { return }
        ritualAuthorization = await ritual.authorization()
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

    func go(_ target: AppScreen) {
        withAnimation(.easeInOut(duration: 0.35)) {
            screen = target
        }
        if target != .shelf { focusedBookID = nil }
    }

    func open(book: Book) {
        activeBookID = book.id
        focusedBookID = nil
        if book.locked && !keeperUnlocked {
            go(.keeperGate)
        } else {
            // Recorded only when the page actually opens — a Book that turned
            // the visitor away at the gate never becomes the ritual's voice.
            lastOpenedBookID = book.id
            go(.page)
        }
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
        purchaseState = .purchasing
        let productID = selectedPlan.productID
        Task { [purchases] in
            do {
                switch try await purchases.purchase(productID) {
                case .success:
                    // Stay on the paywall: the success card is the receipt the
                    // user sees, and its dismissal walks back to the shelf.
                    // (The Memory screen this used to open showed demo notes —
                    // cross-page memory is not a v1 feature.)
                    self.purchaseState = .succeeded
                case .pending:
                    // Ask to Buy / SCA: the transaction is real, the
                    // entitlement is not. Opening Memory here is how a minor
                    // ends up with Plus nobody approved.
                    self.purchaseState = .deferred
                case .cancelled:
                    self.purchaseState = .idle
                }
            } catch {
                self.purchaseState = .failed(Self.purchaseFailure)
            }
        }
    }

    /// A vial pack, by product id. The credits land in the SERVER's wallet when
    /// the transaction verifies and the proxy accepts it — never here. This was
    /// once `credits += pack` behind a button labelled with a price.
    func buyVials(_ productID: String) {
        guard ProductID.consumables.contains(productID) else {
            purchaseState = .failed(Self.purchaseFailure)
            return
        }
        purchaseState = .purchasing
        Task { [purchases] in
            do {
                switch try await purchases.purchase(productID) {
                case .success:
                    self.purchaseState = .succeeded
                    await self.refreshWallet()
                case .pending: self.purchaseState = .deferred
                case .cancelled: self.purchaseState = .idle
                }
            } catch CommerceError.deliveryPending {
                // Paid, but the wallet has not been credited yet. The
                // transaction stays open, so StoreKit redelivers it — say so
                // honestly rather than claiming a failure that lost the money.
                self.purchaseState = .failed(Self.deliveryPending)
            } catch {
                self.purchaseState = .failed(Self.purchaseFailure)
            }
        }
    }

    /// "Restore a binding." App Review requires a working restore on any
    /// auto-renewable subscription, and it is the only way back for a user who
    /// reinstalled or changed device.
    func restorePurchases() {
        purchaseState = .purchasing
        Task { [purchases] in
            do {
                try await purchases.restore()
                self.purchaseState = self.bound ? .succeeded : .idle
            } catch {
                self.purchaseState = .failed(Self.restoreFailure)
            }
        }
    }

    /// What the shop shows on the shelf. Nil while the wallet is still being
    /// read — the room says "counting" rather than "none".
    var vialBalance: Int? { wallet?.available }
    var freeClipsRemaining: Int? { wallet?.freeClipsRemaining }

    // MARK: - Reaching the Vials

    /// Where the shop was opened from. Closing it returns there rather than
    /// dumping the reader on the shelf — someone who stepped out of the Drawer
    /// to look at the vials means to come back to the Drawer.
    private(set) var vialsReturn: AppScreen = .shelf

    func openVials(from origin: AppScreen) {
        vialsReturn = origin
        go(.wallet)
    }

    func closeVials() {
        go(vialsReturn)
    }

    func toggleShelf(book: Book) {
        if hiddenBooks.contains(book.id) {
            hiddenBooks.remove(book.id)
        } else {
            hiddenBooks.insert(book.id)
        }
    }
}

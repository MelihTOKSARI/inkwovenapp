import SwiftUI
import InkCore
import InkMoney

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

    // Commerce. Entitlement is never stored here — see `bound`.
    var credits: Int {
        didSet { defaults.set(credits, forKey: "ink.credits") }
    }
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
        /// Fallback only — `AppModel.displayPrice(for:fallback:)` prefers the
        /// storefront's own string. The period always rides with the price;
        /// a bare number on a renewing plan is a 3.1.2 rejection.
        var price: String { self == .weekly ? "$4.99 / week" : "$9.99 / month" }
        var label: String { self == .weekly ? "seven nights" : "one moon" }
    }

    enum ReplyLength: String, CaseIterable {
        case terse = "Terse", measured = "Measured", full = "Full"
    }

    init(
        defaults: UserDefaults = .standard,
        purchases: any PurchaseServicing = LiveCommerce.purchases
    ) {
        self.defaults = defaults
        self.purchases = purchases
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
        // One moving-picture credit is gifted at the door.
        credits = defaults.object(forKey: "ink.credits") as? Int ?? 1
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
        signedName = defaults.string(forKey: "ink.signedName") ?? ""
        signatureData = defaults.data(forKey: "ink.signature")
        // The old forgeable entitlement flag: remove it so nothing can revive
        // it, and so a device carrying `ink.bound = YES` loses it on this run.
        defaults.removeObject(forKey: "ink.bound")
        observeCommerce()
    }

    // MARK: - Commerce

    private let purchases: any PurchaseServicing
    private var entitlementTask: Task<Void, Never>?
    private var grantTask: Task<Void, Never>?

    private static let purchaseFailure = "The seal would not take. Nothing was charged."
    private static let restoreFailure = "No binding was found for this hand."

    private func observeCommerce() {
        entitlementTask = Task { [purchases] in
            // Armed before `start()` so the reconcile it performs is seen.
            for await snapshot in purchases.snapshots() {
                self.tier = snapshot.tier
            }
        }
        grantTask = Task { [purchases] in
            // Credits are added here and nowhere else: only a verified
            // consumable transaction reaches this stream.
            for await amount in purchases.creditGrants() {
                self.credits += amount
            }
        }
        Task { [purchases] in
            await purchases.start()
            await self.loadStorePrices()
        }
    }

    private func loadStorePrices() async {
        let ids = [ProductID.plusWeekly, ProductID.plusMonthly] + ProductID.consumables.sorted()
        var prices: [String: String] = [:]
        for id in ids {
            if let price = await purchases.displayPrice(for: id) { prices[id] = price }
        }
        storePrices = prices
    }

    /// The storefront's own price string, falling back to the design literal
    /// only until StoreKit answers.
    func displayPrice(for productID: String, fallback: String) -> String {
        storePrices[productID] ?? fallback
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

    /// A vial pack. The count maps to its consumable SKU; the credits are added
    /// by the grant stream when the transaction verifies, never here — this was
    /// `credits += pack` behind a button labelled with a price.
    func buy(pack: Int) {
        guard let productID = Self.creditProductID(for: pack) else {
            purchaseState = .failed(Self.purchaseFailure)
            return
        }
        purchaseState = .purchasing
        Task { [purchases] in
            do {
                switch try await purchases.purchase(productID) {
                case .success: self.purchaseState = .succeeded
                case .pending: self.purchaseState = .deferred
                case .cancelled: self.purchaseState = .idle
                }
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

    private static func creditProductID(for pack: Int) -> String? {
        ProductID.consumables.first { ProductID.creditAmount(for: $0) == pack }
    }

    func spendMovingCredit() -> Bool {
        guard credits > 0 else { return false }
        credits -= 1
        return true
    }

    /// "If a picture fails to develop, its vial returns to you." The debit
    /// above has no reservation behind it, so this is the only refund path
    /// there is — the develop failure path must call it.
    func refundMovingCredit() {
        credits += 1
    }

    func toggleShelf(book: Book) {
        if hiddenBooks.contains(book.id) {
            hiddenBooks.remove(book.id)
        } else {
            hiddenBooks.insert(book.id)
        }
    }
}

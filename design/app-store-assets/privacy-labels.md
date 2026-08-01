# Inkwoven — App Store Connect "App Privacy" answers (v1.0)

These are the exact selections to make in App Store Connect → App Privacy. They are
derived from the shipped privacy manifest at `app/App/PrivacyInfo.xcprivacy`, which is
the source of truth: the manifest declares exactly two collected data types, no
tracking, and no tracking domains. The questionnaire answers below must match it —
a mismatch between the label and the manifest is an audit flag.

## Step 1 — "Do you or your third-party partners collect data from this app?"

**Yes.** (Handwriting snapshots and a device token leave the device — Apple counts
off-device transmission as collection even when nothing is retained for advertising.)

## Step 2 — Data types collected

Select exactly these two. Nothing else.

### 1. User Content → Other User Content

What it covers: rasterized snapshots of the user's handwriting and doodles, typed
text where typing is permitted (iPhone Oracle, keyboard fallback), and the limited
page context sent alongside them to generate a reply.

- **Collected:** Yes
- **Purposes:** App Functionality only
- **Linked to the user's identity:** No
- **Used for tracking:** No

### 2. Identifiers → User ID

What it covers: the pseudonymous device token — a random UUID minted on first launch,
held in the Keychain, and sent as the `x-ink-user` header so the proxy can rate-limit
and meter the install. It maps to no account, name, or email, because none exist.

- **Collected:** Yes
- **Purposes:** App Functionality only
- **Linked to the user's identity:** No
- **Used for tracking:** No

## Step 3 — Everything else: "Not collected"

Explicitly do **not** select any of: Contact Info (no account, no email), Health &
Fitness, Financial Info (purchases run entirely through Apple's StoreKit; the
developer never sees payment data), Location, Sensitive Info, Contacts, Browsing
History, Search History, Diagnostics, Usage Data, or Purchases. The v1 binary ships
no analytics SDK and the privacy manifest declares no such collection.

## Step 4 — Tracking

**"No, we do not use data for tracking purposes."**
Matches `NSPrivacyTracking = false` and the empty `NSPrivacyTrackingDomains` array
in the manifest. There is no ad SDK, no fingerprinting, and no data shared with
brokers.

## Resulting public label

> **Data Not Linked to You**
> - User Content (Other User Content)
> - Identifiers (User ID)

Why "not linked" is the honest answer: linking, in Apple's definition, means the
data is tied to the user's identity — an account, name, email, phone number, or a
profile built from combining data. Inkwoven has no accounts and no sign-in of any
kind; the only identifier is a random per-install UUID that cannot be resolved to a
person by us or anyone downstream. If Sign in with Apple ever ships in a later
version, both data types flip to "Linked to you" and this file must be revised (the
manifest comment says the same).

## Edge cases, answered honestly

- **IP addresses.** The proxy uses the caller's IP transiently for per-IP rate
  limiting; counters expire within about a minute and IPs are not stored in any log
  or database keyed to content. Under Apple's definition (data retained beyond what
  is needed to service the request is "collected"), this ephemeral processing does
  not require a label entry.
- **The Keeper (Face ID-locked Book).** Its pages are treated identically to every
  other Book's for labeling: the lock is device-side, so Keeper snapshots are still
  "Other User Content" when the page answers. No separate disclosure category
  applies, but the privacy policy spells it out.
- **Third-party AI providers (Google, OpenAI, fal.ai).** They receive the same two
  data types via our proxy, for App Functionality only, not linked, not tracking —
  the label already covers third-party collection, so no additional selections are
  needed, but do not answer "No" to Step 1 on the theory that "we" don't collect.

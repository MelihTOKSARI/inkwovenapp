# Inkwoven — App Store Connect submission checklist (v1.0, build 1)

This is the operator's script. **Every step below requires a human signed into App
Store Connect (and the provider dashboards) — none of it can be automated from this
repo.** Work top to bottom; later steps depend on earlier ones. The companion files
in this folder supply the exact text to paste at each step.

Fixed facts used throughout: bundle ID `com.empath.inkwoven`, version `1.0`,
build `1`, signing team `77G7KM4549` (already configured in the Xcode project),
developer account: Melih Toksari (individual).

---

## 1. Create the app record

- [ ] App Store Connect → My Apps → **+** → New App.
- [ ] Platform: iOS. Name: **Inkwoven** — if the name is taken, resolve *now*
      (the listing, subtitle, and keyword logic in `listing.md` all assume the
      name "Inkwoven" indexes; a fallback name changes the keyword line too).
- [ ] Bundle ID: select **com.empath.inkwoven** (register it in the Developer
      portal first if it isn't listed).
- [ ] SKU: `inkwoven-ios-1` (any stable string). Access: Full.

## 2. Upload the build

- [ ] In Xcode: Product → Archive the App target (Release, team 77G7KM4549 is
      already set — do not change signing settings), then Distribute → App Store
      Connect → Upload.
- [ ] Wait for processing to finish (email arrives; the privacy manifest in the
      build must clear without an ITMS-91053 mail).
- [ ] TestFlight: install this exact build on a physical iPad — it is the build
      used for the pre-submit smoke test in step 11.

## 3. Create the subscription group and products

> Full detail — exact field values, localized metadata, sandbox procedure, and the
> rejection-cause table — lives in `subscriptions.md`. The steps below are the summary.

Monetization → Subscriptions:

- [ ] Create subscription group: **Plus** (reference name; the display name shown
      to users can also be "Inkwoven Plus").
- [ ] Product 1 — exact product ID **`plus_weekly`**: auto-renewable,
      duration 1 week, price **$4.99** (USD base; accept Apple's generated
      per-territory prices). Display name: "Inkwoven Plus Weekly".
      Introductory offer: **Free trial, 3 days**, all territories.
- [ ] Product 2 — exact product ID **`plus_monthly`**: auto-renewable,
      duration 1 month, price **$9.99**. Display name: "Inkwoven Plus Monthly".
      No intro offer.
- [ ] The product IDs must match the strings above character for character — the
      shipped binary looks them up by ID; a typo means an empty paywall. They are
      **permanent** once submitted and can never be renamed or reused.
- [ ] Add the localized display name + description each product requires, or they
      stay in "Missing Metadata" and cannot be submitted.
- [ ] Create the three consumables from `credits.md` §3 — Epic J is built as of
      2026-08-02; do this once the physical-device pass and the fal budget cap
      are done (`credits.md` §1). A product for a modality that cannot execute
      is a 2.1 rejection:
      `vials_small` 3 @ $4.99 · `vials_medium` 8 @ $10.99 · `vials_large` 20 @ $24.99
- [ ] Do **not** create Bindery products — it ships as a try-on room with no SKUs.
- [ ] Enrol in the **App Store Small Business Program** (15% commission, not 30%).

## 4. Attach the subscriptions to the version

- [ ] On the 1.0 version page, in the In-App Purchases / Subscriptions section,
      attach **all five products** — both subscriptions and the three vials. First-ever subscriptions must be submitted **with** the
      app version — they cannot be approved standalone before the app is.

## 5. Paste the listing fields

From `listing.md`, into the 1.0 version page and App Information:

- [ ] Subtitle, promotional text, description, keywords — paste the fenced blocks
      exactly (the counts are pre-verified against the field limits).
- [ ] Primary category: **Lifestyle**. Secondary: **Entertainment**.
- [ ] Name and subtitle come from `listing.md` and were revised for ASO on
      2026-08-01 — paste name, subtitle and the keyword field **as a set**, never
      mix old and new, or the no-duplicate rule breaks. The name locks at first
      submission.
- [ ] Optional, free reach: add the en-GB / en-CA / en-AU locales and paste their
      distinct keyword fields from `listing.md`. Reuse the same description.
- [ ] Copyright: © 2026 Melih Toksari.
- [ ] Version string 1.0; select build 1 (uploaded in step 2).

## 6. Upload screenshots

From `design/app-store-assets/screenshots/` (produced per the design brief):

- [ ] iPad 13" set — exact **2064×2752** portrait PNG/JPEG, no alpha. This is the
      primary set; first 3 slides sell.
- [ ] iPhone 6.9" set — exact **1320×2868** portrait. Must show the real iPhone
      companion experience (Oracle + Remembered Pages), never Pencil writing.
- [ ] Apple rejects off-by-one-pixel exports — verify dimensions before upload.

## 7. Answer the two questionnaires

- [ ] App Privacy: follow `privacy-labels.md` selection by selection. Expected
      public label: **Data Not Linked to You** (User Content + Identifiers only).
- [ ] Age rating: follow `age-rating.md`. Expected outcome: **13+**. Answer the
      live questionnaire honestly if its wording has shifted; declare worst-case
      generated content, never "None" for convenience.

## 8. Host and enter the URLs

- [ ] Publish `privacy-policy.md` (this folder) at a stable public URL. The
      support address is filled in already: swareisland@gmail.com.
- [ ] Stand up a support page (a paragraph and the same contact address suffice).
- [ ] Enter the privacy policy URL (App Privacy section) and support URL (version
      page). Marketing URL is optional — leave empty if nothing exists yet.
- [ ] App Store Connect will not accept the submission with placeholder URLs; both
      must resolve publicly.

## 9. Paste the review notes

- [ ] Copy **Part A only** from `review-notes.md` into App Review Information →
      Notes. No demo account fields are needed (no sign-in exists — leave the
      demo-credentials toggle off).
- [ ] Contact info in App Review Information: Melih's real phone + email.

## 10. Pre-submit backend checks (Part B of `review-notes.md`)

- [ ] Proxy live at `https://inkwoven-proxy.fly.dev` and healthy.
- [ ] `GEMINI_API_KEY`, `OPENAI_API_KEY`, `FAL_API_KEY` set as Fly secrets.
- [ ] **`INK_ATTESTATION_MODE=anonymous` set explicitly** — production defaults to
      `required`, which would 401 every exchange for the reviewer.
- [ ] `REDIS_URL` + `DATABASE_URL` wired (durable rate limits + ledger).
- [ ] Provider budget caps set in all three consoles.

## 11. Final smoke test, then submit

- [ ] On the TestFlight build from step 2, on a physical iPad, run one real
      exchange end to end: write → rest the pen → streamed ink reply; plus one
      Artist doodle → developed image. Same day as submission.
- [ ] Sandbox-purchase both plans and tap "Restore a binding" on the paywall once.
- [ ] Submit the version (with both subscriptions attached) for review.
- [ ] Optional: request expedited review, citing a time-sensitive launch.

## After submission

- [ ] Keep the proxy up and keys funded for the entire review window — a reviewer
      hitting a dead backend is the most likely rejection.
- [ ] Watch Resolution Center daily; rejection replies land there.

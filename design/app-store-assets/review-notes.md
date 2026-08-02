# Inkwoven — App Review notes (v1.0)

Two parts. **Part A** is the text to paste into App Store Connect → version page →
"Notes" (App Review Information). **Part B** is the internal pre-submit checklist —
never paste it; complete it before pressing Submit.

---

## Part A — paste into the App Review "Notes" field

```
Thank you for reviewing Inkwoven — a handwriting notebook whose pages answer in AI-generated fiction.

GETTING STARTED
- No account, no sign-in, and no demo credentials are needed. Launch the app and everything is available.
- iPad is the primary experience. Apple Pencil is the nicest way to write, but a finger works everywhere — nothing requires a Pencil. On iPhone the app is a lighter companion (browse your pages, ask the Oracle).

THE CORE FLOW (about 90 seconds)
1. Finish the short onboarding — sign any name; ink and keyboard both work.
2. Open a Book from the shelf. The Oracle is the fastest first try.
3. Write on the page, lift the pen, wait about 3 seconds. The page absorbs the ink and a reply streams back in script. In the Artist a doodle develops into a picture instead. Replies need a network connection; pages are stored on the device.

AI DISCLOSURE
All replies are AI-generated fiction. This is disclosed before first use, on the opening onboarding page ("a spirit of ink — not a person"), and permanently in the Drawer (the settings room, reached from the shelf), which restates it and links the policy sheet with the full AI disclosure and privacy note.

THE KEEPER (locked Book)
The Keeper is the private diary Book, locked with Face ID / Touch ID and the device passcode as fallback. Open it from the shelf and authenticate at the system prompt — a "Use passcode instead" option is offered. The lock is device-side privacy for the owner.

SUBSCRIPTIONS (StoreKit 2, group "Plus")
- Two auto-renewable plans in group "Plus": plus_weekly at $4.99/week with a 3-day free trial, and plus_monthly at $9.99/month. The paywall shows both with the renewal period beside each price and states trial terms before purchase.
- Three consumables (vials_small/medium/large) buy moving-picture credits. No other purchases exist.
- Fastest path to the paywall: Shelf → Drawer → "Subscription — Bind the notebook". The paywall also appears naturally once the day's free answered pages are used up.
- Both plans purchase normally in the sandbox; the trial is on the weekly plan. Restore purchases is the "Restore a binding" link at the foot of the paywall.

MOVING PICTURES (AI-generated video)
- Video is never generated automatically. The model marks whether a reply is a scene worth animating; only then does a "make this move" control appear, and a clip is requested only if the user taps it. Nothing is generated or charged without a deliberate tap.
- Every user gets 2 free clips; after that they buy consumable "vials". A credit is reserved before generation and released automatically on failure, so nobody pays for a clip that did not arrive.
- Prompt and output both pass moderation before anything reaches the page, at the strictest threshold in the app. A flagged clip is never shown and always refunds. Styles are illustrative; no photorealistic real people.
- The Keeper is the private, Face ID-locked diary; converting one of its pages transmits it, so the app asks separate explicit consent before the first Keeper clip.
- Tapping a finished clip expands it full screen, looping; tap or swipe down to return.
- To test: in the Storyteller write two or three sentences of a scene and rest the pen — the reply will offer to move. The Tutor deliberately never offers it; a worked solution is not a scene.

SAFETY
If a user's writing indicates personal crisis, the app deliberately breaks the fiction and shows a plain care screen with real resources instead of a stylized reply — writing that expresses serious distress in any Book will route there. Image generation runs behind provider safety filters, and every Book and output type can be disabled server-side without a new binary if an issue is ever found.

NOTIFICATIONS
The app sends one optional nightly local reminder; permission is requested only after the user's first answered page, it is off if declined, and no push server or remote notification is involved.

REPORTING AI CONTENT (guideline 1.2)
- Any AI reply can be reported: touch and hold the reply text on a page — the current reply or any earlier one in the thread — and choose "Report this reply". The sheet asks for a reason, takes an optional note, states in plain words exactly what will be sent, and transmits nothing until the user taps send. Reports are stored on our server for human review and deleted after 90 days.
- Published contact information: the Drawer (settings) has a "Write to the binder" row that opens an email to our support address; the same address appears in the privacy policy.

The app's backend is a small relay service operated by us; it holds the model API keys and is live for this review — no configuration is needed on your side.
```

---

## Part B — INTERNAL pre-submit checklist (do not paste)

The last paragraph of Part A promises the reviewer a live backend. Make it true
**before** submitting, in this order:

1. **Proxy is live:** `https://inkwoven-proxy.fly.dev` deployed and healthy
   (`fly status`, `GET /health` returns ok).
2. **Model keys set** as Fly secrets: `GEMINI_API_KEY`, `OPENAI_API_KEY`,
   `FAL_API_KEY` (deployment.md §6). A missing key silently drops that Book to echo
   mode — a reviewer seeing their own words parroted back is a rejection.
3. **`INK_ATTESTATION_MODE=anonymous` is set explicitly in production.** The proxy
   defaults to `required` when `NODE_ENV=production` and the mode is unset
   (`app/proxy/src/attest.js`), and App Attest verification is not implemented in
   v1 — an unset mode means every exchange 401s and the app looks broken to the
   reviewer.
4. **Durable stores wired:** `REDIS_URL` + `DATABASE_URL` set so rate limits and
   the ledger survive restarts (deployment.md §5).
5. **One real end-to-end exchange from the actual TestFlight build** on a physical
   iPad: write → rest pen → streamed ink reply, plus one Artist image. Do this
   after steps 1–4, the same day you submit.
6. Provider budget caps set (Google AI Studio, OpenAI, fal.ai) so a review spike
   can't run a surprise bill.

Also worth knowing if the reviewer asks: the app sends a speculative snapshot
upload about 2 seconds after the pen rests (cancelled if writing resumes) so the
committed reply starts faster; it is disclosed in the privacy policy.

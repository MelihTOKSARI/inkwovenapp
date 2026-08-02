# Inkwoven × RevenueCat Shipaton 2026 — Strategy

**Date:** 2026-08-02 · **Sources:** revenuecat-shipaton-2026.devpost.com, shipaton.com/ship-kit, vision.md, prd.md v3, tasks.md, riddle-diary-concept.md

---

## 1. The one rule that decides everything

> "The first public version of your app must be released between **August 1 and September 30, 2026**."

Inkwoven has **not** launched yet — so you qualify, and the July slip turned out to be a gift. Two implications:

1. **Do not rush-release anything before the app is judge-ready** — there is no second first-release.
2. **Launch as early as possible inside the window.** The Grand Prize ($100k) is judged on *traction and growth momentum with evidence of post-launch effort*. Every day between launch and Sep 30 is data. Launching ~Aug 17 gives you 6 weeks of curve; launching Sep 20 gives you 10 days.

Other hard requirements — all already in your architecture:

| Requirement | Inkwoven status |
|---|---|
| RevenueCat SDK powering ≥1 IAP | ✅ Core plan (task A4: sub + credit packs + Bindery) |
| Free trial or promo code for judges | ✅ 7-day trial on annual; also generate App Store promo codes + RC promotional entitlements |
| Demo video ≤2 min | To make (see §5) |
| Store URL, 1024² icon, 1179×2556 screenshots (no device frame) | Listing copy done (app-store-listing.md); screenshots pending (H6) |

Check the excluded-countries list in the official rules once to confirm Türkiye eligibility (standard Devpost exclusions are sanctions countries + Quebec/Brazil-type cases).

---

## 2. Prize targeting — pick 3 + the umbrella

$490k+ pool, eight categories, $15k each for category 1st. Fit ranking for Inkwoven:

| Priority | Award | Why Inkwoven fits | What it costs you |
|---|---|---|---|
| **1** | **HAMM** (strategic use of RevenueCat for revenue) | Textbook entry: subscription + **consumable video credits** (real unit cost, never bundled) + **zero-AI-cost content IAP** (Bindery) + in-fiction paywall + server-tunable soft caps. Few entrants will have 3 monetization layers with a rationale. | A written monetization narrative + RC dashboard evidence. ~Free. |
| **2** | **Design Award** (innovation + aesthetics, explicitly separate from business results) | The entire product is an in-fiction UI: ink absorption, streamed cursive, darkroom image development, no-keyboard onboarding, marginalia-only status, occlusion rule. Nothing else at this hackathon will look like it. | Zero — it's the existing spec. Polish H4 (haptics/sound). |
| **3** | **#BuildInPublic** (quality of public dev narrative) | You're building Aug–Sep anyway, and the product produces inherently viral clips (page drinks ink → answers). | Daily 30-min posting discipline starting **now**. |
| Umbrella | **Grand Prize** (traction + momentum) | The Riddle press wave (TechRadar, Android Authority, Notebookcheck covered the reMarkable hack in July) is live and unconsumed — you are the "consumer version anyone can install" follow-up story. | Press pitches + UGC push + early launch. |

**Skip:** Best Game (Game Master is one Book, not the product's identity — don't dilute), Peace Prize (no honest angle), Catvertising (requires RevenueCat Ads; ads inside the premium fiction would damage the Design/HAMM story — not worth it).

---

## 3. Ship Kit → mapped to your actual backlog

Perks unlock by milestone and arrive by email automatically. Sequence matters: **register + create the RC project + make a sandbox test purchase in week 1** to unlock three perk waves early.

### Use these (direct hits on open tasks)

| Perk | Unlock | Maps to |
|---|---|---|
| **Codemagic** 500 build min/mo | Register | CI (task A1) |
| **OneSignal** Growth free 3 mo | Register | Notification ritual + quiet hours (H2) |
| **Tenjin** Plan S free 3 mo ($600) | Register | Attribution + funnel analytics (A3) |
| **Sentry** $100 credits | First test purchase | Crash/error monitoring, app + proxy |
| **OpenRouter** $10 | Register | Model-routing experiments / eval harness (C1, C7) |
| **Mobbin** 3 mo free | RC project created | Design reference library for Claude Design screens |
| **AppScreens** 50% off | First test purchase | Store screenshots (H6) |
| **AppTweak / AppFollow** 50% off | First store API call | Track the keyword sets already written in app-store-listing.md (incl. en-GB/CA/AU variants) |
| **Noise** $1,000 UGC matching credits | Register | **Biggest marketing perk for you** — UGC creators filming the ink moment (§4) |
| **Asapty** 30-day trial + ASA specialist | First test purchase | Apple Search Ads *keyword research only* — PRD rule stands: no paid spend until organic CAC/LTV exists |

### Note for later (post-hackathon)

- **Paddle** — no fees on first $100k: web sales of credit packs/gift notebooks someday.
- **Stripe $250** — a web landing page / waitlist if you want one for press.
- Skip: Replit, JetBrains Junie, Argent, Bitrig, Layers, Lance (you build with Claude Code; don't switch tools mid-sprint for a discount).

---

## 4. Marketing plan (Aug 2 → Sep 30)

**Hook (decided in riddle-diary-concept.md):** lead with **"the diary that writes back"**; "paper that answers" stays the tagline. Zero WB-trademarked words anywhere user-facing — let journalists make the comparison.

1. **Build-in-public track (starts today, pre-launch).** Daily short clip or note on X + TikTok/Reels: cursive spike, absorption animation, a Book answering, latency graphs, RC paywall screenshots. Weekly devlog thread + Devpost project updates. Openly share revenue numbers post-launch (RC dashboard screenshots) — this is simultaneously your #BuildInPublic entry *and* HAMM evidence.
2. **Press track (launch week).** Pitch the exact outlets that covered the Riddle repo in July — TechRadar, Android Authority, Notebookcheck, Adafruit — with the follow-up story: *"the viral reMarkable diary hack, reborn as a polished iPad app anyone can install."* Plus the App Store featuring pitch (H6): Pencil-native PencilKit showcase is editorial catnip.
3. **UGC track (launch +1 week).** Spend the Noise $1,000 matching credits on creators in journaling / cozy-gaming / stationery niches: "I wrote to my diary and it wrote back." The product moment is the ad; brief creators to film the page, not talk to camera.
4. **Drop cadence (already planned).** Per-Book videos weekly — each is a build-in-public post, a press hook, and a re-engagement event. Halloween grimoire teaser in late Sep lands right before judging.

---

## 5. Timeline

| When | Do |
|---|---|
| **This week (Aug 3–9)** | Register on Devpost + Ship Kit form → perk wave 1. Create RC project → Mobbin. First sandbox purchase as soon as paywall compiles → wave 3. Start posting publicly day 1. Finish engine epics. |
| **Aug 10–16** | Books + monetization + safety complete; TestFlight; submit to App Review with expedited request; screenshots via AppScreens. |
| **~Aug 17–20** | **Launch.** Press pitches out same day. UGC brief to Noise. |
| **Aug 20 – Sep 25** | Weekly Book drops; track ASO (AppTweak); collect traction: downloads, trial starts, conversion, NSM. Post the curve publicly. |
| **Sep 25–29** | Cut the 2-min judge video: 0–20s the gasp (write → ink drunk → answer flows), then 3 Books fast, monetization beat, traction beat. Generate promo codes. Write HAMM + Design narratives into the Devpost description. **Submit Sep 28–29, never Sep 30.** |

---

## 6. Product changes for Shipaton: almost none

The product is already right. Only additions:

- **RC promo codes / promotional entitlements** for judges (unlock Plus + a credit pack so they see video magic without paying).
- **RC Paywalls or Experiments** for one visible A/B (e.g., trial length) — cheap, and it upgrades the HAMM story from "uses RevenueCat" to "runs revenue experiments on it."
- Keep the kill-switch flags: if video moderation risk threatens App Review timing, ship with moving pictures flag-off and enable post-approval — **the launch date matters more than any single modality.**

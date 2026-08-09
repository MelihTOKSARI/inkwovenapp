# Video in Plus — "Four Stirrings"

**Status:** Proposal · **Date:** 2026-08-09 · **Decision owner:** Melih
**Headline:** 4 moving pictures per rolling 7 days included in Plus; monthly $9.99 → $12.99.

> **Provenance.** The repo-side numbers in §7 were read directly from this codebase and are
> confirmed. The model prices in §4 come from web research and are **page-verified, not
> invoice-verified** — no clip has been generated on the proposed route. §8 risk 2 is the
> guardrail for that. Everything here is a proposal; no code has been changed.

---

## 1. The one line per tier

**Free** — "Five moments a day, and three of your pictures come alive."

**Plus** — "Ink all day, ten pictures a day, and four of them come alive every week."

The word *unlimited* appears nowhere — not in the paywall, the listing, or the subscription
metadata. Every claim is a number and every number is the one the server enforces. This is the
same discipline as audit M-20, where a benefit line was narrowed because "freely, page after
page" over-promised.

---

## 2. Tiers

| | **Free** | **Plus** — $4.99/wk (3-day trial) or **$12.99/mo** |
|---|---|---|
| **Ink replies** | 5 moments/day, **shared** with images | No count shown. Anti-abuse ceiling 60/day; 25/day on heavy books |
| **Images** | Spend from the same 5/day pool | **10/day flat, hard stop.** The 8/day soft cap and the 60s→1h cooldown ladder are **deleted** |
| **Video** | **3 lifetime**, granted on the first eligible reply after they've developed an image. Plus **1/month** for anyone who wrote on 12+ distinct days | **4 per rolling 168 hours.** Provable max **20 per 31 days.** Full allowance inside the trial |
| **Crossover** | A clip never spends a moment | A clip never spends an image slot |
| **Vials** | Purchasable | Purchasable; spent only after the weekly allowance is gone |

**Why the 20-clip max is provable, not estimated.** A clip is allowed only if fewer than 4
settled clips fall in the preceding 168h, so `c(i) − c(i−4) > 168` for all i. A 21st clip needs
`c21 − c1 > 5 × 168 = 840h`, against 744h in a 31-day month. **Max 20 clips = $4.00/subscriber
/month of video cost, unconditionally.**

Rolling, not calendar: a 31-day month touches up to six calendar-week segments, so "4 per
calendar week" would permit **24** clips and create a reset-day burst-then-cancel arbitrage.

---

## 3. The video spec

| | Decision | Why |
|---|---|---|
| **Duration** | **4s generated, 8s perceived** | 4s is the floor on both candidate routes. Live Photo is 3.0s; cinemagraph practice is 2–5s. 6s is +50% on the whole video line for motion the loop convention says isn't needed |
| **Route** | Plan at `fal-ai/pixverse/v6/image-to-video`; bake off against `fal-ai/veo3.1/lite/image-to-video` | All arithmetic is sized at PixVerse. If Veo wins, bank the $0.064/clip as margin — never spend it on a bigger allowance |
| **Retire Kling** | `kling-video/v3/standard` at $0.084/s is out | 3.4× the planning route for an ambient page loop |
| **Resolution** | **720p, one tier** | The in-page frame is 420pt ≈ 10.3° at 45cm — 720p is ~125 ppd there against 60ppd for 20/20 vision. Only the full-screen tap bites; fix with MetalFX spatial upscaling on device (free), not 1080p (+100%) |
| **Aspect / fps / codec** | 16:9 · 24fps · HEVC ~2 Mbps | Player already does `.resizeAspectFill` into 16:9 — zero crop loss. 4s ≈ 1.0MB; baked 8s loop ≈ 2.0MB |
| **Audio** | **Off, permanently, every tier** | +33% on PixVerse, +50% on Kling — and it's the right call anyway: the clip autoplays in a small frame while the user is mid-sentence with a Pencil. For atmosphere, bundle a curated local ambient bed at $0.00 marginal |
| **i2v, always** | Image-to-video | Same $/s, so this is fiction not cost: the gasp is that *the picture the page just developed* started breathing. t2v makes a different picture and destroys that |
| **Looping** | **Server-baked ping-pong** (reverse + concat, dupe endpoint frames dropped) | Doubles perceived length to 8s for $0.00 and makes the seam exact by construction. Do NOT buy a seamless loop from the model — identical first/last frames make current models generate almost no motion |
| **Prompt constraint** | **Reversible verbs only** — flame flickers, cloth stirs, water shimmers, chest breathes. Directional verbs banned | This is what turns ping-pong from a trick into a guarantee. `image-live-video-report.md:31` currently says **"smoke drifts"** — directional, would read as played-backwards on the first clip anyone shares. Fix that line first |
| **Bake location** | Dedicated worker ≥1GB, not the 256MB proxy VM | ffmpeg `reverse` buffers every decoded frame: 96 frames at 720p ≈ 133MB in yuv420p before encoder and Node |

---

## 4. Unit costs

Assumes the four routing repins in §7 ship first — they're the plan, not tuning.

| Item | Arithmetic | Cost |
|---|---|---|
| Ink reply, default books | 1,910 in × $0.25/1M + 250 out × $1.50/1M + verdict $0.00019 | **$0.00104** |
| Ink reply, free tier (lean) | 1,194 in + 100 out + verdict | **$0.00064** |
| Ink reply, heavy books (gpt-5-mini) | 2,537 in × $0.25/1M + 700 out × $2.00/1M + verdict | **$0.00222** |
| *heavy books at today's pin (gpt-5.4-mini)* | 2,537 × $0.75/1M + 700 × $4.50/1M | *$0.00524* |
| Image, default (z-image-turbo, 1MP) | 1MP × $0.005 | **$0.005** |
| Image, Artist (flux-2/**flash**/edit) | (1 + 1) MP × $0.005 | **$0.010** |
| *Artist at today's pin (flux-2/edit)* | (1 + 1) MP × $0.012 | *$0.024* |
| **Clip — planning price** | $0.045/s × 4 = $0.180 × 1.08 retry + $0.0005 judge + $0.0055 bake | **$0.20** |
| Clip — if Veo wins the bake-off | $0.03/s × 4 × 1.08 + $0.006 | $0.136 |
| Clip — stress (unresolved PixVerse rate conflict) | $0.050/s × 4 × 1.08 + $0.006 | $0.222 |
| Clip — **today** (kling v3, 5s) | $0.084/s × 5 × 1.08 | $0.454 |

**The whole plan rests on $0.454 → $0.20, a 56% cut.** At today's clip price a 4/week allowance
costs $9.08/month against $11.04 net and the answer would be no.

---

## 5. Margin

Net of Apple's 15%: monthly **$11.0415**; weekly **$18.38/month-equivalent**.

| User | Text | Images | Video | **Cost** | **$12.99/mo** | **$4.99/wk** |
|---|---|---|---|---|---|---|
| Typical — 300 exch, 75 img, 2 clips/wk | $0.312 | $0.488 | $1.734 | **$2.53** | **77.1%** | 86.2% |
| Heavy — 900 exch, 240 img, 3 clips/wk | $0.936 | $1.560 | $2.600 | **$5.10** | **53.8%** | 72.3% |
| Modest writer, full allowance | $0.312 | $0.488 | $4.000 | **$4.80** | **56.5%** | 73.9% |
| **Worst case, default books** — every ceiling pinned 31 days | $1.934 | $3.100 | $4.000 | **$9.03** | **18.2%** | 50.8% |
| **Worst case, heavy books** | $2.849 | $3.100 | $4.000 | **$9.95** | **9.9%** | 45.9% |
| Stress — heavy worst case at $0.222/clip | $2.849 | $3.100 | $4.440 | **$10.39** | **5.9%** | 43.5% |
| Blended portfolio | | | | **$2.48** | **77.6%** | 86.5% |
| Trial abandoner (bounded, once per Apple ID) | $0.037 | $0.059 | $0.800 | **−$0.90** | — | — |

**The worst case does not lose money** — it clears by $2.01/month on default books, $1.09 on
heavy books, and stays positive at the stressed clip price. Every term is a server ceiling
times a unit cost; the 20-clip video term is provable.

**At $9.99 the same worst case loses $0.54 (default) and $1.46 (heavy).** That is the entire
price argument.

**Trial:** at 25% trial-to-paid, blended acquisition = $2.69/converted subscriber, recovered in
month one. Give the full four clips in the trial — the moving picture is the ad.

**Free funnel:** 3 seeds × $0.20 = $0.60 per free user reaching video, vs $0.914 today. 50%
more clips for 34% less money, purely from the model swap.

**Vials — push the saving into pack size, never price:**

| Pack | Price | Net | Grant | Cost | Margin |
|---|---|---|---|---|---|
| small | $4.99 | $4.24 | **5** (was 3) | $1.00 | 76.4% |
| medium | $10.99 | $9.34 | **14** (was 8) | $2.80 | 70.0% |
| large | $24.99 | $21.24 | **36** (was 20) | $7.20 | 66.1% |

---

## 6. Past the allowance — hard stop

No cooldown ladder, no slow queue, no degraded lane. Every surviving operator at $10–20/month
hard-stops; every relaxed-unlimited offer sits at 3–20× this price and they're retreating
(Runway killed Unlimited June 2026). A cooldown ladder is also unbounded on a $0.20 unit —
24 hourly clips is $4.80/day.

The offer still appears on a qualifying reply, rendered asleep. Seeing it teaches the rhythm.

- **Plus, spent:** *"The page has stirred four times this week. It will stir again on Thursday night."* Server returns the exact reopening moment; the client names the night, never a count. Below: *"A vial of ink stirs it sooner."*
- **Plus, image ceiling:** *"The bath must rest until morning."* — the existing fiction, with no waiting ladder in front of it.
- **Free, seeds spent:** *"The Book has shown you what it can do. It will do it as often as you keep it."* — which is the paywall.
- **Global ceiling (fails closed):** *"The ink must rest."* — never a system error.

Spend order becomes **allowance slot → free seed/gift → credit wallet → 402**, so a subscriber
can never silently burn a purchased vial while an included slot is open.

---

## 7. What changes

`[env]` no deploy · `[proxy]` proxy deploy · `[app]` App Store release · `[ASC]` operator only

### Prerequisites — ship first, own commit, before any video work

| Change | Tier | Why |
|---|---|---|
| Set an explicit **thinking budget** on the Gemini call (`models.js:269` passes only `maxOutputTokens`) | `[proxy]` | Gemini 3.x bills thinking as output. Unbudgeted the exchange is $0.00234 not $0.00104, and the worst case flips to a loss |
| Repin default ink **gemini-3.5-flash-lite → 3.1-flash-lite** ($0.30/$2.50 → $0.25/$1.50) | `[proxy]` | The shipping pin is the most expensive Flash-Lite tier; the PRD costed the cheapest |
| Repin heavy books **gpt-5.4-mini → gpt-5-mini** ($0.75/$4.50 → $0.25/$2.00) | `[proxy]` | Undocumented drift; at 5.4-mini the heavy worst case loses $1.25/month |
| Repin Artist **flux-2/edit → flux-2/flash/edit** ($0.024 → $0.010) | `[proxy]` | 58% cut, sub-second, better suited to the develop animation |
| Send an explicit **`image_size` (1MP)** to fal (`models.js:398` sends none) | `[proxy]` | Billed megapixels are currently a provider default that can change without notice |
| **`plusImageDailyCeiling` 40 → 10** | `[proxy]` | **Confirmed at `config.js:103`.** 40/day at flux-2/edit is 40 × 31 × $0.024 = **$29.76/month against $8.49 net — a live insolvency in shipped config, with no video involved.** This one edit recovers more exposure than the entire allowance costs |
| **`plusExchangeDailyCeiling` 300 → 60**, + new 25/day sub-ceiling on heavy books | `[proxy]` | Confirmed at `config.js:98`. 300/day is ~10× any human hand |

### Added

| Change | Tier |
|---|---|
| Plus allowance: 4 per rolling 168h, own per-identity counter | `[proxy]` |
| **Make `/v1/video` tier-aware** — confirmed: the route (server.js:1015–1252) never calls `tierOf`; the only call is at line 615 in the exchange route. A subscriber is treated identically to a free user today | `[proxy]` |
| `allowDaily('vid:'+userID, 4)` circuit breaker — `videosPerUserPerMinute: 2` is currently the only time-window bound on clip volume anywhere | `[proxy]` |
| Free `freeClipsPerUser` **2 → 3** (`config.js:57`), granted lazily after the first developed image | `[proxy]` |
| Free: 1 gift clip/month at 12+ distinct active days | `[proxy]` |
| `freeClipMonthlyCeiling` 2,000 → 6,000, split 5,000 seeds / 1,000 gifts | `[proxy]` |
| Reversible-verb prompt constraint | `[proxy]` |
| Ping-pong bake worker (≥1GB) | infra |
| MetalFX upscale on full-screen tap | `[app]` |
| Paywall copy — the three benefit lines don't mention moving pictures at all today | `[app]` |

### Repriced

| Change | Tier |
|---|---|
| `plus_monthly` $9.99 → **$12.99**. Weekly unchanged | `[ASC]` |
| `VIAL_GRANTS` 3/8/20 → **5/14/36**. Prices unchanged — no ASC work | `[proxy]` |
| `clipSeconds` **5 → 4** (`config.js:74`); route to PixVerse; body gains `resolution`, `generate_audio: false`, `aspect_ratio` (it sends only `prompt` and `duration` today) | `[proxy]` |
| `freeClipsPerIPPerDay` 20 → 10 — raising the per-user grant raises the yield per minted identity | `[proxy]` |

### Deleted

| Change | Tier |
|---|---|
| `cooldownCurveSeconds` — the 60s/5m/15m/1h ladder, entirely. The most user-hostile mechanic in the product, and it exists to protect $0.0065 | `[proxy]` + `[app]` |
| `plusImageDailySoftCap` as a *soft* cap — becomes a flat, stated 10/day | `[proxy]` |
| The "never bundle unlimited video" rule at `credits.md:184-186` — amended with its reasoning recorded. This plan doesn't bundle unlimited video; it bundles a provable max of 20 | docs |

### Not changed
Free's 5/day shared pool. Vial prices. The weekly plan. The wallet reserve/settle/release
lifecycle. The idempotency and refund-on-failure paths in `/v1/video`, which are complete.

**The allowance must ride its own counter, never the `free_clips` ledger** — otherwise one
viral free week denies paying subscribers the thing they bought, and it arrives in fiction as
"the ink must rest" with no way to explain it.

**The allowance can go live before the binary.** The client already renders a server-granted
clip through `freeClipsRemaining` / `freeClipsOpen` as "gifted moments".

---

## 8. Risks and guardrails

1. **Thinking tokens are unmeasured and can invert every number here.** The explicit budget is a
   launch prerequisite. `geminiProvider` already accumulates `candidatesTokenCount` — read one
   real week before scheduling the price change. Alert: mean output > 300 tokens/exchange.
2. **The clip price is page-verified, not invoice-verified.** Two research strands disagree on
   PixVerse's rate ($0.045 vs $0.050/s) and nobody has generated a clip. Sized at $0.20, holds
   to $0.222. Alert when logged mean `unit_cost` > $0.21. Kill switch: `clipSeconds` 4 → 3, a
   linear −25% with no promise change.
3. **Offer-rate risk — the likeliest way this fails as marketing while succeeding as a
   spreadsheet.** Video is offered, not requested: the affordance needs `replyText.length >= 80`
   and a MOVE verdict. If MOVE fires rarely, subscribers pay for four stirrings and see two.
   Instrument `video_offered` / eligible replies from day one; alert below 40%; lever is
   `minConvertibleReplyChars` 80 → 60.
4. **4 seconds rests entirely on ping-pong reading as real.** Ship the reversible-verb
   constraint *with* the model swap, fix `image-live-video-report.md:31` first, then judge a
   20-prompt blind bake-off at 420pt in the real frame before announcing anything.
5. **Free-clip farming.** Clips key to `x-ink-user`; in anonymous attestation that token *is* the
   identity, so rotating it mints seeds. Confirm App Attest is actually enforced in production
   before the monthly gift ships. Seeds first, gift staged a week later.
6. **ffmpeg reverse will OOM the 256MB proxy VM.** Dedicated worker, budgeted at $0.0055/clip.
7. **Credit attach will fall** — roughly $560/month of net at 12k MAU if it halves. If attach is
   below 8% by week 8, cut the allowance 4 → 3, never cut vial prices.
8. **No rollover will generate support mail.** If it shows in cancellation reasons, let up to 2
   unused stirrings carry one week forward — it doesn't move the 20-clip monthly max at all.
9. **Revised analytics guardrail.** The existing spec alerts on 30% of *gross* $9.99, a price
   that's changing. Restate against net, per plan: alert p95 > 25% of net ($2.76/mo, $1.06/wk);
   page at p99 > 50%. Add: mean clips/Plus user/month > 14 (of 20) means underpriced — fix on
   the *next* cohort, never a quiet cut to the current one.
10. **The release valve is always the spec, never the number.** The promise is a trust commitment
    and an App Store release; route, resolution and duration are a proxy deploy. When
    consumption exceeds plan, cut seconds or resolution — never the clip count on a cohort that
    was sold it.

---

## 9. Three decisions for you

1. **$12.99 with 4/week, or hold $9.99 with 2/week?** Both are solvent — $9.99 with a 2-per-168h
   allowance caps at 10 clips/month, worst case 17.2%. **Recommendation: $12.99 and 4/week.** A
   30% rise for the modality the app is built around is the easiest price change a founder ever
   gets, and far easier now than walking an allowance back later.
2. **If the bake-off rejects PixVerse, Veo Lite *and* LTX on the ink-and-parchment look and the
   clip has to stay Kling-class at $0.46 — ship 1/week, or keep video credits-only?**
   **Recommendation: take the allowance cut.** A smaller number still converts; a reversed price
   move doesn't.
3. **Is $1,200/month of free-tier video the acquisition budget you want?** ~18% of subscription
   revenue at 12k MAU, against materially worse CAC from Search Ads. If the appetite is smaller,
   raise the *gift* gate from 12 to 16 active days — never cut the seeds, which are the
   conversion mechanic.

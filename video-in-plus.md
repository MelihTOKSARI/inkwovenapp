# Video in Plus — "Three Stirrings"

**Status:** Proposal v2 — **prices accepted 2026-08-10**, mechanics still proposed
**Date:** 2026-08-09 · **Decision owner:** Melih

> **Partly accepted 2026-08-10.** `VIAL_GRANTS` 3/8/20 → **4/11/28** is landed in code,
> the StoreKit catalog and App Store Connect — the three consumables are live there at
> unchanged prices. The grades are sized on the $0.249 clip the PixVerse repin buys; on
> the outgoing Kling route they still clear 57 / 47 / 40%, so shipping them ahead of the
> repin is safe but the repin is owed.
>
> **`plus_monthly` stays at $9.99 for v1** — deferred, not rejected. App Store Connect
> offers *Plan Subscription Price Change* only once a subscription is approved, so
> $12.99 cannot be entered pre-launch. It is also unnecessary until the allowance below
> ships: with no bundled video, $9.99 is solvent. Raise it when §3 lands, grandfathering
> existing subscribers.
>
> **Everything else here — the three stirrings, joining, the split free pool, the deleted
> cooldown ladder, the PixVerse repin and the §8 prerequisites — remains an unshipped
> proposal.**
**Headline:** 3 stirrings per rolling 7 days in Plus, 5 seconds each, joinable. Monthly $9.99 → $12.99.

> **Provenance.** The repo-side numbers in §8 were read directly from this codebase and are
> confirmed. The model prices in §5 come from web research and are **page-verified, not
> invoice-verified** — no clip has been generated on the proposed route. §9 risk 2 is the
> guardrail. Everything here is a proposal; no code has been changed.

**Changed in v2:** clips are 5s (was 4s), which costs 25% more per clip and forces the weekly
allowance from 4 down to 3. Plus subscribers can **join** clips into one longer picture, one
stirring per 5-second segment. Text limits go **up**, image limits go **down** — the free
tier's shared pool is split so an image no longer costs the same as an ink reply. Free gets
**3 clips total**: 2 lifetime + 1 monthly gift at 12+ writing days.

---

## 1. Why text goes up and images go down

The three modalities are not close to each other in cost, and the current scheme prices them as
if they were:

| | Cost | Relative to an ink reply |
|---|---|---|
| Ink reply | $0.00104 | **1×** |
| Image (blended) | $0.0065 | **6.3×** |
| Image (Artist, worst) | $0.010 | **9.6×** |
| Clip, 5s | $0.249 | **239×** |

Today a free user spends the *same* moment on either an ink reply or an image, so the cheap
thing is rationed at the price of the expensive one. Text is close enough to free that metering
it tightly buys almost nothing and costs the product its whole feel — Inkwoven is a notebook,
and a notebook that stops taking writing is broken. Images are the term that quietly
accumulates. So: **split the free pool, double the free text, cut the free images; raise the
Plus text ceiling and cut the Plus image cap.**

---

## 2. The one line per tier

**Free** — "Ten pages a day, two of them pictures, and three that come alive."

**Plus** — "Write all day, six pictures a day, and three of them stir every week."

*Unlimited* appears nowhere — not in the paywall, the listing, or the subscription metadata.
Every claim is a number and every number is the one the server enforces. Same discipline as
audit M-20, where a benefit line was narrowed because "freely, page after page" over-promised.

---

## 3. Tiers

| | **Free** | **Plus** — $4.99/wk (3-day trial) or **$12.99/mo** |
|---|---|---|
| **Ink replies** | **10/day** (was 5, shared) | No count shown. Anti-abuse ceiling **100/day**; **20/day** sub-ceiling on heavy books |
| **Images** | **2/day**, metered separately (was up to 5 out of the shared pool) | **6/day** flat, hard stop. The 8/day soft cap and the 60s→1h cooldown ladder are **deleted** |
| **Video** | **3 total: 2 lifetime + 1 per month** at 12+ distinct writing days. 5s each. No joining | **3 stirrings per rolling 168 hours.** Provable max **15 per 31 days.** Full allowance inside the trial |
| **Joining** | — | **Yes.** Up to 3 segments into one picture; **one stirring per 5-second segment** |
| **Crossover** | Text and image no longer share a pool; a clip spends neither | A clip never spends an image slot |
| **Vials** | Purchasable | Purchasable; spent only after the weekly allowance is gone |

**Why 3 and not 4.** With N stirrings per rolling 168h, a clip is allowed only if fewer than N
settled clips fall in the preceding 168h, so `c(i) − c(i−N) > 168` and therefore
`168 × floor((M−1)/N) < 744` for a 31-day month → **M ≤ 5N**. At N=4 that is 20 clips; at 5s and
$0.249 that is $4.98/month of video alone, and the heavy-book worst case lands at $10.79 against
$11.04 of net revenue — a 2.3% margin, which is not a margin. At **N=3 the max is 15 clips =
$3.74**, and the worst case clears by $1.49. The 4s→5s decision is what spent the fourth
stirring; it did not spend it on nothing.

Rolling, not calendar: a 31-day month touches up to six calendar-week segments, so "3 per
calendar week" would permit 18 and create a reset-day burst-then-cancel arbitrage.

---

## 4. The video spec

| | Decision | Why |
|---|---|---|
| **Duration** | **5 seconds per stirring** | Founder call. Above the Live Photo (3.0s) and cinemagraph (2–5s) conventions, and the natural unit for joining |
| **Joining** | **Up to 3 segments, one stirring each** | The cost is linear in seconds, so the price is too. A 2-segment join is $0.494 against $0.498 for two singles — **joining is cost-neutral**, which is why one-stirring-per-segment is the honest rule rather than a penalty |
| **Single vs joined playback** | Single: **ping-pong loop**, 10s perceived. Joined: **plays through, crossfade back to start** | Ping-pong doubles a single for $0.00 and makes the seam exact. It cannot apply to a join — reversing a sequence plays the story backwards. So a single buys 10s of *loop*; a join buys 10s of *story*. Paying double for narrative rather than length is a proposition a user can feel |
| **Route** | Plan at `fal-ai/pixverse/v6/image-to-video`; bake off against `fal-ai/veo3.1/lite/image-to-video` | All arithmetic sized at PixVerse. If Veo wins, bank the saving as margin — never spend it on a bigger allowance |
| **Retire Kling** | `kling-video/v3/standard` at $0.084/s is out | 1.9× the planning route at the same 5 seconds |
| **Resolution** | **720p, one tier** | The in-page frame is 420pt ≈ 10.3° at 45cm — 720p is ~125 ppd there against 60ppd for 20/20. Only the full-screen tap bites; fix with MetalFX spatial upscaling on device (free), not 1080p (+100%) |
| **Aspect / fps / codec** | 16:9 · 24fps · HEVC ~2 Mbps | Player already does `.resizeAspectFill` into 16:9 — zero crop loss. 5s ≈ 1.25MB; baked 10s ≈ 2.5MB |
| **Audio** | **Off, permanently, every tier** | +33% on PixVerse, +50% on Kling — and right anyway: the clip autoplays in a small frame while the user is mid-sentence with a Pencil. For atmosphere, bundle a curated local ambient bed at $0.00 marginal |
| **i2v, always** | Image-to-video | Same $/s, so this is fiction not cost: the gasp is that *the picture the page just developed* started breathing |
| **Prompt constraint** | **Singles: reversible verbs only** (flame flickers, cloth stirs, water shimmers). **Joins: directional allowed**, since a join never reverses | This is what makes ping-pong a guarantee rather than a trick. `image-live-video-report.md:31` currently says **"smoke drifts"** — directional, and it would read as played-backwards on the first single anyone shares. Fix that line first |
| **Bake location** | Dedicated worker ≥1GB, not the 256MB proxy VM | ffmpeg `reverse` buffers every decoded frame: 120 frames at 720p ≈ 166MB in yuv420p before encoder and Node. A 3-segment join concat is larger still |

---

## 5. Unit costs

Assumes the routing repins in §8 ship first — they are the plan, not tuning.

| Item | Arithmetic | Cost |
|---|---|---|
| Ink reply, default books | 1,910 in × $0.25/1M + 250 out × $1.50/1M + verdict $0.00019 | **$0.00104** |
| Ink reply, free tier (lean, no memory) | 1,194 in + 100 out + verdict | **$0.00064** |
| Ink reply, heavy books (gpt-5-mini) | 2,537 in × $0.25/1M + 700 out × $2.00/1M + verdict | **$0.00222** |
| *heavy books at today's pin (gpt-5.4-mini)* | 2,537 × $0.75/1M + 700 × $4.50/1M | *$0.00524* |
| Image, default (z-image-turbo, 1MP) | 1MP × $0.005 | **$0.005** |
| Image, Artist (flux-2/**flash**/edit) | (1 + 1) MP × $0.005 | **$0.010** |
| *Artist at today's pin (flux-2/edit)* | (1 + 1) MP × $0.012 | *$0.024* |
| Image, blended 70/30 | 0.7 × $0.005 + 0.3 × $0.010 | **$0.0065** |
| **Stirring (5s) — planning price** | $0.045/s × 5 = $0.225; × 1.08 retry = $0.243; + $0.0005 judge + $0.0055 bake | **$0.249** |
| Stirring — if Veo wins the bake-off | $0.03/s × 5 × 1.08 + $0.006 | $0.168 |
| Stirring — stress (unresolved PixVerse rate) | $0.050/s × 5 × 1.08 + $0.006 | $0.276 |
| 2-segment join | 10s × $0.045 × 1.08 + $0.0005 + $0.008 (one larger bake) | $0.494 |
| Stirring — **today** (kling v3, 5s) | $0.084/s × 5 × 1.08 | $0.454 |

**The plan rests on $0.454 → $0.249, a 45% cut.** At today's clip price even 3/week costs
$6.81/month against $11.04 net and the answer would be no.

---

## 6. Cost by cohort — full limit vs average

Net of Apple's 15%: **monthly $11.0415** · **weekly $4.2415/week = $18.379/month-equivalent**
(4.3333 billings; at 31/7 it is $18.78, so this is the conservative reading).

### Assumptions behind "average"

| | Active days/mo | Ink/active day | Images/active day | Stirrings/mo |
|---|---|---|---|---|
| Free | 12 | 5 | 0.7 | 1 (the gift) |
| Plus | 20 | 15 | 3 | 9.67 (2/wk, one of them a 2-segment join) |

"Full limit" means every ceiling pinned every day for 31 days, all images on the Artist route
at $0.010, and the entire video allowance spent.

### Free

| | Ink | Images | Video | **Total/month** |
|---|---|---|---|---|
| **Full limit** | 310 × $0.00064 = $0.198 | 62 × $0.010 = $0.620 | 3 × $0.249 = $0.747 | **$1.565** (month one) |
| Full limit, steady state | $0.198 | $0.620 | 1 gift × $0.249 = $0.249 | **$1.067** |
| **Average** | 60 × $0.00064 = $0.038 | 8.4 × $0.0065 = $0.055 | $0.249 | **$0.342** |

Free carries no revenue, so these are acquisition spend. **Today's free tier is worse:** 5
shared moments spent entirely on images is 5 × $0.0065 × 31 = $1.008/month of text-and-image
cost, against **$0.818** under the new split ($0.198 + $0.620) — so free users get **twice the
writing for 19% less**, before video. At the 4–6% conversion target, $0.342/month average is
$6.84 of spend per converted subscriber, recovered in the first billing period on either plan.

### Weekly Plus — $4.99/week, net $4.2415

| | Ink | Images | Video | **Total** | **Margin** |
|---|---|---|---|---|---|
| **Full limit, one week** (heavy books) | 7 × $0.1276 = $0.893 | 42 × $0.010 = $0.420 | 3 × $0.249 = $0.747 | **$2.060** | **51.4%** |
| **Full limit, month-equivalent** | $3.956 | $1.860 | $3.735 | **$9.551** | **48.0%** |
| **Average, month-equivalent** | $0.312 | $0.390 | $2.408 | **$3.110** | **83.1%** |
| **3-day trial then cancel** ($0 revenue) | 3 × $0.1276 = $0.383 | 18 × $0.010 = $0.180 | 3 × $0.249 = $0.747 | **−$1.310** | bounded, once per Apple ID |

The weekly plan is the *safer* plan, not the dangerous one — $18.38/month-equivalent against the
monthly's $11.04. The exposure is the trial, and it is capped at $1.31.

### Monthly Plus — $12.99/month, net $11.0415

| | Ink | Images | Video | **Total** | **Margin** |
|---|---|---|---|---|---|
| **Full limit, default books** | 3,100 × $0.00104 = $3.224 | 186 × $0.010 = $1.860 | 15 × $0.249 = $3.735 | **$8.819** | **20.1%** |
| **Full limit, heavy books** | 620 × $0.00222 + 2,480 × $0.00104 = $3.956 | $1.860 | $3.735 | **$9.551** | **13.5%** |
| **Full limit, heavy, at the stress clip price** | $3.956 | $1.860 | 15 × $0.276 = $4.140 | **$9.956** | **9.8%** |
| **Average** | 300 × $0.00104 = $0.312 | 60 × $0.0065 = $0.390 | 9.67 × $0.249 = $2.408 | **$3.110** | **71.8%** |

**Every case is solvent, including the adversary.** The worst case clears by $1.49/month and
stays positive at the stressed clip price. Every term is a server ceiling times a unit cost, and
the 15-stirring video term is provable, not estimated.

**At $9.99 (net $8.4915) the heavy-book full-limit case loses $1.06.** Raising the text ceiling
to 100/day makes the price change *more* necessary than it was in v1, not less — $9.99 does not
survive a generous text tier at any video allowance above 2/week.

### Where the money actually goes

| | Average Plus user | Full-limit Plus user |
|---|---|---|
| Ink | $0.312 (10%) | $3.956 (41%) |
| Images | $0.390 (13%) | $1.860 (20%) |
| **Video** | **$2.408 (77%)** | **$3.735 (39%)** |

For a real subscriber, video is three-quarters of the bill and text is a rounding error. That is
the whole argument for metering video by the unit and leaving text alone.

---

## 7. Past the allowance — hard stop

No cooldown ladder, no slow queue, no degraded lane. Every surviving operator at $10–20/month
hard-stops; every relaxed-unlimited offer sits at 3–20× this price and they are retreating
(Runway killed Unlimited June 2026). A ladder is also unbounded on a $0.249 unit.

The offer still appears on a qualifying reply, rendered asleep. Seeing it teaches the rhythm.

- **Plus, spent:** *"The page has stirred three times this week. It will stir again on Thursday night."* The server returns the exact reopening moment; the client names the night, never a count. Below: *"A vial of ink stirs it sooner."*
- **Plus, joining beyond the allowance:** *"Two stirrings remain — this picture would take three."* Offer the shorter join or a vial. Never start a join that cannot finish.
- **Plus, image ceiling (6/day):** *"The bath must rest until morning."*
- **Free, three spent:** *"The Book has shown you what it can do. It will do it as often as you keep it."* — which is the paywall.
- **Free, gift earned:** *"You have kept this Book faithfully. It has one more picture in it for you."*
- **Global ceiling (fails closed):** *"The ink must rest."* — never a system error.

Spend order: **allowance slot → free seed/gift → credit wallet → 402**, so a subscriber can never
silently burn a purchased vial while an included stirring is open. A join reserves all its
segments up front and releases them together on failure.

---

## 8. What changes

`[env]` no deploy · `[proxy]` proxy deploy · `[app]` App Store release · `[ASC]` operator only

### Prerequisites — ship first, own commit, before any video work

| Change | Tier | Why |
|---|---|---|
| Explicit **thinking budget** on the Gemini call (`models.js:269` passes only `maxOutputTokens`) | `[proxy]` | Gemini 3.x bills thinking as output. Unbudgeted the exchange is $0.00234 not $0.00104 — and at a 100/day ceiling that error is worth **$7.25/month**, which flips the worst case to a loss on its own. The raised text ceiling makes this the single most important line in the plan |
| Repin default ink **gemini-3.5-flash-lite → 3.1-flash-lite** ($0.30/$2.50 → $0.25/$1.50) | `[proxy]` | The shipping pin is the most expensive Flash-Lite tier; the PRD costed the cheapest |
| Repin heavy books **gpt-5.4-mini → gpt-5-mini** ($0.75/$4.50 → $0.25/$2.00) | `[proxy]` | Undocumented drift. At 5.4-mini the heavy-book text line is $9.34/month and nothing here survives |
| Repin Artist **flux-2/edit → flux-2/flash/edit** ($0.024 → $0.010) | `[proxy]` | 58% cut, sub-second, better suited to the develop animation |
| Send an explicit **`image_size` (1MP)** to fal (`models.js:398` sends none) | `[proxy]` | Billed megapixels are currently a provider default that can change without notice |
| **`plusImageDailyCeiling` 40 → 6** | `[proxy]` | **Confirmed at `config.js:103`.** 40/day at the current flux-2/edit pin is $29.76/month against $8.49 net — **a live insolvency in shipped config, with no video involved.** This edit alone recovers more than the whole allowance costs |
| **`plusExchangeDailyCeiling` 300 → 100**, + new **20/day heavy-book sub-ceiling** | `[proxy]` | Confirmed at `config.js:98`. 300/day is ~$10.23/month of text exposure; 100/day with the heavy books capped is $3.96 and is still ~3× any human hand |

### Added

| Change | Tier |
|---|---|
| Plus allowance: **3 per rolling 168h**, own per-identity counter | `[proxy]` |
| **Joining**: multi-segment request, N stirrings reserved atomically, one bake, one archive entry | `[proxy]` + `[app]` |
| **Make `/v1/video` tier-aware** — confirmed: the route (server.js:1015–1252) never calls `tierOf`; the only call is line 615, in the exchange route. A subscriber is treated identically to a free user today | `[proxy]` |
| `allowDaily('vid:'+userID, 3)` circuit breaker — `videosPerUserPerMinute: 2` is currently the only time-window bound on clip volume anywhere | `[proxy]` |
| **Split the free pool**: separate daily counters for ink (10) and image (2), replacing the single shared 5 | `[proxy]` + `[app]` |
| Free: **1 gift clip/month at 12+ distinct writing days** — the one genuinely new counter | `[proxy]` |
| `freeClipMonthlyCeiling` 2,000 → 4,000, split 2,500 seeds / 1,500 gifts | `[proxy]` |
| Reversible-verb constraint on singles; directional allowed on joins | `[proxy]` |
| Ping-pong / concat bake worker (≥1GB) | infra |
| MetalFX upscale on the full-screen tap | `[app]` |
| Paywall copy — the three benefit lines don't mention moving pictures at all today | `[app]` |

### Repriced

| Change | Tier |
|---|---|
| `plus_monthly` $9.99 → **$12.99**. Weekly unchanged at $4.99 | `[ASC]` |
| `VIAL_GRANTS` 3/8/20 → **4/11/28** (sized on the $0.249 clip: 76% / 71% / 67% margin) | `[proxy]` |
| `clipSeconds` **stays 5** (`config.js:74` — no change); route to PixVerse; body gains `resolution`, `generate_audio: false`, `aspect_ratio` (it sends only `prompt` and `duration` today) | `[proxy]` |
| `freeClipsPerUser` **stays 2** (`config.js:57`); the third clip is the monthly gift, not a bigger seed grant | — |
| `freeClipsPerIPPerDay` 20 → 10 | `[proxy]` |

### Deleted

| Change | Tier |
|---|---|
| `cooldownCurveSeconds` — the 60s/5m/15m/1h ladder, entirely. The most user-hostile mechanic in the product, and it exists to protect $0.0065 | `[proxy]` + `[app]` |
| `plusImageDailySoftCap` as a *soft* cap — becomes a flat, stated 6/day | `[proxy]` |
| The shared free moment pool — text and images meter separately now | `[proxy]` + `[app]` |
| The "never bundle unlimited video" rule at `credits.md:184-186` — amended, reasoning recorded. This bundles a provable max of 15, not unlimited | docs |

### Not changed
Vial prices. The weekly plan. The wallet reserve/settle/release lifecycle. The idempotency and
refund-on-failure paths in `/v1/video`, which are complete.

**The allowance must ride its own counter, never the `free_clips` ledger** — otherwise one viral
free week denies paying subscribers the thing they bought, and it arrives in fiction as "the ink
must rest" with no way to explain it.

---

## 9. Risks and guardrails

1. **Thinking tokens are unmeasured, and the raised text ceiling triples the damage they can do.**
   At 100 exchanges/day an unbudgeted 1,000 thinking tokens per reply is $7.25/month per
   subscriber. The explicit budget is a hard launch prerequisite, not a follow-up. `geminiProvider`
   already accumulates `candidatesTokenCount` — **read one real week before scheduling the price
   change.** Alert: mean output > 300 tokens/exchange.
2. **The clip price is page-verified, not invoice-verified.** Two research strands disagree on
   PixVerse's rate ($0.045 vs $0.050/s) and nobody has generated a clip. Sized at $0.249, holds to
   $0.276. Alert when logged mean `unit_cost` > $0.26. Kill switch: **cut resolution, never
   seconds** — 5s is now a promise, 720p is a config value.
3. **Joining multiplies every video risk by 3.** A 3-segment join is one request that spends a
   whole week's allowance, runs three generations, and can fail halfway. Reserve all segments
   atomically, release them together, and never charge for a partial join. Cap joins at 3
   segments so a single request cannot exceed one week's worth of spend.
4. **Offer-rate risk — the likeliest way this fails as marketing while succeeding as a
   spreadsheet.** Video is offered, not requested: the affordance needs `replyText.length >= 80`
   and a MOVE verdict. If MOVE fires rarely, subscribers pay for three stirrings and see one.
   Instrument `video_offered` / eligible replies from day one; alert below 40%; lever is
   `minConvertibleReplyChars` 80 → 60.
5. **Ping-pong must read as real, or 5s singles look short.** Ship the reversible-verb constraint
   *with* the model swap, fix `image-live-video-report.md:31` ("smoke drifts") first, then judge a
   20-prompt blind bake-off at 420pt in the real frame before announcing anything.
6. **Cutting free images 5 → 2 may cost conversion, not just money.** The image is the hook for
   the Artist book, which is the most shareable door in. Guardrail: watch `image_generated` per
   free user and D1 activation by book. If Artist activation drops, the cheap fix is 3 images/day
   for free ($0.31/month more at full limit), *not* restoring the shared pool.
7. **Free-clip farming.** Clips key to `x-ink-user`; in anonymous attestation that token *is* the
   identity. Confirm App Attest is enforced in production before the monthly gift ships. Seeds
   first, gift staged a week later.
8. **ffmpeg will OOM the 256MB proxy VM.** 5s at 720p24 is 120 frames ≈ 166MB before encoder and
   Node; a 3-segment concat is larger. Dedicated worker, budgeted at $0.0055–0.008/picture.
9. **Credit attach will fall** — roughly $560/month of net at 12k MAU if it halves. If attach is
   below 8% by week 8, cut the allowance 3 → 2, never cut vial prices.
10. **Revised analytics guardrail.** The existing spec alerts on 30% of *gross* $9.99, a price
    that is changing. Restate against net, per plan: alert p95 > 25% of net ($2.76/mo, $1.06/wk);
    page at p99 > 50%. Add **mean stirrings per Plus user per month > 11** (of 15) — that means
    underpriced, and the fix is a price move on the *next* cohort, never a quiet cut to the
    current one. Track joins separately: a join is one picture but N stirrings, and conflating
    them will make consumption look lower than it is.
11. **The release valve is the spec, never the number.** The promise (3 stirrings, 5 seconds) is a
    trust commitment and an App Store release; route and resolution are a proxy deploy.

---

## 10. Three decisions for you

1. **3 stirrings at 5s, or 4 at 4s?** Both are solvent; they are the same money. 4×4s is 16
   seconds a week and a slightly better paywall line; 3×5s is 15 seconds a week and a better
   *clip*, and it makes joining land on a round number. **Recommendation: 3 at 5s** — you asked
   for 5s, and a longer single is the thing people screen-record.
2. **Does joining need its own price, or is one-stirring-per-segment enough?** The arithmetic says
   enough: a 2-segment join costs $0.494 against $0.498 for two singles, so a surcharge would be
   inventing a cost that isn't there. **Recommendation: no surcharge.** The scarcity is already
   in the allowance.
3. **Free images at 2/day or 3/day?** 2/day is $0.62/month at full limit, 3/day is $0.93. The
   third image costs $0.31 per fully-maxed free user and might be what makes the Artist book
   convert. **Recommendation: launch at 2 and treat the third as the first lever you pull** if
   free-tier Artist activation disappoints — it is a config value, so it is a same-day change.

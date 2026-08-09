# Free tier — building the muscle, then asking

**Status:** Proposal · **Date:** 2026-08-09 · **Decision owner:** Melih
**Companion to:** [video-in-plus.md](video-in-plus.md) — that doc sets the numbers; this one
sets how we find out whether they are right.

**The decision this doc defends:** ship the v2 numbers unchanged, instrument properly, change
nothing for two weeks, then move exactly one lever at a time against rules written in advance.

---

## 1. What the free tier is for

Not a trial. Not a sample. **A habit.** The muscle we are teaching is *come back to the
notebook tonight* — and that reflex is built by frequency of return, not by volume per session.
A free user who writes four pages every evening for three weeks is worth far more than one who
writes forty pages on a Saturday and never opens it again.

That gives the free tier one job and one shape:

> **Let a free reader finish one satisfying session a day, then stop cleanly — and let the stop
> arrive at the end of the session, never in the middle of it.**

Being cut off mid-thought does not create desire; it creates the memory of a broken object, and
it breaks the very muscle we are trying to build. Being told *"that is today's page — come back
tomorrow, or bind the notebook and keep going"* does both jobs at once: it ends the ritual on a
clean beat and names the way past it.

This is also the only free-tier fiction that fits an enchanted notebook. A diary is a
once-a-day object. The limit is not a meter running out — it is the book closing for the night.

---

## 2. The insight that should govern every change

**The knob that controls free-tier cost and the knob that controls conversion are not the same
knob.** They are barely even related, and moving them together is how this gets fumbled.

Free tier at full limit, month one (from video-in-plus.md §6):

| Line | Cost | Share of free cost |
|---|---|---|
| Ink — 10/day × 31 | $0.198 | **12.6%** |
| Images — 2/day × 31 (Artist worst) | $0.620 | **39.6%** |
| Video — 2 seeds + 1 gift | $0.747 | **47.7%** |
| **Total** | **$1.565** | |

What each ink lever actually saves, per fully-maxed free user per month:

| Free ink/day | Monthly ink cost | Saving vs 10/day |
|---|---|---|
| 12 | $0.238 | — |
| **10 (proposed)** | **$0.198** | — |
| 8 | $0.159 | $0.039 |
| 6 | $0.119 | $0.079 |
| 5 (today) | $0.099 | $0.099 |

**Cutting free ink from 10/day to 6/day saves eight cents a month and 5% of the free tier's
cost.** Ink is not a cost lever. If we ever cut it, we cut it because it is a *conversion*
lever — and we should say so out loud rather than dressing it as thrift.

The corollary matters just as much: **images and video are the cost, and they are already
tight** (2/day and 3 lifetime-ish). If free-tier spend ever needs to come down, it comes out of
those two, and both are one config value.

---

## 3. Where the ink ceiling actually binds

A realistic diary or Storyteller session is 2–5 exchanges. At 10/day, that reader **never** meets
the ink wall — so for them, 10 vs 6 changes nothing in either direction, cost or conversion.

The ink ceiling binds on exactly one population: **long-session books.** The Game Master runs a
solo campaign; the Tutor works through a problem set. Those are 10–30 exchanges in one sitting,
and they hit any daily ink limit inside a single session — which is precisely the mid-session
cut we must not ship.

So the honest first question is not "is 10 too many?" It is **"who is hitting the wall, and were
they mid-session when it happened?"** Both are measurable, neither is currently measured, and
the answer changes what we'd do:

- If only Game Master and Tutor readers hit it → the fix is a **per-book free allowance**, not a
  global cut. Long-session books get fewer, longer-lived sessions; the diary books keep theirs.
- If nobody hits it → ink is not doing any conversion work, and conversion is being driven by
  archive, video, and memory. Cutting ink then is pure downside: it annoys people for $0.08.
- If everybody hits it → 10 really is too low for the way people write, and the ceiling is
  landing inside sessions across the board.

---

## 4. The 2×2 that tells us where we are

Two numbers place us. Everything else is detail.

- **Ceiling contact** — share of free weekly-active readers who hit any daily ceiling at least
  once in the week.
- **D7 return** — share of installs writing again on day 7.

| | **Low contact (< 20%)** | **High contact (> 55%)** |
|---|---|---|
| **D7 at or above 30%** | **Too generous.** The muscle formed and nothing ever asks for payment. Tighten — and tighten the *conversion* knob (ink, archive window), not the cost knob | **The spot.** Habit formed, ceiling felt. Hold everything and let it run |
| **D7 below 30%** | **Not a limits problem.** People are leaving for a product reason. Touching limits here makes it worse — go look at reply quality, the ritual, and first-session time | **Too stingy.** We are cutting people off before the habit forms. Raise, or move where the wall lands, before anything else |

The bottom-left cell is the one that costs teams the most, because a limits change is easy and a
product change is not. Write the rule down now, while it is cheap to be honest: **if D7 is under
30% and contact is under 20%, limits are not the problem and we do not touch them.**

---

## 5. What we measure, and what "right" looks like

| Signal | Definition | Target | Too generous | Too stingy |
|---|---|---|---|---|
| **Days active / free WAU** | Distinct writing days per active week | **≥ 3** by week 2 | — | < 2 |
| **D7 / D30 return** | Existing PRD targets | 30% / 20% | — | below |
| **Ceiling contact** | Free WAU hitting any daily ceiling weekly | **25–40%** | < 20% | > 55% |
| **Mid-session wall rate** | Ceiling hits where the reader wrote again within 10 min | **< 25%** | — | > 40% |
| **Time to first paywall** | Median days install → first `paywall_shown` | **7–14 days** | > 21 | < 3 |
| **Paywall trigger mix** | Share by moments / archive / memory / video | no single trigger > 60% | — | — |
| **Free → paid** | PRD target | **4–6%** by week 8 | — | — |
| **Cost per free MAU** | Model spend / free MAU | **< $0.50** | — | — |
| **Ritual reach** | Notification permission granted, and `ritual_opened` / notifications sent | grant > 50% | — | — |

**Ritual reach sits in this table on purpose.** The habit engine in this product is the per-book
notification ritual, not the daily limit. Limits do not build muscle — they only decide when
someone is asked to pay. If the notification grant rate is poor, the muscle never forms no
matter where the ceilings sit, and every limits experiment we run will read as noise. **Check
ritual reach before running any limits experiment.** The ask already fires at the first answered
page, which is the right moment; whether it lands is unmeasured.

---

## 6. Instrumentation to add first

The existing schema (`AnalyticsEvent.swift`) already carries `install`, `first_stroke`,
`page_sent`, `page_answered`, `paywall_shown(trigger:)`, `ritual_opened`,
`notification_permission_answered`, and the full video funnel. Three things are missing, and
without them this plan cannot run:

| Event | Payload | Why it is load-bearing |
|---|---|---|
| **`limit_reached`** | `kind` (ink/image/video), `book`, `exchanges_this_session`, `seconds_since_session_start` | The single most important event in this document. `paywall_shown` tells us someone hit a wall; it does not tell us **whether they were mid-session**, which is the whole difference between a clean close and a broken object |
| **`session_ended`** | `exchanges`, `images`, `duration_s`, `hit_limit`, `book` | Gives session length per book — the number that decides whether a per-book allowance is the answer |
| **`session_started`** | `book`, `days_since_last_session` | Streak and return-cadence distribution, which is the muscle itself |

Deliberately **not** adding: anything derivable server-side from timestamps we already store.
Two of these three are session-boundary events the client alone can know, which is why they have
to be events.

---

## 7. The ladder — one lever at a time

Nothing moves for two weeks. A limits change with no baseline is not an experiment, it is a
guess with extra steps.

| Phase | Action | Hold constant |
|---|---|---|
| **Weeks 0–2 — baseline** | Ship v2 numbers. Add the three events. Change nothing. Read the 2×2 | Everything |
| **Weeks 3–4 — first lever** | Whatever §4 points at, and only that | Price, video allowance, everything else |
| **Weeks 5–8 — second lever** | The next one, only if the first has settled | Price |
| **Week 8+** | Re-read against the PRD's 4–6% conversion target | — |

**Lever order, cheapest and most reversible first:**

1. **Where the wall lands**, before how high it is. If the mid-session rate is above 40%, the fix
   is a per-book allowance for long-session books — the Game Master and Tutor get a session-shaped
   limit while the diary books keep a daily one. Costs nothing; fixes the actual complaint.
2. **Free ink 10 → 8 → 6.** A conversion lever worth $0.04–0.08/month in cost. Only if contact is
   under 20% *and* D7 is healthy. Move one step at a time; 10 → 6 in one jump makes the cause
   unreadable.
3. **The archive window, 30 days → 21.** Probably the strongest untried conversion lever in the
   product, and it costs literally nothing — it changes when the past fades, not what we spend.
   It also converts the users who have *already* built the muscle, which is exactly the cohort
   worth charging.
4. **Free images 2/day → 3/day** (up, not down) if free-tier Artist activation disappoints.
   $0.31/month per maxed free user. Images are the hook for the most shareable book.
5. **Video seeds** — the last thing touched in either direction. It is 48% of free cost and the
   entire word-of-mouth engine, and it is the one lever where being wrong is expensive both ways.

**Never move two levers in one period, and never move a limit and the price in the same period.**
The v2 price change to $12.99 is itself a period; nothing else moves during it.

---

## 8. Decision rules, written before the data

Committing now, while nothing is at stake, so we are not arguing about thresholds while looking
at a number we do not like:

- **Contact < 20% AND D7 ≥ 30%** → too generous. Pull lever 3 (archive 30 → 21) first, lever 2
  second. Not both.
- **Contact > 55% AND D7 < 30%** → too stingy. Pull lever 1 (where the wall lands) first. Do not
  raise ink until the mid-session rate is under 25%.
- **Mid-session rate > 40%** → fix immediately regardless of anything else in this table. This is
  a broken-object bug wearing a pricing costume.
- **D7 < 30% AND contact < 20%** → limits are not the problem. No limits change. Escalate to
  reply quality, ritual reach, and time-to-first-answered-page.
- **Time to first paywall < 3 days** → we are asking before the muscle exists. Raise the trigger,
  not the price.
- **Any single paywall trigger > 60% of shows** → the others are dead weight and should be
  re-tuned, not celebrated.
- **Cost per free MAU > $0.50** → cut images or video, never ink. Ink cannot produce that number.

---

## 9. What we do not do while learning

- **No price change after $12.99.** One price move per year, and this is it.
- **No new free-tier mechanic.** The scheme is already four numbers (10 ink, 2 images, 3 clips,
  30-day archive); a fifth makes the results unreadable and the pitch unrepeatable.
- **No unlimited anything**, including as an experiment. It cannot be walked back.
- **No cutting the video seeds to fund an ink increase.** Ink cannot cost enough to need funding.
- **No "temporary" generosity for a launch push.** A limit people have felt cannot be tightened
  later without it reading as a takeaway.

---

## 10. The one thing I would change today

Everything above says hold and learn, with one exception worth flagging now rather than in three
weeks: **10 ink/day is above what a diary session needs and below what a Game Master session
needs, which means it is the wrong shape for both.** It will not bind on the readers we most
want to convert, and it will bind mid-session on the readers who write longest.

I am not proposing to change it before baseline — the whole point of §7 is that we do not guess.
But I would expect the first two weeks of `limit_reached` data to point at **a per-book free
allowance** rather than a different global number, and it is worth knowing that is the likely
answer before the data arrives, so we recognise it when it does.

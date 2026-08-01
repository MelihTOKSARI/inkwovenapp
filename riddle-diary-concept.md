# Inkwoven — The "Riddle Diary" Concept: Where It Lives & How to Make It the Main Concept

**Type:** Concept-placement report · **Date:** 2026-07-17 · **Inputs:** vision.md (v2), prd.md (v3), tasks.md + fresh external research

---

## 1. The short answer

**The Tom Riddle diary concept is not a new thing to add — it already *is* Inkwoven's core.** It just isn't named as the main concept anywhere, because Vision v2 deliberately demoted "the diary" to one Book on the shelf (The Keeper) and made the abstract *paper engine* the brand.

If the diary-that-writes-back should be the **main concept**, the fix is not new scope — it's a repositioning pass across three documents and the store listing. The engine and the 8 Books stay exactly as built; the *story we lead with* changes from "a paper engine with 8 Books" to "the enchanted diary, which can become anything."

## 2. Where the concept lives today (the map)

| Element of the movie mechanic | Where it already exists | Doc location |
|---|---|---|
| Write in the diary with a pen | PencilKit canvas, pen-first everywhere | PRD §4 (engine), tasks B1–B4 |
| The page drinks your ink | Ink-absorption animation, strokes removed after reply | PRD §4 exchange lifecycle, tasks B3 ✅ done |
| It answers in flowing script | Streamed cursive ink renderer | PRD §4, tasks A6/C3 |
| A private diary that remembers you | **The Keeper** (Face ID, local-first, cross-page memory) | Vision launch shelf, PRD §4, tasks E3 + D5 |
| Moving pictures on the page | Video renderer ("Daily-Prophet style" — internal shorthand only) | PRD §4, tasks C5 |
| Proof people want this | "the open-source 'Riddle' project proved organic fascination" | vision.md §Opportunity, PRD §1 |

So: **the concept's home is the paper engine + The Keeper**, and its *citation* is already in vision.md. What's missing is its promotion from evidence-and-one-Book to **the identity of the product**.

## 3. Fresh external validation (fetched 2026-07-17)

The Riddle project — the diary of Tom Riddle for the reMarkable Paper Pro — had a full press cycle **this month**:

- The GitHub repo is at **~1.1k stars / 77 forks, MIT-licensed**: Rust ink engine, 2.8s idle-commit → PNG snapshot → vision-LLM → streamed cursive reply, with a local page memory. Functionally, it is Inkwoven's engine loop on e-ink hardware.
- **TechRadar** called it "one of the smartest e-reader features I've seen"; **Android Authority**, **Notebookcheck**, **Adafruit** (Jul 14), **Republic World** (Jul 7) and others covered it the same week.
- Coverage highlights the exact wedge in your PRD: installation is hacker-only (dev mode, SSH, root, one specific device/OS). **The fascination is proven; the accessible consumer version does not exist.** Inkwoven on iPad is that version.

Implication: the "diary that writes back" framing is *currently riding a live press wave*. Leading with it is not just cleaner positioning — it's timely, and journalists already have the reference loaded.

## 4. What "main concept" should mean — recommendation

Three ways to read your directive, with a clear pick:

**A. Full pivot — Inkwoven becomes only a diary app.** ❌ Not recommended. It throws away 7 built Books, the Bindery, credits, and the platform economics, days after the all-in build.

**B. Reposition — the enchanted diary is the brand story and front door; the shelf is the depth. ✅ Recommended.** Everything shipped stays; the narrative inverts: *"The diary that writes back — and becomes whatever you need."* The diary is the hook people can repeat in one sentence (fixing the "eight doors dilute the launch story" risk you flagged H/H in PRD §8); the Books become the "it's more than a diary" second beat.

**C. Soft touch — just make the hero demo the diary moment.** Half-measure; fine as a fallback, but it leaves the one-liner abstract.

### Concrete placement — the edits, doc by doc

1. **vision.md → "The concept (source of truth)"** — add the diary framing as the *narrative identity* on top of the engine: keep "a medium, not a single-purpose app" as architecture truth, but open with the enchanted-diary story. New one-liner candidate: *"The diary that writes back — an enchanted notebook for iPad that answers your handwriting in ink, pictures, and moving pictures."* Also upgrade the Riddle mention from a "why now" aside to a named validation paragraph (1.1k stars, July 2026 press cycle, hacker-only install = our opening).
2. **prd.md §8 open question ("hero demo = engine ink moment or Artist doodle")** — **resolve it: the hero demo is the diary moment.** Write a worry → ink drunk by the page → a warm answer flows back. It's the scene everyone already knows from the film, which makes the 20-second video self-explaining.
3. **prd.md §6 / tasks H1 (onboarding vignette)** — onboarding *is* the diary: the notebook introduces itself in ink and invites you to write to it, Keeper-flavored, before revealing the shelf. First answered page ≤90s already fits this perfectly.
4. **tasks H6 (store listing + press kit)** — lead ASO/listing with "the diary that writes back," keep "paper that answers" as the tagline beneath. Add the press angle: *"the viral reMarkable diary hack, reborn as a polished iPad app anyone can install"* — pitch the same outlets that just covered Riddle (TechRadar, Android Authority, Notebookcheck) with the consumer follow-up story.
5. **The Keeper (tasks E3)** — promote from "retention king" to **default/first Book**: shelf order puts the Keeper first; the notebook opens as a diary on first run.
6. **New file suggestion** — keep this report in the repo as `riddle-diary-concept.md` at root (peer of vision/prd/tasks), so the positioning decision has a home and a date.

## 5. The IP guardrail (non-negotiable)

The concept is the movie's; the words must never be. "Tom Riddle," "Harry Potter," "Hogwarts," "Daily Prophet," and any WB-trademarked names must appear **nowhere user-facing**: app name, store listing, keywords, screenshots, press kit, in-app copy, or marketing videos. Reasons:

- **App Review Guideline 5.2 (intellectual property)** — third-party IP in metadata or content is a standard rejection/takedown trigger, and you're submitting with AI images + video + credits already drawing scrutiny (PRD §8, M/H risk).
- Warner Bros. actively enforces the franchise; press can say "like Tom Riddle's diary" (fair comment — they already do for Riddle), **but you can't**.
- Your PRD already encodes the right instinct for the Correspondent ("public-domain/original figures only, zero trademarked references") — this report just extends that rule to the brand layer. Internal docs saying "Daily-Prophet style" are fine; scrub any such phrase before it reaches copy decks.

Safe vocabulary that keeps the resonance: *enchanted diary, the diary that writes back, living notebook, the page drinks your ink, moving pictures.* Let journalists make the Riddle comparison for you — it's a stronger endorsement when they say it.

Note also: the open-source Riddle repo is MIT-licensed, so even code-level inspiration is clean; the only thing you can't borrow is the character name it trades under.

## 6. Risks of the repositioning (and why they're acceptable)

| Risk | Read |
|---|---|
| "Diary" narrows perceived audience (journaling ≠ gamers/artists) | Mitigated by the second beat: "…and becomes whatever you need." Per-Book videos (already the post-launch plan) re-broaden weekly. |
| Vision v2's launch-discipline rule said the journal is *not* the identity | That rule was about *feature focus*, and v3 already overrode launch scope. Branding via the diary doesn't change scope — it gives the 8-door product the single repeatable sentence the rule was actually protecting. |
| Riding a movie reference without naming it underperforms | The Riddle press cycle proves the mechanic markets itself even unnamed — "notebook that writes back" was the headline phrasing in most coverage. |

## 7. Bottom line

Put the concept **at the top of vision.md as the brand story, into the hero demo and onboarding as the first experience, and into the store listing as the hook** — with The Keeper promoted to the default first Book. Don't add scope; invert the narrative. And keep every trademarked word out of everything a user or reviewer sees.

---

### Sources

- [GitHub — MaximeRivest/riddle](https://github.com/MaximeRivest/riddle)
- [TechRadar — interactive tool turns reMarkable Paper Pro into Tom Riddle's diary](https://www.techradar.com/tablets/ereaders/this-new-interactive-tool-on-the-remarkable-paper-pro-turns-your-device-into-tom-riddles-diary-from-harry-potter-and-its-one-of-the-smartest-e-reader-features-ive-seen)
- [Android Authority — reMarkable Paper Pro mod: Tom Riddle's diary](https://www.androidauthority.com/remarkable-paper-pro-tom-riddles-diary-disappearing-ink-3684286/)
- [Adafruit blog — Making the Diary of Tom Riddle for the reMarkable Paper Pro (2026-07-14)](https://blog.adafruit.com/2026/07/14/making-the-diary-of-tom-riddle-for-the-remarkable-paper-pro)
- [Notebookcheck — Someone turned a reMarkable tablet into Tom Riddle's diary](https://www.notebookcheck.net/Someone-turned-a-reMarkable-tablet-into-Tom-Riddle-s-diary.1335689.0.html)
- [Republic World — Tom Riddle diary comes to life thanks to AI (2026-07-07)](https://www.republicworld.com/tech/this-video-shows-a-notebook-that-writes-back-like-harry-potter-s-tom-riddle-diary-but-there-s-a-catch-2026-07-07-131560)
- Project docs: vision.md, prd.md, tasks.md (Inkwoven repo)

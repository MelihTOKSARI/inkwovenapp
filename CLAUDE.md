# Inkwoven — project rules

> The folder-wide rules in `../CLAUDE.md` apply in full. This file adds Inkwoven's own law.

## The ink follows the Riddle diary — STRICT, NON-NEGOTIABLE

Every exchange between the writer and Ink behaves like the Tom Riddle diary in the Harry
Potter film. This is the core interaction of the product, not a styling choice. Any change
to writing, replying, or media rendering is measured against this rule first.

**IP guardrail:** the movie reference is internal shorthand only. "Tom Riddle",
"Harry Potter", "Hogwarts" and any other WB-trademarked name appear **nowhere
user-facing** — app copy, store listing, keywords, screenshots, press kit, marketing.
See `riddle-diary-concept.md` §5. Safe vocabulary: *enchanted diary, the diary that
writes back, the page drinks your ink, moving pictures.*

### The law of the ink (from the approved Claude Design spec, "Inkwoven Ink Behaviour")

1. **The page drinks the ink — nothing is cleared.** When writing is done with, it is
   absorbed: blur up, opacity down, a small settle downward, each glyph offset slightly
   in time (the scatter). Never clear, never slide away, never fade out as one block.
2. **Answers are never placed.** Ink's reply writes itself glyph by glyph at a legible
   hand's pace, a nib at the writing head, the freshest glyphs still "wet" (softer,
   slightly blurred) behind it. Never a fully-formed block fading in, never typing
   dots, never a spinner.
3. **The answer takes the centre of its page** — whole screen or half page, the same
   optical centre. The writer's line lives in the same centred column as the reply,
   never docked to the bottom edge. One measure (one max-width) for the whole exchange.
4. **A picture alone may swell to fill the page. Words never do.** With words, media
   sits below the ink at a modest size; alone, it opens larger and may then take the
   whole page.

### The contract (timings — the design's source of truth)

| Beat | Value |
|---|---|
| a glyph | 34 ms base cadence, ±11 ms jitter; +300 ms after `. — ? ! ;`, +150 ms after `,`; spaces ×0.7 |
| the absorb | 1500 ms · blur to 7 px · sink 7 px · ease `cubic-bezier(.55,.06,.68,.19)` |
| the scatter | per-glyph absorb delay, ≤ 420 ms |
| a picture develops | 2200 ms — parchment veil lifts, blur 16 px + sepia → clear |
| picture sizes | with words 46% / alone 70% → may grow to full page |
| moving picture sizes | with words 56% / alone 80% → may grow to full page |

**Reduced motion is honoured, never skipped:** every duration folds to ~a third
(×0.35, floor 90 ms). The absorb and the write-out still happen — shorter, not absent.

### Voice and material

- Copy stays in-fiction: the book speaks, the app never does. No UI voice
  ("Submit", "Loading", "Error"), no status chrome, no warnings — the diary mechanic
  itself is the feedback.
- A moving picture carries the living treatment (slow breathe, faint film flicker);
  a picture develops like a photograph, it does not pop in.
- No emoji. AI disclosure stays woven in-fiction ("a spirit of ink, not a person").

### Craft floors

- Hit targets never below 44 pt.
- Before any UX change, read `vision.md` and `prd.md`.

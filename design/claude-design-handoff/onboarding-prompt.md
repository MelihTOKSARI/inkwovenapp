# Claude Design instruction — Inkwoven: the first opening

Design the app's entire first-run experience, replacing the current text-and-signature onboarding. Use `tokens.json`, `../design-system.md`, and the existing screens in `../screens.md` as the world this must join.

## What Inkwoven is (context you are designing for)

An enchanted notebook for iPad + Apple Pencil. You write on the page by hand; the page **drinks your ink** and answers — in flowing script, in a picture that develops like a photograph, or in a short **moving picture** you can tap and fall into. What the paper is *for* is decided by which Book you open. This is the anti-chatbot: an object with a pen, not a window with a keyboard.

**The problem you are solving:** today the app opens on a wall of text and a signature line, then drops the user onto a shelf of eight books they cannot tell apart. Nothing ever shows them what the app *does*.

## The scenario — one continuous shot

There are no separate screens. This is one camera move through one object, and the user can cut it short at any moment by touching the glass.

| # | Beat | Duration | What is on screen |
|---|---|---|---|
| 1 | **The room** | hold 0.8s | A dark room. One closed book lies flat on a table, seen from a step back and slightly above. A candle off-frame-left. Nothing else — no logo lockup, no button, no title card. |
| 2 | **Coming closer** | 1.5s | The book grows to fill the frame — the *room* moves toward it, not a UI zoom. The candle glow widens with it. |
| 3 | **It opens itself** | 1.2s | The cover lifts and falls open. Pages riffle past and settle on one page, as if the book knew which one. |
| 4 | **Into the page** | 0.8s | The open page fills the screen. Parchment edge to edge. This is now the surface the whole rest of the app uses. |
| 5 | **It writes** | streaming | The welcome writes itself in ink, one stroke-pace glyph at a time. |
| 6 | **The moving picture** | user-triggered | A picture sits on the page below the writing, in the `DevelopFrame` plate. Tapping it expands it past the page to fill the screen, looping, no chrome, dismiss by tap or swipe down. |
| 7 | **The flyleaf** | user-paced | The page asks for a signature, written in ink on a ruled line. |
| 8 | **The seal** | 0.6s | A wax seal below the signature. Pressing it carries the reader **into the first Book's page** — not to a shelf. |

**Beat 6 is the most important screen in this brief.** It is the app's hero modality used to teach the app: a moving picture on a page, expanded by tapping it. Design it as a photograph the book already holds — plate, edge, a little warmth — never as a media player. No progress bar, no play triangle over the image, no timeline, no mute button, no close X. If it needs an invitation, the invitation is a line of ink in the margin.

## Screens and states to deliver

1. **The room** — book closed on the table, both orientations.
2. **Mid-approach** — one frame from beat 2, to fix the camera language.
3. **The open page, writing** — mid-stream, with the ink cursor.
4. **The open page, settled** — full welcome + the picture on the page + the flyleaf line.
5. **The moving picture, expanded** — full-bleed, looping, zero chrome.
6. **The flyleaf, unsigned** — ghost prompt in the ruled line.
7. **The flyleaf, signed** — signature in ink, wax seal risen beneath it.
8. **No-Pencil variant** — the same flyleaf when the writer has no Pencil and the keyboard is the hand. The keyboard must not cover the line being written.
9. **Reduce Motion variant** — beats 1–4 collapse to a single 300ms cross-fade straight to the open page; the writing arrives whole.
10. **Returning signer** — someone who already signed and reset the app: page opens already sealed, seal reads differently.
11. **The picture is absent** — the clip failed to load or was skipped. The page must look intentional with nothing where the plate was; never an empty frame with a broken glyph.

## Copy (use verbatim)

The writing on the page, in ink, in order:

> I am a notebook, and tonight I become yours.
>
> Write on my pages with your own hand. I drink the ink, and I write back — in words, in pictures, and sometimes in pictures that move.

In the margin beside the picture, small and quiet:

> *touch it, and it opens*

The disclosure — required, and it must be worn as a bookplate in the **top margin**, not buried at the foot:

> **a spirit of ink, not a person**
> Inkwoven composes fiction on your behalf — it is not advice, and never a substitute for a human hand when you need one.

The flyleaf:

> **sign, and it is yours**
> *(ghost, in the line)* sign your name in ink

The seal:

> open the first page

The escape, top-right, small caps, quiet, always present:

> skip

## Non-negotiables

1. **Nothing here may be a cutscene the user is trapped in.** Any touch during beats 1–4 completes the approach instantly and lands on the open page. There is no "next", no dots, no skip *within* the animation — the skip in the corner leaves onboarding entirely.
2. **The fiction is the interface.** If an element could not exist on a desk in 1890, redesign it. That kills: play buttons, progress bars, page dots, tooltips, coach marks, "step 1 of 4", any modal with a Next.
3. **The hand owns the bottom of the page.** Everything informative — the disclosure, status, marginalia — sits in the **top** margin. The signature line is the one thing allowed low, because that is where a hand belongs.
4. **Pen-first.** The Pencil is the interface. A keyboard appearing where ink should be is a bug, not a fallback; the keyboard is only the hand when no Pencil exists.
5. **Paper is light, room is dark.** Beats 1–3 are the candlelit room; beats 4–8 are warm parchment. Never a flat white screen.
6. **Accessible magic.** WCAG AA, ≥44pt targets, Dynamic Type on all UI text, Reduce Motion = cross-fade, and every beat has a VoiceOver equivalent — a blind reader must be able to sign and pass through without seeing a single animation.
7. **This ends inside a Book, not on a shelf.** The shelf is not part of the first session.

## Motion

Follow `../design-system.md` motion tokens. Specific to this flow: approach 1.5s ease-out (never a linear zoom — it should feel like leaning in), page-riffle 1.2s with 5–7 page edges passing, page-settle 0.8s, ink streams at a straight pen pace (~38ms/glyph), the moving picture expands 400ms from its plate to full-bleed with the page dimming behind it.

## Output

One HTML page per state above, on-token, iPad-first (1194×834 landscape and 834×1194 portrait). Make the approach (beats 1–4) and the picture expansion (beat 6) **interactive** — those two are the whole idea and a static frame cannot show whether they work.

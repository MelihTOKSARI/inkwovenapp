# Inkwoven — App Store screenshot brief for Claude Design

**Deliverable:** 6 landscape iPad screenshots + 1 App Preview video + 3 icon directions.
**Status:** the previous set was deleted and is not a reference. Start clean.

How to use this file: §1–4 is the art direction Claude Design needs seeded. §5 is the
per-slot prompts, ready to paste. §6–7 are the alternate directions if the first doesn't
land. Slots 1–3 carry the listing — they get the most space here for a reason.

---

## 1. Hard specs — non-negotiable

| | |
|---|---|
| Orientation | **Landscape** |
| Size | **2752 × 2064** px (13″ iPad). 2732 × 2048 also accepted |
| Format | PNG or JPEG, **RGB, no alpha channel, no transparency** |
| Count | 6 (max 10) |
| App Preview | 1600 × 1200 landscape, 15–30s |
| Icon | 1024 × 1024 PNG, no alpha, **no rounded corners** (Apple masks) |

Apple rejects screenshots that are off by a single pixel. Export at exact size, flatten
alpha, verify before upload.

Two content rules that bite: the UI shown must be **real shipping UI**, not invented
mockup, and no "Download Now"-style CTAs or unverifiable claims.

---

## 2. The brand, seeded from `design/claude-design-handoff/tokens.json`

**Palette.** parchment `#F4EAD5` · parchment-deep `#E7D7B4` · ink `#2E2418` (iron-gall —
brown-black, never pure black) · ink-faded `#6B5A43` · room `#17110B` · room-raised
`#241B12` · candle `#C9962E` · candle-bright `#E8B84B` · wax `#7A2E2B`.

**Book accents.** Storyteller `#3E4E6B` · Artist `#9C4A3C` · Game Master `#4A5D3A` ·
Oracle `#5B4370` · Keeper `#6E3B34` · Correspondent `#8A6B4F` · Tutor `#46607C` ·
Parlor `#7C4E68`.

**Type.** Display: Cormorant Garamond 600. Body: EB Garamond 400. Captions: EB Garamond
500, **small caps, 0.08 letter-spacing** — this is the store-caption face.

**Personality.** Candlelit stationery. Parchment grain. Iron-gall ink that blooms
slightly into the fibre. 1890 desk, not 2026 dashboard. Every control diegetic — wax
seals, ribbons, marginalia.

**One-line hook.** *Paper that answers.*

---

## 3. The art direction

Read this before generating anything. It is the difference between a screenshot set and a
folder of captures.

**Light is the subject.** One warm source, off-frame, upper left. It rakes across the
paper so the grain reads as texture, then falls off hard into `room` at the edges. Every
frame should have a glowing centre and dark corners — that is what makes a 300px thumbnail
legible in a scrolling row. The previous set failed precisely here: flat, evenly-lit cream
that dissolved into the App Store's own background.

**Ink is not black.** `#2E2418`. Iron-gall browns as it dries and feathers into fibre.
Cursive strokes should vary in weight the way a real nib does — heavy on the downstroke,
hairline on the return.

**Negative space is atmosphere, not emptiness.** An unwritten half-page is only beautiful
if it is *lit* — if it carries grain, warmth, a shadow gradient, the edge of a candle's
reach. An unlit empty page is a blank rectangle. This is the single most important note in
this document.

**Depth, not flatness.** The page sits on a surface in a room. Slight perspective, a real
shadow under the leading edge, a hint of the desk beyond the paper's edge. Not a
face-on UI capture pasted onto a colour field.

**No device frames.** The page fills the frame. We are not selling an iPad app; we are
selling a notebook that happens to be an iPad app.

**Restraint.** One idea per slot. Never two UI panels, never callout arrows, never a badge
cluster. If a slot needs an arrow to explain it, the slot is wrong.

---

## 4. The strategy behind the slot order

Only slots 1–3 appear in search results before anyone scrolls. They are the listing.

Premium creative apps — Procreate, Sky, Nomad Sculpt, Concepts — lead with the **output**,
undressed: full-bleed, no caption, no frame, often as autoplay video. Journaling apps like
Day One lead with **social proof** instead: press logos and user counts baked across the
top, the UI small and functionally decorative.

Inkwoven has no press and no user count, so the social-proof route is closed. The output
route is open, and it is the stronger one, because your output is the most photogenic
thing in the category.

So: **slot 1 is the moving picture.** Not the shelf, not onboarding, not a blank page. The
one thing no competitor has, shown as the thing it is.

Captions are baked into the frame as **marginalia** — small caps in the top margin, the way
an annotation sits on a real page — not as a marketing bar above the image. Day One does
this and it reads as part of the object rather than an ad for it. It suits a notebook with
a voice.

---

## 5. DIRECTION A — "The Candle" — RECOMMENDED

Full-bleed, no device frames, no colour fields. Every slot is a photograph of the page
under candlelight. Highest ceiling, and the only direction that looks like the product
feels.

### The three that matter

Slots 1–3 must work as a set of three thumbnails, read left to right, with no text
legible except the caption. Test them at 300px wide before going further.

---

#### SLOT 1 — the hook: a page becoming a window

> **Prompt for Claude Design:**
>
> Landscape 2752×2064. A single sheet of aged parchment fills the frame, lit by one warm
> candle source off-frame upper left, falling off to near-black `#17110B` at the corners.
> Written on the page in flowing iron-gall cursive `#2E2418`, upper third: a short scene —
> *"The lantern swung once, and the door was already open."* Below the writing, occupying
> the lower two-thirds, a moving picture has bloomed **into** the paper: a dim corridor
> with a swinging lantern, rendered as if the paper itself has become a window into a lit
> room. The video's light spills onto the surrounding parchment fibre and warms it. Edges
> where the image meets the paper are soft and slightly fibrous — developed into the sheet,
> not pasted on top. Faint candle glow `rgba(201,150,46,0.18)`. Deep shadow under the
> page's leading edge; a suggestion of dark desk beyond.
>
> Top margin, small caps EB Garamond `#E7D7B4`, letter-spaced, quiet:
> **THE PAGE BECOMES A WINDOW**
>
> No device frame. No UI chrome. No buttons. Painterly, candlelit, cinematic — closer to a
> still from an animated film than to a product screenshot.

**Why this slot works:** it is the only image in the category that cannot be faked by a
competitor, and it explains the product without a sentence of copy.

**Caption alternates** — pick by which reads at thumbnail scale:
`THE PAGE BECOMES A WINDOW` · `WRITE A SCENE. FALL INTO IT.` · `YOUR STORY, MOVING` ·
no caption at all (Procreate's play — viable if the image is strong enough)

---

#### SLOT 2 — the mechanic: ink drunk, ink returned

> **Prompt for Claude Design:**
>
> Landscape 2752×2064. Same parchment, same candlelight, same falloff. The page shows one
> exchange, mid-moment: at the top, a few lines of **handwritten user text** in a slightly
> irregular human hand, partly *dissolving* — the strokes softening and sinking into the
> fibre, as though the paper is drinking them. Directly below, a reply is flowing back in a
> different, finer, more confident cursive hand `#2E2418`, caught **mid-stroke** — the last
> word incomplete, the nib's path implied. Weight varies naturally: heavy downstrokes,
> hairline returns. A faint warm bloom sits under the newest characters, as if the ink is
> still wet.
>
> An Apple Pencil rests at the lower right, tip just off the paper, catching a highlight
> from the candle. No hand.
>
> Top margin, small caps `#E7D7B4`:
> **IT DRINKS YOUR INK. THEN ANSWERS.**
>
> No device frame, no UI. The contrast between the two hands — human and other — is the
> entire subject.

**Why:** slot 1 sells the spectacle; slot 2 proves there is a real mechanic underneath.
Mid-stroke is essential — a finished reply is a paragraph, a reply in progress is magic.

**Caption alternates:** `IT DRINKS YOUR INK. THEN ANSWERS.` · `WRITE BY HAND. IT WRITES BACK.` ·
`REST THE PEN. THE PAGE REPLIES.`

---

#### SLOT 3 — the range: eight Books on a shelf

> **Prompt for Claude Design:**
>
> Landscape 2752×2064. A dark wooden shelf in a candlelit room, `#17110B` deepening to
> black at the frame edges. Eight bound notebooks stand and lean, each a distinct
> leather/cloth binding in its own accent — deep blue `#3E4E6B`, rust `#9C4A3C`, moss
> `#4A5D3A`, violet `#5B4370`, oxblood `#6E3B34`, tan `#8A6B4F`, slate blue `#46607C`,
> plum `#7C4E68` — with worn foil titling catching the candlelight. One volume is pulled
> slightly forward, open, its page glowing warm and faintly written-on, drawing the eye.
> Textures read: grain, cloth weave, foil, the softness of old board.
>
> Top margin, small caps `#E7D7B4`:
> **EIGHT BOOKS. ONE NOTEBOOK.**
>
> Warm, inviting, physical. A library at night, not an app menu.

**Why:** slots 1–2 sell one magic trick; slot 3 answers "and then what?" before the user
scrolls away. It is also the most colourful frame in the set, which gives the
three-thumbnail row a rhythm: warm gold → warm gold → deep jewel tones.

**Caption alternates:** `EIGHT BOOKS. ONE NOTEBOOK.` · `A DIFFERENT BOOK, A DIFFERENT MAGIC` ·
`EIGHT DOORS INTO THE SAME PAPER`

---

### Slots 4–6 — the supporting cast

Same light, same grain, same caption treatment. These are seen by people already
interested; they can be more specific.

#### SLOT 4 — the Artist

> Landscape 2752×2064. Parchment under candlelight. Left half: a rough, honest, slightly
> clumsy pencil doodle — a crooked house, a bird, something a real person drew in ten
> seconds. Right half: the same subject *developing* into finished painterly art, revealed
> in a soft vertical gradient as if a photograph surfacing in a darkroom tray — edges first,
> midtones behind, detail still arriving at the trailing edge. The unfinished boundary is
> the point; do not show a completed image. Warm falloff to `#17110B`.
>
> Top margin small caps: **YOUR DOODLE, DEVELOPED**

#### SLOT 5 — the Game Master

> Landscape 2752×2064. Parchment, candlelight, moss-green `#4A5D3A` ribbon at the page
> edge. Handwritten player action in a human hand at top; below it, narration flowing back
> in a distinct confident cursive; beside the narration, a small developed illustration of
> the scene — a torchlit stair, a figure at the bottom — framed like a plate in an old
> adventure novel, its edges sunk into the paper. Composition should feel like a page from
> an illustrated Victorian book.
>
> Top margin small caps: **A GAME MASTER THAT DRAWS THE SCENE**

#### SLOT 6 — the Keeper

> Landscape 2752×2064. The most intimate frame in the set. Parchment gone slightly cooler
> and dimmer — the candle burning low, the room darker `#17110B`, oxblood `#6E3B34` ribbon.
> A short private entry in a human hand; beneath it, a reply in a quiet, gentle cursive,
> shorter than the others. A small wax seal in `#7A2E2B` sits closed at the page corner —
> the lock, diegetic, never an icon. Deepest shadows in the set. It should feel like the end
> of a day.
>
> Top margin small caps: **A DIARY THAT ANSWERS. LOCKED.**

---

### App Preview video (15–30s, 1600×1200 landscape)

The single highest-leverage asset in the listing, because the mechanic sells itself on
sight and three of your four strongest competitors lead with autoplay video.

**First 3 seconds, no negotiation:** Pencil touches paper → ink is drunk → first cursive
stroke of the reply appears. That is the whole product, and it must land before anyone
decides to scroll.

Then: reply completes in the Book's hand (4s) → a picture develops in the tray (5s) → the
*make this move* affordance appears and is tapped (3s) → the clip blooms into the page (4s)
→ **it expands past the page to fill the entire screen, looping** (6s) → hold on the
title. No voiceover. No music with lyrics. Room tone and pen sound if anything.

The full-screen expansion is the money shot. Give it the last third and let it breathe.

---

## 6. DIRECTION B — "The Window" — the alternate

Same art direction, different structure: the six slots are **one continuous fall through
the page**, read left to right as a sequence.

Slot 1 the page is written on and glowing faintly. Slot 2 the moving picture begins to
bloom in the paper. Slot 3 it has grown past the page's margins. Slot 4 the paper edges
are gone entirely and we are inside the scene. Slot 5 the shelf, as a breath. Slot 6 the
Keeper, as a return to quiet.

Slots 1–4 share continuous colour, light angle and perspective, so the strip reads as one
widening shot. **Higher ceiling than Direction A, higher risk:** each slot must also stand
alone, because Apple shows them individually in some placements, and a mid-sequence frame
that means nothing by itself is a wasted slot.

Worth generating alongside A for slots 1–3 only, and comparing at thumbnail scale.

---

## 7. DIRECTION C — "The Bindery" — the safe control

The Goodnotes/Notability pattern, executed in Inkwoven's palette instead of pastels.

Each slot: the page floating with a soft drop shadow on a flat field in one Book accent
colour — Storyteller blue, Artist rust, Oracle violet, and so on. Bold Cormorant Garamond
caption above the page, high contrast, benefit-led. The strip reads as a deliberate colour
sequence when scrolled.

**Most legible at thumbnail, most conventional, least distinctive.** Its real use is as
the B-arm in a Product Page Optimization test against Direction A once there is traffic —
it is a genuinely different hypothesis, not a lesser version of the same one.

---

## 8. Icon — three directions

The icon does more than sit on the home screen: **Apple pulls its dominant colour into the
product page header gradient.** Sky's page is gold, Procreate's purple-black, Day One's
blue. Candlelit amber against a category of blue-and-white productivity apps is a free
differentiator, decided entirely here.

All three: 1024×1024, no alpha, no rounded corners, no text, legible at 60px, one or two
colours doing the work.

**A. The Wax Seal.** A wax seal in `#7A2E2B` on near-black `#17110B`, pressed with a
simple quill-and-drop glyph, one candle highlight raking across the wax's ridges. Reads as
a bold red-brown circle at 60px. *Page header becomes deep oxblood.* Strongest silhouette;
least explicit about what the app does.

**B. The Lit Page.** A single parchment corner `#F4EAD5` curling out of darkness, one
cursive stroke blooming across it in iron-gall, candle-bright `#E8B84B` catching the
curl's edge. *Page header becomes warm amber* — the best of the three for the store page.
Most on-brand; risks reading as a generic notes app at small size unless the stroke is
bold and singular.

**C. The Ink Drop.** A single iron-gall droplet `#2E2418` mid-bloom on parchment, its
feathered edges just beginning to spread, warm rim-light. Geometric, minimal, highest
legibility at 60px. *Page header becomes pale parchment* — which is the weakest of the
three on a product page, and the reason I'd rank it last despite it being the cleanest
mark.

**Tie the icon to slot 1:** whichever wins, its dominant colour and one motif must recur
in the first screenshot. That link is what makes a listing feel authored.

---

## 9. Rules — check every frame against these

- Legible at **300px wide**. If the caption can't be read, the caption is too small.
- Caption ≤ 6 words. Benefit or promise, never a feature name.
- One idea per slot. No arrows, no callouts, no badge clusters.
- Same light angle, same grain, same caption position and face across all six.
- Real shipping UI only — no invented screens, no fabricated copy.
- No device frames, no other-platform silhouettes, no "Download Now", no "#1 App".
- Iron-gall `#2E2418`, never `#000000`.
- Every frame has a lit centre and dark corners.
- Empty space is lit and grained, or it doesn't exist.
- Verify the set reads in both light and dark App Store appearance.

---

## 10. Export checklist

- [ ] 6 × landscape PNG at exactly **2752 × 2064**
- [ ] RGB, alpha channel flattened and removed
- [ ] Verified at 300px thumbnail, in a row, in that order
- [ ] App Preview at 1600 × 1200, 15–30s, hook in the first 3 seconds
- [ ] Icon 1024 × 1024, no alpha, square corners, checked at 60px
- [ ] Icon colour and slot 1 visibly related
- [ ] Nothing shown that the shipping build cannot do

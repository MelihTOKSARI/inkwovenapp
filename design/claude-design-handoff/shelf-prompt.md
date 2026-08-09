# Claude Design instruction — Inkwoven: the shelf that grows

Redesign the home screen. Use `tokens.json`, `../design-system.md`, and the page screens in `../screens.md` as the world this must join. Read `onboarding-prompt.md` and `custom-book-prompt.md` first — this screen is the middle of that arc.

## What Inkwoven is (context you are designing for)

An enchanted notebook for iPad + Apple Pencil. You write by hand; the page drinks your ink and answers in flowing script, in a developing picture, or in a short moving picture you can fall into. Which **Book** you open decides what the paper is for — the Oracle answers questions, the Artist paints what you draw, the Keeper is a diary that writes back. Eight of them exist.

## The problem you are solving

Today the home screen shows all eight books at once: eight identical leather spines on a ledge, eight names in rotated gilt, and no way to tell what any of them does without tapping each one twice. It reads as a menu of eight things a stranger cannot distinguish, and it is the first thing anyone sees.

**The fix is not a better menu. It is a room that starts nearly empty and fills up.** The reader begins with one book. A second arrives. Then a third. By the time all eight stand on the ledge the reader knows what a Book is, and the shelf they are looking at is one they watched assemble itself.

## The arc this screen has to carry

> **one book → a few books → your book**

Nothing is ever locked, hidden behind a purchase, or withheld — every Book can be brought to the shelf at any time from the Drawer. What is staged is *arrival*, not access. A Book that has not arrived yet simply is not on the table, the way a book you have not been given yet is not in your house.

## Part 1 — the count states

The shelf's whole layout changes with how many Books are on it. These are the states to design, and they are the heart of this brief.

| Books | Arrangement | Reading |
|---|---|---|
| **1** | One book lying **flat on the table**, closed, facing the reader. Candle beside it. No ledge, no shelf — this is a desk. | *You have a book.* |
| **2–3** | Still flat, but **stacked**, slightly askew, the top one offset so all spines are legible. A hand could lift any one of them. | *You have a few books.* |
| **4–5** | The ledge appears. Books **stand and lean** — not a tidy row: two upright, one leaning into its neighbour, a gap where more will go. | *This is becoming a shelf.* |
| **6–8** | A full standing row, evenly spaced, the ledge full corner to corner. The room has become a library. | *This is a collection.* |
| **0** | Every Book hidden from the Drawer. An empty ledge, a candle, and one line of ink saying where they went. | *An empty shelf is still a room, not an error.* |

Design **all five**, in both orientations. The transitions between them matter as much as the states — a shelf that goes from 3 to 4 should visibly *become* a shelf, not cut to a different screen.

The custom Book (see `custom-book-prompt.md`) has a blank spine until it is bound. Show it in the 4–5 state, unfinished, standing among finished ones.

## Part 2 — the anatomy of a Book on the shelf

Each Book carries, at all times, without a tap:

1. **The spine or cover**, in that Book's own leather colour, with its gilt title. When the book lies flat (states 1–3) the reader sees the **cover**, not the spine — design both.
2. **A card on the ledge beneath it** — one line, small caps, quiet, saying plainly what the Book does. This is the single most important piece of text on the screen and it is always visible for every Book. Never behind a tap, never rotating, never one at a time.
   - `answers the question on the page` · `paints the sketch you leave it` · `a diary that answers — sealed with Face ID` · `carries on any story you begin` · `runs an adventure, one move at a time` · `letters answered by whoever you address` · `works a problem through, step by step` · `riddles, guessing games, draw-and-guess` · `a book that answers however you ask it to`
3. **One tap opens it.** There is no peek, no preview, no long-press menu, no second tap. Design the press state.

Three per-Book conditions to design, all in ornament only, none as a badge:
- **Sealed** (the Keeper) — a still lock, brass not gold. It must read as *private*, never as *paid*.
- **Resting** (we turned it off server-side) — dimmed, the candle not reaching it.
- **Untouched for a long while** — a fine layer of dust on the top edge, which wipes away the first time it is opened.

## Part 3 — the transitions

Five, in order of how often they are seen:

1. **Opening a Book** — the hero transition. The book comes off the shelf toward the reader, opens, and its page becomes the screen. It must rhyme with the app's first opening (see `onboarding-prompt.md` beats 2–4), because that is the same move: the room leans in, the cover lifts, the page fills the frame.
2. **Closing back to the shelf** — the reverse, and the book goes back to its own place. The reader should never lose track of which book they just put down.
3. **A Book arrives.** The most important transition in this brief. It happens on a launch *after* the reader has earned it, never mid-session and never over a modal. The room is simply different than it was: a new book is on the table, the candle is on it, and the arrangement has re-settled around it. **No badge. No "NEW". No counter. No dialog.** If the reader does not notice, the card under the spine will tell them when they do.
4. **The shelf becoming a shelf** — 3 books lying flat, and the fourth arrival lifts them all upright onto a ledge. Design this one carefully; it is the moment the reader's collection becomes a library and it happens exactly once.
5. **A Book leaves** (hidden from the Drawer) — it is put away, the row closes the gap, and the arrangement steps back down a state if the count crosses a boundary.

## Part 4 — the hidden things

The room rewards attention. These are never announced, never required, never listed anywhere, and there is **no achievements screen, no counter, no collection gallery** — the moment a secret is recorded somewhere it stops being a secret and becomes a chore. They exist for the reader who sits still and looks.

Design at least these, plus your own:

- **The candle answers the device.** Tilt the iPad and the glow shifts across the leather; shadows lengthen on the side away from the light. A room lit by one flame, held in two hands.
- **Idle, after ~20 seconds.** Something small happens and passes: wax runs down the candle and sets, a moth crosses the light, a spine settles with a creak, a loose page slips a little further out of a book.
- **Touch the candle.** It gutters, flares, and the whole shelf brightens for a second. Nothing else happens. That is the point.
- **The hour is real.** Late at night the candle is burned lower and the room is darker; near dawn a cold grey edge reaches the ledge. The reader who opens the app at 3am gets a different room than the one who opens it at noon.
- **A book you have an unfinished page in** keeps its ribbon hanging out.
- **The room remembers.** Wax accumulates on the candle over weeks. The moth comes back. This is what makes it a world rather than a set of easter eggs — design the state after one day and after two months.

Rules for all of them: nothing hidden may block a tap, delay an open, or occupy the same attention as a Book. Every one must be absent under Reduce Motion without leaving a hole. None may be the only way to learn anything.

## Part 5 — the room around the books

- **The header**: the wordmark, and three doors — Vials (credits), Bindery (covers and inks), Drawer (settings, and where Books are brought back). Keep all three always. Quiet them: none of them may out-animate a Book. The credit shop currently has a breathing glow and a travelling highlight on a 2.6s loop — it is the loudest thing on a screen whose subject is the books.
- **The writing above the shelf**: the notebook talks to itself in ink and the page drinks it, looping. It demonstrates the mechanic and belongs to no particular Book. Keep it small, keep it far from the cards, and never let it narrate or name what the reader should do.
- **Room variants**: the app has light/dark room themes. Every state above must hold in both, and the ink on the ledge cards must stay AA in the lighter one.

## Non-negotiables

1. **The fiction is the interface.** If it could not exist on a desk in 1890, redesign it. No badges, no counters, no dots, no tooltips, no coach marks, no "3 of 8", no NEW ribbons, no onboarding overlay.
2. **Nothing is ever shown as locked.** A Book that has not arrived is absent, not chained. There is no padlock anywhere on this screen except the Keeper's seal, and that one means *private*.
3. **Every Book's card line is always visible.** This is the fix for the whole screen; do not make it conditional, rotating, or gestural.
4. **One tap opens.** No peek, no long-press menu on a spine.
5. **Paper is light, room is dark** — this screen is the candlelit room. Never a flat iOS list.
6. **Accessible magic** — WCAG AA, ≥44pt targets (the flat-lying covers and the standing spines both), Dynamic Type on the cards, Reduce Motion replaces every animation above with a cross-fade, and a VoiceOver reader hears each Book's name and card line from the same string the sighted reader sees.
7. **Both orientations, iPad-first** (1194×834 and 834×1194). The 6–8 state in portrait is the hardest layout in the app — solve it explicitly rather than shrinking the landscape one.

## Output

One HTML page per state and per transition above, on-token. Make the **count states** and the **opening transition** interactive — a static frame cannot show whether a shelf becoming a shelf feels like a room changing or like a screen redrawing. Include a control that steps the book count 1 → 8 so the whole arc can be watched in one go.

# Claude Design instruction — Inkwoven: the book the writer makes

Design the creation, binding, and editing of a **custom Book** — a Book whose voice the writer invents instead of one we shipped. Use `tokens.json`, `../design-system.md`, and the shelf and page screens in `../screens.md` as the world this must join.

## What Inkwoven is (context you are designing for)

An enchanted notebook for iPad + Apple Pencil. You write by hand; the page drinks your ink and answers in flowing script. Each **Book** on the shelf answers in its own voice, its own hand, its own ink — the Oracle answers questions, the Artist paints what you draw, the Keeper is a diary that writes back.

Every Book so far was written by us. This one is written by the reader: they decide who answers them, in what voice, in what language, from where. It is the last Book they are given and the one they will describe to a friend.

## The single rule that shapes every screen

**There is no form.** No text fields with labels, no dropdowns, no sliders, no "Create character" button, no wizard with a Next. The book **asks**, one question at a time, in ink, on its own first page — and the writer answers by hand exactly as they would answer any other Book. The character sheet is a *consequence* of the conversation, not the way in.

If any screen you design could be rebuilt as a settings form without loss, it is the wrong screen.

## Part 1 — the unwritten book arrives

It appears on the shelf like any Book, with no announcement. Design its resting state:

- **The blank spine.** Same leather construction as the others, but nothing is finished: no gilt title, no monogram in the ring, the ribbon undyed. It should read as *a book waiting to be written*, not as a locked or missing item. It must never look like a placeholder, an empty state, or a purchase.
- **Its card on the ledge** (the one-line label under each spine): `a book that answers however you ask it to`
- **Contrast frame:** show it beside two finished spines so the difference is legible at a glance.

## Part 2 — the binding conversation

Open it and the first page asks. One question at a time: the question rises in ink, the writer answers by hand below it, the answer is absorbed into the page, the next question rises in its place. Same absorb/answer grammar as every other Book — **the creation of the Book teaches how Books work.**

Six questions. Each answer is short, and each may be skipped by writing nothing and resting the pen.

| # | The question, in ink | What it sets |
|---|---|---|
| 1 | `What shall I call you?` | what the Book calls the writer |
| 2 | `And what will you call me?` | the Book's name — becomes the spine title |
| 3 | `Where am I writing from, and when?` | place and era, which colour the voice |
| 4 | `Should I be kind to you, or honest with you?` | temperament |
| 5 | `In what tongue shall I answer?` | reply language |
| 6 | `One thing I should know about you.` | the single fact the Book carries |

Design **three** of these screens fully (1, 4, and 6 — a plain answer, an answer with a choice in it, and an open one), plus the transition between two questions.

Question 4 and question 5 are the two that tempt a designer toward controls. Solve them in the room's own materials instead:

- **Q4** — the writer may simply write "kind" or "honest" or a sentence of their own. If you give a touchable shortcut, make it two **wax-stamped cards** lying on the page, not a segmented control.
- **Q5** — a language genuinely needs a list. Make it a set of **ribbon tags** laid along the page's edge, the writer's own hand still able to write an answer instead. Never a dropdown, never a picker wheel.

Also design: **abandoning and returning** — the writer leaves after question 3 and comes back. The page holds what was answered, faint, and asks question 4 again as if it had been waiting.

## Part 3 — the binding

The moment the last question is answered, the book binds itself. This is the payoff screen and it should be the most beautiful thing in this brief.

- The spine takes a colour drawn from the answers.
- The monogram ring fills with the initial of the name the writer gave it.
- **The spine title is set in the writer's own handwriting**, taken from the signature on the flyleaf — every other Book wears our gilt; this one wears theirs. This is the single most important detail in the entire brief.
- The ribbon takes its dye.
- Then the shelf, with the new book standing among the others, finished.

Design: the binding moment mid-animation, the finished spine in isolation, and the shelf after.

## Part 4 — the sheet

The full character lives as a **bookplate pasted inside the front cover** — reachable from the Book's own page, and mirrored in the Drawer for people who look for settings there. It is a card in a book, not a preferences screen.

Everything set in Part 2 is here and editable by writing over it. Two things appear here that the conversation never asked for, because they are refinements rather than beginnings: **how long its replies run** (a line, a paragraph) and **what it should never do**.

Design: the bookplate at rest, the bookplate with one line being rewritten in ink, and the "unbind this book" action — destructive, in-fiction (the plate lifts away and the spine goes blank again), with a real confirmation.

## Part 5 — the second one costs

The first custom Book is free and complete. A second is where the money is. Design that moment in-fiction and in the Bindery's language, never as an interstitial paywall over the shelf:

> **the bindery holds one more blank book**
> Bound for subscribers. Yours stays yours, whatever you decide.

Wax-seal CTA. It must be readable as an offer, not as a lock on something already made — nothing the writer has already written is ever behind it.

## Non-negotiables

1. **No forms, no wizards, no progress dots, no "Step 3 of 6".** The page asks; the hand answers. That is the entire interaction model.
2. **The fiction is the interface** — if it could not exist on a desk in 1890, redesign it.
3. **The hand owns the bottom of the page.** Questions and status live in the top margin; the answering space is below.
4. **Pen-first.** Every answer is written by hand. Keys are the fallback only when no Pencil exists, and they must never cover the line being written.
5. **Each answer is short and discrete** — a name, a place, a word, one sentence. Do not design a large free-writing box for "describe your character"; the space you give is the instruction, and a big empty box invites a page of text that this Book cannot honour.
6. **Nothing here may promise a person.** This Book answers in a voice the writer chose; it is still ink. The bookplate carries the same quiet disclosure line the flyleaf does.
7. **Accessible magic** — WCAG AA, ≥44pt targets, Dynamic Type, Reduce Motion = cross-fade, and every question answerable with VoiceOver on.
8. **Both orientations**, iPad-first (1194×834 and 834×1194).

## Output

One HTML page per screen listed above, on-token. Make **Part 2** interactive end to end — the question-and-answer rhythm is the product, and a static frame cannot show whether it feels like being asked or like being processed. Make **Part 3** interactive too; the binding is the moment the writer will screen-record.

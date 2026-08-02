# Inkwoven — App Store listing (v1.0)

All copy below is final draft, sized against App Store Connect limits and true of the
shipping v1 build (no video, no credit packs, no accounts, no sync). Character counts
are for the exact strings between the quotes/fences.

---

> **ASO revision, 2026-08-01.** Name, subtitle and keyword field were rebuilt as one
> indexed set. The previous pair (`Inkwoven` / `The notebook that writes back`) read
> beautifully but indexed almost nothing: the name carried no keyword, the subtitle was
> mostly stop words, and every search term was crowded into the keyword field — the
> weakest of the three. **Swap all three fields together or the no-duplicate rule breaks.**
> The name locks at first submission.

---

## App name (30 char limit — 30 used)

```
Inkwoven: Handwriting Notebook
```

*"Handwriting" is the differentiator no competitor can claim and a winnable lane
(MyScript-led, not locked up). "Notebook" is the category word Goodnotes and Notability
left open when both chose "AI Notes" for their titles.*

## Subtitle (30 char limit — 29 used)

```
Apple Pencil diary, art & ink
```

*Five tokens, zero overlap with the name. "Diary" covers the journaling pool in a
visible field. Deliberately no "AI" in either visible field — in a results page of
"AI Journal & Diary" clones, the listing that doesn't say AI reads like a real object,
and the term is fully indexed from the keyword field anyway.*

**Reviewer fallback** if "Apple Pencil" is flagged under Apple's third-party trademark
guidelines (referential use is permitted, so this should pass — but have it ready):

```
Pencil-first diary, art & ink
```

*29 chars. If used, add `apple` to the keyword field.*

## Promotional text (170 char limit — 158 used; editable anytime without review)

```
Write with your Pencil — or a fingertip — and the page answers: flowing script, or a picture that develops before your eyes. Eight Books, one enchanted shelf.
```

## Description (4000 char limit — 2,600 used; leads with the hook)

```
Paper that answers.

Inkwoven is a notebook for iPad whose pages answer your handwriting. Write with Apple Pencil or a fingertip, let the pen rest, and the page drinks your ink — then a reply flows back in script, or a picture develops on the page like a photograph in a tray.

Eight Books sit on the shelf, and each one turns the same paper into something different:

• THE KEEPER — the diary that writes back, locked behind Face ID.
• THE STORYTELLER — begin a tale and it continues in ink, with scenes that develop as pictures.
• THE ARTIST — your doodle develops into finished art.
• THE GAME MASTER — a solo adventure: write what you do, and the page narrates and illustrates what happens.
• THE ORACLE — ask anything, and an answer is drawn in ink; cryptic or plain, as it pleases.
• THE CORRESPONDENT — write letters to figures of history and fiction, and they answer in their own hands.
• THE TUTOR — worked solutions and gentle corrections, written out step by step.
• PARLOR GAMES — riddles, twenty questions, draw-and-guess.

A SPIRIT OF INK, NOT A PERSON
Everything the page writes or draws is fiction composed by AI — the notebook says so plainly on its very first page. It is not advice, and never a substitute for a human hand. If your writing suggests you are in real distress, the notebook sets the fiction aside and shows you real resources instead.

PRIVATE BY DESIGN
No account. No sign-in. No ads. No tracking. Your pages live on your device — delete them all, or export them as PDF or text, whenever you like. To compose a reply, a snapshot of the page you just wrote is sent securely to our server and on to the AI services that generate the answer, identified only by a random device token — never a name, an email, or a profile. The full story is in our privacy policy.

MADE FOR THE PENCIL, NEVER GATED ON IT
Inkwoven is built iPad-first: pressure-sensitive ink, palm rejection, paper that feels like paper. Apple Pencil is the finest way to write here — and a finger works everywhere, on every page. On iPhone, Inkwoven is a companion: revisit your pages and consult the Oracle wherever you are.

FREE EVERY DAY
Every Book is free to open, with a few answered pages each day. Pages older than 30 days fade until the notebook is bound to you. Inkwoven Plus removes the daily limit and keeps your whole archive:

• $4.99 per week, with the first 3 days free
• $9.99 per month — the same notebook, 54% less

Subscriptions renew automatically until cancelled; manage or cancel anytime in your App Store account settings. Restore purchases from the paywall.

Requires iOS 17 or later. Works on iPad and iPhone.
```

## Keywords — en-US (100 char limit — 98 used)

Rules honored: comma-separated, **no spaces**, no word repeated from the name or
subtitle (those already index), singulars only, no competitor brands, highest-value
terms first.

```
ai,journal,story,doodle,sketch,drawing,rpg,adventure,fiction,letter,pen,pal,game,master,solo,write
```

**What this buys, via Apple's cross-field recombination** — none of these phrases is
written out anywhere, all are matchable: *ai notebook · ai diary · ai journal ·
handwriting journal · apple pencil notebook · pencil drawing · doodle art · pencil
sketch · ai game master · solo rpg · interactive fiction · pen pal · story game.*

`ai` leads the field: invisible to users, weighted first in the index.
`pen,pal` as two tokens beats `penpal` — it matches the two-word search *and* frees
"pen" to recombine with apple, ai and ink.

**Removed from the previous field, and why:**

| Term | Reason |
|---|---|
| `handwriting`, `diary`, `pencil`, `art` | Promoted to the name/subtitle — keeping them here is an illegal duplicate and wasted budget |
| `oracle` | Guideline **4.3(b)** names *fortune telling* as a saturated category that gets new submissions rejected. Never let metadata frame that Book as standalone divination |
| `magic` | No search intent |
| `letters` | Apple pluralizes automatically — `letter` covers both |
| `notes` | Unwinnable: Goodnotes and Notability both put "AI Notes" in their actual titles |

### English-variant locales — free extra coverage

Each storefront is a separate index that *also* reads the en-US fields, so a different
keyword set per locale multiplies reach at zero translation cost. Add these locales in
App Store Connect and reuse the same description; only the keyword field changes.
Verified: no overlap with en-US, with each other, or with the visible fields.

| Locale | Keyword field | Chars |
|---|---|---|
| en-GB | `sketchbook,handwritten,storybook,bedtime,riddle,tutor,quill,notepad,fantasy,roleplay` | 84 |
| en-CA | `journaling,scrapbook,reflection,mindful,puzzle,homework,cursive,narrative,penmanship` | 84 |
| en-AU | `sketching,doodling,storytelling,workbook,fable,imagination,creative,companion,notepaper` | 87 |

## Categories

- **Primary:** Lifestyle
- **Secondary (suggestion):** Entertainment — the Books skew play (Game Master,
  Parlor Games, Storyteller) more than productivity. Graphics & Design is the
  runner-up if Entertainment ever feels wrong.

## URL slots

App Store Connect will not accept the submission without real, reachable URLs in the
first two slots below. Host these before starting the submission (see
`asc-checklist.md` step 8).

Support contact address (resolved): **swareisland@gmail.com** — this is also the
address in `privacy-policy.md` and in the app's Drawer contact row.

Recommended host: a public GitHub repo named `inkwoven` with Pages enabled. No paid
domain needed; Apple and Google both accept it.

| Field | Value | Status |
|---|---|---|
| Support URL (required) | `https://<github-user>.github.io/inkwoven/support` — app name, a sentence, and swareisland@gmail.com is enough | **not yet hosted — blocks submission** |
| Privacy policy URL (required) | `https://<github-user>.github.io/inkwoven/privacy` — publish `privacy-policy.md` from this folder verbatim | **not yet hosted — blocks submission** |
| Marketing URL (optional) | repo root — fine to leave empty for v1 | optional |

Load both in a private browser window before submitting. App Review opens them, and a
404 here is a same-day rejection.

## Copyright field

```
© 2026 Melih Toksari
```

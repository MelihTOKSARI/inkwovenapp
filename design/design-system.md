# Inkwoven — Design System ("Candlelit Stationery")

**Platform note:** implemented in SwiftUI (deliberate deviation from RN default — see PRD §7). Tokens map 1:1 to SwiftUI: colors → Asset Catalog, type → custom fonts + Dynamic Type, spacing → 4pt grid.

## Principles
1. **The fiction is the interface.** No chrome while writing; every control is diegetic (wax seals, ribbons, marginalia). If a UI element couldn't exist on a desk in 1890, redesign it.
2. **Paper is light, room is dark.** Pages are warm parchment; everything around them (shelf, stores, settings) is a candlelit room — dark leather, brass, low glow.
3. **Motion serves the fiction.** Absorption, development, and script animation are the product; standard iOS transitions only where unnoticed.
4. **The hand owns the bottom of the page.** Occlusion rule: no informative UI (status, errors, cards, banners) in the bottom region while the canvas is active — the writing hand covers it. Status renders as top-margin marginalia (QuietBanner); placement flips with left-handed mode. Absorption ends in stroke *removal*, never low-opacity ghosting.
5. **Accessible magic.** WCAG AA contrast on all text, ≥44pt hit targets, Dynamic Type on UI text (handwriting replies exempt but user-scalable), color never the only signal, Reduce Motion honored with cross-fades.

## Color

| Token | Hex | Use |
|---|---|---|
| parchment | #F4EAD5 | page background |
| parchment-deep | #E7D7B4 | aged edges, cards |
| ink | #2E2418 | iron-gall ink, primary text |
| ink-faded | #6B5A43 | secondary text, old pages |
| room | #17110B | shelf/store background |
| room-raised | #241B12 | shelves, cards on dark |
| candle | #C9962E | accent, focus glow, CTAs |
| candle-bright | #E8B84B | highlights, active states |
| wax | #7A2E2B | seals, destructive-adjacent, paywall accent |
| success-herb | #4A5D3A | confirmations |
| danger-ember | #8C3B2E | errors (in-fiction tinted) |

**Book accents (spine, hand, ribbon):** Storyteller #3E4E6B · Artist #9C4A3C · Game Master #4A5D3A · Oracle #5B4370 · Keeper #6E3B34 · Correspondent #8A6B4F · Tutor #46607C · Parlor #7C4E68.

Contrast pairs verified AA: ink on parchment 10.9:1; parchment on room 12.4:1; candle-bright on room 8.1:1; never candle on parchment for body text.

## Typography

| Role | Face | Size/weight |
|---|---|---|
| Display (Book titles, paywall) | Cormorant Garamond SemiBold | 34/28pt |
| Body (UI, settings, store) | EB Garamond Regular | 17pt, Dynamic Type |
| Caption/labels | EB Garamond Medium, letter-spaced small caps | 13pt |
| Ink replies (the hands) | Per-Book script faces (8 variants: e.g. flowing copperplate for Correspondent, tight scholar's hand for Tutor, jagged quill for Game Master) | 20–24pt, user-scalable |
| Numerals (wallet, prices) | Cormorant Garamond tabular | — |

## Spacing, shape, elevation
4pt grid; page margins 24pt; card padding 16pt. Radius: paper 2pt, cards 6pt, seals/circles full. No hard shadows — candle glow (warm, wide, low-alpha) for focus/elevation; pressed states darken like thumbed paper.

## Components
- **BookSpine / BookCover** — shelf unit: accent color, foil title, whisper line on focus, lock badge (Keeper), "resting" state (flag-off).
- **Page** — parchment surface + texture per Book; hosts canvas, replies, developed images.
- **InkReply** — streaming cursive text block in the Book's hand.
- **DevelopFrame** — image/video container with progressive-reveal mask + preview-first state.
- **WaxSealButton** — primary CTA (paywall, purchase): wax circle + embossed glyph.
- **RibbonTab** — navigation/filter (timeline, store categories).
- **VialChip** — credit balance/pack unit.
- **MarginNote** — memory entries; tear-out affordance (perforation on long-press).
- **ToolTray** — inkwell/blotter cluster, top corner: undo, eraser, hold ("the page waits"), cancel, turn page; dormant (near-invisible) while pen moves.
- **CandleSheet** — modal sheet on dark room background.
- **QuietBanner** — in-fiction status (offline, cooldown): italic, ink-faded, no red.
- **CrisisCard** — the one deliberately *plain* component: system font, high contrast, no texture. Breaking the fiction is the design.

## Motion tokens
The contract lives in CLAUDE.md: absorb 1500ms cubic-bezier(.55,.06,.68,.19) to blur 7 / sink 7 · the reply surfaces WHOLE as the absorb reversed (same duration/blur/distance, curve mirrored) — never streamed, never a typewriter · develop 2200ms veil-to-clear · page-turn 450ms · seal-press 200ms haptic-paired. Reduce Motion: every time folds to ~a third (floor 90ms); nothing skips.

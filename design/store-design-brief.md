# Inkwoven — App Store Design Brief (icon + screenshots)

**For:** Claude Design handoff · **Scope:** visuals only (copy/ASO = `app-store-assets`)
**Stores:** Apple App Store only (SwiftUI iOS/iPadOS — no Google Play build, so no Play icon/feature graphic)
**Date:** 2026-07-06 · Specs verified against Apple docs + 2026 summaries

---

## 1. Exact export specs (Apple enforces exact pixels — 1px off = rejection)

| Asset | Size | Format | Notes |
|---|---|---|---|
| App icon (master) | 1024×1024 | PNG, no alpha, **no rounded corners** (Apple masks) | sRGB |
| App icon (iOS 26 layered) | 1024×1024 canvas, background + up to 4 layers | Transparent PNG/SVG layers → Icon Composer `.icon` | Liquid Glass depth/specular; keep art clear of corners |
| iPad 13″ screenshots (**primary — iPad-first app**) | 2064×2752 portrait | PNG/JPEG, no alpha | 1–10; first 3 sell |
| iPhone 6.9″ screenshots | 1320×2868 portrait | PNG/JPEG, no alpha | 1–10; must show the **actual iPhone experience** (read-only companion + Oracle), not Pencil writing |
| App preview video (optional, later) | per-device specs | — | Post-launch; the absorb/develop motion is made for it |

Smaller devices auto-scale down from these two sizes — design once per class.

---

## 2. Brand theme block (from `tokens.json` / design system)

- **Palette:** parchment #F4EAD5 · ink #2E2418 · room #17110B · candle #C9962E / candle-bright #E8B84B · wax #7A2E2B · 8 Book accent colors (spines)
- **Type:** Cormorant Garamond SemiBold (display/captions) · EB Garamond (support) · per-Book script hands (never as caption type)
- **Motifs:** wax seal, book spines on a candlelit shelf, ribbon tabs, ink absorbing into paper, photographs developing, candle-glow elevation (no hard shadows)
- **Personality:** cozy-magic, 1890s stationery, candlelit room around warm paper; "if it couldn't exist on a desk in 1890, redesign it"
- **One-line hook:** **Paper that answers.**
- **Icon ↔ first screenshot tie (mandatory):** shared candle-glow-on-dark + parchment/wax motif so the store page reads as one object

---

## 3. Icon — 3 directions (design all 3, return for a pick)

**Global icon rules:** no text anywhere; legible at ~60px with 1–2 dominant colors; square canvas, art clear of corners (iOS 26 rounds + masks); must read on both light and dark home screens; deliver flat 1024 master **plus** separated layers (background / mid / foreground) for Icon Composer.

### A. The Wax Seal (symbolic mark) — *recommended starting point*
- **Concept:** the brand ritual reduced to one mark — a wax seal pressed onto the notebook.
- **Key visual:** a single wax-red (#7A2E2B) seal, embossed with an ink-drop-becoming-flourish glyph, centered on dark leather (#17110B) with a soft candle glow (#C9962E) from the upper corner.
- **Why recognizable:** one warm circle on near-black — 2 colors, zero clutter, unmistakable at 60px; the WaxSealButton is already the app's primary CTA, so store → product is seamless.
- **Layering (iOS 26):** background = leather + glow · mid = seal disc · foreground = embossed glyph (specular).
- **Trade-off:** quiet about the *magic* — says "fine stationery" more than "AI answers."

### B. The Answering Page (mascot-forward — the notebook is the hero)
- **Concept:** the product moment itself: an open page glowing in a dark room while script streams across it.
- **Key visual:** open parchment (#F4EAD5) spread filling ~70% of canvas, one candle-bright (#E8B84B) cursive stroke mid-word, room-dark (#17110B) surround with glow halo.
- **Why recognizable:** light-in-darkness silhouette; parchment field pops among saturated gradient icons on any home screen.
- **Layering:** background = dark room + halo · mid = page · foreground = glowing stroke.
- **Trade-off:** most detail of the three — must be ruthlessly simplified or it mushes at 60px (one stroke, no lines of text).

### C. The Ink Drop (minimal glyph)
- **Concept:** ink meets paper, paper answers — a drop whose splash resolves into a reply flourish.
- **Key visual:** oversized iron-gall ink drop (#2E2418) landing on full-bleed parchment (#F4EAD5); the ripple's far edge curls into a script loop; tiny candle glint on the drop.
- **Why recognizable:** 2 flat colors, poster-grade contrast, scales perfectly; the most timeless of the three.
- **Layering:** background = parchment · mid = ripple/flourish · foreground = drop (glass specular suits Liquid Glass best).
- **Trade-off:** risks reading as a generic notes/writing app without the flourish carrying the "it answers" idea.

---

## 4. Screenshot set — 3 styles (pick one system for the whole set)

### Style 1 — Bold benefit captions *(recommended: safest, highest-converting)*
Room-dark (#17110B) panels, candle-glow vignette; device frame with real screens; Cormorant Garamond caption in parchment #F4EAD5, top third, ≤6 words. Slide accents borrow the featured Book's spine color.

### Style 2 — One continuous scene
A single candlelit desk scene flows across all slides — the notebook open at different pages, wax seals and vials scattered on the desk, each slide "turning the page" to the next Book. Highest brand theater; captions engraved as small-caps brass plaques. Trade-off: slides 4–6 lose meaning if viewed alone (store shows them individually in search).

### Style 3 — In-context / lifestyle
Hands + Apple Pencil on iPad in cozy real moments (armchair by lamplight for Keeper, bedside for Storyteller, café for Artist). Warm photography, screens composited in. Trade-off: needs photo-real generation quality; weakest at showing UI detail.

---

## 5. Recommended sequence (iPad 13″ primary set, ≤6 slides — first 2–3 sell)

| # | Slide | Real screen | Caption (≤6 words) |
|---|---|---|---|
| 1 | **Hero — the gasp** | The Page: handwriting absorbed, cursive reply mid-stream | **Paper that answers.** |
| 2 | The core choice | The Shelf: 8 Books, candlelit room | One notebook. Eight Books. |
| 3 | Most shareable | The Artist: doodle → DevelopFrame art reveal | Your doodle becomes art. |
| 4 | **Differentiator** | The Page: moving picture looping in DevelopFrame | Even the pictures move. |
| 5 | Retention story | The Keeper page + Face ID lock badge | The diary that writes back. |
| 6 | CTA | Onboarding vignette / starter page with wax seal | Open your notebook. |

**iPhone 6.9″ set (compliance-true, 4 slides):** 1) Oracle card drawn in ink — "Ask the Oracle anything." · 2) Companion timeline (Remembered Pages) — "Your pages, everywhere." · 3) share-card composer — "Share the magic." · 4) CTA — "The notebook awaits on iPad." *(honest framing: iPhone is the companion)*

---

## 6. Recognizability rules (bake in, verify before export)

Captions high-contrast (parchment on room ≥12:1), clear of notch/Dynamic Island and the Get button zone; icon legible at 60px in 1–2 colors; slide 1 shares the icon's glow + parchment motif; verify the set in light and dark store themes; lead with the emotional hook (slide 1) and the differentiator by slide 4; visuals should echo search language ("AI journal", "story generator", "magic notebook") — a notebook, ink, a developing picture must be *seen*, not explained.

---

## 7. Claude Design handoff instructions

1. Seed the project from `design/claude-design-handoff/tokens.json` + `design/screens.md` (real screens: ShelfView, PageView, RememberedView, KeeperGateView, OnboardingView).
2. Generate the **3 icon directions** first at 1024×1024 (flat master + 3-layer separation each) → return for a pick.
3. Then the **6-slide iPad set** in Style 1 on a tall master canvas; export exact 2064×2752; derive the 4-slide iPhone set at 1320×2868 from the same system.
4. If output is a JS/HTML bundle, export **PDF** and rasterize with pymupdf to exact pixel sizes (no browser).
5. Export checklist: sRGB · no alpha · exact dims · icon corners un-rounded · captions ≤6 words · slide-1/icon motif match.

**Next step after assets:** `app-store-assets` skill for title/subtitle/keywords/description.

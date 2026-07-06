# Claude Design instruction — Inkbound

Design every screen in `../screens.md` using `tokens.json` and `../design-system.md`. iPad-first (1194×834 landscape + portrait), plus two iPhone screens (companion timeline, Oracle).

Non-negotiables:
1. The fiction is the interface — diegetic controls only (wax seals, ribbons, vials, marginalia). The Page has zero chrome while writing.
2. Pages are warm parchment; everything else is a candlelit dark room. Never a flat white iOS screen.
3. Show the states, not just the happy path: absorbing, ink streaming, image developing (preview-first), moving picture, cooldown ("the ink must rest"), offline, crisis interstitial (the one deliberately plain, fiction-breaking screen).
4. Each of the 8 Books gets a distinct spine, paper tone, and script hand — they must be tellable apart at a glance on the shelf.
5. Paywall is in-fiction ("bind the notebook to you") with wax-seal CTA; pricing $9.99/mo, $59.99/yr + 7-day trial; credits as sealed vials (10/30/100).
6. WCAG AA, ≥44pt targets, Reduce Motion fallback = cross-fade.
7. Screenshot-friendly: every screen should work as an App Store screenshot.

Output one HTML page per screen group, on-token, interactive where it teaches the flow (shelf → page → reply).

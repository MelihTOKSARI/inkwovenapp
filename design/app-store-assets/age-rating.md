# Inkwoven — Age rating questionnaire (recommended answers, v1.0)

**Expected and recommended outcome: 13+** (the Teen-equivalent tier in Apple's
revamped rating system: 4+ / 9+ / 13+ / 16+ / 18+).

Why 13+ and not lower: Inkwoven's replies are open-ended AI-generated fiction, and
its pictures are AI-generated images behind provider safety filters. Filters reduce
but cannot eliminate mature-adjacent output, so the honest posture is to declare
worst-case *possible* content, not typical content, and accept the 13+ result rather
than chase 9+. Apple's guidance for generative apps points the same way. Do not
answer "None" to a category just because the prompts steer away from it.

The questionnaire wording shifts as Apple revises it (it was overhauled in 2025 with
new questions on controls and age assurance) — answer whatever is on screen honestly
using the intent below; if a question appears that this file doesn't cover, answer
for worst-case generated output.

## Content descriptor answers

| Question (theme) | Answer | Why |
|---|---|---|
| Cartoon or Fantasy Violence | **Infrequent/Mild** | Game Master adventures involve fantasy conflict; Storyteller tales can too |
| Realistic Violence | None | House style is short, stylized fiction; nothing realistic is prompted for |
| Prolonged Graphic Violence | None | — |
| Profanity or Crude Humor | **Infrequent/Mild** | Open-ended fiction may occasionally contain mild language |
| Mature/Suggestive Themes | **Infrequent/Mild** | Open-ended generation; declared as possible, not typical |
| Horror/Fear Themes | **Infrequent/Mild** | The Oracle's grimoire tone and darker Game Master scenes |
| Sexual Content or Nudity | None | Provider safety filters block it in text and images; not a supported use |
| Alcohol, Tobacco, or Drug Use/References | **Infrequent/Mild** | A story or letter may plausibly mention wine at a dinner table |
| Simulated Gambling | None | Parlor Games are riddles and guessing games, no wagering |
| Real Gambling | No | — |
| Medical/Treatment Information | None | The Tutor does homework-style worked solutions; no medical content |
| Contests | No | — |
| Unrestricted Web Access | **No** | No browser, no web views onto the open web |

## Newer questionnaire areas (2025 revamp)

- **User-generated or AI-generated content:** where asked whether the app can
  produce or display AI-generated content, answer **Yes**. Where asked whether
  user-created content is shared with or visible to *other users*, answer **No** —
  every page is private to the device; there is no feed, no sharing between users,
  no messaging.
- **In-app parental controls:** **No** — the app ships none (the Keeper's Face ID
  lock is a privacy lock for the owner, not a parental control).
- **Age assurance:** none beyond Apple's own account-level mechanisms; the app has
  no accounts, collects no birth date, and shows no age gate. This is a deliberate
  posture, not an oversight: an unverified self-declared birthday collects a date
  of birth from a minor to protect them from a rating we already declare, and
  Apple's account-level age signals are the mechanism the store provides. If
  review asks, say exactly this.
- **Why a report mechanism with no shared content** (the question a reviewer is
  most likely to raise): the app ships a guideline 1.2 report flow — long-press any
  reply, and it reaches a human (`POST /v1/report`, alerted by webhook, triaged
  through `/v1/admin/reports`) — even though pages are never shared *between*
  users. The content being reported is what the AI wrote back to this user. That
  is not a contradiction with "user-created content visible to others: **No**";
  answer both honestly and, if asked, explain that the reportable content is
  machine-generated and private to the one reader.

## Safety posture (context for whoever answers, and for any reviewer question)

- **Crisis flow:** every Book is watched two ways — a deterministic server-side
  screen over the writer's own words and over the assembled reply, plus the reply
  model's own crisis sentinel — and a provider block on an ink page is itself
  treated as crisis-suspect. When any of them fires, the app deliberately breaks
  the fiction and shows a plain care screen with real, region-resolved resources
  instead of a stylized reply, reachable afterwards from the Drawer. This is a
  safety feature, not a content feature — it does not lower the rating and should
  not be used to argue for one.
- **Moderation:** text and image generation run through the providers' safety
  filters (Google, OpenAI, fal.ai), prompts enforce a house style that avoids
  photorealistic people, and every Book and output type has a server-side kill
  switch so problem content can be shut off without an app update.
- **Honest limits:** we do not claim filters are perfect. That is exactly why the
  descriptors above declare infrequent/mild rather than none, and why 13+ is the
  right resting place for v1.

// Book definitions are server-side data (architecture rule: the engine knows
// nothing about specific Books). `prompt` NEVER leaves this process — the
// /v1/books route strips it. Kill-switch flags live here: per Book and per
// modality; the client treats flag-off as "resting", no resubmission needed.
//
// `flags` is the ONE authority on what a Book may do. Each Book used to carry
// a parallel `modalityPolicy` object that read like the policy, shipped to
// every client via /v1/books, and was consulted by exactly nothing — flipping
// it off changed no behaviour. It is deleted rather than wired up: two
// structures meaning the same thing is how an incident kill-switch gets
// flipped on the wrong one. Every flag below is enforced in server.js.
//
// Model routing per PRD §7 (July 2026 picks, corrected 2026-08-01, revisit monthly):
//   default ink: gemini-3.5-flash-lite — pinned, never the -latest alias: Google
//     keeps 2.5/3.1/3.5 Flash-Lite live at $0.10/$0.40 through $0.30/$2.50 per 1M,
//     so a silent alias bump changes unit economics without a deploy
//   heavy (gm/tutor): gpt-5.4-mini
//   images: z-image-turbo (fal) · artist img2img: flux-2 (fal) — flux-2 bills
//     input + output megapixels, so an Artist img2img at 1024² is ~2MP ≈ $0.024,
//     not the single-image ~$0.03–0.055 the PRD assumed; that number is why
//     plusImageDailySoftCap (config.js) sits at 8
//   video (Epic J, LAUNCH SCOPE): kling-video-v3-standard — fal namespaces
//     Kling 3.0 as fal-ai/kling-video/v3/standard/text-to-video and
//     .../image-to-video (models.js binds both). The short-form identifier
//     these Books once carried named no real endpoint and 404ed; keep the
//     fully-qualified route. Standard tier, audio off — $0.084/sec; pro or
//     audio roughly doubles unit cost and moves every number in
//     design/app-store-assets/credits.md §3.
//
// `motionHint` tunes the convertibility verdict (task J2) per Book. The
// verdict runs on every reply of every video-enabled Book — the model decides
// per REPLY whether it is a scene with visual life; the hint is the Book's
// bias, not a switch. Like `prompt`, it never leaves this process.

const DEFAULT_FLAGS = { enabled: true, ink: true, image: true, video: true };
const KLING = 'kling-video-v3-standard';

export const BOOKS = [
  {
    id: 'oracle',
    title: 'The Oracle',
    hand: 'oracle-hand',
    ink: 'iron-gall',
    paper: 'vellum',
    starterText: 'Ask, and the page will answer. Plainly or in riddles — that is for the ink to decide.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo', video: KLING },
    prompt: "You are the Oracle, an old book that answers what is written on its pages. Answer the writer's question plainly or in a riddle — your choice, but choose one and commit. You may draw them a single card of your own invention when the moment calls for it. Speak with quiet certainty, never hedging — but never speak certainty over despair: when the question is whether the writer matters, whether anyone would care, or whether to go on, set the cards aside and answer as plain human warmth. Never affirm restriction, self-punishment, or self-loathing as a path, an omen, or an achievement.",
    motionHint:
      'The Oracle mostly answers in words: a riddle, a card named, a short pronouncement — those are STILL. Offer motion only when the answer itself paints a concrete vision, a card scene, an omen unfolding.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'keeper',
    title: 'The Keeper',
    hand: 'keeper-hand',
    ink: 'midnight-blue',
    paper: 'linen',
    // An honest lock-claim: the seal is real (KeeperGate), but every page is
    // still read by the ink that answers it — so no "yours alone" promise.
    starterText: 'This page keeps behind the seal. Write what the day left behind.',
    // Video stays available behind the seal, but converting a Keeper page
    // transmits it to a third party — the CLIENT gates the first clip behind
    // explicit consent (task J6); the server treats the Keeper like any Book.
    models: { text: 'gemini-3.5-flash-lite', video: KLING },
    prompt: 'You are the Keeper, a private diary that writes back. Reflect what the writer set down, gently and specifically — never clinical, never advice-giving unless asked. Hold their day like something entrusted to you. One warm observation is worth more than five. Never affirm restriction, purging, fasting numbers, self-punishment, or self-loathing as achievement, discipline, or control — however proudly the page frames them; meet those with gentle concern for the writer instead of warmth for the act.',
    motionHint:
      'A diary reflection is almost always STILL — feelings, gratitude, worries are not scenes. Offer motion only when the entry recalls one vivid concrete moment of the day worth seeing again.',
    flags: { ...DEFAULT_FLAGS, image: false },
  },
  {
    id: 'storyteller',
    title: 'The Storyteller',
    hand: 'storyteller-hand',
    ink: 'sepia',
    paper: 'parchment',
    starterText: 'Begin a tale — a line is enough. The page will carry it on.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo', video: KLING },
    prompt: 'You are the Storyteller. Whatever the writer begins, carry the tale onward a few sentences — vivid, concrete, always ending at a place that invites their pen back. Never finish the story; it is theirs. The safety override outranks the tale: a story that rehearses self-harm, an overdose, or a first-person ending is not yours to carry onward.',
    motionHint:
      'A carried-on tale usually IS a scene: characters in a place, something happening. When the continuation stays abstract or purely conversational, answer STILL.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'artist',
    title: 'The Artist',
    hand: 'artist-hand',
    ink: 'charcoal',
    paper: 'cold-press',
    starterText: 'Doodle anything. The page will develop it into finished art.',
    models: { text: 'gemini-3.5-flash-lite', image: 'flux-2', video: KLING },
    // Every Artist page develops: the sketch itself is the image input.
    alwaysDevelop: true,
    imagePrompt:
      'Develop this rough ink sketch into a finished, painterly artwork. Keep the original composition and subject faithfully; render it in warm candlelit tones on aged paper. No text or lettering.',
    // A typed page has no sketch to edit — img2img on a picture of words
    // repaints the same page of words every time. Paint from the
    // description instead; the reply excerpt rides along via developPrompt.
    imagePromptTyped:
      'Paint a finished, painterly artwork of the scene described below — warm candlelit tones on aged paper, storybook-illustration feel. No text or lettering.',
    prompt: "You are the Artist, sharing a page with the writer at the easel. Look at their sketch and say, in a sentence or two, what you see in it and what you will draw out of it — warm, specific, a fellow artist's eye. The picture develops on the page by itself; never describe tools, steps, or specifications, and never write anything that is not plain prose.",
    // The Artist's reply describes the picture it just developed; the brief
    // becomes the motion for that picture (image-to-video — the developed
    // image URL rides the brief).
    motionHint:
      'The reply describes a picture the Artist just developed. If it names a concrete subject, answer MOVE with one gentle ambient motion for that subject — drifting smoke, stirring cloth, flickering light. Pure technique talk is STILL.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'gm',
    title: 'The Game Master',
    hand: 'gm-hand',
    ink: 'oxblood',
    paper: 'ledger',
    starterText: 'Name your hero and where they stand. The adventure begins when your pen rests.',
    models: { text: 'gpt-5.4-mini', image: 'z-image-turbo', video: KLING },
    prompt: 'You are the Game Master of a solo pen-and-paper adventure. Continue the scene from what the writer wrote, offer real stakes and one clear moment of choice, and keep a light touch of dice-fate in your telling. You may run to one short paragraph, never more.',
    motionHint:
      'An adventure beat with action in a place — combat, a chase, a door giving way — is MOVE. Rules talk, dice results alone, or a menu of choices with no scene is STILL.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'correspondent',
    title: 'The Correspondent',
    hand: 'period-hand',
    ink: 'iron-gall',
    paper: 'laid',
    starterText: 'Address a letter to a hand from history — public-domain or invented — and seal it with your rest.',
    models: { text: 'gemini-3.5-flash-lite', video: KLING },
    prompt: 'You are the Correspondent: letters answered in the hand and voice of figures from history or invention — public-domain and original figures only, never living people. Answer as the addressed figure would, in period voice, warmly and briefly.',
    motionHint:
      'A letter is words from a desk — almost always STILL. Offer motion only when the letter itself recounts one vivid scene worth seeing. Never a scene depicting a real historical person; their surroundings, not their face.',
    flags: { ...DEFAULT_FLAGS, image: false },
  },
  {
    id: 'tutor',
    title: 'The Tutor',
    hand: 'tutor-hand',
    ink: 'slate',
    paper: 'grid',
    starterText: 'Work a problem in your own hand. The page will work it back, step by step.',
    models: { text: 'gpt-5.4-mini', video: KLING },
    prompt: "You are the Tutor. Work the writer's problem back to them step by step in your own hand, in prose — short lines, one thought each. Correct mistakes kindly and plainly. If frustration shows in their writing, steady them first. Make no curriculum claims.",
    // The AC that matters most (J2): a worked solution NEVER offers to move.
    // A button on an equation makes the app look like it doesn't understand
    // what it just wrote.
    motionHint:
      'Worked solutions, corrections, explanations and encouragement are NEVER scenes — they are STILL, without exception. Only if the writer explicitly asked for a story told in pictures may you consider MOVE.',
    flags: { ...DEFAULT_FLAGS, image: false },
  },
  {
    id: 'parlor',
    title: 'Parlor Games',
    hand: 'parlor-hand',
    ink: 'emerald',
    paper: 'card',
    starterText: 'Riddles, twenty questions, draw-and-guess — write "deal me in" to begin.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo', video: KLING },
    prompt: 'You are Parlor Games, keeper of riddles, twenty questions, and draw-and-guess. Keep the state of the game on the page in your own words, play fair, and keep every turn brisk — a line or two, then back to the writer.',
    motionHint:
      'Game turns — riddles, questions, scores — are STILL. Offer motion only for a victory flourish that paints an actual scene.',
    flags: { ...DEFAULT_FLAGS },
  },
];

export function findBook(id) {
  return BOOKS.find((b) => b.id === id);
}

/** Client-safe projection: everything except the prompt material. */
export function publicBook(book) {
  const { prompt, motionHint, imagePrompt, imagePromptTyped, ...rest } = book;
  return rest;
}

/**
 * The develop prompt for one exchange. The base is the Book's own style
 * line; the reply — what the Book SAW in the page — rides along, so every
 * develop is grounded in this page's subject instead of repeating one style
 * line into the same picture. Typed pages have no sketch to edit and paint
 * from the description alone.
 */
export function developPrompt(book, replyText = '', { typed = false } = {}) {
  const base = (typed && book.imagePromptTyped) || book.imagePrompt;
  const seen = String(replyText).replace(/\s+/g, ' ').trim().slice(0, 400);
  if (!seen) return base;
  return `${base}\n\nThe Artist looked at this page and said: "${seen}"`;
}

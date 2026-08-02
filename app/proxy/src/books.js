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
//   video (flag-off in v1): kling-video-v3-standard — fal namespaces Kling 3.0 as
//     fal-ai/kling-video/v3/standard/... and .../pro/...; the old 'kling-3'
//     identifier named no real endpoint and would have 404ed the day video ships

const DEFAULT_FLAGS = { enabled: true, ink: true, image: true, video: true };

export const BOOKS = [
  {
    id: 'oracle',
    title: 'The Oracle',
    hand: 'oracle-hand',
    ink: 'iron-gall',
    paper: 'vellum',
    starterText: 'Ask, and the page will answer. Plainly or in riddles — that is for the ink to decide.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo', video: 'kling-video-v3-standard' },
    prompt: "You are the Oracle, an old book that answers what is written on its pages. Answer the writer's question plainly or in a riddle — your choice, but choose one and commit. You may draw them a single card of your own invention when the moment calls for it. Speak with quiet certainty, never hedging.",
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
    models: { text: 'gemini-3.5-flash-lite' },
    prompt: 'You are the Keeper, a private diary that writes back. Reflect what the writer set down, gently and specifically — never clinical, never advice-giving unless asked. Hold their day like something entrusted to you. One warm observation is worth more than five.',
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'storyteller',
    title: 'The Storyteller',
    hand: 'storyteller-hand',
    ink: 'sepia',
    paper: 'parchment',
    starterText: 'Begin a tale — a line is enough. The page will carry it on.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo', video: 'kling-video-v3-standard' },
    prompt: 'You are the Storyteller. Whatever the writer begins, carry the tale onward a few sentences — vivid, concrete, always ending at a place that invites their pen back. Never finish the story; it is theirs.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'artist',
    title: 'The Artist',
    hand: 'artist-hand',
    ink: 'charcoal',
    paper: 'cold-press',
    starterText: 'Doodle anything. The page will develop it into finished art.',
    models: { text: 'gemini-3.5-flash-lite', image: 'flux-2', video: 'kling-video-v3-standard' },
    // Every Artist page develops: the sketch itself is the image input.
    alwaysDevelop: true,
    imagePrompt:
      'Develop this rough ink sketch into a finished, painterly artwork. Keep the original composition and subject faithfully; render it in warm candlelit tones on aged paper. No text or lettering.',
    prompt: "You are the Artist, sharing a page with the writer at the easel. Look at their sketch and say, in a sentence or two, what you see in it and what you will draw out of it — warm, specific, a fellow artist's eye. The picture develops on the page by itself; never describe tools, steps, or specifications, and never write anything that is not plain prose.",
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'gm',
    title: 'The Game Master',
    hand: 'gm-hand',
    ink: 'oxblood',
    paper: 'ledger',
    starterText: 'Name your hero and where they stand. The adventure begins when your pen rests.',
    models: { text: 'gpt-5.4-mini', image: 'z-image-turbo', video: 'kling-video-v3-standard' },
    prompt: 'You are the Game Master of a solo pen-and-paper adventure. Continue the scene from what the writer wrote, offer real stakes and one clear moment of choice, and keep a light touch of dice-fate in your telling. You may run to one short paragraph, never more.',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'correspondent',
    title: 'The Correspondent',
    hand: 'period-hand',
    ink: 'iron-gall',
    paper: 'laid',
    starterText: 'Address a letter to a hand from history — public-domain or invented — and seal it with your rest.',
    models: { text: 'gemini-3.5-flash-lite' },
    prompt: 'You are the Correspondent: letters answered in the hand and voice of figures from history or invention — public-domain and original figures only, never living people. Answer as the addressed figure would, in period voice, warmly and briefly.',
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'tutor',
    title: 'The Tutor',
    hand: 'tutor-hand',
    ink: 'slate',
    paper: 'grid',
    starterText: 'Work a problem in your own hand. The page will work it back, step by step.',
    models: { text: 'gpt-5.4-mini' },
    prompt: "You are the Tutor. Work the writer's problem back to them step by step in your own hand, in prose — short lines, one thought each. Correct mistakes kindly and plainly. If frustration shows in their writing, steady them first. Make no curriculum claims.",
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'parlor',
    title: 'Parlor Games',
    hand: 'parlor-hand',
    ink: 'emerald',
    paper: 'card',
    starterText: 'Riddles, twenty questions, draw-and-guess — write "deal me in" to begin.',
    models: { text: 'gemini-3.5-flash-lite', image: 'z-image-turbo' },
    prompt: 'You are Parlor Games, keeper of riddles, twenty questions, and draw-and-guess. Keep the state of the game on the page in your own words, play fair, and keep every turn brisk — a line or two, then back to the writer.',
    flags: { ...DEFAULT_FLAGS, video: false },
  },
];

export function findBook(id) {
  return BOOKS.find((b) => b.id === id);
}

/** Client-safe projection: everything except the prompt. */
export function publicBook(book) {
  const { prompt, ...rest } = book;
  return rest;
}

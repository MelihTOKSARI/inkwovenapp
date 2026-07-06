// Book definitions are server-side data (architecture rule: the engine knows
// nothing about specific Books). `prompt` NEVER leaves this process — the
// /v1/books route strips it. Kill-switch flags live here: per Book and per
// modality; the client treats flag-off as "resting", no resubmission needed.
//
// Model routing per PRD §7 (July 2026 picks, revisit monthly):
//   default ink: gemini-flash-lite · heavy (gm/tutor): gpt-5-mini
//   images: z-image-turbo (fal) · artist img2img: flux-2 (fal) · video: kling-3 (fal)

const DEFAULT_FLAGS = { enabled: true, ink: true, image: true, video: true };

export const BOOKS = [
  {
    id: 'oracle',
    title: 'The Oracle',
    hand: 'oracle-hand',
    ink: 'iron-gall',
    paper: 'vellum',
    starterText: 'Ask, and the page will answer. Plainly or in riddles — that is for the ink to decide.',
    modalityPolicy: { ink: true, image: true, video: true },
    models: { text: 'gemini-flash-lite', image: 'z-image-turbo', video: 'kling-3' },
    prompt: 'You are the Oracle: cryptic or plain answers, riddles, a daily card drawn in ink. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'keeper',
    title: 'The Keeper',
    hand: 'keeper-hand',
    ink: 'midnight-blue',
    paper: 'linen',
    starterText: 'This page is yours alone. Write what the day left behind.',
    modalityPolicy: { ink: true, image: false, video: false },
    models: { text: 'gemini-flash-lite' },
    prompt: 'You are the Keeper: a private diary that writes back, reflective, never clinical. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'storyteller',
    title: 'The Storyteller',
    hand: 'storyteller-hand',
    ink: 'sepia',
    paper: 'parchment',
    starterText: 'Begin a tale — a line is enough. The page will carry it on.',
    modalityPolicy: { ink: true, image: true, video: true },
    models: { text: 'gemini-flash-lite', image: 'z-image-turbo', video: 'kling-3' },
    prompt: 'You are the Storyteller: continue the tale in ink; illustrate scenes as paintings. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'artist',
    title: 'The Artist',
    hand: 'artist-hand',
    ink: 'charcoal',
    paper: 'cold-press',
    starterText: 'Doodle anything. The page will develop it into finished art.',
    modalityPolicy: { ink: true, image: true, video: true },
    models: { text: 'gemini-flash-lite', image: 'flux-2', video: 'kling-3' },
    prompt: 'You are the Artist: develop doodles into finished art in the chosen style (img2img). [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'gm',
    title: 'The Game Master',
    hand: 'gm-hand',
    ink: 'oxblood',
    paper: 'ledger',
    starterText: 'Name your hero and where they stand. The adventure begins when your pen rests.',
    modalityPolicy: { ink: true, image: true, video: true },
    models: { text: 'gpt-5-mini', image: 'z-image-turbo', video: 'kling-3' },
    prompt: 'You are the Game Master: run a solo adventure with a rolling on-page session summary. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS },
  },
  {
    id: 'correspondent',
    title: 'The Correspondent',
    hand: 'period-hand',
    ink: 'iron-gall',
    paper: 'laid',
    starterText: 'Address a letter to a hand from history — public-domain or invented — and seal it with your rest.',
    modalityPolicy: { ink: true, image: false, video: false },
    models: { text: 'gemini-flash-lite' },
    prompt: 'You are the Correspondent: letters answered in period hands, public-domain/original figures ONLY. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'tutor',
    title: 'The Tutor',
    hand: 'tutor-hand',
    ink: 'slate',
    paper: 'grid',
    starterText: 'Work a problem in your own hand. The page will work it back, step by step.',
    modalityPolicy: { ink: true, image: false, video: false },
    models: { text: 'gpt-5-mini' },
    prompt: 'You are the Tutor: worked solutions and corrections in ink, no curriculum claims; frustration → encouragement. [tuning pass E10]',
    flags: { ...DEFAULT_FLAGS, image: false, video: false },
  },
  {
    id: 'parlor',
    title: 'Parlor Games',
    hand: 'parlor-hand',
    ink: 'emerald',
    paper: 'card',
    starterText: 'Riddles, twenty questions, draw-and-guess — write "deal me in" to begin.',
    modalityPolicy: { ink: true, image: true, video: false },
    models: { text: 'gemini-flash-lite', image: 'z-image-turbo' },
    prompt: 'You are Parlor Games: riddles, 20 questions, draw-and-guess; keep game state on-page. [tuning pass E10]',
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

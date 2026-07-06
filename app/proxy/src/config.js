// Server-tunable knobs (GET /v1/config): the client fetches these at launch
// and on foreground — cap and cooldown changes ship without an app release.
export const CONFIG = {
  freeMomentsPerDay: 5,
  plusImageDailySoftCap: 20,
  // Cooldown per image past the soft cap; last entry repeats.
  cooldownCurveSeconds: [60, 300, 900, 3600],
  rateLimits: {
    exchangesPerUserPerMinute: 30,
    exchangesPerIPPerMinute: 60,
  },
  onboardingCreditGrant: 1,
};

# Inkwoven Privacy Policy

**Effective date:** August 1, 2026
**Developer:** Melih Toksari (individual developer)
**Contact:** swareisland@gmail.com

This policy is written to be read, not skimmed past. It describes exactly what the
Inkwoven app does with your writing, in plain language. If anything here is unclear,
write to the address above.

## What Inkwoven is

Inkwoven is a notebook app for iPad and iPhone. You write or draw on a page by hand;
the page answers with AI-generated fiction — a written reply, or a picture. To
produce those answers, some of what you put on the page has to leave your device.
This policy is mostly about that.

## What stays on your device

Everything, by default. Your pages — the ink strokes, the replies, the pictures —
are stored locally on your device. So are your settings, the signature you write
during onboarding, and the Keeper's lock state. Inkwoven has no accounts and no
cloud sync: we do not keep a copy of your notebook anywhere. (Your pages may be
included in your own device backups, such as iCloud device backup, which you control
through iOS — that is between you and Apple, and we have no access to it.)

## What leaves your device, and when

When you finish writing and the pen rests, the app sends the following to our relay
server (the "Inkwoven proxy") so a reply can be generated:

- **A snapshot of your handwriting or doodle** — an image of the part of the page
  you just wrote or drew. Whatever you wrote in it is in it: if you write your name,
  an address, or anything private on a page, that content travels with the snapshot.
- **Typed text**, in the few places typing is allowed (the Oracle on iPhone, and the
  keyboard fallback when no pencil is available).
- **Limited page context** — the text of the page's earlier ink in the current
  session, and brief summaries the notebook keeps of earlier pages where a Book
  uses them, so replies can stay coherent.
- **A pseudonymous device token** — a random identifier created on your device the
  first time the app runs, stored in the device Keychain. It lets our server apply
  fair-use limits per install. It is not your name, email, or Apple ID, and we have
  no way to connect it to you as a person.

**Speculative upload:** to make replies feel instant, the app may upload the
snapshot about 2 seconds after your pen rests — before the reply is actually
requested. If you start writing again, that upload is cancelled or simply expires
unused on the server within about a minute. If you do continue to the reply, the
already-uploaded snapshot is used.

The only other time anything leaves your device is a report you choose to file
about a reply — see "Reporting a reply" below.

## Who receives it

Two hops, both solely to generate your reply:

1. **The Inkwoven proxy** — a small relay server we operate. It holds the AI
   providers' API keys, applies rate limits, and forwards your page to the model.
2. **AI providers, acting as processors for generation only:** Google (Gemini
   models) for most written replies, OpenAI for some Books' written replies, and
   fal.ai for generated pictures. They receive the snapshot and context needed to
   compose the answer, handle it under their API terms, and act as processors for
   Inkwoven — we do not give any of them permission to use your content for
   advertising, and we do not send them your device token's history, your other
   pages, or anything beyond what the single exchange needs.

## What we do NOT collect

- No account and no sign-in — we cannot identify you and do not try.
- No advertising, no ad networks, no trackers, no fingerprinting.
- No analytics profiles of your writing.
- No location, contacts, photos, or microphone access.
- We never sell your data, and never share it with anyone except the AI providers
  above, for the sole purpose of answering your page.

## The Keeper's lock, clarified

The Keeper is the private diary Book, locked with Face ID or your device passcode.
That lock is a **device-side** lock: it stops other people who hold your iPad from
opening the Book. It is not an upload exemption — when a Keeper page answers, its
snapshot and context travel the same path described above, because that is the only
way any page can answer. If you want writing that never leaves the device at all,
write on a page and delete it without waiting for a reply, or keep that writing
outside Inkwoven.

## Reporting a reply

If a reply is offensive, wrong, or otherwise misbehaves, you can report it: touch
and hold the reply on the page and choose "Report this reply." Reporting is the
one way any page content is ever stored on our server, and it happens only
because you asked:

- **Only ever user-initiated.** Nothing is reported automatically — no sampling,
  no background flagging, no quiet telemetry of your pages. A report exists
  because you pressed send, or it does not exist.
- **What a report sends** — named on the report sheet before you send it: the
  reply you are reporting, an image of your strokes from that page, which Book it
  came from, when it was written, your chosen reason, and your optional note.
  Reporting a Keeper page shows a stronger notice first, because that page is
  otherwise sealed on your device.
- **Nothing leaves until you press send.** Dismissing the sheet sends nothing;
  a failed send is not retried behind your back.
- **Deleted after 90 days.** Reports are kept so a human can review them, and
  the server deletes them 90 days after they are filed. A report's content never
  appears in server logs — the log records only that a report with some reason
  was filed.

## Retention

- **On your device:** pages stay until you delete them.
- **On the Inkwoven proxy:** your page content is not retained after the exchange
  is served. Snapshots exist on the server only as short-lived working data — a
  speculative upload is deleted the moment it is used, and expires on its own
  within about a minute if it never is. With a single exception — a report you
  choose to file, described under "Reporting a reply" — page content is not
  written to the proxy's logs or its database. What the proxy does keep is
  bookkeeping tied to the random device token: fair-use counters that expire
  within minutes, and a small ledger of granted and spent credits — none of which
  contains anything you wrote.
- **Reports you file:** kept for human review, deleted 90 days after filing.
- **At the AI providers:** they process your content to produce the reply, under
  their respective API terms, which govern their systems — we cannot make promises
  on their behalf. What we can promise is what we send: only the single exchange's
  snapshot and context, with a random token, and nothing that identifies you.

## Your controls

- **Delete all pages** — in the Drawer (settings). This tears out every page in
  every Book, immediately and unrecoverably.
- **Tear out a single page** — remove any individual page from the notebook.
- **Export** — take your pages with you as PDF or text, from the Drawer.
- **The Keeper lock** — Face ID/passcode protection for your private Book.
- **Stop anytime** — deleting the app removes the notebook and its token from your
  device.

## Purchases

Subscriptions are bought through Apple. Apple handles all payment; we never see
your payment details, name, or billing address. Manage or cancel subscriptions in
your App Store account settings.

## Children

Inkwoven is not directed at children under 13, and its App Store rating reflects
that its AI-generated fiction is intended for teens and adults.

## Crisis situations

If your writing suggests you are in crisis, the app sets its fiction aside and
shows a plain screen with real support resources. This routing happens as part of
generating a reply, through the same path described above; it does not create any
additional record about you.

## Changes to this policy

If this policy changes in a way that matters — new data leaving the device, new
recipients, new retention — we will update this page and its effective date before
the change ships. The current version always lives at this URL.

## Contact

Questions, concerns, or requests: swareisland@gmail.com.

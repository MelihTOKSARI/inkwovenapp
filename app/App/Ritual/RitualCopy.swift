import InkCore

/// The nightly lines, spoken in the voice of the Book the writer last opened.
/// The title stays constant and plain — the body carries the voice. Four lines
/// per Book, dealt by the day's ordinal: consecutive nights never repeat, and
/// a line comes back no sooner than four nights on (a four-line pool cannot
/// promise seven distinct nights, so the rotation maximises distance instead).
enum RitualCopy {
    static let title = "The evening page"

    static func line(for book: BookID, night ordinal: Int) -> String {
        let pool = lines[book] ?? keeperLines
        let index = ((ordinal % pool.count) + pool.count) % pool.count
        return pool[index]
    }

    /// The Keeper is the fallback voice — the Book a writer with no history
    /// would meet a diary in.
    private static let keeperLines = [
        "The day is not yet written. The seal waits for your hand.",
        "Whatever today left behind, the page will keep it.",
        "A quiet page waits behind the seal.",
        "Days fade by morning. Written ones do not.",
    ]

    private static let lines: [BookID: [String]] = [
        .oracle: [
            "The candle is lit. Ask, and be answered slant.",
            "Tonight's answer waits on tonight's question.",
            "The ink knows something it will only say sideways.",
            "Ask once, before the wick burns low.",
        ],
        .keeper: keeperLines,
        .storyteller: [
            "The page leans in to listen. Once, there was…",
            "The story stopped at dusk, where the road forks.",
            "Tonight's chapter still wants its first line.",
            "The lantern is trimmed, and the tale half-told.",
        ],
        .artist: [
            "The dark is mixed. Describe the day in a breath.",
            "Show me what today looked like, and I will see it too.",
            "Something from today is still waiting to develop.",
            "One line from you, and I will mix the rest.",
        ],
        .gameMaster: [
            "The torches gutter. The party waits on your word.",
            "You left the cave unmapped. The lantern stands ready.",
            "The dice lie where you left them. Your move.",
            "Night falls on the camp, and the watch is yours.",
        ],
        .correspondent: [
            "The writing desk is lit, and the inkwell full.",
            "A letter begun is easier to finish than to forget.",
            "Unanswered letters keep. Unwritten ones do not.",
            "The evening post has gone; the page has not.",
        ],
        .tutor: [
            "What shall we learn tonight?",
            "One question, taken apart together, before the candle goes.",
            "The evening always has room for one more why.",
            "Sit. The lesson is whatever you bring.",
        ],
        .parlor: [
            "The table is set and the cards are warm.",
            "One round before the candles are snuffed.",
            "The parlor keeps a chair for you.",
            "The game is afoot, and your seat is empty.",
        ],
    ]
}

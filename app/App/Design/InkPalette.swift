import SwiftUI

// Design tokens from design/claude-design-handoff/tokens.json and the
// Inkwoven.dc.html handoff. Two room variants (candlelight / daylight)
// drive everything outside the parchment page.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Approximation of CSS `color-mix(in oklab, a p%, b)` used throughout
    /// the handoff for spine gradients and per-book ink.
    static func mix(_ a: UInt32, _ p: Double, _ b: UInt32) -> Color {
        func c(_ h: UInt32, _ shift: UInt32) -> Double { Double((h >> shift) & 0xFF) / 255 }
        return Color(
            .sRGB,
            red: c(a, 16) * p + c(b, 16) * (1 - p),
            green: c(a, 8) * p + c(b, 8) * (1 - p),
            blue: c(a, 0) * p + c(b, 0) * (1 - p)
        )
    }
}

enum Ink {
    static let parchment = Color(hex: 0xF4EAD5)
    static let parchmentBright = Color(hex: 0xFBF3DF)
    static let parchmentDeep = Color(hex: 0xE7D7B4)
    static let ink = Color(hex: 0x2E2418)
    static let inkFaded = Color(hex: 0x6B5A43)
    static let room = Color(hex: 0x17110B)
    static let roomRaised = Color(hex: 0x241B12)
    static let candle = Color(hex: 0xC9962E)
    static let candleBright = Color(hex: 0xE8B84B)
    static let wax = Color(hex: 0x7A2E2B)
    static let waxDeep = Color(hex: 0x5C211F)
    static let successHerb = Color(hex: 0x4A5D3A)
    static let dangerEmber = Color(hex: 0x8C3B2E)
    static let sealIvory = Color(hex: 0xE7CFA0)
    static let goldTitleTop = Color(hex: 0xF4E6BD)
}

enum RoomVariant: String, Codable {
    case candlelight, daylight
}

/// Resolved room palette; matches the CSS custom properties in the handoff.
struct RoomTheme {
    let variant: RoomVariant
    let bgInner: Color
    let bgMid: Color
    let bgOuter: Color
    let heading: Color
    let text: Color
    let dim: Color
    let accent: Color
    let cardTop: Color
    let cardBottom: Color
    let ledgeTop: Color
    let ledgeMid: Color
    let ledgeBottom: Color
    let bar: Color
    let logoFrom: Color
    let logoTo: Color
    let logoSub: Color
    let whisperInk: Color
    let whisperBG: Color
    let vignette: Color
    let oracleBloom: Color

    static let candlelight = RoomTheme(
        variant: .candlelight,
        bgInner: Color(hex: 0x241A11), bgMid: Color(hex: 0x17110B), bgOuter: Color(hex: 0x0E0906),
        heading: Color(hex: 0xE8B84B), text: Color(hex: 0xE7D9BF),
        dim: Color(hex: 0x9A876A), accent: Color(hex: 0xC9962E),
        cardTop: Color(hex: 0x241B12), cardBottom: Color(hex: 0x1A130C),
        ledgeTop: Color(hex: 0x3A2C1B), ledgeMid: Color(hex: 0x241A10), ledgeBottom: Color(hex: 0x160F09),
        bar: Color(hex: 0x140E09, opacity: 0.82),
        logoFrom: Color(hex: 0xF4E3B0), logoTo: Color(hex: 0xD4A43A), logoSub: Color(hex: 0x9A876A),
        whisperInk: Color(hex: 0xF4E2AC), whisperBG: Color(hex: 0x120C07, opacity: 0.66),
        vignette: Color.black.opacity(0.5),
        oracleBloom: Color(hex: 0xE8B84B, opacity: 0.5)
    )

    // Daylight re-inked for WCAG AA body (audit A-5): the old dim #7A6544 on
    // bgOuter #BDA478 measured 2.32:1 — below even the 3:1 non-text floor —
    // exactly where the Drawer renders body copy on a 13" iPad in landscape.
    // The outer gradient stop is clamped lighter and dim/accent/heading are
    // darkened; every pair now measures ≥4.5:1 on its worst background
    // (dim 4.87, accent 5.00, heading 4.99, text 6.78). Candlelight passes
    // as it always did and is untouched.
    static let daylight = RoomTheme(
        variant: .daylight,
        bgInner: Color(hex: 0xE9DCBE), bgMid: Color(hex: 0xD8C39C), bgOuter: Color(hex: 0xD0B990),
        heading: Color(hex: 0x653C10), text: Color(hex: 0x3D2F1F),
        dim: Color(hex: 0x554526), accent: Color(hex: 0x613E0D),
        cardTop: Color(hex: 0xF7EFD9), cardBottom: Color(hex: 0xE6D7B7),
        ledgeTop: Color(hex: 0xB79F70), ledgeMid: Color(hex: 0x9C8154), ledgeBottom: Color(hex: 0x7D6540),
        bar: Color(hex: 0xE9DDC1, opacity: 0.82),
        logoFrom: Color(hex: 0x8A5411), logoTo: Color(hex: 0x5A3409), logoSub: Color(hex: 0x6B5330),
        whisperInk: Color(hex: 0x553714), whisperBG: Color(hex: 0xFAF4E4, opacity: 0.92),
        vignette: Color(hex: 0x4A361A, opacity: 0.24),
        oracleBloom: Color(hex: 0x96601A, opacity: 0.34)
    )

    var roomBackground: some View {
        RadialGradient(
            colors: [bgInner, bgMid, bgOuter],
            center: UnitPoint(x: 0.26, y: 0.04),
            startRadius: 0,
            endRadius: 1100
        )
    }
}

private struct RoomThemeKey: EnvironmentKey {
    static let defaultValue = RoomTheme.candlelight
}

extension EnvironmentValues {
    var room: RoomTheme {
        get { self[RoomThemeKey.self] }
        set { self[RoomThemeKey.self] = newValue }
    }
}

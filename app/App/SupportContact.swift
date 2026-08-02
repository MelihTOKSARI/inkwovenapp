import Foundation

/// The published support address (App Review guideline 1.2). Defined once —
/// every surface that names it, the Drawer's "Write to the binder" row today,
/// reads this constant; the string appears nowhere else in code.
enum SupportContact {
    static let email = "swareisland@gmail.com"
    // Force-unwrapped on a compile-time literal only, per the DI.swift rule:
    // the string is fixed in source and provably parses.
    static var mailURL: URL { URL(string: "mailto:\(email)")! }
}

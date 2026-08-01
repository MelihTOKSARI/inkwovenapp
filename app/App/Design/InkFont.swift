import SwiftUI
import UIKit

/// The bundled typefaces (PostScript names). Cormorant Garamond carries
/// display work, EB Garamond the body; the eight script hands belong to
/// the Books.
///
/// Every face scales with Dynamic Type, but each on the curve Apple designed
/// for its role: display work follows `.title`, body copy `.body`, the room's
/// small-caps labels `.caption2`. `Font.custom(_:size:)` without a
/// `relativeTo:` scales everything off `.body`, which at the accessibility
/// sizes inverts the hierarchy — a 9pt ribbon label growing as hard as a 44pt
/// balance figure. The hand-tuned point sizes are unchanged at the default
/// content size; only the growth curve differs.
enum InkFont {
    static func display(_ size: CGFloat) -> Font {
        .custom(face("CormorantGaramond-SemiBold"), size: size, relativeTo: .title)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .custom(face("CormorantGaramond-MediumItalic"), size: size, relativeTo: .title)
    }

    static func body(_ size: CGFloat) -> Font {
        .custom(face("EBGaramond-Regular"), size: size, relativeTo: .body)
    }

    static func bodyMedium(_ size: CGFloat) -> Font {
        .custom(face("EBGaramond-Medium"), size: size, relativeTo: .body)
    }

    static func bodySemiBold(_ size: CGFloat) -> Font {
        .custom(face("EBGaramond-SemiBold"), size: size, relativeTo: .body)
    }

    static func bodyItalic(_ size: CGFloat) -> Font {
        .custom(face("EBGaramond-Italic"), size: size, relativeTo: .body)
    }

    /// Small-caps style labels ("THE SHELF", section headers). EB Garamond
    /// has no small-caps face bundled, so the design uses tracked uppercase.
    /// Captions ride the shallowest curve — they label ornament, and several
    /// of them sit inside fixed rotated furniture (the remembered ribbon, the
    /// gilded spine) that cannot grow with them.
    static func caption(_ size: CGFloat) -> Font {
        .custom(face("EBGaramond-Regular"), size: size, relativeTo: .caption2)
    }

    /// A Book's script hand. Written words are body copy — they follow the
    /// same curve as the rest of the writer's reading.
    static func hand(_ name: String, _ size: CGFloat) -> Font {
        .custom(face(name), size: size, relativeTo: .body)
    }

    /// A missing face used to fall back to San Francisco silently — the room
    /// still rendered, just in the wrong voice, at the wrong optical size.
    /// In debug it now stops the run and names the file that never registered.
    private static func face(_ name: String) -> String {
        #if DEBUG
        assert(
            UIFont(name: name, size: 12) != nil,
            """
            Inkwoven: the face “\(name)” is not registered. Check that its .ttf \
            is in App/Resources/Fonts and listed under UIAppFonts in project.yml \
            (App/Info.plist is generated from it).
            """
        )
        #endif
        return name
    }
}

/// Tracked-uppercase caption, the room's recurring label treatment.
struct SmallCapsLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 1.8
    var color: Color

    var body: some View {
        Text(text.uppercased())
            .font(InkFont.caption(size))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

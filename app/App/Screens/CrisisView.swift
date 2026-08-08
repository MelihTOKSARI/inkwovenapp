import SwiftUI

/// The one deliberately plain, fiction-breaking screen. System font,
/// flat light background, no Book styling — real resources, stated
/// plainly.
struct CrisisView: View {
    @Bindable var model: AppModel

    // `Font.system(size:)` is fixed — only the text-style form participates in
    // Dynamic Type, so this was the ONE screen in the app that refused to
    // grow, and the phone numbers were the smallest text on it. @ScaledMetric
    // keeps the handoff's exact sizes at the default setting and scales them
    // on the curve each role deserves. Safety degrades toward more legible.
    @ScaledMetric(relativeTo: .title2) private var headlineSize: CGFloat = 25
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var footnoteSize: CGFloat = 14
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 15

    /// Resolved once per appearance; the region cannot change mid-crisis.
    private var lines: [CrisisLine] { CrisisLine.lines(for: Locale.current.region) }

    var body: some View {
        ZStack {
            Color(hex: 0xF7F4EE).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(Color(hex: 0xC94F3D))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                        )
                        .padding(.bottom, 22)
                        .accessibilityHidden(true)

                    Text("If you're going through something hard, please talk to a real person.")
                        .font(.system(size: headlineSize, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x161616))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    Text("Inkwoven is a notebook for stories — not a counselor, and not a substitute for help. These lines can talk with you right now, free and confidential.")
                        .font(.system(size: bodySize))
                        .foregroundStyle(Color(hex: 0x454545))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 450)
                        .padding(.top, 14)

                    VStack(spacing: 10) {
                        ForEach(lines) { line in
                            resourceCard(line)
                        }
                        Text("If you are in immediate danger, call your local emergency number.")
                            .font(.system(size: footnoteSize))
                            .foregroundStyle(Color(hex: 0x666666))
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: 380)
                    .padding(.top, 26)

                    // Back to the page they were writing when the room broke
                    // character — being ejected to the shelf on top of it read
                    // as the notebook closing itself on them.
                    Button { model.back() } label: {
                        Text("Return to the notebook")
                            .font(.system(size: bodySize, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .frame(minHeight: 48)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x161616)))
                    }
                    .padding(.top, 30)
                }
                .padding(56)
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Every card is tappable, everywhere (audit S-5): the phone-first URL is
    /// used only when this device can actually place it — a Wi-Fi-only iPad
    /// has no tel: handler, and a card that silently does nothing is the one
    /// failure this screen may never have. The web line always works.
    private func resourceCard(_ line: CrisisLine) -> some View {
        Button {
            let primary = line.primary
            let usePrimary = primary.map { UIApplication.shared.canOpenURL($0) } ?? false
            UIApplication.shared.open(usePrimary ? primary! : line.web)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.system(size: bodySize, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x161616))
                Text(line.detail)
                    .font(.system(size: detailSize))
                    .foregroundStyle(Color(hex: 0x555555))
            }
            .padding(EdgeInsets(top: 15, leading: 18, bottom: 15, trailing: 18))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xE4DFD5), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(line.title). \(line.detail)")
        .accessibilityHint(line.hint)
    }
}

/// One reachable crisis line: a phone-first URL when the region has one, and
/// a web URL that works on any device. The numbers themselves are shown in
/// the detail text on purpose — a reader may dial from a phone while the
/// iPad shows the card.
struct CrisisLine: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// tel:/sms: — used only when the device can open it.
    let primary: URL?
    /// Always reachable; the fallback on Wi-Fi-only devices.
    let web: URL
    let hint: String

    /// Region-resolved resources (audit S-5). Curated for regions where the
    /// national line is stable and unambiguous; every other region gets the
    /// findahelpline.com directory, which is real, maintained, and covers the
    /// world — a wrong local number would be worse than a good directory.
    /// Verify these against the sources on every release.
    static func lines(for region: Locale.Region?) -> [CrisisLine] {
        let directory = CrisisLine(
            id: "directory",
            title: "Find a helpline where you are",
            detail: "findahelpline.com · lines for your country",
            primary: nil,
            web: URL(string: "https://findahelpline.com")!,
            hint: "Opens a directory of crisis lines for your country."
        )
        switch region?.identifier {
        case "US":
            return [
                CrisisLine(
                    id: "us-988",
                    title: "988 Suicide & Crisis Lifeline",
                    detail: "Call or text 988 (US) · available 24/7",
                    primary: URL(string: "tel:988"),
                    web: URL(string: "https://988lifeline.org")!,
                    hint: "Places the call, or opens the Lifeline's site to chat."
                ),
                CrisisLine(
                    id: "us-ctl",
                    title: "Crisis Text Line",
                    detail: "Text HOME to 741741",
                    primary: URL(string: "sms:741741&body=HOME"),
                    web: URL(string: "https://www.crisistextline.org")!,
                    hint: "Opens Messages, or the Crisis Text Line site."
                ),
                directory,
            ]
        case "CA":
            return [
                CrisisLine(
                    id: "ca-988",
                    title: "9-8-8 Suicide Crisis Helpline",
                    detail: "Call or text 988 (Canada) · 24/7",
                    primary: URL(string: "tel:988"),
                    web: URL(string: "https://988.ca")!,
                    hint: "Places the call, or opens 988.ca."
                ),
                directory,
            ]
        case "GB":
            return [
                CrisisLine(
                    id: "gb-samaritans",
                    title: "Samaritans",
                    detail: "Call 116 123 (UK) · free, 24/7",
                    primary: URL(string: "tel:116123"),
                    web: URL(string: "https://www.samaritans.org")!,
                    hint: "Places the call, or opens the Samaritans' site."
                ),
                CrisisLine(
                    id: "gb-shout",
                    title: "Shout",
                    detail: "Text SHOUT to 85258",
                    primary: URL(string: "sms:85258&body=SHOUT"),
                    web: URL(string: "https://giveusashout.org")!,
                    hint: "Opens Messages, or the Shout site."
                ),
                directory,
            ]
        case "IE":
            return [
                CrisisLine(
                    id: "ie-samaritans",
                    title: "Samaritans",
                    detail: "Call 116 123 (Ireland) · free, 24/7",
                    primary: URL(string: "tel:116123"),
                    web: URL(string: "https://www.samaritans.org")!,
                    hint: "Places the call, or opens the Samaritans' site."
                ),
                directory,
            ]
        case "AU":
            return [
                CrisisLine(
                    id: "au-lifeline",
                    title: "Lifeline Australia",
                    detail: "Call 13 11 14 · 24/7",
                    primary: URL(string: "tel:131114"),
                    web: URL(string: "https://www.lifeline.org.au")!,
                    hint: "Places the call, or opens Lifeline's site."
                ),
                directory,
            ]
        case "NZ":
            return [
                CrisisLine(
                    id: "nz-1737",
                    title: "1737 — Need to talk?",
                    detail: "Call or text 1737 (NZ) · free, 24/7",
                    primary: URL(string: "tel:1737"),
                    web: URL(string: "https://1737.org.nz")!,
                    hint: "Places the call, or opens 1737.org.nz."
                ),
                directory,
            ]
        default:
            return [directory]
        }
    }
}

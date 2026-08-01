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
                        resourceCard(
                            title: "988 Suicide & Crisis Lifeline",
                            detail: "Call or text 988 (US) · available 24/7",
                            url: URL(string: "tel:988")
                        )
                        resourceCard(
                            title: "Crisis Text Line",
                            detail: "Text HOME to 741741",
                            url: URL(string: "sms:741741&body=HOME")
                        )
                        Text("Outside the US: find a local line at findahelpline.com")
                            .font(.system(size: footnoteSize))
                            .foregroundStyle(Color(hex: 0x777777))
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: 380)
                    .padding(.top, 26)

                    Button { model.go(.shelf) } label: {
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

    private func resourceCard(title: String, detail: String, url: URL?) -> some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: bodySize, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x161616))
                Text(detail)
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
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityHint(url?.scheme == "sms" ? "Opens Messages." : "Places the call.")
    }
}

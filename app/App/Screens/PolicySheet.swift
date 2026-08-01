import SwiftUI

/// Terms, privacy, and the AI disclosure in one place, reachable from the
/// paywall's "Terms & privacy" link and the Drawer's footer. Apple requires a
/// working terms-of-use and privacy link inside any app selling auto-renewable
/// subscriptions; this sheet is that link's destination, and it tells the
/// truth in plain words rather than legalese.
struct PolicySheet: View {
    @Environment(\.room) private var room
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color(hex: 0x080503, opacity: 0.66)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 26) {
                        section(
                            "A spirit of ink, not a person",
                            "Everything the pages write back is fiction composed by artificial-intelligence models. It is not a person, not advice — medical, legal, financial or otherwise — and never a substitute for a human hand when you need one. If your writing suggests you are in danger, the notebook sets the fiction aside and shows you real help."
                        )
                        section(
                            "What leaves the device",
                            "To answer a page, Inkwoven sends a picture of what you wrote or drew — with a little surrounding context — to its own server, which passes it to AI providers (Google, OpenAI, fal.ai) solely to compose the reply. A page may begin its journey a moment after your pen rests. A random install token identifies this device to the server; there is no account, no advertising, no tracking, and nothing is ever sold. The Keeper's lock is a lock on this device — its pages still travel, like any other Book's, to be answered."
                        )
                        section(
                            "What stays with you",
                            "Your pages live on this device. You can export them as PDF or text, and Delete all pages in the Drawer does exactly what it says. Without a binding, pages older than thirty days fade from view — they remain on the device, and binding the notebook restores them."
                        )
                        section(
                            "The binding",
                            "The binding is an auto-renewing subscription, charged to your Apple account at the price shown on the paywall in your local currency — by the moon, or by the year with the first seven days free. It renews until cancelled, at least a day before renewal, in your device Settings under your Apple ID subscriptions. \"Restore a binding\" on the paywall recovers a purchase on a new or reinstalled device."
                        )
                        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                            Text("Apple's standard licence agreement (EULA)")
                                .font(InkFont.body(14))
                                .foregroundStyle(room.accent)
                                .underline()
                                .frame(minHeight: 44, alignment: .leading)
                        }
                    }
                    .padding(EdgeInsets(top: 24, leading: 30, bottom: 36, trailing: 30))
                }
            }
            .frame(maxWidth: 560, maxHeight: 640)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [room.cardTop, room.cardBottom],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(room.accent.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 30, y: 15)
            )
            .padding(30)
        }
        .transition(.opacity)
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                SmallCapsLabel(text: "the fine print", size: 11, tracking: 2.4, color: room.dim)
                Text("Terms & Privacy")
                    .font(InkFont.display(26))
                    .foregroundStyle(room.heading)
            }
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(room.dim)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close terms and privacy")
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(room.accent.opacity(0.12)).frame(height: 1)
        }
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCapsLabel(text: title, size: 12, tracking: 1.8, color: room.accent)
            Text(body)
                .font(InkFont.body(15))
                .foregroundStyle(room.text)
                .lineSpacing(5)
        }
    }
}

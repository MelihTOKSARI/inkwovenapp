import SwiftUI
import InkAnalytics

/// The binder asking what went wrong with a page (guideline 1.2's report
/// mechanism). Presented the house way — scrim + centered card, driven by
/// `AppModel.reportTarget` — and styled as the room's furniture, not a
/// support form. Content leaves the device only when the seal is pressed;
/// the consent line above it says so in plain words, and the Keeper's pages
/// get a stronger one.
struct ReportSheet: View {
    @Environment(\.room) private var room
    @State private var model: ReportModel
    let onClose: () -> Void
    let onSent: () -> Void

    init(
        entry: PageArchive.Entry,
        book: Book,
        submitter: any ReportSubmitting,
        analytics: Analytics,
        onClose: @escaping () -> Void,
        onSent: @escaping () -> Void
    ) {
        _model = State(initialValue: ReportModel(
            entry: entry, book: book, submitter: submitter, analytics: analytics
        ))
        self.onClose = onClose
        self.onSent = onSent
    }

    var body: some View {
        ZStack {
            Color(hex: 0x080503, opacity: 0.66)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("When a page answers poorly, the binder wants to know of it. Say what went wrong, and this page goes to a human hand for review.")
                            .font(InkFont.body(15))
                            .foregroundStyle(room.text)
                            .lineSpacing(5)

                        reasons
                        noteField
                        consent

                        if case .failed(let line) = model.phase {
                            QuietBanner(text: line, size: 14)
                        }
                        if model.phase == .sending {
                            QuietBanner(text: "the page travels to the binder…", size: 14)
                                .transition(.opacity)
                        }

                        actions
                    }
                    .padding(EdgeInsets(top: 22, leading: 30, bottom: 30, trailing: 30))
                }
            }
            .frame(maxWidth: 520, maxHeight: 640)
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
            // Keeps VoiceOver inside the sheet while it stands open.
            .accessibilityAddTraits(.isModal)
        }
        .transition(.opacity)
        .onChange(of: model.phase) { _, phase in
            if phase == .sent { onSent() }
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 3) {
                SmallCapsLabel(text: "a word with the binder", size: 11, tracking: 2.4, color: room.dim)
                Text("Report this reply")
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
                .accessibilityLabel("Close without reporting")
            }
        }
        .padding(EdgeInsets(top: 18, leading: 20, bottom: 8, trailing: 12))
        .overlay(alignment: .bottom) {
            Rectangle().fill(room.accent.opacity(0.12)).frame(height: 1)
        }
    }

    private var reasons: some View {
        VStack(alignment: .leading, spacing: 10) {
            SmallCapsLabel(text: "what went wrong", size: 12, tracking: 1.8, color: room.accent)
            ForEach(ReportReason.allCases, id: \.self) { reason in
                reasonChip(reason)
            }
        }
    }

    private func reasonChip(_ reason: ReportReason) -> some View {
        let selected = model.reason == reason
        return Button {
            model.reason = reason
        } label: {
            HStack {
                Text(reason.label)
                    .font(selected ? InkFont.bodyMedium(15) : InkFont.body(15))
                    .foregroundStyle(room.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(room.accent)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(room.accent.opacity(selected ? 0.16 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(room.accent.opacity(selected ? 0.5 : 0.2), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityLabel(reason.spoken)
        .accessibilityHint("Reason for the report. Choose one.")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SmallCapsLabel(text: "add a note, if you wish", size: 12, tracking: 1.8, color: room.accent)
            TextField("a few words about what happened", text: $model.note, axis: .vertical)
                .font(InkFont.body(15))
                .foregroundStyle(room.text)
                .lineLimit(3...6)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(room.accent.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(room.accent.opacity(0.2), lineWidth: 1)
                        )
                )
                .accessibilityLabel("Optional note, up to \(ReportModel.noteLimit) characters")
            if model.note.count > 400 {
                Text("\(model.note.count)/\(ReportModel.noteLimit)")
                    .font(InkFont.caption(11))
                    .foregroundStyle(room.dim)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    /// Never decorative and never hidden: this is the line App Review and the
    /// privacy policy both lean on.
    private var consent: some View {
        Text(model.consentLine)
            .font(model.isPrivatePage ? InkFont.bodyMedium(13.5) : InkFont.body(13.5))
            .foregroundStyle(room.text)
            .lineSpacing(4)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Text("Keep it between us")
                    .font(InkFont.body(15))
                    .foregroundStyle(room.dim)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            Spacer()
            WaxSealButton(label: "send to the binder", diameter: 34, labelFont: InkFont.bodyItalic(15)) {
                Task { await model.send() }
            }
            .disabled(!model.canSend)
            .opacity(model.canSend ? 1 : 0.45)
            .accessibilityHint(
                model.reason == nil
                    ? "Choose a reason first."
                    : "Sends the reply and your page to the binder for review."
            )
        }
    }
}

/// Attaches the report context menu only when there is a completed reply to
/// report — no menu ever appears mid-stream or on a failed exchange, and an
/// empty long-press lift never happens.
struct ReportableReply: ViewModifier {
    let entry: PageArchive.Entry?
    let report: (PageArchive.Entry) -> Void

    func body(content: Content) -> some View {
        if let entry {
            content.contextMenu {
                Button("Report this reply", systemImage: "flag") {
                    report(entry)
                }
            }
        } else {
            content
        }
    }
}

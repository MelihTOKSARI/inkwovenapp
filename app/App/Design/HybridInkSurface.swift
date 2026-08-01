import UIKit
import PencilKit

/// ONE writing surface, two hands. The same field arranges itself by pen
/// state — never two inputs side by side:
/// - pencil active → PencilKit ink; any input draws; the keyboard never rises;
/// - no pencil → the very same field hosts the keyboard's text: a deliberate
///   tap focuses it (the surface never summons the keys itself — pen first),
///   typing lands on the page in a script hand, and a stray finger tap can
///   no longer ink a dot.
/// The first pencil touch anywhere flips the surface to ink for good
/// (PenPresence persists it); the keyboard bows out mid-session.
/// `setWantsKeys` remains for surfaces that DO invite typing on entry
/// (the flyleaf signature); the page never calls it.
@MainActor
final class HybridInkSurface: UIView, UITextViewDelegate {
    let canvas = PKCanvasView()
    let textView = UITextView()

    /// Typed text sits on the signature line (foot of the field) when true;
    /// at the top of the page when false.
    var bottomAligned = false
    /// Return commits instead of inserting a newline (the flyleaf).
    var singleLine = false
    var onTypedChange: ((String) -> Void)?
    var onReturn: (() -> Void)?

    private var pencilActive: Bool?
    private var wantsKeys = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.frame = bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(canvas)

        textView.backgroundColor = .clear
        textView.frame = bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.autocorrectionType = .no
        textView.showsVerticalScrollIndicator = false
        textView.keyboardDismissMode = .interactive
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 12, right: 0)
        textView.delegate = self
        addSubview(textView)

        // Which hand touches this surface? A pencil flips the whole app.
        PenPresence.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The single-field contract: the same surface re-arms for the hand in
    /// play. No pencil → the text layer takes the touches and the canvas
    /// goes pencil-only (a pencil can still write at any moment, and its
    /// first touch flips the mode). Pencil → ink owns every touch.
    func apply(pencilActive: Bool) {
        guard self.pencilActive != pencilActive else { return }
        self.pencilActive = pencilActive
        canvas.drawingPolicy = pencilActive ? .anyInput : .pencilOnly
        textView.isUserInteractionEnabled = !pencilActive
        if pencilActive, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    /// Focus follows transitions only, so the surface never fights a writer
    /// who dismissed the keyboard themselves.
    func setWantsKeys(_ wants: Bool) {
        guard wants != wantsKeys else { return }
        wantsKeys = wants
        if wants {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, self.wantsKeys, self.textView.isUserInteractionEnabled,
                      self.window != nil, !self.textView.isFirstResponder else { return }
                self.textView.becomeFirstResponder()
            }
        } else if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bottomAligned {
            // Full-height touch target, but the written name rests on the
            // signature line — same place the ink would sit.
            let line = (textView.font?.lineHeight ?? 32) + 14
            textView.textContainerInset = UIEdgeInsets(
                top: max(8, bounds.height - line), left: 4, bottom: 10, right: 4
            )
        }
    }

    // MARK: - UITextViewDelegate

    func textViewDidChange(_ textView: UITextView) {
        onTypedChange?(textView.text)
    }

    func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
    ) -> Bool {
        if singleLine, text.contains("\n") {
            textView.resignFirstResponder()
            onReturn?()
            return false
        }
        return true
    }
}

import AppKit

// ---------- The logo, one way everywhere ----------
//
// Every place the product's mark appears draws it through here: the Studio header, the wizard's
// top line, the gate before the app opens. So the mark is one thing, at one size, in one place on
// each frame, and when the logo arrives it replaces the stand-in here and nowhere else. Until then
// the mark is the wordmark: the name in bold lowercase at 18, tracked tight, in ink.
//
// On a frame it stands at column 1 on the top line's baseline (44 from the top of the wizard and
// the gate), and what else that line carries follows it after one gutter.

final class Logo: NSView {
    static let size: CGFloat = 18
    static var font: NSFont { Design.font(size, .bold) }
    static var attributed: NSAttributedString {
        NSAttributedString(string: Brand.wordmark, attributes: [.font: font, .foregroundColor: Design.ink, .kern: -0.4])
    }

    /// Draws the mark with its baseline at `baseline`, in a flipped view (the Studio window's).
    static func draw(x: CGFloat, baseline: CGFloat) {
        attributed.draw(at: NSPoint(x: x, y: baseline - font.ascender))
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { let s = Self.attributed.size(); return NSSize(width: ceil(s.width), height: ceil(s.height)) }
    /// So a baseline anchor lines the mark up with text beside it.
    override var lastBaselineOffsetFromBottom: CGFloat { -Self.font.descender }
    override var firstBaselineOffsetFromTop: CGFloat { intrinsicContentSize.height + Self.font.descender }

    override func draw(_ dirtyRect: NSRect) { Self.attributed.draw(at: .zero) }
}

import AppKit

// ---------- The logo, one way everywhere ----------
//
// Every place the product's mark appears draws it through here: the Studio header, the wizard's
// top line, the gate before the app opens. So the mark is one thing, with an explicit size for each surface on
// each frame, and when the logo arrives it replaces the stand-in here and nowhere else. Until then
// the mark is the wordmark: bold lowercase, tracked tight, in ink.
//
// On a frame it stands at column 1 on the top line's baseline (44 from the top of the wizard and
// the gate), and what else that line carries follows it after one gutter.

final class Logo: NSView {
    static let size: CGFloat = 18
    private static let headerLockup: NSImage? = {
#if SWIFT_PACKAGE
        // build.sh installs resources directly in the app, while SwiftPM's bare
        // executable uses its generated resource bundle. Do not initialise
        // Bundle.module in the installed app: it traps when that bundle is absent.
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
#else
        let bundle = Bundle.main
#endif
        guard let url = bundle.url(forResource: "ColorgainLogo", withExtension: "pdf") ?? bundle.url(forResource: "ColorgainLogo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// The selected Confluence lockup, centred in the expanded header at the wordmark's grid origin.
    static func headerSidePadding(over railWidth:CGFloat,height:CGFloat=46)->CGFloat {
        let width=headerLockup.map{height*$0.size.width/$0.size.height} ?? attributed.size().width
        return max(0,(railWidth-width)/2)
    }
    static func drawHeader(centredOver railWidth:CGFloat,centreY:CGFloat,height:CGFloat=46){
        drawHeader(x:headerSidePadding(over:railWidth,height:height),centreY:centreY,height:height)
    }
    static func drawHeader(x: CGFloat, centreY: CGFloat, height: CGFloat = 46) {
        guard let image = headerLockup else {
            draw(x: x, baseline: centreY + Design.Text.headline.size / 2, size: Design.Text.headline.size)
            return
        }
        let width = height * image.size.width / image.size.height
        let rect=NSRect(x:x,y:centreY-height/2,width:width,height:height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:rect).addClip()
        let context=NSGraphicsContext.current?.cgContext
        context?.beginTransparencyLayer(auxiliaryInfo:nil)
        image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        Design.ink.setFill();rect.fill(using:.sourceIn)
        context?.endTransparencyLayer()
        NSGraphicsContext.restoreGraphicsState()
    }

    static var font: NSFont { Design.font(size, .bold) }
    static var attributed: NSAttributedString {
        NSAttributedString(string: Brand.wordmark, attributes: [.font: font, .foregroundColor: Design.ink, .kern: -0.4])
    }

    /// Draws the mark with its baseline at `baseline`, in a flipped view (the Studio window's).
    static func draw(x: CGFloat, baseline: CGFloat, size:CGFloat = Logo.size) {
        let markFont=Design.font(size,.bold)
        let mark=NSAttributedString(string:Brand.wordmark,attributes:[.font:markFont,.foregroundColor:Design.ink,.kern:-0.4])
        mark.draw(at:NSPoint(x:x,y:baseline-markFont.ascender))
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

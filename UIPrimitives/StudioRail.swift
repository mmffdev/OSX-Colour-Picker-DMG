import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

class StudioRail: ClickCursorView {
    override var handCursorRects:[NSRect]{arrow == .none ? []:[AreaHeader.arrowRect(in:bounds,insetRight:insetRight).insetBy(dx:-8,dy:-8)]}

    var inset: CGFloat = 24 { didSet { if inset != oldValue { needsLayout = true } } }
    var insetRight: CGFloat = 24 { didSet { if insetRight != oldValue { needsLayout = true } } }
    /// The arrow in the header, and what a press on it does.
    var arrow = AreaHeader.Arrow.open { didSet { needsDisplay = true } }
    var onArrow: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if arrow != .none, AreaHeader.arrowRect(in: bounds, insetRight: insetRight).insetBy(dx: -8, dy: -8).contains(p) { onArrow?(); return }
        super.mouseDown(with: event)
    }
    static let top: CGFloat = 22
    var expandedWidth: CGFloat? { didSet { if expandedWidth != oldValue { needsLayout = true; needsDisplay = true } } }
    var contentWidth: CGFloat { expandedWidth ?? bounds.width }
    var contentOffset: CGFloat = 0
    let scroll = FittedScrollView()
    let body: RailBody
    var heading = "" { didSet { needsDisplay = true } }
    /// The two Labels under the heading.
    var labels: (String, String) = ("", "") { didSet { needsDisplay = true } }

    init(body: RailBody) {
        self.body = body
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Design.card.cgColor
        layer?.masksToBounds = true
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = body
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    /// The header stays put; only the rows scroll, under the Rule.
    override func layout() {
        super.layout()
        let scrollFrame = NSRect(x: 0, y: AreaHeader.height + contentOffset, width: contentWidth, height: bounds.height - AreaHeader.height - contentOffset)
        if scroll.frame != scrollFrame { scroll.frame = scrollFrame }
        let insetsChanged = body.inset != inset || body.insetRight != max(0, insetRight - QuietScroller.lane)
        body.inset = inset; body.insetRight = max(0, insetRight - QuietScroller.lane)
        let bodyFrame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scroll.frame.height, body.height))
        let resized = body.frame != bodyFrame
        if resized { body.frame = bodyFrame }
        scroll.verticalScrollElasticity = body.height > scroll.frame.height ? .allowed : .none
        if resized || insetsChanged { body.needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        AreaHeader.draw(heading: heading, left: labels.0, right: labels.1, in: NSRect(x: 0, y: 0, width: contentWidth, height: bounds.height), inset: inset, insetRight: insetRight, arrow: arrow)
    }

    class RailBody: ClickCursorView {
    override var handCursorRects:[NSRect]{[]}

        var inset: CGFloat = 24, insetRight: CGFloat = 24
        override var isFlipped: Bool { true }
        var height: CGFloat { 0 }
        /// Master Inner: a row's top at a count of units from the rule, and the line its text sits on.
        static var unit: CGFloat { Design.App.unit }
        static var line: CGFloat { Design.App.textBaseline }
    }
}

/// The header of an area, drawn the same in rail1, rail2, the page and the history rail: the Heading
/// with the arrow on its baseline, a row of two Labels under it, and the Rule beneath, at one height in
/// every area so the rule reads as one line across the window broken only by each area's side padding.
/// It never scrolls; what is under it does.

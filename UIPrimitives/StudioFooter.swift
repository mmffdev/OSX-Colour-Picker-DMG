import AppKit
import QuartzCore
import UniformTypeIdentifiers
import ImageIO

// MARK: - The title strip

/// Nothing to see: a full-width band across the top of the window, the height of the title bar, around
/// Apple's three buttons, which keep their own menus. A press on it moves the window, and over it the
/// pointer is the open hand.
final class TitleStrip: NSView {
    static let height: CGFloat = 24
    override var mouseDownCanMoveWindow: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

// MARK: - Master Inner, drawn over the window

/// The grid over everything: the twelve columns as faint bands with their edges, the two margins, the
/// header's baseline, the area header's lines, then the beat under the rule, every unit, with the
/// line text sits on in each. In the grid's orange, light enough to read through. Takes no clicks.
final class GridOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    /// The page's content, left edge and width: its columns are drawn as the page lays them, from its own width.
    var page = NSRect.zero { didSet { needsDisplay = true } }
    /// While the splash is up: the window's twelve columns the whole way across, the header's baseline, and the beat from the band's top.
    var splash = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        typealias A = Design.App
        let w = bounds.width, h = bounds.height, c = A.gridColour
        let cw = A.columnWidth(in: w)
        func column(_ x: CGFloat, _ width: CGFloat) {
            fill(NSRect(x: x, y: 0, width: width, height: h), c.withAlphaComponent(0.05))
            fill(NSRect(x: x, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
            fill(NSRect(x: x + width - 1, y: 0, width: 1, height: h), c.withAlphaComponent(0.45))
        }
        if splash {
            for i in 1...A.columns { column(A.column(i, in: w), cw) }
            fill(NSRect(x: 0, y: StudioHeader.baseline, width: w, height: 1), c.withAlphaComponent(0.6))
            var y = StudioSplash.bandTop
            while y < h {
                fill(NSRect(x: 0, y: y, width: w, height: 1), c.withAlphaComponent(0.25))
                fill(NSRect(x: 0, y: y + A.textBaseline, width: w, height: 1), c.withAlphaComponent(0.6))
                y += A.unit
            }
            return
        }
        // The window's columns up to the page, then the page's own, then the window's again past it.
        for i in 1...A.columns {
            let x = A.column(i, in: w)
            if page.width > 0, x + cw > page.minX, x < page.maxX { continue }
            column(x, cw)
        }
        if page.width > 0 {
            let own = A.pageColumns(width: page.width, in: w)
            for x in own.x { column(page.minX + x, own.width) }
        }
        // The header's baseline, the area header's heading and label lines and its rule.
        let strong = c.withAlphaComponent(0.6), faint = c.withAlphaComponent(0.25)
        fill(NSRect(x: 0, y: StudioHeader.baseline, width: w, height: 1), strong)
        let top = A.header + 1
        for y in [AreaHeader.headingBaseline, AreaHeader.labelBaseline, AreaHeader.rule] { fill(NSRect(x: 0, y: top + y, width: w, height: 1), strong) }
        // The beat: a unit line and, within each unit, the line text sits on.
        var y = top + AreaHeader.height
        let bottom = h - A.footer
        while y < bottom {
            fill(NSRect(x: 0, y: y, width: w, height: 1), faint)
            fill(NSRect(x: 0, y: y + A.textBaseline, width: w, height: 1), strong)
            y += A.unit
        }
        fill(NSRect(x: 0, y: h - A.footer + StudioFooter.baseline, width: w, height: 1), strong)
    }
}

// MARK: - The footer, 48 high

/// Left: a 10 square of the current colour, its name, its hex. Centre: three text actions. Right: the release line.
final class StudioFooter: ClickCursorView {
    override var handCursorRects:[NSRect]{swatchHits}

    private let appearancePresets=AppearancePresetControl()
    var grid: (x: CGFloat, column: CGFloat, centre: CGFloat) = (24, 96, 480) { didSet { if grid != oldValue { needsDisplay = true } } }
    private(set) var hex = Brand.masterHex
    private(set) var name = Brand.masterName
    var onAct: ((Int) -> Void)?
    /// A word from the controller, "Picked Hemlock", in the actions' place for four seconds.
    private var flash: String?
    private var flashTimer: Timer?
    func flash(_ text: String) {
        flash = text; needsDisplay = true
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.flash = nil; self?.needsDisplay = true }
    }
    private var swatchHits: [NSRect] = []
    private var copyObserver: NSObjectProtocol?
    static let baseline: CGFloat = 30

    init() {
        super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = Design.card.cgColor
        addSubview(appearancePresets)
        copyObserver = NotificationCenter.default.addObserver(forName: ColourCopies.changed, object: nil, queue: .main) { [weak self] _ in self?.needsDisplay = true }
    }
    deinit { if let copyObserver { NotificationCenter.default.removeObserver(copyObserver) } }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func set(hex: String, name: String) { self.hex = hex; self.name = name; needsDisplay = true }

    override func layout(){super.layout();appearancePresets.frame=NSRect(x:bounds.width-Design.App.railWidth-140,y:(bounds.height-28)/2,width:140,height:28)}

    override func draw(_ dirtyRect: NSRect) {
        hairline(x: 0, y: 0, width: bounds.width)
        let b = Self.baseline
        swatchHits = []
        let size = min(24, max(12, (grid.centre - grid.x - 32 - 9 * 8) / 10))
        for (index, entry) in Array(ColourCopies.recent.suffix(10)).enumerated() {
            let rect = NSRect(x: grid.x + CGFloat(index) * (size + 8), y: (bounds.height - size) / 2, width: size, height: size)
            fill(rect, Design.hex(entry.key)); swatchHits.append(rect)
        }
        // The actions as text from the page's left edge, the live one Medium; a flash takes their place while it lasts.
        let x = grid.centre
        if let f = flash { Design.attributed(f, .body).draw(x: x, baseline: b, width: grid.x + 12 * grid.column + 11 * Design.App.gutter - 200 - x) }
        Design.attributed(ContentViewController.releaseLine, .caption, colour: Design.quiet).draw(right: grid.x + 12 * grid.column + 11 * Design.App.gutter, baseline: b)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let index = swatchHits.firstIndex(where: { $0.contains(p) }) {
            let entry = Array(ColourCopies.recent.suffix(10))[index]
            ColourCopies.copy(entry.key, sourceCMYK: entry.sourceCMYK, record: false)
            return
        }

    }
}

import AppKit

// ---------- How every page begins ----------
//
// The title row, then the action bar: the same on every page, from one set of numbers. Change a
// number here and every page follows. Pages laid out with constraints pin the header to the top
// safe area; pages laid out by hand give it a frame. Either way its insides are the same.

enum PageStyle {
    /// Left and right inset of the title, the bar and most page content.
    static let side: CGFloat = 20
    /// The title's middle, below the toolbar. The sidebar's first row is centred on the same line.
    static let titleCentre: CGFloat = 28
    static let titleFont = NSFont.systemFont(ofSize: TextSize.title, weight: .bold)
    /// The action bar: its row height, the gap under the title, and the gap between its items.
    static let barHeight: CGFloat = 28
    /// The clear space between the title panel and the bar.
    static let barGap: CGFloat = 8
    static let barSpacing: CGFloat = 8
    /// From the top safe area to where the page's own content starts.
    static let height: CGFloat = 88
    /// The title panel runs from the top edge, the full width, down to this far below the title.
    static let titlePad: CGFloat = 8
}

final class PageHeader: NSView {
    /// The page's name. A page that lets the user rename what it shows passes its own field.
    let title: NSTextField
    /// The bar's left: a count, or a word on what is showing.
    let subtitle = caption("")
    /// Open space between the subtitle and the actions; hidden when a page needs the bar's full width.
    let gap = NSView()
    /// The bar: pills, subtitle, gap, then whatever the page passed.
    let bar: NSStackView
    /// Pills before the subtitle: where what the page shows belongs, such as its project.
    let pills = NSStackView()
    /// Barber-pole stripes behind the title: the mark of something that belongs to a project.
    var striped = false { didSet { needsDisplay = true } }
    /// The padlock before the title, shown for anything in a project: open, or shut when the project is locked.
    private let lockMark = NSImageView()
    private var titleRow: NSStackView!
    var lock: Bool? = nil {
        didSet {
            lockMark.isHidden = lock == nil
            lockMark.image = symbol(lock == true ? "lock.fill" : "lock.open", lock == true ? "Locked" : "Unlocked", size: 16, weight: .semibold)
            lockMark.contentTintColor = lock == true ? .systemOrange : .tertiaryLabelColor
            lockMark.toolTip = lock == true ? "The project is locked: nothing in it can change" : "The project is unlocked"
        }
    }

    init(title: NSTextField = NSTextField(labelWithString: ""), actions: [NSView] = []) {
        self.title = title
        bar = NSStackView(views: [pills, subtitle, gap] + actions)
        super.init(frame: .zero)
        pills.orientation = .horizontal
        pills.spacing = 6
        pills.setContentHuggingPriority(.required, for: .horizontal)
        pills.isHidden = true
        title.font = PageStyle.titleFont
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.orientation = .horizontal
        bar.spacing = PageStyle.barSpacing
        bar.alignment = .centerY
        lockMark.isHidden = true
        lockMark.setContentHuggingPriority(.required, for: .horizontal)
        let titleRow = NSStackView(views: [lockMark, title])
        self.titleRow = titleRow
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        for v in [titleRow, bar] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            titleRow.centerYAnchor.constraint(equalTo: topAnchor, constant: PageStyle.titleCentre),
            titleRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            titleRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side),
            bar.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: PageStyle.titlePad + PageStyle.barGap),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: PageStyle.barHeight),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Where the page's own content starts, measured from the top safe area. The bar can grow a
    /// second row (a tag bar, say); the page then starts below that.
    var contentTop: CGFloat { max(PageStyle.height, bar.frame.maxY + PageStyle.side / 2) }

    override func layout() {
        super.layout()
        if striped { needsDisplay = true }   // the panel follows the title's own size
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: PageStyle.height) }

    /// Shows one pill, or none, naming the project; a click runs `onClick`.
    func setProject(_ name: String?, onClick: @escaping () -> Void) {
        pills.views.forEach { $0.removeFromSuperview() }
        guard let name = name else { pills.isHidden = true; return }
        let pill = PillButton(title: name, symbol: "folder", action: onClick)
        pills.addArrangedSubview(pill)
        pills.isHidden = false
    }

    /// Stripes 20 points wide with 20-point gaps at 45 degrees, three percent lighter than
    /// the background in dark mode and three percent darker in light, on the title panel: the full
    /// width, touching the top, down to `titlePad` below the title, with the bar clear beneath it.
    override func draw(_ dirtyRect: NSRect) {
        guard striped, let titleRow = titleRow else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? .gray
        let shade = base.blended(withFraction: 0.03, of: dark ? .white : .black) ?? base
        // The view is not flipped: the top edge is bounds.maxY, and the panel reaches down past the title.
        let floor = titleRow.frame.minY - PageStyle.titlePad
        let band = NSRect(x: 0, y: floor, width: bounds.width, height: bounds.maxY - floor)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: band)
        shade.setFill()
        let stripe: CGFloat = 20, step: CGFloat = 40
        // Each stripe is a parallelogram leaning at 45 degrees, wide enough to cross the band whole.
        var x = band.minX - band.height
        while x < band.maxX + band.height {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: band.minY))
            path.line(to: NSPoint(x: x + stripe, y: band.minY))
            path.line(to: NSPoint(x: x + stripe + band.height, y: band.maxY))
            path.line(to: NSPoint(x: x + band.height, y: band.maxY))
            path.close()
            path.fill()
            x += step
        }
        ctx.restoreGState()
    }
}

/// A small rounded pill with a symbol and a name, used for where something belongs.
final class PillButton: NSButton {
    private let onClick: () -> Void

    init(title: String, symbol name: String, action: @escaping () -> Void) {
        onClick = action
        super.init(frame: .zero)
        self.title = title
        image = symbol(name, title, size: 10)
        imagePosition = .imageLeading
        bezelStyle = .badge
        controlSize = .small
        font = NSFont.systemFont(ofSize: TextSize.caption, weight: .medium)
        contentTintColor = .labelColor
        target = self
        self.action = #selector(clicked)
        toolTip = "Show the project in the sidebar"
        setContentHuggingPriority(.required, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func clicked() { onClick() }
}

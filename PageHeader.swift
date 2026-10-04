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
    static let height: CGFloat = 96
    /// The title panel runs from the top edge, the full width, to twice the title centre, so the
    /// title sits in its exact middle with the same clear space above and below.
    static var titlePanelHeight: CGFloat { titleCentre * 2 }
}

/// The title panel every rail begins with: the name, in the page's own title font, on the page's
/// own title line, with the page's own inset. rail1's reads "Catalogue"; rail2's names the place
/// its page is. The page and the History rail have the same panel as the top of their header.
final class TitlePanel: NSView {
    let title = NSTextField(labelWithString: "")

    init(_ text: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        title.stringValue = text
        title.font = PageStyle.titleFont
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: PageStyle.titlePanelHeight),
            title.centerYAnchor.constraint(equalTo: topAnchor, constant: PageStyle.titleCentre),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -PageStyle.side),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
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
    /// A mark of the page's own before the title, such as the purpose a palette's page is turned to. Hidden until given an image.
    let mark = NSImageView()
    private var titleRow: NSStackView!
    /// The title panel's far right: a page's view switches, sized to sit with the title.
    let trailing = NSStackView()
    /// The point size of a symbol in the title panel, to stand beside the title's capitals.
    static let titleSymbol: CGFloat = 17
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
        trailing.orientation = .horizontal
        trailing.spacing = 10
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mark.isHidden = true
        mark.contentTintColor = .labelColor
        mark.setContentHuggingPriority(.required, for: .horizontal)
        let titleRow = NSStackView(views: [lockMark, mark, title, trailing])
        titleRow.distribution = .fill
        self.titleRow = titleRow
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        for v in [titleRow, bar] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            titleRow.centerYAnchor.constraint(equalTo: topAnchor, constant: PageStyle.titleCentre),
            titleRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            titleRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: PageStyle.titlePanelHeight + PageStyle.barGap),
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

    /// Stripes 20 points wide with 20-point gaps at 45 degrees, two percent lighter than
    /// the background in dark mode and two percent darker in light, on the title panel: the full
    /// width, touching the top, the title in its middle, with the bar clear beneath it.
    override func draw(_ dirtyRect: NSRect) {
        guard striped else { return }
        // The view is not flipped: the top edge is bounds.maxY, and the panel hangs from it.
        Theme.drawStripes(in: NSRect(x: 0, y: bounds.maxY - PageStyle.titlePanelHeight, width: bounds.width, height: PageStyle.titlePanelHeight))
    }

}

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

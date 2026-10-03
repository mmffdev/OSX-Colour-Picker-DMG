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
    static let barGap: CGFloat = 2
    static let barSpacing: CGFloat = 8
    /// From the top safe area to where the page's own content starts.
    static let height: CGFloat = 80
}

final class PageHeader: NSView {
    /// The page's name. A page that lets the user rename what it shows passes its own field.
    let title: NSTextField
    /// The bar's left: a count, or a word on what is showing.
    let subtitle = caption("")
    /// Open space between the subtitle and the actions; hidden when a page needs the bar's full width.
    let gap = NSView()
    /// The bar: subtitle, gap, then whatever the page passed.
    let bar: NSStackView

    init(title: NSTextField = NSTextField(labelWithString: ""), actions: [NSView] = []) {
        self.title = title
        bar = NSStackView(views: [subtitle, gap] + actions)
        super.init(frame: .zero)
        title.font = PageStyle.titleFont
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.orientation = .horizontal
        bar.spacing = PageStyle.barSpacing
        bar.alignment = .centerY
        for v in [title, bar] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            title.centerYAnchor.constraint(equalTo: topAnchor, constant: PageStyle.titleCentre),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side),
            bar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: PageStyle.barGap),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side),
            bar.heightAnchor.constraint(greaterThanOrEqualToConstant: PageStyle.barHeight),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Where the page's own content starts, measured from the top safe area. The bar can grow a
    /// second row (a tag bar, say); the page then starts below that.
    var contentTop: CGFloat { max(PageStyle.height, bar.frame.maxY + PageStyle.side / 2) }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: PageStyle.height) }
}

import AppKit

// ---------- The History rail ----------
//
// A rail on the right listing every step, oldest at the top, the current one selected. Click a
// step to take the library back to it; press Delete to drop a step; Play Back walks from the first
// step to the current one. The list follows the library's history as it changes.

final class HistoryRailController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let library: LibraryController
    private let table = HistoryTable()
    private lazy var header = PageHeader(actions: [play, remove])
    private lazy var scope = NSSegmentedControl(labels: ["Project", "Global"], trackingMode: .selectOne, target: self, action: #selector(scopeChanged))
    /// The project whose steps are listed; nil lists everything. Follows the page, until the user picks.
    private var project: UUID?
    private var pickedByUser = false
    /// Rows of the table as indices into the history's steps.
    private var rows: [Int] = []
    private lazy var play = toolButton("Play Back", "play.fill", "Walk through the steps from the first to the current one", target: self, action: #selector(playTapped))
    private lazy var remove = toolButton("", "trash", "Delete the selected step", target: self, action: #selector(deleteTapped))
    /// How many steps are listed, and where: its own line under the bar, so a narrow rail never cuts it.
    private let count = caption("", size: TextSize.body)
    private var playing: Timer?
    private var following = false

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        header.title.stringValue = "History"
        header.subtitle.isHidden = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("step"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .fullWidth   // no padding of the table's own: the cell sets the page inset itself
        table.rowHeight = 40
        table.intercellSpacing = .zero   // a cell starts on the rail's own edge, so its inset is the page inset
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        table.onDelete = { [weak self] in self?.deleteTapped() }
        let scroll = LetGoScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        for v in [header, count, scroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
            count.topAnchor.constraint(equalTo: header.bar.bottomAnchor, constant: PageStyle.barGap),
            count.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PageStyle.side),
            count.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PageStyle.side),
            scroll.topAnchor.constraint(equalTo: count.bottomAnchor, constant: PageStyle.barGap),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // The toggle leads the bar, on the title's left edge, and stands as tall as the buttons beside it.
        header.bar.insertArrangedSubview(scope, at: 0)
        scope.controlSize = .regular
        scope.font = NSFont.systemFont(ofSize: TextSize.body)
        scope.setContentHuggingPriority(.required, for: .horizontal)
        scope.heightAnchor.constraint(equalTo: play.heightAnchor).isActive = true
        scope.centerYAnchor.constraint(equalTo: play.centerYAnchor).isActive = true
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .historyDidChange, object: library)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: .selectionDidChange, object: library)
        pageChanged()
    }

    /// Inside a project the rail offers Project or Global and starts on Project; outside, it is global only.
    @objc private func pageChanged() {
        let now = library.currentProject
        scope.isHidden = now == nil
        if now != project { pickedByUser = false }
        if !pickedByUser { project = now }
        scope.selectedSegment = project == nil ? 1 : 0
        reload()
    }

    @objc private func scopeChanged() {
        pickedByUser = true
        project = scope.selectedSegment == 0 ? library.currentProject : nil
        reload()
    }

    @objc func reload() {
        let history = library.history
        rows = history.steps.indices.filter { project == nil || history.steps[$0].project == project }
        table.reloadData()
        following = true
        if let row = rows.firstIndex(of: history.current) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        following = false
        let name = project.flatMap { library.library.project($0)?.name }
        count.stringValue = rows.isEmpty ? (name.map { "No steps in \($0) yet" } ?? "No steps yet")
            : plural(rows.count, "Step") + (name.map { " in \($0)" } ?? "")
        play.isEnabled = rows.count > 1
        remove.isEnabled = table.selectedRow >= 0
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("step")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? StepCell ?? { let c = StepCell(); c.identifier = id; return c }()
        let index = rows[row]
        let step = library.history.steps[index]
        cell.show(step, change: library.history.change(at: index), project: project == nil ? step.project.flatMap { library.library.project($0)?.name } : nil,
                  isPast: index > library.history.current)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        remove.isEnabled = table.selectedRow >= 0
        guard !following, table.selectedRow >= 0, rows.indices.contains(table.selectedRow), rows[table.selectedRow] != library.history.current else { return }
        library.goToStep(rows[table.selectedRow])
    }

    // MARK: Actions

    /// Walks the listed steps from the first to the last at or before the current one.
    @objc private func playTapped() {
        playing?.invalidate()
        let path = rows.filter { $0 <= max(library.history.current, 0) }
        guard path.count > 1 else { return }
        var at = 0
        library.goToStep(path[0])
        playing = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] t in
            at += 1
            guard let self = self, at < path.count, path[at] < self.library.history.steps.count else { t.invalidate(); return }
            self.library.goToStep(path[at])
        }
    }

    @objc private func deleteTapped() {
        let row = table.selectedRow
        guard row >= 0, rows.indices.contains(row) else { return }
        library.deleteStep(rows[row])
    }
}

/// A step: a symbol for what it did, its title, then when, where, and which colours came or went,
/// each with a tiny swatch of itself.
private final class StepCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = caption("")
    private let chips = NSStackView()
    private let line = NSStackView()
    private var leading: NSLayoutConstraint!
    private var trailing: NSLayoutConstraint!
    /// When the step happened: on the title line, hard right, never cut short.
    private let when = caption("")

    override init(frame: NSRect) {
        super.init(frame: frame)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.imageAlignment = .alignLeft   // the symbol's left edge on the title's left edge
        when.alignment = .right
        when.setContentHuggingPriority(.required, for: .horizontal)
        when.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.font = NSFont.systemFont(ofSize: TextSize.body)
        title.lineBreakMode = .byTruncatingTail
        detail.lineBreakMode = .byTruncatingTail
        chips.orientation = .horizontal
        chips.spacing = 3
        chips.setContentHuggingPriority(.required, for: .horizontal)
        line.setViews([chips, detail], in: .leading)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 6
        let top = NSStackView(views: [title, when])
        top.orientation = .horizontal
        top.alignment = .firstBaseline
        top.spacing = 8
        top.distribution = .fill
        let column = NSStackView(views: [top, line])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        top.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        line.trailingAnchor.constraint(lessThanOrEqualTo: column.trailingAnchor).isActive = true
        let row = NSStackView(views: [icon, column])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        // Just short of required: a cell is briefly narrower than its two insets while the table sizes it.
        leading = row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side)
        trailing = row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PageStyle.side)
        trailing.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The table sets a cell in from its own edge by a few points. The insets are measured against
    /// the row, so the symbol's ink lands on the title's left edge and the time on the bar's right edge.
    override func layout() {
        if let rowView = superview {
            let left = PageStyle.side + StepCell.inkInset - frame.minX
            let right = -(PageStyle.side - (rowView.bounds.maxX - frame.maxX))
            if leading.constant != left { leading.constant = left }
            if trailing.constant != right { trailing.constant = right }
        }
        super.layout()
    }
    /// A label's text starts two points inside its frame and a symbol's ink one point inside its image.
    private static let inkInset: CGFloat = 1

    func show(_ step: HistoryStep, change: StepChange, project: String?, isPast: Bool) {
        icon.image = symbol(stepSymbol(for: step.title), step.title, size: 13)
        icon.contentTintColor = isPast ? .tertiaryLabelColor : .secondaryLabelColor
        title.stringValue = step.title
        title.textColor = isPast ? .tertiaryLabelColor : .labelColor
        var parts: [String] = []
        // The colours that came or went, by name: "Scarlet added", "Blaze Orange, Orange removed".
        if !change.added.isEmpty { parts.append(change.added.prefix(2).map(colourName).joined(separator: ", ") + (change.added.count > 2 ? " +\(change.added.count - 2)" : "") + " added") }
        if !change.removed.isEmpty { parts.append(change.removed.prefix(2).map(colourName).joined(separator: ", ") + (change.removed.count > 2 ? " +\(change.removed.count - 2)" : "") + " removed") }
        when.stringValue = stepStamp(step.date)
        when.textColor = isPast ? .tertiaryLabelColor : .secondaryLabelColor
        if let p = project { parts.append(p) }
        detail.stringValue = parts.joined(separator: "  \u{00B7}  ")
        chips.views.forEach { $0.removeFromSuperview() }
        for hex in (change.added + change.removed).prefix(4) {
            let chip = NSView()
            chip.wantsLayer = true
            chip.layer?.backgroundColor = colorFromHex(hex)?.cgColor
            chip.layer?.cornerRadius = 3
            chip.layer?.borderWidth = 0.5
            chip.layer?.borderColor = NSColor.black.withAlphaComponent(0.25).cgColor
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.widthAnchor.constraint(equalToConstant: 12).isActive = true
            chip.heightAnchor.constraint(equalToConstant: 12).isActive = true
            chips.addArrangedSubview(chip)
        }
        chips.isHidden = chips.views.isEmpty
        line.isHidden = chips.views.isEmpty && detail.stringValue.isEmpty   // a lone title sits in the row's middle
    }
}

/// A table that hands the Delete key to the rail.
final class HistoryTable: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?(); return }
        super.keyDown(with: event)
    }
}

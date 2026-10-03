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
    private lazy var play = toolButton("Play Back", "play.fill", "Walk through the steps from the first to the current one", target: self, action: #selector(playTapped))
    private lazy var remove = toolButton("", "trash", "Delete the selected step", target: self, action: #selector(deleteTapped))
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("step"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = 36
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
        table.onDelete = { [weak self] in self?.deleteTapped() }
        let scroll = LetGoScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        for v in [header, scroll] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .historyDidChange, object: library)
        reload()
    }

    @objc func reload() {
        let history = library.history
        table.reloadData()
        following = true
        if history.current >= 0 {
            table.selectRowIndexes([history.current], byExtendingSelection: false)
            table.scrollRowToVisible(history.current)
        } else {
            table.deselectAll(nil)
        }
        following = false
        let count = history.steps.count
        header.subtitle.stringValue = count == 0 ? "No steps yet" : plural(count, "Step")
        play.isEnabled = history.current > 0
        remove.isEnabled = table.selectedRow >= 0
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { library.history.steps.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("step")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? StepCell ?? { let c = StepCell(); c.identifier = id; return c }()
        let step = library.history.steps[row]
        cell.show(step, project: step.project.flatMap { library.library.project($0)?.name }, isPast: row > library.history.current)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        remove.isEnabled = table.selectedRow >= 0
        guard !following, table.selectedRow >= 0, table.selectedRow != library.history.current else { return }
        library.goToStep(table.selectedRow)
    }

    // MARK: Actions

    @objc private func playTapped() {
        playing?.invalidate()
        let end = library.history.current
        guard end > 0 else { return }
        var at = 0
        library.goToStep(0)
        playing = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] t in
            at += 1
            guard let self = self, at <= end, at < self.library.history.steps.count else { t.invalidate(); return }
            self.library.goToStep(at)
        }
    }

    @objc private func deleteTapped() {
        let row = table.selectedRow
        guard row >= 0 else { return }
        library.deleteStep(row)
    }
}

/// A step: its title, then who and when underneath.
private final class StepCell: NSTableCellView {
    private let title = NSTextField(labelWithString: "")
    private let detail = caption("")

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = NSFont.systemFont(ofSize: TextSize.body)
        title.lineBreakMode = .byTruncatingTail
        let column = NSStackView(views: [title, detail])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PageStyle.side),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            column.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    func show(_ step: HistoryStep, project: String?, isPast: Bool) {
        title.stringValue = step.title
        title.textColor = isPast ? .tertiaryLabelColor : .labelColor
        var parts = [StepCell.clock.string(from: step.date)]
        if let p = project { parts.append(p) }
        detail.stringValue = parts.joined(separator: "  \u{00B7}  ")
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

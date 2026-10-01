import AppKit

// ---------- Settings ----------
//
// App menu → Settings… (⌘,). Catalogue, sync folder and backups. Everything here is per Mac:
// each Mac chooses its own path to the shared folder.

final class SettingsWindowController: NSWindowController {
    private weak var library: LibraryWindowController?

    private let cataloguePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let folderLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let whenPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keepPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var syncOnlyControls: [NSControl] = []

    private let keepChoices = [10, 25, 50, 100, 0]

    convenience init(library: LibraryWindowController) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Settings"
        win.isReleasedWhenClosed = false
        self.init(window: win)
        self.library = library
        build()
        refresh()
        win.center()
    }

    // MARK: Layout

    private func heading(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return l
    }

    private func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.alignment = .right
        l.textColor = .secondaryLabelColor
        return l
    }

    private func note(_ s: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .horizontal
        s.spacing = 8
        return s
    }

    private func build() {
        guard let content = window?.contentView else { return }

        cataloguePopup.target = self
        cataloguePopup.action = #selector(catalogueChosen)

        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        whenPopup.addItems(withTitles: ["Ask me what to do", "Merge automatically"])
        whenPopup.target = self
        whenPopup.action = #selector(whenChosen)

        keepPopup.addItems(withTitles: keepChoices.map { $0 == 0 ? "Keep every backup" : "Keep the newest \($0)" })
        keepPopup.target = self
        keepPopup.action = #selector(keepChosen)

        let turnOff = button("Turn Off Sync", #selector(turnOffSync))
        let showSync = button("Show in Finder", #selector(showSyncFolder))
        let syncNow = button("Sync Now", #selector(syncNow))
        let showBackups = button("Show Backups", #selector(showBackups))
        syncOnlyControls = [turnOff, showSync, syncNow, whenPopup]

        let grid = NSGridView(views: [
            [heading("Catalogue"), NSGridCell.emptyContentView],
            [label("Open:"), cataloguePopup],
            [NSGridCell.emptyContentView, row([button("New Catalogue\u{2026}", #selector(newCatalogue)),
                                               button("Open File\u{2026}", #selector(openCatalogueFile)),
                                               button("Show in Finder", #selector(showCatalogue))])],
            [NSGridCell.emptyContentView, note("A catalogue is a separate library of colours and swatches. The app reopens the one you used last.")],

            [heading("Sync"), NSGridCell.emptyContentView],
            [label("Folder:"), folderLabel],
            [NSGridCell.emptyContentView, row([button("Choose\u{2026}", #selector(chooseFolder)), turnOff, showSync])],
            [label("When changes are found:"), whenPopup],
            [label("Status:"), statusLabel],
            [NSGridCell.emptyContentView, row([syncNow])],
            [NSGridCell.emptyContentView, note("Pick a folder inside iCloud Drive, Dropbox or any shared drive, then choose the same folder on your other Mac. Every catalogue syncs to its own folder inside it.")],

            [heading("Backups"), NSGridCell.emptyContentView],
            [label("Keep:"), keepPopup],
            [NSGridCell.emptyContentView, row([showBackups])],
            [NSGridCell.emptyContentView, note("Both copies are saved before every merge, in the sync folder and on this Mac.")],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 400
        for r in [0, 4, 11] {
            grid.row(at: r).topPadding = r == 0 ? 0 : 14
            grid.cell(atColumnIndex: 0, rowIndex: r).xPlacement = .leading
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: r, length: 1))
        }
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
    }

    // MARK: State

    func refresh() {
        guard let library = library else { return }

        cataloguePopup.removeAllItems()
        cataloguePopup.addItems(withTitles: library.availableCatalogues())
        cataloguePopup.selectItem(withTitle: library.catalogue)

        let folder = SyncSettings.folder
        folderLabel.stringValue = folder.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Sync is off"
        folderLabel.toolTip = folder?.path
        folderLabel.textColor = folder == nil ? .secondaryLabelColor : .labelColor
        syncOnlyControls.forEach { $0.isEnabled = folder != nil }

        whenPopup.selectItem(at: SyncSettings.askBeforeMerging ? 0 : 1)
        keepPopup.selectItem(at: keepChoices.firstIndex(of: SyncSettings.backupsToKeep) ?? 2)
        statusLabel.stringValue = folder == nil ? "Choose a folder to start syncing." : library.syncStatus
    }

    // MARK: Actions

    @objc private func catalogueChosen() {
        guard let name = cataloguePopup.titleOfSelectedItem else { return }
        library?.open(catalogue: name)
    }

    @objc private func newCatalogue() { library?.newCatalogue() }
    @objc private func openCatalogueFile() { library?.openCatalogueFile() }

    @objc private func showCatalogue() {
        guard let name = library?.catalogue else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [Catalogues.standard.directory(for: name).appendingPathComponent("library.json")])
    }

    @objc private func chooseFolder() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Sync Here"
        panel.message = "Choose a folder in iCloud Drive, Dropbox or another shared location"
        if let current = SyncSettings.folder { panel.directoryURL = current }
        panel.beginSheetModal(for: w) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            SyncSettings.folder = url
            self?.library?.syncNow()
            self?.refresh()
        }
    }

    @objc private func turnOffSync() {
        SyncSettings.folder = nil
        library?.syncTurnedOff()
        refresh()
    }

    @objc private func showSyncFolder() {
        guard let folder = SyncSettings.folder else { return }
        let root = SyncEngine.root(in: folder)
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: root.path) ? root : folder)
    }

    @objc private func syncNow() { library?.syncNow() }

    @objc private func whenChosen() { SyncSettings.askBeforeMerging = whenPopup.indexOfSelectedItem == 0 }

    @objc private func keepChosen() {
        SyncSettings.backupsToKeep = keepChoices[max(0, keepPopup.indexOfSelectedItem)]
    }

    @objc private func showBackups() {
        guard let name = library?.catalogue else { return }
        let dir = Catalogues.standard.directory(for: name).appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

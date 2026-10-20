import AppKit
import UniformTypeIdentifiers

// ---------- Settings ----------
//
// App menu → Settings… (⌘,). Six panels. Everything here is per Mac.

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
    l.font = NSFont.systemFont(ofSize: TextSize.body)
    l.textColor = .secondaryLabelColor
    l.preferredMaxLayoutWidth = 400
    return l
}

private func row(_ views: [NSView]) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .lastBaseline
    s.spacing = 8
    return s
}

private let blank = NSGridCell.emptyContentView

/// A panel is a two-column grid: labels on the left, controls on the right.
class SettingsPanel: NSViewController {
    let library: LibraryController

    init(library: LibraryController, title: String, icon: String) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.icon = icon
    }
    required init?(coder: NSCoder) { fatalError() }

    private(set) var icon = ""
    /// Width of the left-hand column.
    var labelWidth: CGFloat { 170 }

    func rows() -> [[NSView]] { [] }
    /// Rows under every section of the panel, whichever is showing.
    func footerRows() -> [[NSView]] { [] }
    func refresh() {}

    // A panel with more than one heading is shown a section at a time: a bar of the headings at the
    // top, and under it the rows of the one that is chosen. So no panel is taller than its tallest
    // section, and none runs off the foot of the screen.
    private var sectionBar: NSSegmentedControl?
    private var sectionGrids: [NSView] = []
    private var sectionKey: String { "settingsSection." + (title ?? "") }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 9
        grid.columnSpacing = 10
        grid.rowAlignment = .lastBaseline
        grid.yPlacement = .top
        // A panel that is one view across, as Permissions is, has no columns to set.
        guard grid.numberOfColumns > 1 else { return grid }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = labelWidth
        grid.column(at: 1).width = 400
        for r in 0..<grid.numberOfRows {
            // A row with nothing on the right is a heading, and spans both columns.
            guard grid.cell(atColumnIndex: 1, rowIndex: r).contentView == nil,
                  grid.cell(atColumnIndex: 0, rowIndex: r).contentView != nil else { continue }
            grid.row(at: r).topPadding = r == 0 ? 0 : 12
            grid.cell(atColumnIndex: 0, rowIndex: r).xPlacement = .leading
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: r, length: 1))
        }
        return grid
    }

    /// A heading row: a label on the left and nothing on the right.
    private func headingTitle(_ row: [NSView]) -> String? {
        guard row.count == 2, row[1] === blank, row[0] !== blank, let label = row[0] as? NSTextField, !label.stringValue.isEmpty else { return nil }
        return label.stringValue
    }

    override func loadView() {
        let all = rows()
        // The rows under each heading; rows before the first heading go with the first.
        var sections: [(title: String, rows: [[NSView]])] = []
        for row in all {
            if let title = headingTitle(row) { sections.append((title, [])) }
            else if sections.isEmpty { sections.append(("", [row])) }
            else { sections[sections.count - 1].rows.append(row) }
        }
        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .centerX
        body.spacing = 20
        if sections.count > 1 {
            // Each word of a heading starts with a capital on the bar.
            let titles = sections.map { $0.title.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
            let bar = ClickCursorSegmentedControl(labels: titles, trackingMode: .selectOne, target: self, action: #selector(sectionChosen))
            bar.font = NSFont.systemFont(ofSize: TextSize.body)
            bar.selectedSegment = min(max(0, AppPreferences.shared.integer(forKey: sectionKey)), sections.count - 1)
            sectionBar = bar
            sectionGrids = sections.map { grid($0.rows) }
            body.addArrangedSubview(bar)
            sectionGrids.forEach { body.addArrangedSubview($0) }
            for (at, one) in sectionGrids.enumerated() { one.isHidden = at != bar.selectedSegment }
        } else {
            body.addArrangedSubview(grid(all))
        }
        let foot = footerRows()
        if !foot.isEmpty { body.addArrangedSubview(grid(foot)) }
        body.translatesAutoresizingMaskIntoConstraints = false
        let v = NSView()
        v.addSubview(body)
        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: v.topAnchor, constant: 22),
            body.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            body.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 28),
            body.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsPanel.minimumWidth),
        ])
        view = v
    }

    @objc private func sectionChosen() {
        guard let bar = sectionBar else { return }
        AppPreferences.shared.set(bar.selectedSegment, forKey: sectionKey)
        for (at, one) in sectionGrids.enumerated() { one.isHidden = at != bar.selectedSegment }
        view.layoutSubtreeIfNeeded()
        resizeWindow()
    }

    /// The window takes the height of the section now showing, its top edge staying where it is.
    private func resizeWindow() {
        if let group = parent as? SettingsGroupController { group.resizeForSelection(); return }
        let size = view.fittingSize
        preferredContentSize = size
        guard let window = view.window, let content = window.contentView else { return }
        var frame = window.frame
        let change = size.height - content.frame.height
        frame.origin.y -= change
        frame.size.height += change
        window.setFrame(frame, display: true, animate: true)
    }

    /// Every panel is at least this wide, so the window's toolbar shows all the panels' icons.
    static let minimumWidth: CGFloat = 1040

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
        preferredContentSize = view.fittingSize
    }

    func popup(_ titles: [String], _ action: Selector) -> NSPopUpButton {
        let p = ClickCursorPopupButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: titles)
        p.target = self
        p.action = action
        return p
    }

    func check(_ title: String, _ action: Selector) -> NSButton {
        ClickCursorButton(checkboxWithTitle: title, target: self, action: action)
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = ActionButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }
}

// MARK: General

final class GeneralPanel: SettingsPanel {
    private lazy var format = popup(ColourFormat.allCases.map { $0.title }, #selector(changed))
    private lazy var hexCase = popup(["UPPERCASE  \u{2014}  #4F8093", "lowercase  \u{2014}  #4f8093"], #selector(changed))
    private lazy var sounds = check("Play a sound when picking and copying", #selector(changed))
    private lazy var keep = check("Keep picking until Esc is pressed", #selector(changed))
    private lazy var wheel = check("Scrolling past the end of a palette opens the next one", #selector(changed))
    private lazy var imageSize = popup(imageSizes.map { "\($0) colours" }, #selector(changed))
    private let imageSizes = [4, 6, 8, 10, 12, 16]

    override func rows() -> [[NSView]] {[
        [heading("Copying"), blank],
        [label("A click on a swatch copies:"), format],
        [label("Hex letters:"), hexCase],
        [blank, note("The rows on a colour card always copy their own format, whatever is chosen here.")],
        [heading("Picking"), blank],
        [blank, keep],
        [blank, sounds],
        [label("Palette from an image:"), imageSize],
        [blank, note("Fewer are returned when the image has fewer clearly different colours.")],
        [heading("Moving around"), blank],
        [blank, wheel],
    ]}

    override func refresh() {
        format.selectItem(at: ColourFormat.allCases.firstIndex(of: Prefs.copyFormat) ?? 0)
        hexCase.selectItem(at: Prefs.lowercaseHex ? 1 : 0)
        sounds.state = Prefs.sounds ? .on : .off
        keep.state = Prefs.keepPicking ? .on : .off
        wheel.state = Prefs.wheelChangesPalette ? .on : .off
        imageSize.selectItem(at: imageSizes.firstIndex(of: Prefs.imagePaletteSize) ?? 2)
    }

    @objc private func changed() {
        Prefs.copyFormat = ColourFormat.allCases[max(0, format.indexOfSelectedItem)]
        Prefs.lowercaseHex = hexCase.indexOfSelectedItem == 1
        Prefs.sounds = sounds.state == .on
        Prefs.keepPicking = keep.state == .on
        Prefs.wheelChangesPalette = wheel.state == .on
        Prefs.imagePaletteSize = imageSizes[max(0, imageSize.indexOfSelectedItem)]
    }
}

// MARK: Cards & Grid

final class AppearancePanel: SettingsPanel {
    private lazy var rowChecks: [NSButton] = ColourFormat.cardRows.map { check($0.label, #selector(changed)) }
    private lazy var names = check("Show colour names", #selector(changed))
    private lazy var contrast = check("Show contrast against white and black text", #selector(changed))
    private lazy var size = popup(TileSize.allCases.map { $0.title }, #selector(changed))
    private lazy var bars = check("Show palette bars under the tiles", #selector(changed))

    override func rows() -> [[NSView]] {[
        [heading("Swatch Cards"), blank],
        [label("Rows on each card:"), row(Array(rowChecks.prefix(5)))],
        [blank, row(Array(rowChecks.dropFirst(5)))],
        [blank, note("P3, Adobe RGB and BT.2020 are the same colour written in those wider spaces; L*a*b* is under D50.")],
        [blank, names],
        [blank, note("Names are the nearest of about 1,700 named colours, so they are approximate.")],
        [blank, contrast],
        [blank, note("The ratio and its WCAG grade: AA needs 4.5 for body text, AAA needs 7.")],
        [heading("All Swatches"), blank],
        [label("Tile size:"), size],
        [blank, bars],
        [blank, note("Each palette has its own colour, shown as a bar under its swatches.")],
    ]}

    override func refresh() {
        let shown = Prefs.houseCardRows
        for (b, f) in zip(rowChecks, ColourFormat.cardRows) { b.state = shown.contains(f) ? .on : .off }
        names.state = Prefs.showNames ? .on : .off
        contrast.state = Prefs.showContrast ? .on : .off
        bars.state = Prefs.showPaletteBars ? .on : .off
        size.selectItem(at: Prefs.tileSize.rawValue)
    }

    @objc private func changed(_ sender: NSControl) {
        if rowChecks.contains(where: { $0 === sender }) {
            let selected = zip(rowChecks, ColourFormat.cardRows).filter { $0.0.state == .on }.map { $0.1 }
            if selected != Prefs.houseCardRows { Prefs.houseCardRows = selected }
        } else if sender === names {
            if (names.state == .on) != Prefs.showNames { Prefs.showNames = names.state == .on }
        } else if sender === contrast {
            if (contrast.state == .on) != Prefs.showContrast { Prefs.showContrast = contrast.state == .on }
        } else if sender === bars {
            if (bars.state == .on) != Prefs.showPaletteBars { Prefs.showPaletteBars = bars.state == .on }
        } else if sender === size {
            let selected = TileSize(rawValue: size.indexOfSelectedItem) ?? .medium
            if selected != Prefs.tileSize { Prefs.tileSize = selected }
        }
    }
}

// MARK: Export

final class ExportPanel: SettingsPanel, NSTextFieldDelegate, NSTextViewDelegate {
    private lazy var format = popup(ExportFormat.allCases.map { $0.title }, #selector(changed))
    private lazy var naming = popup(["Colour names  \u{2014}  steel-blue", "Numbers  \u{2014}  1, 2, 3"], #selector(changed))
    private lazy var hexCase = popup(["lowercase  \u{2014}  #4f8093", "UPPERCASE  \u{2014}  #4F8093"], #selector(changed))
    private let prefix = NSTextField(string: "")
    private let preview = NSTextField(labelWithString: "")
    private let owner = NSTextField(string: "")
    private let licence = NSTextView()
    override func rows() -> [[NSView]] {
        prefix.delegate = self
        prefix.placeholderString = "swatch"
        prefix.widthAnchor.constraint(equalToConstant: 160).isActive = true
        preview.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        preview.textColor = .secondaryLabelColor
        return [
            [heading("Exporting palettes"), blank],
            [label("Usual format:"), format],
            [blank, note("The format offered first when you export. You can still choose another each time.")],
            [heading("Variable names"), blank],
            [label("Prefix:"), prefix],
            [label("Name each colour by:"), naming],
            [label("Hex letters:"), hexCase],
            [label("Example:"), preview],
            [blank, note("Used by the CSS, SCSS and Android formats. Tailwind always uses --color-, as Tailwind expects.")],
            [heading("Adobe apps"), blank],
            [blank, note(Permission.all.isEmpty
                ? "Add To Adobe Apps writes a palette in the form Photoshop, Illustrator or InDesign expects, for you to put in that app's library folder."
                : "Add To Adobe Apps puts a palette where Photoshop, Illustrator or InDesign keeps its libraries. Doing that without a password each time is set up under Permissions.")],
            [heading("Design pack licence"), blank],
            [label("Owner:"), owner],
            [label("Licence text:"), licenceBox()],
            [blank, row([button("Use the Standard Text", #selector(resetLicence))])],
            [blank, note("Written to LICENSE.md in every design pack. {owner}, {year} and {pack} are filled in at export.")],
        ]
    }

    private func licenceBox() -> NSView {
        owner.placeholderString = "Your name or company"
        owner.delegate = self
        owner.widthAnchor.constraint(equalToConstant: 260).isActive = true
        licence.isRichText = false
        licence.font = NSFont.systemFont(ofSize: 13)
        licence.isAutomaticQuoteSubstitutionEnabled = false
        licence.textContainerInset = NSSize(width: 4, height: 6)
        licence.delegate = self
        licence.autoresizingMask = [.width]
        licence.textContainer?.widthTracksTextView = true
        let scroll = FittedScrollView()
        scroll.documentView = licence
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 120).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 400).isActive = true
        return scroll
    }

    @objc private func resetLicence() {
        Prefs.licenceText = DesignPack.defaultLicence
        licence.string = Prefs.licenceText
    }

    func textDidEndEditing(_ notification: Notification) { Prefs.licenceText = licence.string }

    override func refresh() {
        let o = Prefs.exportOptions
        format.selectItem(at: ExportFormat.allCases.firstIndex(of: Prefs.exportFormat) ?? 0)
        naming.selectItem(at: o.naming.rawValue)
        hexCase.selectItem(at: o.lowercaseHex ? 0 : 1)
        prefix.stringValue = o.prefix
        owner.stringValue = Prefs.licenceOwner
        if licence.string != Prefs.licenceText { licence.string = Prefs.licenceText }
        showPreview()
    }

    private func showPreview() {
        let sample = [ExportPalette(name: "Brand", colours: [ExportColour(name: "Steel Blue", hex: "#4F8093")])]
        let css = ExportFormat.css.data(sample, options: Prefs.exportOptions).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        preview.stringValue = css.split(separator: "\n").first { $0.contains("--") }.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    @objc private func changed() {
        Prefs.exportFormat = ExportFormat.allCases[max(0, format.indexOfSelectedItem)]
        var o = ExportOptions()
        o.prefix = slug(prefix.stringValue.isEmpty ? "swatch" : prefix.stringValue)
        o.naming = ExportOptions.Naming(rawValue: naming.indexOfSelectedItem) ?? .names
        o.lowercaseHex = hexCase.indexOfSelectedItem == 0
        Prefs.exportOptions = o
        showPreview()
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === owner { Prefs.licenceOwner = owner.stringValue; return }
        changed()
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === owner { Prefs.licenceOwner = owner.stringValue; return }
        changed(); prefix.stringValue = Prefs.exportOptions.prefix
    }
}

// MARK: Catalogues

final class CataloguePanel: SettingsPanel {
    private lazy var open = popup([], #selector(chosen))

    override func rows() -> [[NSView]] {[
        [heading("Catalogue"), blank],
        [label("Default Catalogue:"), open],
        [blank, row([button("New\u{2026}", #selector(newCatalogue)), button("Rename\u{2026}", #selector(renameCatalogue)),
                     button("Open File\u{2026}", #selector(openFile)), button("Show in Finder", #selector(reveal))])],
        [blank, note("Choose the catalogue to open now. Colorgain remembers it and opens it at your next launch. Each catalogue keeps its own Library tree and last selected page. Open File adds a library.json export or backup as a new catalogue.")],
        [heading("Earlier versions"), blank],
        [blank, row([button("Import from MMFFDev Colour 2", #selector(importV2))])],
        [blank, note("Adds anything in your version 2 library that is missing here. Version 2's own library is never changed.")],
    ]}

    override func refresh() {
        open.removeAllItems()
        open.addItems(withTitles: library.availableCatalogues())
        open.selectItem(withTitle: library.catalogue)
    }

    @objc private func chosen() { if let name = open.titleOfSelectedItem { library.open(catalogue: name) } }
    @objc private func newCatalogue() { library.newCatalogue(); refresh() }
    @objc private func renameCatalogue() { library.renameCatalogue(); refresh() }
    @objc private func openFile() { library.openCatalogueFile(); refresh() }
    @objc private func importV2() { library.importFromV2() }

    @objc private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting(
            [library.store.url])
    }
}

// MARK: Sync

final class SyncPanel: SettingsPanel {
    private let folder = NSTextField(labelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private lazy var when = popup(["Ask me what to do", "Merge automatically"], #selector(changed))
    private lazy var keep = popup(keepChoices.map { $0 == 0 ? "Keep every backup" : "Keep the newest \($0)" }, #selector(changed))
    private lazy var turnOff = button("Turn Off Sync", #selector(turnOffSync))
    private lazy var showFolder = button("Show in Finder", #selector(showSyncFolder))
    private lazy var syncNow = button("Sync Now", #selector(syncNowTapped))
    private let keepChoices = [10, 25, 50, 100, 0]

    override func rows() -> [[NSView]] {
        folder.lineBreakMode = .byTruncatingMiddle
        folder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.preferredMaxLayoutWidth = 400
        return [
            [heading("Sync"), blank],
            [label("Folder:"), folder],
            [blank, row([button("Choose\u{2026}", #selector(chooseFolder)), turnOff, showFolder])],
            [label("When changes are found:"), when],
            [label("Status:"), status],
            [blank, row([syncNow])],
            [blank, note("Pick a folder inside iCloud Drive, Dropbox or any shared drive, then choose the same folder on your other Mac. Every catalogue syncs to its own folder inside it.")],
            [heading("Backups"), blank],
            [label("Keep:"), keep],
            [blank, row([button("Show Backups", #selector(showBackups))])],
            [blank, note("Both copies are saved before every merge, in the sync folder and on this Mac.")],
        ]
    }

    override func refresh() {
        guard isViewLoaded else { return }
        let chosen = SyncSettings.folder
        folder.stringValue = chosen.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Sync is off"
        folder.toolTip = chosen?.path
        folder.textColor = chosen == nil ? .secondaryLabelColor : .labelColor
        [turnOff, showFolder, syncNow, when].forEach { ($0 as NSControl).isEnabled = chosen != nil }
        when.selectItem(at: SyncSettings.askBeforeMerging ? 0 : 1)
        keep.selectItem(at: keepChoices.firstIndex(of: SyncSettings.backupsToKeep) ?? 2)
        status.stringValue = chosen == nil ? "Choose a folder to start syncing." : library.syncStatus
    }

    @objc private func changed() {
        SyncSettings.askBeforeMerging = when.indexOfSelectedItem == 0
        SyncSettings.backupsToKeep = keepChoices[max(0, keep.indexOfSelectedItem)]
    }

    @objc private func chooseFolder() {
        guard let w = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Sync Here"
        panel.message = "Choose a folder in iCloud Drive, Dropbox or another shared location"
        if let current = SyncSettings.folder { panel.directoryURL = current }
        panel.beginSheetModal(for: w) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if let old = SyncSettings.folder, old != url { FolderAccess.forget(old) }
            FolderAccess.remember(url)
            SyncSettings.folder = url
            self?.library.syncNow()
            self?.refresh()
        }
    }

    @objc private func turnOffSync() {
        if let old = SyncSettings.folder { FolderAccess.forget(old) }
        SyncSettings.folder = nil
        library.syncTurnedOff()
        refresh()
    }

    @objc private func showSyncFolder() {
        guard let chosen = SyncSettings.folder else { return }
        let root = SyncEngine.root(in: chosen)
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: root.path) ? root : chosen)
    }

    @objc private func syncNowTapped() { library.syncNow() }

    @objc private func showBackups() {
        let dir = Catalogues.standard.directory(for: library.catalogue).appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
}

// MARK: Shortcuts

final class ShortcutsPanel: SettingsPanel {
    private var quickFields:[String:ShortcutField]=[:]
    private var fields: [ShortcutField] = []
    private var ids: [String] = []
    private let message = note(" ")

    override var labelWidth: CGFloat { 220 }

    override func rows() -> [[NSView]] {
        message.textColor = .systemRed
        // A section to each menu, so the list is never longer than the longest menu.
        var rows: [[NSView]] = [[heading("Quick Keys"),blank]]
        for command in QuickKeys.commands {
            let field=ShortcutField(frame:.zero);field.quickKey=QuickKeys.key(for:command.id)
            field.onQuickRecord={ [weak self] key in self?.recordQuick(key,for:command.id) }
            quickFields[command.id]=field
            let clear=symbolButton("xmark.circle",tooltip:"Remove this quick key",target:self,action:#selector(clearQuick(_:)))
            clear.identifier=NSUserInterfaceItemIdentifier(command.id)
            rows.append([label(command.title+":"),row([field,clear])])
        }
        var menu = ""
        for (at, command) in Shortcuts.commands.enumerated() {
            if command.menu != menu {
                menu = command.menu
                rows.append([heading(menu), blank])
            }
            let field = ShortcutField(frame: .zero)
            field.onRecord = { [weak self] shortcut, keyCode in self?.record(shortcut, keyCode, at: at) }
            let clear = symbolButton("xmark.circle", tooltip: "Remove this shortcut", target: self, action: #selector(clear(_:)))
            clear.tag = at
            fields.append(field)
            ids.append(command.id)
            rows.append([label(command.title + ":"), row([field, clear])])
        }
        return rows
    }

    override func footerRows() -> [[NSView]] {
        [
            [blank, message],
            [blank, button("Restore Defaults", #selector(restore))],
            [blank, note("Click a shortcut, then type the new one. Shortcuts that macOS or the Edit menu already use, such as \u{2318}C for Copy, cannot be taken.")],
        ]
    }

    override func refresh() {
        for (id,field) in quickFields {field.quickKey=QuickKeys.key(for:id)}
        let current = Dictionary(uniqueKeysWithValues: Shortcuts.commands.map { ($0.id, $0.shortcut) })
        for (field, id) in zip(fields, ids) { field.shortcut = current[id] ?? nil }
    }

    private func recordQuick(_ key:String?,for id:String){
        if let key,let conflict=QuickKeys.commands.first(where:{$0.id != id && QuickKeys.key(for:$0.id) == key}) {
            message.stringValue="\(key) is already used by \(conflict.title)."
        } else {QuickKeys.set(key ?? "",for:id);message.stringValue=" "}
        view.window?.makeFirstResponder(nil);refresh()
    }
    @objc private func clearQuick(_ sender:NSButton){if let id=sender.identifier?.rawValue{recordQuick(nil,for:id)}}

    private func record(_ shortcut: Shortcut?, _ keyCode: Int?, at: Int) {
        let problem = Shortcuts.set(shortcut, keyCode: keyCode, for: ids[at])
        message.stringValue = shortcut.flatMap { s in problem?.message(for: s) } ?? " "
        view.window?.makeFirstResponder(nil)
        refresh()
    }

    @objc private func clear(_ sender: NSButton) { record(nil, nil, at: sender.tag) }

    @objc private func restore() {
        Shortcuts.restoreDefaults();Prefs.quickKeys=[:]
        message.stringValue = " "
        refresh()
    }
}

// MARK: Theme

final class ThemePanel: SettingsPanel {
    private let selectionBackground = ClickCursorColorWell()
    private let selectionText = ClickCursorColorWell()
    private let hoverBackground = ClickCursorColorWell()
    private let hoverText = ClickCursorColorWell()
    private let activeBackground = ClickCursorColorWell()
    private let activeText = ClickCursorColorWell()
    /// Match The Mac, Light, Dark, My Own Colours: one is always ticked.
    private lazy var modes: [NSButton] = ThemeMode.allCases.map { check($0.title, #selector(modeChosen(_:))) }
    /// For My Own Colours: the background, and whether its text is black, white, or whichever reads better.
    private let ownBackground = ClickCursorColorWell()
    private lazy var ownText = popup(ThemeText.allCases.map { $0.title }, #selector(ownChanged))

    @objc private func ownChanged() {
        if let hex = hexOf(ownBackground.color) { Theme.customBackground = hex }
        if ThemeText.allCases.indices.contains(ownText.indexOfSelectedItem) { Theme.customText = ThemeText.allCases[ownText.indexOfSelectedItem] }
        Theme.choose(.custom)   // changing a colour of your own turns them on
        refresh()
    }

    @objc private func modeChosen(_ sender: NSButton) {
        if ThemeMode.allCases.indices.contains(sender.tag) { Theme.choose(ThemeMode.allCases[sender.tag]) }
        refresh()
    }

    override func rows() -> [[NSView]] {
        for (at, box) in modes.enumerated() { box.tag = at }
        ownBackground.target = self
        ownBackground.action = #selector(ownChanged)
        ownBackground.widthAnchor.constraint(equalToConstant: 44).isActive = true
        ownBackground.heightAnchor.constraint(equalToConstant: 24).isActive = true
        for well in [selectionBackground, selectionText, hoverBackground, hoverText, activeBackground, activeText] {
            well.target = self
            well.action = #selector(changed(_:))
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        func pair(_ background: NSColorWell, _ text: NSColorWell) -> NSView {
            row([background, caption("Background", size: TextSize.caption), text, caption("Text", size: TextSize.caption)])
        }
        return [
            [heading("Appearance"), blank],
            [label("Theme:"), modes[0]],
            [blank, modes[1]],
            [blank, modes[2]],
            [blank, modes[3]],
            [label("My Background:"), row([ownBackground])],
            [label("My Text:"), ownText],
            [blank, note("Match The Mac follows System Settings; Light and Dark hold whatever the Mac says. Light is an off-white, a neutral grey just below white. My Own Colours puts your background on every page, with black or white text: Automatic takes whichever reads better on it. The button at the foot of the window switches between light and dark. Press L to turn the background charcoal, then black, then white, then off-white, then back to the theme, and Shift-L to show the page alone, full screen.")],
            [heading("Sidebar"), blank],
            [label("Selected Row:"), pair(selectionBackground, selectionText)],
            [blank, row([button("Reset To Default", #selector(resetSidebar))])],
            [heading("Buttons"), blank],
            [label("Hover:"), pair(hoverBackground, hoverText)],
            [label("Active:"), pair(activeBackground, activeText)],
            [blank, row([button("Reset To Default", #selector(resetButtons))])],
            [blank, note("Hover is a button under the pointer; Active is one being pressed, or the choice that is on in a toggle. The defaults are greys taken from the background, so the controls stay quiet beside your colours. They follow the background as it is stepped lighter or darker.")],
        ]
    }

    override func refresh() {
        for (box, mode) in zip(modes, ThemeMode.allCases) { box.state = mode == Theme.mode ? .on : .off }
        ownBackground.color = colorFromHex(Theme.customBackground) ?? .gray
        ownText.selectItem(at: ThemeText.allCases.firstIndex(of: Theme.customText) ?? 0)
        selectionBackground.color = Theme.sidebarSelectionBackground
        selectionText.color = Theme.sidebarSelectionText
        hoverBackground.color = Theme.buttonHoverBackground
        hoverText.color = Theme.buttonHoverText
        activeBackground.color = Theme.buttonActiveBackground
        activeText.color = Theme.buttonActiveText
    }

    /// Only the well that was changed is kept; the others stay on their defaults.
    @objc private func changed(_ well: NSColorWell) {
        let hex = hexOf(well.color)
        switch well {
        case selectionBackground: Prefs.sidebarSelectionBackground = hex
        case selectionText: Prefs.sidebarSelectionText = hex
        case hoverBackground: Prefs.buttonHoverBackground = hex
        case hoverText: Prefs.buttonHoverText = hex
        case activeBackground: Prefs.buttonActiveBackground = hex
        default: Prefs.buttonActiveText = hex
        }
        library.reloadSidebarTheme()
    }

    @objc private func resetSidebar() {
        Prefs.sidebarSelectionBackground = nil
        Prefs.sidebarSelectionText = nil
        refresh()
        library.reloadSidebarTheme()
    }

    @objc private func resetButtons() {
        Prefs.buttonHoverBackground = nil
        Prefs.buttonHoverText = nil
        Prefs.buttonActiveBackground = nil
        Prefs.buttonActiveText = nil
        refresh()
    }
}

// MARK: Halo

/// A slider that goes back to its starting value on a double click.
final class ResettingSlider: ClickCursorSlider {
    var resting = 1.0
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2 else { super.mouseDown(with: event); return }
        doubleValue = resting
        sendAction(action, to: target)
    }
}

/// The halo: how fast the mouse wheel turns it, its colours, and a halo to try them on.
final class HaloSettingsPanel: SettingsPanel {
    private let speed = ResettingSlider(value: 1, minValue: Prefs.haloWheelSpeedRange.lowerBound, maxValue: Prefs.haloWheelSpeedRange.upperBound, target: nil, action: nil)
    private var tester: HaloMenu?
    /// The halo's wells, each with the name its colour is saved under.
    private var haloWells: [(well: NSColorWell, part: String)] = []
    /// The halo's layers, in the order of their Reset buttons: the name parts each one clears.
    private let haloLayers = [["centre.background", "centre.text"]] + (1...3).map { n in
        ["background", "text", "cursorBackground", "cursorText"].map { "ring\(n).\($0)" }
    }

    private func haloPair(_ background: String, _ text: String, reset layer: Int? = nil) -> NSView {
        let wells = [background, text].map { part -> NSColorWell in
            let well = ClickCursorColorWell()
            haloWells.append((well, part))
            return well
        }
        var views: [NSView] = [wells[0], caption("Background", size: TextSize.caption), wells[1], caption("Text", size: TextSize.caption)]
        if let layer = layer {
            let reset = button("Reset", #selector(resetHalo(_:)))
            reset.tag = layer
            views.append(reset)
        }
        return row(views)
    }

    override func rows() -> [[NSView]] {
        haloWells = []
        speed.resting = 1
        speed.target = self
        speed.action = #selector(speedChanged)
        speed.widthAnchor.constraint(equalToConstant: 200).isActive = true
        speed.toolTip = "Double-click to reset"
        var out: [[NSView]] = [
            [heading("Scrolling"), blank],
            [label("Mouse Sensitivity:"), row([caption("Slower", size: TextSize.caption), speed, caption("Faster", size: TextSize.caption)])],
            [blank, row([button("Test Halo", #selector(test(_:)))])],
            [blank, note("How far the wheel or trackpad has to move to turn a ring by one place. Double-click the slider to put it back. Test Halo opens a halo of letters: Up grows the next ring, the back arrow steps back one ring, and X closes the halo.")],
            [heading("Colours"), blank],
            [label("Information:"), haloPair("centre.background", "centre.text", reset: 0)],
        ]
        for (n, name) in ["Primary", "Secondary", "Tertiary"].enumerated() {
            out.append([label("\(name) Ring:"), haloPair("ring\(n + 1).background", "ring\(n + 1).text", reset: n + 1)])
            out.append([label("Highlight Cursor:"), haloPair("ring\(n + 1).cursorBackground", "ring\(n + 1).cursorText")])
        }
        out.append([blank, note("Information is the circle in the middle of the halo. Primary is the first ring; Secondary and Tertiary are the rings that grow outside it. A ring's Highlight Cursor is the wedge at the top that marks the choice. Unset, the rings are the button colours turned round, and Information and the cursors are the button colours as they are. Reset puts one layer back.")])
        for item in haloWells {
            item.well.target = self
            item.well.action = #selector(changed(_:))
            item.well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            item.well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        return out
    }

    override func refresh() {
        speed.doubleValue = Prefs.haloWheelSpeed
        for item in haloWells { item.well.color = Theme.halo(item.part) }
    }

    @objc private func speedChanged() { Prefs.haloWheelSpeed = speed.doubleValue }

    @objc private func changed(_ well: NSColorWell) {
        if let halo = haloWells.first(where: { $0.well === well }) { Prefs.setHaloColour(hexOf(well.color), halo.part) }
    }

    /// Puts one layer of the halo back to its defaults: the centre, or a ring with its cursor.
    @objc private func resetHalo(_ sender: NSButton) {
        guard haloLayers.indices.contains(sender.tag) else { return }
        for part in haloLayers[sender.tag] { Prefs.setHaloColour(nil, part) }
        refresh()
    }

    /// Opens a halo of letters over the button, three rings deep, to try the wheel and the colours on.
    @objc private func test(_ sender: NSButton) {
        let halo = tester ?? HaloMenu(label: "Test Halo", hint: "Scroll to turn, click to choose", actions: [])
        tester = halo
        halo.actions = HaloSettingsPanel.letters { [weak halo] in halo?.back() }
        halo.open(over: sender)
    }

    /// The alphabet over three rings: A to I, J to R, S to Z. Up grows the next ring (the last
    /// has none), and X closes the halo from the first ring.
    static func letters(back: @escaping () -> Void) -> [HaloAction] {
        let rings = [Array("ABCDEFGHI"), Array("JKLMNOPQR"), Array("STUVWXYZ")]
        func ring(_ at: Int) -> [HaloAction] {
            var out = rings[at].map { letter in
                HaloAction(id: String(letter), label: String(letter), symbol: "\(String(letter).lowercased()).circle", description: "Ring \(at + 1)", keepsOpen: true)
            }
            if at + 1 < rings.count {
                out.append(HaloAction(id: "up\(at)", label: "Up", symbol: "arrow.up", description: "Open ring \(at + 2)", children: { ring(at + 1) }))
            }
            // The first ring closes with X; the rings outside it get the halo's own back arrow.
            if at == 0 { out.append(HaloAction(id: "x", label: "X", symbol: "xmark", description: "Close the halo", keepsOpen: true, onSelect: back)) }
            return out
        }
        return ring(0)
    }
}

// MARK: Projects

/// What a project starts with. For now: the purpose a new palette is turned to.
final class ProjectsPanel: SettingsPanel {
    /// One box per purpose, of which exactly one is ticked.
    private lazy var purposes: [NSButton] = Purpose.allCases.map { check($0.title, #selector(purposeChosen(_:))) }

    override func rows() -> [[NSView]] {
        for (at, box) in purposes.enumerated() {
            box.tag = at
            box.toolTip = Purpose.allCases[at].about
        }
        var out: [[NSView]] = [[heading("Default Purpose"), blank]]
        for (at, box) in purposes.enumerated() { out.append([at == 0 ? label("New Palettes Are For:") : blank, box]) }
        out.append([blank, note("Every palette is turned to one purpose at a time, which sets the values and the checks its page shows. A new palette starts on the purpose ticked here, and it can be turned to another under Purposes on its page.")])
        return out
    }

    override func refresh() {
        let chosen = Prefs.defaultPurpose
        for (box, purpose) in zip(purposes, Purpose.allCases) { box.state = purpose == chosen ? .on : .off }
    }

    /// One is always ticked: a press on the ticked one leaves it ticked, and a press on another moves the tick.
    @objc private func purposeChosen(_ sender: NSButton) {
        if Purpose.allCases.indices.contains(sender.tag) { Prefs.defaultPurpose = Purpose.allCases[sender.tag] }
        refresh()
    }
}

// MARK: Organisation

/// Who is using the app: the same fields as the project form's Studio section. Kept as typed, and
/// laid into the Studio section of every new project, where each can still be changed or filled
/// from a template.
final class OrganisationPanel: SettingsPanel, NSTextFieldDelegate {
    private var fields: [(field: ProjectField, box: NSTextField)] = []

    override func rows() -> [[NSView]] {
        var out: [[NSView]] = [[heading("Organisation"), blank]]
        for field in ProjectField.fields(in: .studio) {
            let box = NSTextField()
            box.placeholderString = field.placeholder
            box.delegate = self
            if field.kind == .lines {
                box.tag = 1   // Return starts a new line in these
                box.usesSingleLineMode = false
                box.cell?.wraps = true
                box.cell?.isScrollable = false
                box.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
            fields.append((field, box))
            out.append([label(field.title + ":"), box])
        }
        out.append([blank, note("Your own organisation. A new project's Studio section starts with these details; on the project's Overview page any of them can be changed, or filled from a saved template.")])
        return out
    }

    override func refresh() {
        let saved = Prefs.organisation
        for (field, box) in fields where box.currentEditor() == nil { box.stringValue = saved[field.rawValue] ?? "" }
    }

    private func keep() {
        var values: [String: String] = [:]
        for (field, box) in fields { values[field.rawValue] = box.stringValue }
        Prefs.organisation = ProjectField.tidy(values)
    }

    func controlTextDidChange(_ obj: Notification) { keep() }
    func controlTextDidEndEditing(_ obj: Notification) { keep() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control.tag == 1, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }
}

// MARK: Colour

/// The house's colour profiles: named sets of channels a project or a palette is proofed for.
/// Every change is kept as it is made.
final class ColourPanel: SettingsPanel, NSTextFieldDelegate {
    private var profiles: [ColourProfile] = []
    private var selected: UUID?
    private lazy var picker = popup([], #selector(picked))
    private let nameField = NSTextField()
    private var spaceChecks: [(space: RGBSpace, box: NSButton)] = []
    private var targetChecks:[(space:ColourTargetSpace,box:NSButton)]=[]
    private lazy var printCheck = check("Print, through a press profile", #selector(changed))
    private lazy var press = popup(PressProfiles.all.map { $0.name }, #selector(changed))
    private lazy var intent = popup(RenderingIntent.allCases.map { $0.name }, #selector(changed))
    private lazy var blackPoint = check("Black Point Compensation", #selector(changed))
    private lazy var legal = check("Video Values In Legal Range (64 To 940)", #selector(changed))
    private lazy var houseDefault = check("Use for palettes and projects with no profile of their own", #selector(defaultChanged))
    private lazy var remove = button("Delete", #selector(deleteTapped))

    override func rows() -> [[NSView]] {
        nameField.delegate = self
        targetChecks=ColourTargetSpace.allCases.map{($0,check($0.name+": "+$0.hint,#selector(changed)))}
        spaceChecks = RGBSpace.allCases.map { ($0, check("\($0.name): \($0.about)", #selector(changed))) }
        var out: [[NSView]] = [
            [heading("Colour Profiles"), blank],
            [label("Profile:"), row([picker, button("New", #selector(newTapped)), button("Duplicate", #selector(duplicateTapped)), remove])],
            [label("Name:"), nameField],
            [blank, houseDefault],
            [heading("Channels"), blank],
        ]
        var lastChannel = ""
        for (space, box) in spaceChecks {
            out.append([space.channel == lastChannel ? blank : label(space.channel + ":"), box])
            lastChannel = space.channel
            if space == RGBSpace.allCases.last(where: { $0.isVideo }) { out.append([blank, legal]) }
        }
        for (space,box) in targetChecks {out.append([label(space.name+":"),box])}
        out += [
            [label("Print:"), printCheck],
            [label("Press profile:"), press],
            [label("Rendering intent:"), intent],
            [blank, blackPoint],
            [blank, note("A profile is the set of channels a piece of work is delivered to. A project picks one on its Overview page and a palette can pick its own. Each swatch then shows, under Channels, the value to use in every channel and how far it sits from the master colour. Press profiles are the ICC files on this Mac. Relative colorimetric keeps a colour that is in range exactly as it is, which is what a brand colour needs. Absolute colorimetric shows the colour on the press's own paper. Black point compensation keeps dark colours apart on a press whose black is not fully dark, at the cost of lifting them slightly. Legal range writes Rec. 709 and Rec. 2020 values as broadcast expects, 64 for black and 940 for white. The CMYK row on every card is the build for this press.")],
        ]
        return out
    }

    override func refresh() {
        profiles = ColourProfiles.load()
        if selected == nil || !profiles.contains(where: { $0.id == selected }) { selected = ColourProfiles.houseDefault ?? profiles.first?.id }
        if !profiles.contains(where: { $0.id == selected }) { selected = profiles.first?.id }
        show()
    }

    private var current: Int? { profiles.firstIndex { $0.id == selected } }

    private func show() {
        picker.removeAllItems()
        picker.addItems(withTitles: profiles.map { $0.name })
        guard let i = current else { return }
        picker.selectItem(at: i)
        let p = profiles[i]
        if nameField.currentEditor() == nil { nameField.stringValue = p.name }
        for (space, box) in spaceChecks { box.state = p.holds(space.rawValue) ? .on : .off }
        for (space,box) in targetChecks {box.state=p.holds(space.rawValue) ? .on:.off}
        printCheck.state = p.print != nil ? .on : .off
        let chosenPress = p.print?.press ?? PressProfiles.generic
        if press.itemTitles.contains(chosenPress) { press.selectItem(withTitle: chosenPress) }
        intent.selectItem(at: RenderingIntent.allCases.firstIndex(of: p.print?.intent ?? .relative) ?? 0)
        press.isEnabled = p.print != nil
        intent.isEnabled = p.print != nil
        blackPoint.state = p.print?.blackPoint == true ? .on : .off
        blackPoint.isEnabled = p.print != nil && p.print?.intent != .perceptual
        let video = p.channels.filter { $0.rgb?.isVideo == true }
        legal.state = video.contains { $0.legal == true } ? .on : .off
        legal.isEnabled = !video.isEmpty
        houseDefault.state = (ColourProfiles.houseDefault ?? profiles.first?.id) == p.id ? .on : .off
        remove.isEnabled = profiles.count > 1
    }

    /// Writes the profiles and tells the pages, which show their proofs afresh.
    private func keep() {
        try? ColourProfiles.save(profiles)
        NotificationCenter.default.post(name: .prefsDidChange, object: nil)
    }

    @objc private func picked() {
        view.window?.makeFirstResponder(nil)
        if profiles.indices.contains(picker.indexOfSelectedItem) { selected = profiles[picker.indexOfSelectedItem].id }
        show()
    }

    @objc private func changed() {
        guard let i = current else { return }
        var channels = spaceChecks.filter { $0.box.state == .on }.map {
            ProfileChannel(space: $0.space.rawValue, legal: $0.space.isVideo && legal.state == .on ? true : nil)
        }
        channels += targetChecks.filter{$0.box.state == .on}.map{ProfileChannel(space:$0.space.rawValue,legal:$0.space.isHDR && legal.state == .on ? true:nil)}
        if printCheck.state == .on {
            channels.append(ProfileChannel(space: ProfileChannel.print, press: press.titleOfSelectedItem ?? PressProfiles.generic,
                                           intent: RenderingIntent.allCases[max(intent.indexOfSelectedItem, 0)],
                                           blackPoint: blackPoint.state == .on ? true : nil))
        }
        profiles[i].channels = channels
        profiles[i].changedAt = Date()
        keep()
        show()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let i = current else { return }
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != profiles[i].name else { nameField.stringValue = profiles[i].name; return }
        profiles[i].name = typed
        profiles[i].changedAt = Date()
        keep()
        show()
    }

    @objc private func defaultChanged() {
        guard let i = current else { return }
        // There is always a default: unticking the one that is it leaves it ticked.
        ColourProfiles.houseDefault = profiles[i].id
        keep()
        show()
    }

    private func add(_ profile: ColourProfile) {
        view.window?.makeFirstResponder(nil)
        profiles.append(profile)
        selected = profile.id
        keep()
        show()
        view.window?.makeFirstResponder(nameField)
    }

    @objc private func newTapped() {
        add(ColourProfile(id: UUID(), name: uniqueName("New Profile", among: profiles.map { $0.name }), channels: [ProfileChannel(space: RGBSpace.srgb.rawValue)], changedAt: Date()))
    }

    @objc private func duplicateTapped() {
        guard let i = current else { return }
        add(ColourProfile(id: UUID(), name: uniqueName(profiles[i].name + " Copy", among: profiles.map { $0.name }), channels: profiles[i].channels, changedAt: Date()))
    }

    @objc private func deleteTapped() {
        guard let i = current, profiles.count > 1 else { return }
        let gone = profiles.remove(at: i).id
        if ColourProfiles.houseDefault == gone { ColourProfiles.houseDefault = profiles.first?.id }
        selected = profiles[min(i, profiles.count - 1)].id
        keep()
        show()
    }
}

// MARK: History

final class HistoryPanel: SettingsPanel {
    private lazy var enabled = check("Keep a history for this library", #selector(enabledChanged))
    private let whereKept = NSTextField(labelWithString: "")
    private let stepChoices = [0, 25, 50, 100, 200, 500]
    private lazy var steps = popup(stepChoices.map { $0 == 0 ? "Unlimited" : "\($0)" }, #selector(changed))

    override func rows() -> [[NSView]] {
        whereKept.lineBreakMode = .byTruncatingMiddle
        whereKept.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return [
            [heading("History"), blank],
            [blank, enabled],
            [blank, note("Every change becomes a step in the History rail (View \u{25B8} Show History). Click a step to go back to it. Each library keeps a history of its own.")],
            [heading("Global history"), blank],
            [label("Kept in:"), whereKept],
            [blank, row([button("Show in Finder", #selector(showFile)), button("Clear History", #selector(clear))])],
            [blank, note("A file of its own beside the catalogue\u{2019}s index, holding what each step changed, never a copy of everything, so it stays small and can be cleared without touching your work.")],
            [heading("Steps to save"), blank],
            [label("Keep:"), steps],
            [blank, note("Once the limit is reached the oldest step is dropped. Unlimited keeps everything.")],
        ]
    }

    override func refresh() {
        let on = library.historyEnabled
        enabled.state = on ? .on : .off
        whereKept.stringValue = (library.historyFileURL().path as NSString).abbreviatingWithTildeInPath
        steps.selectItem(at: stepChoices.firstIndex(of: Prefs.historySteps) ?? 2)
        for c in [whereKept, steps] as [NSControl] { c.isEnabled = on }
    }

    @objc private func enabledChanged() {
        library.setHistoryEnabled(enabled.state == .on)
        refresh()
    }

    @objc private func changed() {
        Prefs.historySteps = stepChoices[max(0, steps.indexOfSelectedItem)]
    }

    @objc private func showFile() { NSWorkspace.shared.activateFileViewerSelecting([library.historyFileURL()]) }
    @objc private func clear() { library.clearHistory() }
}

/// Metadata defaults are configured once, then applied when native assets are created.
final class MetadataSettingsPanel: SettingsPanel {
    private let creation=AnalysisMenu("On Create",[])
    private let export=AnalysisMenu("On Export",[])
    private let inspector=AnalysisMenu("Inspector Loadout",[])
    private let deletePreset=AnalysisMenu("Saved Preset",[])
    private let editMaster=SwissButton("Edit Master Template…",.quiet)
    private let editPreset=SwissButton("Create Preset…",.quiet)
    private let removePreset=SwissButton("Remove Preset",.quiet)
    override func rows()->[[NSView]] {
        for control in [creation,export,inspector,deletePreset] {control.frame.size=NSSize(width:310,height:32)}
        creation.changed={ [weak self] index in var config=MetadataConfiguration.load();config.creationPreset=index>0 ? self?.creation.titleOfSelectedItem:nil;config.save() }
        export.changed={ [weak self] index in var config=MetadataConfiguration.load();config.exportPreset=index>0 ? self?.export.titleOfSelectedItem:nil;config.save() }
        inspector.changed={ [weak self] index in var config=MetadataConfiguration.load();config.inspectorPreset=index>0 ? self?.inspector.titleOfSelectedItem:nil;config.save() }
        editMaster.actionSymbol="slider.horizontal.3";editMaster.target=self;editMaster.action=#selector(openMaster)
        editPreset.actionSymbol="plus";editPreset.target=self;editPreset.action=#selector(openPreset)
        removePreset.actionSymbol="trash";removePreset.target=self;removePreset.action=#selector(removeSelectedPreset)
        return [
            [heading("Master Metadata"),blank],
            [label("Defaults:"),editMaster],
            [blank,note("Creator, rights, keywords and custom fields in this template appear on every new palette and typography asset. Creation and file dates come from the asset itself.")],
            [heading("Workflow Presets"),blank],
            [label("On Create:"),creation],
            [label("On Export:"),export],
            [label("Inspector:"),inspector],
            [blank,note("A preset stores metadata values. The create choice adds non-empty preset values over the master template. The export and inspector choices are saved for their workflows.")],
            [heading("Manage Presets"),blank],
            [label("Preset:"),deletePreset],
            [blank,row([editPreset,removePreset])]
        ]
    }
    override func refresh() {
        let config=MetadataConfiguration.load(),names=MetadataPresetStore.all().keys.sorted()
        creation.options(["Master Defaults"]+names,selected:names.firstIndex(of:config.creationPreset ?? "").map{$0+1} ?? 0)
        export.options(["No Export Preset"]+names,selected:names.firstIndex(of:config.exportPreset ?? "").map{$0+1} ?? 0)
        inspector.options(["All Fields"]+names,selected:names.firstIndex(of:config.inspectorPreset ?? "").map{$0+1} ?? 0)
        deletePreset.options(["Choose Preset"]+names)
        removePreset.isEnabled = deletePreset.indexOfSelectedItem>0
        deletePreset.changed={ [weak self] index in self?.removePreset.isEnabled=index>0 }
    }
    @objc private func openMaster() {
        let config=MetadataConfiguration.load()
        let sample=Swatch(id:UUID(),name:"New Asset Defaults",createdAt:Date(),entries:[],metadata:config.master)
        AssetMetadataEditor.present(sample,over:view) { metadata,_ in
            var updated=MetadataConfiguration.load();updated.master=metadata;updated.save()
        }
    }
    @objc private func openPreset() {
        let sample=Swatch(id:UUID(),name:"New Metadata Preset",createdAt:Date(),entries:[],metadata:MetadataConfiguration.load().master)
        AssetMetadataEditor.present(sample,over:view) { [weak self] metadata,_ in
            let alert=NSAlert();alert.messageText="Name Metadata Preset"
            let field=NSTextField(string:"New Preset");field.frame=NSRect(x:0,y:0,width:280,height:28)
            alert.accessoryView=field;alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else{return}
            MetadataPresetStore.save(metadata,named:field.stringValue);self?.refresh()
        }
    }
    @objc private func removeSelectedPreset() {
        guard deletePreset.indexOfSelectedItem>0,let name=deletePreset.titleOfSelectedItem else{return}
        MetadataPresetStore.remove(name)
        var config=MetadataConfiguration.load()
        if config.creationPreset==name {config.creationPreset=nil}
        if config.exportPreset==name {config.exportPreset=nil}
        if config.inspectorPreset==name {config.inspectorPreset=nil}
        config.save();refresh()
    }
}

// MARK: Window

final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()
    private var panels: [SettingsPanel] = []
    private var groups: [SettingsGroupController] = []
    private var themeObserver: NSObjectProtocol?

    convenience init(library: LibraryController) {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.toolbarStyle = .preference
        self.init(window: win)

        panels = [
            GeneralPanel(library: library, title: "General", icon: "gearshape"),
            OrganisationPanel(library: library, title: "Organisation", icon: "building.2"),
            CataloguePanel(library: library, title: "Catalogues", icon: "books.vertical"),
            SyncPanel(library: library, title: "Sync", icon: "arrow.triangle.2.circlepath"),
            ProjectsPanel(library: library, title: "Projects", icon: "folder"),
            SimpleCatalogueSettingsPanel(library: library, title: "Catalogue Structure", icon: "list.bullet.indent"),
            ExportPanel(library: library, title: "Export", icon: "square.and.arrow.up"),
            HistoryPanel(library: library, title: "History", icon: "clock.arrow.circlepath"),
            AppearancePanel(library: library, title: "Cards & Grid", icon: "square.grid.2x2"),
            ShortcutsPanel(library: library, title: "Shortcuts", icon: "keyboard"),
            ColourPanel(library: library, title: "Colour", icon: "dial.medium"),
            ThemePanel(library: library, title: "Theme", icon: "paintpalette"),
            HaloSettingsPanel(library: library, title: "Halo", icon: "circle.circle"),
        ] + (Permission.all.isEmpty ? [] : [PermissionsPanel(library: library, title: "Permissions", icon: "lock.shield")])
        #if APPSTORE
        panels.append(EditionPanel(library: library, title: "Edition", icon: "bag"))
        #endif
        let colourProfiles = panels[10]
        let proofing = ProofingDefaultsPanel(library: library, title: "Proofing", icon: "checkmark.seal")
        let spectral = SpectralViewingPanel(library: library, title: "Measurements & Spectral Viewing", icon: "waveform.path")
        let display = DisplayViewingPanel(library: library, title: "Display & Viewing Environment", icon: "display")
        var appPanels = [panels[0], panels[8], panels[9], panels[11], panels[12]]
        if let permissions = panels.first(where: { $0 is PermissionsPanel }) { appPanels.append(permissions) }
        #if APPSTORE
        if let edition = panels.first(where: { $0 is EditionPanel }) { appPanels.append(edition) }
        #endif
        let metadata=MetadataSettingsPanel(library: library, title:"Metadata", icon:"info.square")
        groups = [SettingsGroupController(title: "App & Interaction", icon: "gearshape", panels: appPanels),
                  SettingsGroupController(title: "Library & Data", icon: "books.vertical", panels: [panels[1], panels[2], panels[5], panels[7], metadata]),
                  SettingsGroupController(title: "Colour Management", icon: "dial.medium", panels: [colourProfiles, proofing, spectral, display]),
                  SettingsGroupController(title: "Connections & Sharing", icon: "arrow.triangle.2.circlepath", panels: [panels[3], panels[6]])]
        panels += [proofing, spectral, display, metadata]
        tabs.tabStyle = .toolbar
        for group in groups {
            let item = NSTabViewItem(viewController: group)
            item.label = group.title ?? ""
            item.image = symbol(group.icon, group.title ?? "")
            tabs.addTabViewItem(item)
        }
        win.contentViewController = tabs
        win.center()
        themeObserver = NotificationCenter.default.addObserver(forName: .themeDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.applyCurrentTheme()
        }
        Theme.apply(to: win)
        DispatchQueue.main.async { [weak self] in self?.applyCurrentTheme() }
        shouldCascadeWindows = false
        win.setFrameAutosaveName("MMFFDevColour3Settings")   // comes back where it was left
        tabs.selectedTabViewItemIndex = min(max(0, AppPreferences.shared.integer(forKey: "settingsGroup")), groups.count - 1)
        panelWatch = tabs.observe(\.selectedTabViewItemIndex) { tabs, _ in AppPreferences.shared.set(tabs.selectedTabViewItemIndex, forKey: "settingsGroup") }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .appStateDidChange, object: library)
    }
    private var panelWatch: NSKeyValueObservation?

    deinit {
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    private func applyCurrentTheme() {
        guard let window else { return }
        Theme.apply(to: window)
        refresh()
    }

    @objc func refresh() { panels.forEach { if $0.isViewLoaded { $0.refresh() } } }

    func showSpectralViewing() {
        for (groupIndex, group) in groups.enumerated() {
            if let index=group.panels.firstIndex(where:{$0 is SpectralViewingPanel}) {
                tabs.selectedTabViewItemIndex=groupIndex;group.selectedTabViewItemIndex=index;return
            }
        }
    }
    func showMetadata() {
        guard let index=panels.firstIndex(where:{$0 is MetadataSettingsPanel}) else{return}
        showPanel(index)
    }
    func showPanel(_ index: Int) {
        guard panels.indices.contains(index) else { return }
        let panel = panels[index]
        for (groupIndex, group) in groups.enumerated() {
            if let childIndex = group.panels.firstIndex(where: { $0 === panel }) {
                tabs.selectedTabViewItemIndex = groupIndex
                group.selectedTabViewItemIndex = childIndex
                return
            }
        }
    }
}


/// Toolbar groups keep the existing controllers, including their section controls and stores.
final class SettingsGroupController: NSTabViewController {
    let panels: [SettingsPanel]
    let icon: String
    private var selectionWatch: NSKeyValueObservation?
    init(title: String, icon: String, panels: [SettingsPanel]) {
        self.panels = panels; self.icon = icon
        super.init(nibName: nil, bundle: nil)
        self.title = title
        tabStyle = .segmentedControlOnTop
        for panel in panels { addTabViewItem(NSTabViewItem(viewController: panel)) }
        let key = "settingsGroupTab." + title
        selectedTabViewItemIndex = min(max(0, AppPreferences.shared.integer(forKey: key)), panels.count - 1)
        selectionWatch = observe(\.selectedTabViewItemIndex) { [weak self] controller, _ in
            AppPreferences.shared.set(controller.selectedTabViewItemIndex, forKey: key)
            DispatchQueue.main.async { self?.resizeForSelection() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewWillAppear() { super.viewWillAppear(); resizeForSelection() }
    func resizeForSelection() {
        guard panels.indices.contains(selectedTabViewItemIndex) else { return }
        let panel = panels[selectedTabViewItemIndex]
        panel.view.layoutSubtreeIfNeeded()
        let size = NSSize(width: max(SettingsPanel.minimumWidth, panel.view.fittingSize.width), height: panel.view.fittingSize.height + 52)
        preferredContentSize = size
        guard let window = view.window, let content = window.contentView else { return }
        let desired = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let maxHeight = window.screen?.visibleFrame.height ?? desired.height
        var frame = window.frame
        let height = min(maxHeight, desired.height)
        frame.origin.y += frame.height - height; frame.size.height = height
        frame.size.width = max(frame.width, desired.width)
        if abs(content.frame.height - size.height) > 1 { window.setFrame(frame, display: true) }
    }
}

final class ProofingDefaultsPanel: SettingsPanel {
    private lazy var output = check("Show Output Proof", #selector(changeOutput))
    override func rows() -> [[NSView]] {
        [[label("Palette Comparison:"), output],
         [blank, note("Compare the original preview with the selected output target across palettes and swatches. The actionbar controls this same global choice. A predicted colour difference is not a measured approval.")],
         [blank, note("Saved viewing profiles, the active output target, rendering intent and difference tolerance are managed in the palette workspace’s Preset dropdown. Colour Profiles in these settings manages delivery channel sets.")]]
    }
    override func refresh() { output.state = Prefs.deltaWarningsEnabled ? .on : .off }
    @objc private func changeOutput() { Prefs.deltaWarningsEnabled = output.state == .on }
}

final class SpectralViewingPanel: SettingsPanel {
    private lazy var enable = check("Enable Spectral Viewing", #selector(enableChanged))
    private lazy var material = check("This Is An Opaque, Non-Fluorescent Material", #selector(materialChanged))
    private let sampleMenu = AnalysisMenu("Measured Sample", [])
    private let paletteMenu = AnalysisMenu("Link To Palette", [])
    private let colourMenu = AnalysisMenu("Link To Swatch", [])
    private let observerMenu = AnalysisMenu("Spectral Calculation Observer", SpectralEngine.Observer.allCases.map(\.label))
    private let status = note("")
    private let review = note("Choose a CxF3 file containing spectral reflectance measurements.")
    private let detail = note("")
    private let linkStatus = note("")
    private lazy var add = button("Add Measurements", #selector(addImport))
    private lazy var cancel = button("Cancel Import", #selector(cancelImport))
    private lazy var link = button("Link Sample To Swatch", #selector(linkSample))
    private lazy var unlink = button("Remove Swatch Link", #selector(removeLink))
    private var staged: CxFReflectance.Import?
    private var samples: [SpectralSample] = []
    private var palettes: [Swatch] = []
    private var entries: [SwatchEntry] = []
    private var spectralState = SpectralStore.State()
    private var catalogueID: UUID? { CatalogueTree.catalogue(in: library.store.root)?.id }
    override func rows() -> [[NSView]] {
        sampleMenu.changed = { [weak self] _ in self?.material.state = .off; self?.updateDetails() }
        paletteMenu.changed = { [weak self] _ in self?.updateSwatches() }
        colourMenu.changed = { [weak self] _ in self?.material.state = .off; self?.updateDetails() }
        observerMenu.changed = { [weak self] index in self?.save { $0.observer = SpectralEngine.Observer.allCases[index] } }
        add.isEnabled = false; cancel.isEnabled = false
        return [[heading("Measurements"), blank],
                [label("Spectral Viewing:"), enable],
                [label("Observer:"), observerMenu],
                [blank, status],
                [blank, button("Import Spectral Measurements…", #selector(importFile))],
                [blank, review],
                [blank, row([add,cancel])],
                [blank, note("CxF3 reflectance fractions, 1–10 nm sampling, covering at least 380–730 nm. Original files and declared measurement metadata are retained. No RGB matching or invented wavelengths.")],
                [heading("Swatch Links"), blank],
                [label("Measured Sample:"), sampleMenu],
                [label("Palette:"), paletteMenu],
                [label("Swatch:"), colourMenu],
                [blank, material],
                [blank, row([link,unlink])],
                [blank, row([button("Export Source CxF…", #selector(exportSource)),button("Remove Source…", #selector(removeSource))])],
                [blank, linkStatus],
                [blank, detail],
                [blank, note("Preview: ICC LWL spectral weights; fixed D65 display reference, including the illuminant cast. It is a predicted display colour, not an ambient-adaptation model or a physical approval. Out-of-display-gamut results are clipped. 10° XYZ values use standard 2° RGB for an approximate screen preview, not an exact observer conversion. Links belong to this workspace, catalogue, palette and swatch; changing a colour’s definition invalidates its link.")]]
    }
    override func refresh() {
        SpectralStore.shared.reload(); spectralState = SpectralStore.shared.snapshot()
        samples = spectralState.samples
        let selectedColour = entries.indices.contains(colourMenu.indexOfSelectedItem) ? entries[colourMenu.indexOfSelectedItem].hex : nil
        let selectedSample = sampleMenu.indexOfSelectedItem
        sampleMenu.options(samples.map { $0.name + " · " + $0.objectID }, selected: max(0, min(selectedSample, samples.count-1)))
        let previous = palettes.indices.contains(paletteMenu.indexOfSelectedItem) ? palettes[paletteMenu.indexOfSelectedItem].id : nil
        palettes = library.library.swatches.filter { !$0.isTypography && !$0.entries.isEmpty }
        paletteMenu.options(palettes.map(\.name), selected: previous.flatMap { id in palettes.firstIndex { $0.id == id } } ?? 0)
        enable.state = spectralState.enabled ? .on : .off
        observerMenu.selectItem(at: SpectralEngine.Observer.allCases.firstIndex(of: spectralState.observer) ?? 0)
        status.stringValue = SpectralStore.shared.problem ?? "\(samples.count) Measured Samples · \(spectralState.links.count) Saved Links · " + (spectralState.enabled ? "Enabled" : "Off")
        updateSwatches(preserving: selectedColour)
    }
    private func save(_ change: (inout SpectralStore.State) throws -> Void) {
        do { try SpectralStore.shared.update(change); refresh() }
        catch { status.stringValue = error.localizedDescription; enable.state = spectralState.enabled ? .on : .off }
    }
    @objc private func enableChanged() {
        if enable.state == .on && spectralState.links.isEmpty {
            enable.state = .off
            status.stringValue = "Import measurements, then use Swatch Links to link a sample before enabling Spectral Viewing."
            if samples.isEmpty { importFile() }
            return
        }
        let enabled = enable.state == .on
        if enabled {
            do {try SpectralEngine.validateReferenceTables()}
            catch {status.stringValue=error.localizedDescription;enable.state = .off;return}
        }
        save { $0.enabled = enabled }
        if !enabled { PaletteViewing.illuminant = .normal }
    }
    @objc private func importFile() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "cxf") ?? .xml]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= CxFReflectance.maximumBytes else { throw failure("Choose a CxF file smaller than 4 MB.") }
                self.staged = try CxFReflectance.read(Data(contentsOf: url), name: url.lastPathComponent)
                guard let staged = self.staged else { return }
                self.review.stringValue = "Review: \(staged.name) · \(staged.samples.count) Validated Reflectance Measurements. First sample: \(staged.samples[0].name), \(staged.samples[0].start)–\(staged.samples[0].end) nm at \(staged.samples[0].interval) nm. Add Measurements keeps these records and the original file; it does not alter any master colour or create links."
                self.add.isEnabled = true; self.cancel.isEnabled = true
                (self.parent as? SettingsGroupController)?.resizeForSelection()
            } catch {
                self.staged = nil; self.add.isEnabled = false; self.cancel.isEnabled = false
                self.review.stringValue = "Import Failed: " + error.localizedDescription
                (self.parent as? SettingsGroupController)?.resizeForSelection()
            }
        }
    }
    @objc private func addImport() {
        guard let staged else { return }
        do {
            try SpectralStore.shared.update { state in
                if !state.imports.contains(where: { $0.digest == staged.digest }) { state.imports.append(staged) }
            }
            self.staged = nil; add.isEnabled = false; cancel.isEnabled = false
            review.stringValue = "Measurements added. Choose Swatch Links, select a measured sample and its actual palette swatch, then confirm the material and link them."
            refresh()
        } catch { review.stringValue = error.localizedDescription }
    }
    @objc private func cancelImport() { staged = nil; add.isEnabled = false; cancel.isEnabled = false; review.stringValue = "Import Cancelled. No measurements were added." }
    private func updateSwatches(preserving key: String? = nil) {
        entries = palettes.indices.contains(paletteMenu.indexOfSelectedItem) ? palettes[paletteMenu.indexOfSelectedItem].entries : []
        colourMenu.options(entries.map { ($0.name ?? library.library.name(of: $0.hex, in: nil)) + " · " + ColourKeys.label($0.hex) }, selected: key.flatMap { key in entries.firstIndex { $0.hex == key } } ?? 0)
        material.state = .off; updateDetails()
    }
    private func context() -> (UUID,UUID,SwatchEntry,ColourDefinition)? {
        guard let catalogueID, palettes.indices.contains(paletteMenu.indexOfSelectedItem), entries.indices.contains(colourMenu.indexOfSelectedItem) else { return nil }
        let entry=entries[colourMenu.indexOfSelectedItem]
        guard library.library.swatch(palettes[paletteMenu.indexOfSelectedItem].id)?.entries.contains(where:{$0.hex == entry.hex}) == true,let definition=library.library.definition(of:entry.hex) else { return nil }
        return (catalogueID,palettes[paletteMenu.indexOfSelectedItem].id,entry,definition)
    }
    private func updateDetails() {
        let sample = samples.indices.contains(sampleMenu.indexOfSelectedItem) ? samples[sampleMenu.indexOfSelectedItem] : nil
        if let sample {
            let condition = sample.metadata.filter { $0.key.hasSuffix("Observer") || $0.key.hasSuffix("Illuminant") || $0.key.hasSuffix("DeviceIllumination") || $0.key.hasSuffix("Backing") || $0.key.hasSuffix("Model") }.sorted { $0.key < $1.key }.map { $0.key.components(separatedBy:"/").last!+": "+$0.value }.joined(separator:" · ")
            let predictions = [PaletteViewing.Illuminant.d50,.d65,.a].compactMap { light -> String? in
                guard let prediction=try? SpectralEngine.predict(sample,light:light,observer:spectralState.observer) else{return nil}
                return String(format:"%@ · XYZ %.5f, %.5f, %.5f%@",light.rawValue,prediction.xyz.x,prediction.xyz.y,prediction.xyz.z,prediction.clipped ? " · Display Gamut Clipped":"")
            }.joined(separator:"\n")
            detail.stringValue = "\(sample.fileName) · Object \(sample.objectID) · \(sample.start)–\(sample.end) nm / \(sample.interval) nm. Source SHA-256: \(sample.fileDigest.prefix(16))…\n" + (condition.isEmpty ? "Measurement conditions: Not Declared. Original CxF retained." : condition) + "\nCalculated \(spectralState.observer.label), white Y = 1:\n" + predictions
        } else { detail.stringValue = "Import a spectral measurement file first." }
        let c=context()
        let saved=c.flatMap { spectralState.links[SpectralStore.key(catalogue:$0.0,palette:$0.1,colour:$0.2.hex)] }
        let valid=c.map { saved?.stamp == SpectralStore.Stamp($0.3) } ?? false
        linkStatus.stringValue = saved.map { linked in "Linked: " + (spectralState.samples.first { $0.id == linked.sampleID }?.name ?? linked.sampleID) + (valid ? "" : " · Colour Changed — Relink Required") } ?? "This swatch has no spectral link."
        link.isEnabled = sample != nil && c?.3.kind == .surface && material.state == .on
        unlink.isEnabled = saved != nil
        if c?.3.kind == .light { linkStatus.stringValue = "Emissive colours cannot use a surface-reflectance measurement." }
        (parent as? SettingsGroupController)?.resizeForSelection()
    }
    @objc private func materialChanged() { updateDetails() }
    @objc private func linkSample() {
        guard material.state == .on, samples.indices.contains(sampleMenu.indexOfSelectedItem), let c=context(), c.3.kind == .surface else { return }
        let sample=samples[sampleMenu.indexOfSelectedItem], key=SpectralStore.key(catalogue:c.0,palette:c.1,colour:c.2.hex)
        save { state in state.links[key] = .init(sampleID:sample.id,stamp:.init(c.3),materialConfirmed:true) }
    }
    @objc private func exportSource() {
        guard samples.indices.contains(sampleMenu.indexOfSelectedItem),let window=view.window,
              let source=spectralState.imports.first(where:{$0.digest == samples[sampleMenu.indexOfSelectedItem].fileDigest}) else{return}
        let panel=NSSavePanel();panel.nameFieldStringValue=source.name;panel.allowedContentTypes=[.init(filenameExtension:"cxf") ?? .xml]
        panel.beginSheetModal(for:window){ [weak self] response in
            guard response == .OK,let url=panel.url else{return}
            do {
                let granted=url.startAccessingSecurityScopedResource();defer{if granted{url.stopAccessingSecurityScopedResource()}}
                try Handler_File_Manager.shared.publishRaw(source.original,to:url)
                self?.linkStatus.stringValue="Original CxF exported byte for byte."
            }catch{self?.linkStatus.stringValue=error.localizedDescription}
        }
    }
    @objc private func removeSource() {
        guard samples.indices.contains(sampleMenu.indexOfSelectedItem),let window=view.window else{return}
        let sample=samples[sampleMenu.indexOfSelectedItem]
        let ids=Set(spectralState.samples.filter{$0.fileDigest == sample.fileDigest}.map(\.id))
        let count=spectralState.links.values.filter{ids.contains($0.sampleID)}.count
        SwissConfirm.ask(over:window,title:"Remove Spectral Source",note:"Remove \(sample.fileName) from this workspace, its measurements and \(count) swatch links. The original external file and master colours remain unchanged. Slide across to remove.",commit:"Remove"){ [weak self] in
            self?.save { state in
                state.imports.removeAll{$0.digest == sample.fileDigest}
                state.links=state.links.filter{!ids.contains($0.value.sampleID)}
                if state.links.isEmpty {state.enabled=false}
            }
        }
    }
    @objc private func removeLink() {
        guard let c=context() else { return }
        save { state in state.links.removeValue(forKey:SpectralStore.key(catalogue:c.0,palette:c.1,colour:c.2.hex)); if state.links.isEmpty { state.enabled=false } }
    }
}

final class DisplayViewingPanel: SettingsPanel {
    override func rows() -> [[NSView]] {
        [[label("Display Calibration:"), note("Colorgain does not measure or calibrate your display. Manage its profile and calibration using macOS or your calibration software.")],
         [label("Viewing Illuminant:"), note("D50 and D65 are standard daylight illuminants; A is a different standard illuminant. Selecting one does not calibrate the monitor or determine the appearance of an unmeasured material.")],
         [label("Preview Status:"), note("An on-screen prediction depends on the display and declared viewing assumptions. It is separate from physical measurement and human approval.")]]
    }
}

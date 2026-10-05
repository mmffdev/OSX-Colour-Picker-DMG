import AppKit

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
    func refresh() {}

    override func loadView() {
        let grid = NSGridView(views: rows())
        grid.rowSpacing = 9
        grid.columnSpacing = 10
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
        grid.translatesAutoresizingMaskIntoConstraints = false
        let v = NSView()
        v.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: v.topAnchor, constant: 22),
            grid.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: v.leadingAnchor, constant: 28),
            grid.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -24),
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsPanel.minimumWidth),
        ])
        view = v
    }

    /// Every panel is at least this wide, so the window's toolbar shows all the panels' icons.
    static let minimumWidth: CGFloat = 980

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
        preferredContentSize = view.fittingSize
    }

    func popup(_ titles: [String], _ action: Selector) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: titles)
        p.target = self
        p.action = action
        return p
    }

    func check(_ title: String, _ action: Selector) -> NSButton {
        NSButton(checkboxWithTitle: title, target: self, action: action)
    }

    func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
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
        [heading("Colour cards"), blank],
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

    @objc private func changed() {
        Prefs.houseCardRows = zip(rowChecks, ColourFormat.cardRows).filter { $0.0.state == .on }.map { $0.1 }
        Prefs.showNames = names.state == .on
        Prefs.showContrast = contrast.state == .on
        Prefs.showPaletteBars = bars.state == .on
        Prefs.tileSize = TileSize(rawValue: size.indexOfSelectedItem) ?? .medium
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
        preview.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
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
            [blank, note("Add To Adobe Apps puts a palette where Photoshop, Illustrator or InDesign keeps its libraries. Doing that without a password each time is set up under Permissions.")],
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
        licence.font = NSFont.systemFont(ofSize: 11)
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
        [label("Open:"), open],
        [blank, row([button("New\u{2026}", #selector(newCatalogue)), button("Rename\u{2026}", #selector(renameCatalogue)),
                     button("Open File\u{2026}", #selector(openFile)), button("Show in Finder", #selector(reveal))])],
        [blank, note("A catalogue is a separate library with its own swatches and palettes, in the way Lightroom has catalogues. The app reopens the one you used last. Open File turns a library.json from an export or a backup into a new catalogue.")],
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
    private let projectsFolder = NSTextField(labelWithString: "")
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
            [heading("Project files"), blank],
            [label("Projects folder:"), projectsFolder],
            [blank, row([button("Choose\u{2026}", #selector(chooseProjects))])],
            [blank, note("Every project is also kept as a file of its own here, always current, so it can be handed over whole. Right-click a project to keep it somewhere else instead.")],
        ]
    }

    override func refresh() {
        guard isViewLoaded else { return }
        let chosen = SyncSettings.folder
        folder.stringValue = chosen.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Sync is off"
        projectsFolder.lineBreakMode = .byTruncatingMiddle
        projectsFolder.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        projectsFolder.stringValue = ((ProjectFiles.folder ?? library.store.url.deletingLastPathComponent().appendingPathComponent("Projects")).path as NSString).abbreviatingWithTildeInPath
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

    @objc private func chooseProjects() { library.chooseProjectsFolder() }

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
            SyncSettings.folder = url
            self?.library.syncNow()
            self?.refresh()
        }
    }

    @objc private func turnOffSync() {
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
    private var fields: [ShortcutField] = []
    private var ids: [String] = []
    private let message = note(" ")

    override var labelWidth: CGFloat { 220 }

    override func rows() -> [[NSView]] {
        message.textColor = .systemRed
        var rows: [[NSView]] = [[heading("Keyboard shortcuts"), blank]]
        for (at, command) in Shortcuts.commands.enumerated() {
            let field = ShortcutField(frame: .zero)
            field.onRecord = { [weak self] shortcut, keyCode in self?.record(shortcut, keyCode, at: at) }
            let clear = symbolButton("xmark.circle", tooltip: "Remove this shortcut", target: self, action: #selector(clear(_:)))
            clear.tag = at
            fields.append(field)
            ids.append(command.id)
            rows.append([label(command.title + ":"), row([field, clear])])
        }
        return rows + [
            [blank, message],
            [blank, button("Restore Defaults", #selector(restore))],
            [blank, note("Click a shortcut, then type the new one. Shortcuts that macOS or the Edit menu already use, such as \u{2318}C for Copy, cannot be taken.")],
        ]
    }

    override func refresh() {
        let current = Dictionary(uniqueKeysWithValues: Shortcuts.commands.map { ($0.id, $0.shortcut) })
        for (field, id) in zip(fields, ids) { field.shortcut = current[id] ?? nil }
    }

    private func record(_ shortcut: Shortcut?, _ keyCode: Int?, at: Int) {
        let problem = Shortcuts.set(shortcut, keyCode: keyCode, for: ids[at])
        message.stringValue = shortcut.flatMap { s in problem?.message(for: s) } ?? " "
        view.window?.makeFirstResponder(nil)
        refresh()
    }

    @objc private func clear(_ sender: NSButton) { record(nil, nil, at: sender.tag) }

    @objc private func restore() {
        Shortcuts.restoreDefaults()
        message.stringValue = " "
        refresh()
    }
}

// MARK: Theme

final class ThemePanel: SettingsPanel {
    private let selectionBackground = NSColorWell()
    private let selectionText = NSColorWell()
    private let hoverBackground = NSColorWell()
    private let hoverText = NSColorWell()
    private let activeBackground = NSColorWell()
    private let activeText = NSColorWell()
    /// Match The Mac, Light, Dark, My Own Colours: one is always ticked.
    private lazy var modes: [NSButton] = ThemeMode.allCases.map { check($0.title, #selector(modeChosen(_:))) }
    /// For My Own Colours: the background, and whether its text is black, white, or whichever reads better.
    private let ownBackground = NSColorWell()
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
final class ResettingSlider: NSSlider {
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
            let well = NSColorWell()
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
    private lazy var printCheck = check("Print, through a press profile", #selector(changed))
    private lazy var press = popup(PressProfiles.all.map { $0.name }, #selector(changed))
    private lazy var intent = popup(RenderingIntent.allCases.map { $0.name }, #selector(changed))
    private lazy var blackPoint = check("Black Point Compensation", #selector(changed))
    private lazy var legal = check("Video Values In Legal Range (64 To 940)", #selector(changed))
    private lazy var houseDefault = check("Use for palettes and projects with no profile of their own", #selector(defaultChanged))
    private lazy var remove = button("Delete", #selector(deleteTapped))

    override func rows() -> [[NSView]] {
        nameField.delegate = self
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
    private lazy var projectHistory = check("Write each project's steps into its project file", #selector(changed))
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
            [blank, note("A file of its own beside the library file, so the library stays lean and the history can be cleared without touching your work. Steps hold only names, colours, order and tags, never images.")],
            [heading("Project history"), blank],
            [blank, projectHistory],
            [blank, note("A step that changes one project is also listed in that project's file, so whoever receives the project sees how it came about.")],
            [heading("Steps to save"), blank],
            [label("Keep:"), steps],
            [blank, note("Once the limit is reached the oldest step is dropped. Unlimited keeps everything.")],
        ]
    }

    override func refresh() {
        let on = library.historyEnabled
        enabled.state = on ? .on : .off
        whereKept.stringValue = (library.historyFileURL().path as NSString).abbreviatingWithTildeInPath
        projectHistory.state = Prefs.projectHistory ? .on : .off
        steps.selectItem(at: stepChoices.firstIndex(of: Prefs.historySteps) ?? 2)
        for c in [whereKept, projectHistory, steps] as [NSControl] { c.isEnabled = on }
    }

    @objc private func enabledChanged() {
        library.setHistoryEnabled(enabled.state == .on)
        refresh()
    }

    @objc private func changed() {
        Prefs.projectHistory = projectHistory.state == .on
        Prefs.historySteps = stepChoices[max(0, steps.indexOfSelectedItem)]
    }

    @objc private func showFile() { NSWorkspace.shared.activateFileViewerSelecting([library.historyFileURL()]) }
    @objc private func clear() { library.clearHistory() }
}

// MARK: Window

final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()
    private var panels: [SettingsPanel] = []

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
            ExportPanel(library: library, title: "Export", icon: "square.and.arrow.up"),
            HistoryPanel(library: library, title: "History", icon: "clock.arrow.circlepath"),
            AppearancePanel(library: library, title: "Cards & Grid", icon: "square.grid.2x2"),
            ShortcutsPanel(library: library, title: "Shortcuts", icon: "keyboard"),
            ColourPanel(library: library, title: "Colour", icon: "dial.medium"),
            ThemePanel(library: library, title: "Theme", icon: "paintpalette"),
            HaloSettingsPanel(library: library, title: "Halo", icon: "circle.circle"),
            PermissionsPanel(library: library, title: "Permissions", icon: "lock.shield"),
        ]
        tabs.tabStyle = .toolbar
        for p in panels {
            let item = NSTabViewItem(viewController: p)
            item.label = p.title ?? ""
            item.image = symbol(p.icon, p.title ?? "")
            tabs.addTabViewItem(item)
        }
        win.contentViewController = tabs
        win.center()
        shouldCascadeWindows = false
        win.setFrameAutosaveName("MMFFDevColour3Settings")   // comes back where it was left
        showPanel(preferences.integer(forKey: "settingsPanel"))
        panelWatch = tabs.observe(\.selectedTabViewItemIndex) { tabs, _ in preferences.set(tabs.selectedTabViewItemIndex, forKey: "settingsPanel") }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .appStateDidChange, object: library)
    }
    private var panelWatch: NSKeyValueObservation?

    @objc func refresh() { panels.forEach { if $0.isViewLoaded { $0.refresh() } } }

    func showPanel(_ index: Int) {
        if panels.indices.contains(index) { tabs.selectedTabViewItemIndex = index }
    }
}

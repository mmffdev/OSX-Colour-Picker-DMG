import AppKit
import UniformTypeIdentifiers

// ---------- The library, and everything that changes it ----------
//
// Views read from here and ask for changes here. They never touch the store themselves.

extension Notification.Name {
    /// Colours or palettes changed.
    static let libraryDidChange = Notification.Name("libraryDidChange")
    static let historyDidChange = Notification.Name("historyDidChange")
    /// The page showing changed (Selection in `current`).
    static let selectionDidChange = Notification.Name("selectionDidChange")
    /// Project files were written, or one was found missing.
    static let projectFilesDidChange = Notification.Name("projectFilesDidChange")
    /// Catalogue, sync status or picking state changed.
    static let appStateDidChange = Notification.Name("appStateDidChange")
    /// A short confirmation for the status bar. userInfo["text"].
    static let statusMessage = Notification.Name("statusMessage")
}

enum Selection: Equatable {
    case all
    case palette(UUID)
    /// All Swatches, showing only what carries the tag.
    case tag(String)
    /// cLab: the colour wheel and its result strip.
    case lab
    /// cTools: checking a text colour against a background.
    case contrast
    /// A project's Overview page, in its Information bucket.
    case overview(UUID)
}

final class LibraryController: NSObject {
    /// The open catalogue's files; its schema is read from the same folder.
    private(set) var store: LibraryStore { didSet { SchemaTrial.use(store: store); watchTree() } }
    private(set) var library = Library()
    private(set) var catalogue: String
    weak var window: NSWindow?

    /// Asks the window to show something. `rename` puts the palette's name into edit mode.
    var onShow: ((Selection, _ rename: Bool) -> Void)?
    /// Redraws the sidebar after the theme changed; set by the window.
    var onThemeChange: (() -> Void)?
    func reloadSidebarTheme() { onThemeChange?() }

    /// Scrolls the sidebar to a project and opens it; set by the window.
    var onRevealProject: ((UUID) -> Void)?
    /// Asks the visible page to scroll to and select a swatch.
    var onReveal: ((String) -> Void)?
    /// Lays a form over the page (nil takes it away), filling its width or in a centred column; set by the window.
    var onCover: ((NSViewController?, _ fills: Bool) -> Void)?
    /// Opens cLab with this colour as the base; set by the window.
    var onOpenLab: ((String) -> Void)?
    /// Opens Contrast on a Typography palette, to edit one of its pairings or (nil) to make a new one; set by the window.
    var onOpenContrast: ((_ palette: UUID, _ style: UUID?) -> Void)?
    /// What cLab's strip holds, kept up to date by cLab so it can be exported and shared like a palette.
    var labPalette: ExportPalette?
    /// The pair the Contrast tool is checking, kept up to date by the tool for the same reason.
    var contrastPalette: ExportPalette?

    private(set) var picking = false
    private(set) var syncStatus = "Not synced yet."
    private var syncAsking = false
    private var syncPaused = false
    private var lastSyncComplaint: String?
    private var loadedStamp: Date?
    private var reportedQuarantine: URL?

    override convenience init() { self.init(catalogue: Catalogues.currentName) }

    /// A controller on one catalogue; the app uses the current one, scripts may name another.
    init(catalogue name: String) {
        catalogue = name
        store = Catalogues.standard.store(for: name)
        super.init()
        SchemaTrial.use(store: store)
        SchemaTrial.library = { [unowned self] dir in dir.standardizedFileURL == self.store.root.standardizedFileURL ? self.library : nil }
        NotificationCenter.default.addObserver(forName: .schemaDidChange, object: nil, queue: .main) { [weak self] n in self?.schemaChanged(n) }
    }

    // MARK: Reading

    var favourites: [Swatch] { library.orderedFavourites }
    /// Every palette of colours once, in sidebar order: project by project, then the loose ones.
    /// Typography palettes are left out: colours are not added to them, and they have a list of their own.
    var paletteOrder: [Swatch] {
        (library.orderedProjects.flatMap { library.palettes(in: $0.id) } + library.palettes(in: nil)).filter { !$0.isTypography }
    }

    var paletteSort: SortOrder {
        get { SortOrder(rawValue: AppPreferences.shared.object(forKey: "paletteSort") as? Int ?? SortOrder.oldest.rawValue) ?? .oldest }
        set { AppPreferences.shared.set(newValue.rawValue, forKey: "paletteSort"); changed() }
    }

    func hexes(in id: UUID) -> [String] { library.hexes(inSwatch: id, by: paletteSort) }

    func palettes(holding hex: String) -> [Swatch] {
        paletteOrder.filter { s in s.entries.contains { $0.hex == hex } }
    }

    // MARK: Loading and saving

    func reload() {
        do { library = try store.load() } catch { show(error) }
        loadedStamp = store.modificationDate
        loadHistory()
        for note in store.notes { Diagnostics.log("tree", note) }
        if let report = store.takeMigration() {
            var words = "\(plural(report.members, "member")) and \(plural(report.palettes, "palette")) were brought across into the catalogue's own tree of folders. The old folders are kept whole in \(report.backup.lastPathComponent)."
            if !report.orphans.isEmpty { words += " Palettes from \(report.orphans.joined(separator: ", ")) went to the Library." }
            if historyEnabled { history.record("Brought Across From The Earlier Layout", library: library, before: library, limit: Prefs.historySteps); historyChanged() }
            let a = NSAlert()
            a.messageText = "\(catalogue) now follows its schema on disk"
            a.informativeText = words + (report.notes.isEmpty ? "" : "\n\n" + report.notes.joined(separator: "\n"))
            present(a)
        }
        watchTree()
        // Once per catalogue: every colour known only by its hex gets its source and linear master, written back as one step.
        if library.colours.contains(where: { $0.source == nil }) { apply("Complete Colour Records") { $0.completeColourRecords() } }
        changed()
        if let aside = store.quarantinedFile, aside != reportedQuarantine {
            reportedQuarantine = aside
            let a = NSAlert()
            a.alertStyle = .warning
            a.messageText = "The library file could not be read"
            a.informativeText = "It has been kept at \(aside.path) and a fresh library was started."
            present(a)
        }
    }

    /// Picks up changes made by the hotkey process or another Mac while the window was in the background.
    func windowBecameActive() {
        if window?.firstResponder is NSText { return } // a name is being edited
        if store.modificationDate != loadedStamp { reload() }
        sync()
    }

    struct LockedProject: LocalizedError {
        let name: String
        var errorDescription: String? { "\u{201C}\(name)\u{201D} is locked." }
        var recoverySuggestion: String? { "Unlock the project in the sidebar to change what is in it." }
    }

    /// Every change goes through here, and becomes a step in the history under `title`.
    /// A change to anything in a locked project is refused before it is saved.
    func apply(_ title: String = "Change", schema: SchemaTrial.SchemaFile? = nil, _ body: (inout Library) -> Void) {
        let before = library
        do {
            library = try store.mutate(schema: schema) { lib in
                var trial = lib
                body(&trial)
                // A palette just made is turned to the default purpose straight away: a palette always has one.
                let had = Set(lib.swatches.map { $0.id })
                for made in trial.swatches where !had.contains(made.id) && made.purpose == nil && !made.isTypography {
                    trial.choosePurpose(Prefs.defaultPurpose, ofPalette: made.id)
                }
                if let name = lib.lockedProjectChanged(by: trial) { throw LockedProject(name: name) }
                lib = trial
            }
            loadedStamp = store.modificationDate
        } catch let locked as LockedProject {
            flash("\(locked.errorDescription ?? "") \(locked.recoverySuggestion ?? "")")
            NSSound.beep()
            return
        } catch {
            show(error)
        }
        if library != before { recordStep(title, before: before) }
        changed()
        sync()
        watch?.settle()
    }

    // MARK: History

    private(set) var history = StepHistory()
    private var historyTimer: Timer?

    var historyEnabled: Bool { Prefs.historyEnabled(for: catalogue) }

    private func recordStep(_ title: String, before: Library?) {
        guard historyEnabled else { return }
        history.record(title, library: library, before: before, limit: Prefs.historySteps)
        historyChanged()
    }

    private func historyChanged() {
        NotificationCenter.default.post(name: .historyDidChange, object: self)
        historyTimer?.invalidate()
        historyTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.saveHistory() }
    }

    private func saveHistory() {
        guard historyEnabled else { return }
        do { try HistoryStore.save(history, beside: store.url) } catch { flash("Could not save the history: \(error.localizedDescription)") }
    }

    func loadHistory() {
        history = historyEnabled ? HistoryStore.load(beside: store.url) : StepHistory()
        if history.isEmpty, historyEnabled { history.record("Opened", library: library, before: nil, limit: Prefs.historySteps) }
        NotificationCenter.default.post(name: .historyDidChange, object: self)
    }

    /// Takes the library back (or forward) to a step, the schema with it, and writes the tree as it was then. Not a step itself.
    func goToStep(_ index: Int) {
        guard let then = history.go(to: index, from: library, schema: SchemaTrial.schema(for: store.root) ?? store.schema) else { return }
        do { try store.save(then.library, schema: then.schema); library = then.library; loadedStamp = store.modificationDate } catch { show(error); return }
        NotificationCenter.default.post(name: .schemaDidChange, object: nil)
        historyChanged()
        changed()
        sync()
        watch?.settle()
    }

    func deleteStep(_ index: Int) {
        history.delete(at: index)
        historyChanged()
    }

    func historyFileURL() -> URL { HistoryStore.url(beside: store.url) }

    func setHistoryEnabled(_ on: Bool) {
        Prefs.setHistoryEnabled(on, for: catalogue)
        if on { loadHistory() } else { history = StepHistory(); NotificationCenter.default.post(name: .historyDidChange, object: self) }
        stateChanged()
    }

    func clearHistory() {
        history = StepHistory()
        history.record("Opened", library: library, before: nil, limit: Prefs.historySteps)
        historyChanged()
    }

    private func changed() {
        NotificationCenter.default.post(name: .libraryDidChange, object: self)
    }

    // MARK: The tree on disk

    /// The folder a member lives in, found by its id wherever the tree has it.
    func memberFolderURL(_ id: UUID) -> URL? { CatalogueTree.folder(ofWorkGroup: id, in: store.root) }
    /// A palette's file, found by its id wherever the tree has it.
    func paletteFileURL(_ id: UUID) -> URL? { CatalogueTree.file(ofPalette: id, in: store.root) }

    func setProjectLocked(_ id: UUID, _ on: Bool) {
        apply(on ? "Lock Project" : "Unlock Project") { $0.setProjectLocked(id, on) }
    }

    func isLocked(palette id: UUID) -> Bool {
        library.swatch(id)?.projectID.flatMap { library.project($0)?.isLocked } ?? false
    }

    /// Shows the member's folder in Finder.
    func showProjectFile(_ id: UUID) {
        if let url = memberFolderURL(id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    // MARK: Watching the tree

    private var watch: CatalogueWatch?

    /// Keeps the watch on the open catalogue's folder, and takes the tree as it stands as the app's own doing.
    private func watchTree() {
        if let w = watch, w.root.standardizedFileURL == store.root.standardizedFileURL { w.settle(); return }
        watch?.stop()
        let made = CatalogueWatch(root: store.root) { [weak self] in self?.treeChangedOutside() }
        made.start()
        watch = made
    }

    /// Finder, or another app, changed the tree: it is read again, unless a name is being typed or a pick is under way.
    private func treeChangedOutside() {
        if window?.firstResponder is NSText || picking { watch?.settle(); return }
        reload()
        flash("The catalogue changed in Finder and was read again")
    }

    /// The schema was written through the store: a step in the history, when it changed.
    private func schemaChanged(_ n: Notification) {
        defer { watch?.settle() }
        guard let before = n.userInfo?["before"] as? SchemaTrial.SchemaFile, let after = n.userInfo?["after"] as? SchemaTrial.SchemaFile, before != after else { return }
        loadedStamp = store.modificationDate
        if historyEnabled { history.record("Change Schema", library: library, before: library, schema: (before, after), limit: Prefs.historySteps); historyChanged() }
    }

    private func stateChanged() { NotificationCenter.default.post(name: .appStateDidChange, object: self) }

    func flash(_ text: String) {
        NotificationCenter.default.post(name: .statusMessage, object: self, userInfo: ["text": text])
    }

    func show(_ error: Error) { Diagnostics.log("library", error: error); present(NSAlert(error: error)) }

    private func present(_ alert: NSAlert, then: ((NSApplication.ModalResponse) -> Void)? = nil) {
        // Only a window that is on screen takes the sheet: a sheet brings its window up, and an error before
        // the Studio window exists would otherwise drag the old window into view beside it.
        if let w = window, w.isVisible { alert.beginSheetModal(for: w) { then?($0) } }
        else { then?(alert.runModal()) }
    }

    // MARK: Copying

    /// A click on a swatch: copies in the format chosen in Settings.
    func copy(_ hex: String) {
        let text = Prefs.copyText(hex)
        copyToClipboard(text)
        playShutter()
        flash("Copied \(text)")
    }

    /// A click on a card row, or Copy As: copies in that format whatever the setting.
    func copy(_ hex: String, as format: ColourFormat) {
        let text = format.text(hex, lowercase: Prefs.lowercaseHex)
        copyToClipboard(text)
        playShutter()
        flash("Copied \(format.label)  \(text)")
    }

    func copy(_ hexes: [String], from name: String? = nil) {
        guard !hexes.isEmpty else { return }
        if hexes.count == 1 { copy(hexes[0]); return }
        copyToClipboard(hexes.map { Prefs.copyText($0) }.joined(separator: Prefs.copyFormat == .hex || Prefs.copyFormat == .hexBare ? ", " : "\n"))
        playShutter()
        flash("Copied \(plural(hexes.count, "swatch", "swatches"))" + (name.map { " from \($0)" } ?? ""))
    }

    // MARK: Picking

    /// Starts picking, or stops if already picking. The loupe returns after each pick until Esc
    /// or a click on the app's own window, unless that is switched off in Settings.
    @objc func togglePicking() {
        if picking { stopPicking(); return }
        picking = true
        stateChanged()
        sampleNext()
    }

    func stopPicking() {
        guard picking else { return }
        picking = false
        stateChanged()
        sync() // held back while the loupe was up
    }

    private func sampleNext() {
        guard picking else { return }
        NSColorSampler().show { [weak self] color in
            guard let self = self, self.picking else { return }
            // Esc gives no colour; a click on our own window means "I'm done".
            guard let color = color, let picked = ColourDefinition.picked(color), !self.clickLandedOnThisWindow() else {
                self.stopPicking()
                return
            }
            playShutter()
            // A colour sRGB can show is kept as its hex, as ever; one it cannot is kept whole, under a key of its own.
            var key: String?
            self.apply("Pick Colour") { key = $0.addPick(picked) }
            guard let hex = key else { return }
            copyToClipboard(Prefs.copyText(hex))
            self.onReveal?(hex)
            let into = self.library.activeSwatch.map { " \u{2192} \($0.name)" } ?? ""
            self.flash("Picked \(colourName(hex))  \(ColourKeys.label(hex))\(into)" + (picked.fitsSRGB ? "" : "  \u{00B7}  Beyond sRGB, Kept Whole"))
            if Prefs.keepPicking { DispatchQueue.main.async { self.sampleNext() } }
            else { self.stopPicking() }
        }
    }

    /// Sample: a rectangle dragged over the screen becomes a palette of the colours under it.
    @objc func sampleArea() {
        stopPicking()
        guard CGPreflightScreenCaptureAccess() else {
            // macOS asks once; the toolbar button works the next time, after the app is allowed.
            CGRequestScreenCaptureAccess()
            flash("Allow Screen Recording for \(Brand.name) in System Settings \u{25B8} Privacy & Security, then try Sample again")
            return
        }
        ScreenSampler.begin { [weak self] image in
            guard let self = self else { return }
            guard let image = image else { return }
            let hexes = extractPalette(from: image, count: Prefs.imagePaletteSize)
            guard !hexes.isEmpty else { self.flash("No colours found in that area"); return }
            playShutter()
            let id = self.createPalette(named: "Sampled", hexes: hexes)
            let name = id.flatMap { self.library.swatch($0)?.name } ?? "palette"
            self.flash("Sampled \(plural(hexes.count, "swatch", "swatches")) into \(name)")
        }
    }

    private func clickLandedOnThisWindow() -> Bool {
        guard let w = window else { return false }
        let p = NSEvent.mouseLocation
        guard w.frame.contains(p) else { return false }
        let top = NSWindow.windowNumber(at: p, belowWindowWithWindowNumber: 0)
        return top <= 0 || top == w.windowNumber || NSApp.window(withWindowNumber: top) != nil
    }

    // MARK: Palettes

    @objc func newPalette() { addPalette(to: nil) }

    func addPalette(to project: UUID?) {
        var id: UUID?
        apply("New Palette") { lib in
            id = lib.createSwatch()
            if let id = id, let p = project { lib.move(id, to: p, index: Int.max) }
        }
        if let id = id { onShow?(.palette(id), true) }
    }

    // MARK: Projects

    /// Opens the project form; saving it creates the project.
    @objc func newProject() { startProject(moving: nil) }

    /// Asks for one line of text in the middle of the page; set by the window.
    var onPrompt: ((ModalPrompt) -> Void)?

    /// Asks for the project's name, makes it, and opens its Overview page, where its details are
    /// filled in. `palette`, when given, goes into the project as a copy once it is made.
    /// `kind` is what the schema calls it, where that is not Project; `made` is told the new project's id, to place it.
    func startProject(moving palette: UUID?, called kind: String = "Project", in collection: SchemaCollection? = nil, made placed: ((UUID) -> Void)? = nil) {
        onPrompt?(ModalPrompt(title: "New \(kind)", message: "Name the \(kind.lowercased()). Its details are filled in on its Overview page, which opens next.",
                              placeholder: "Client, product or piece of work", confirm: "Create \(kind)", symbol: "folder.badge.plus",
                              check: { ProjectField.problem(name: $0, values: [:]) }) { [weak self] name in
            guard let self = self else { return }
            var id: UUID?
            self.apply("New Project") { lib in
                let made = lib.createProject(named: name)
                // The Studio section starts as the organisation set in Settings; the form can change any of it.
                let organisation = ProjectField.tidy(Prefs.organisation)
                if !organisation.isEmpty { lib.setProjectDetails(made, organisation) }
                id = made
            }
            guard let made = id, let project = self.library.project(made) else { return }
            placed?(made)
            self.flash("Created \(kind) \(project.name)")
            self.onShow?(.overview(made), false)
            // The copy goes in by the usual door, which asks about notes when the palette has some.
            if let palette = palette { self.move(palette: palette, to: made, index: 0) }
        })
    }

    /// Asks for a member's name, makes it in `collection` (the first collection when none is given, made then if the catalogue
    /// has none), and keeps `hexes` in it as a palette. The page stays where it is: this is for a tool, such as Colour Lab or
    /// Contrast, saving its colours without leaving.
    func startProject(keeping hexes: [String], named paletteName: String, in collection: SchemaCollection? = nil) {
        let kind = SchemaTrial.memberName(of: collection ?? SchemaTrial.collections.first ?? SchemaTrial.SchemaFile.fresh.collections[0])
        onPrompt?(ModalPrompt(title: "New \(kind)", message: "Name the \(kind.lowercased()). These colours go into it as the palette \u{201C}\(paletteName)\u{201D}.",
                              placeholder: "Client, product or piece of work", confirm: "Create \(kind)", symbol: "folder.badge.plus",
                              check: { ProjectField.problem(name: $0, values: [:]) }) { [weak self] name in
            guard let self = self else { return }
            var id: UUID?
            self.apply("New Project") { lib in
                let made = lib.createProject(named: name)
                // The Studio section starts as the organisation set in Settings; the form can change any of it.
                let organisation = ProjectField.tidy(Prefs.organisation)
                if !organisation.isEmpty { lib.setProjectDetails(made, organisation) }
                id = made
            }
            guard let made = id, self.library.project(made) != nil else { return }
            // It goes where it was asked for, so it shows under that collection in rail1 at once.
            let home = collection.flatMap { c in SchemaTrial.collections.first { $0.id == c.id } } ?? SchemaTrial.homeForNewMember()
            SchemaTrial.place(made, in: home.id, folder: nil)
            self.keep(hexes, named: paletteName, in: made)
        })
    }

    // MARK: Colour profiles

    /// Keeps the print condition CMYK values are worked out for in step with the page showing, the library and Settings.
    func watchPrintCondition() {
        for name in [Notification.Name.selectionDidChange, .libraryDidChange, .prefsDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshPrintCondition() }
        }
        refreshPrintCondition()
    }

    private func refreshPrintCondition() {
        var palette: UUID?
        if case .palette(let id)? = current { palette = id }
        let chosen: ColourProfile
        if palette == nil, let project = currentProject { chosen = profile(forProject: project).profile } else { chosen = profile(forPalette: palette).profile }
        PrintCondition.current = chosen.printCondition
    }

    /// The house's profiles, from Settings.
    var houseProfiles: [ColourProfile] { ColourProfiles.load() }

    /// Every profile on offer: the house's, then any this library uses that the house no longer has.
    var offeredProfiles: [ColourProfile] {
        let house = houseProfiles
        return house + library.colourProfiles.filter { mine in !house.contains { $0.id == mine.id } }
    }

    /// The profile a palette's page works to: the one for the purpose on show, else the palette's own.
    func profile(forPalette id: UUID?) -> (profile: ColourProfile, origin: ProfileOrigin) {
        if let id = id, let purpose = shownPurpose(for: id) { return (profile(for: purpose, ofPalette: id), .palette) }
        return library.profile(forPalette: id, house: houseProfiles, houseDefault: ColourProfiles.houseDefault)
    }

    /// The profile a palette works to for one purpose: the one chosen for it, else the purpose's own.
    func profile(for purpose: Purpose, ofPalette id: UUID) -> ColourProfile {
        let chosen = library.swatch(id)?.config(for: purpose)?.profile
        return chosen.flatMap { want in offeredProfiles.first { $0.id == want } } ?? purpose.starter
    }

    // MARK: Purposes

    /// The one purpose a palette is turned to. A palette always has one: where none has been
    /// chosen for it, it is the default purpose from Settings. nil only for a palette that is not there.
    func shownPurpose(for id: UUID) -> Purpose? { library.swatch(id).map { $0.purpose ?? Prefs.defaultPurpose } }

    /// Turns a palette to a purpose. The choice is the palette's, kept with its project.
    func show(_ purpose: Purpose?, forPalette id: UUID) {
        guard let purpose = purpose, library.swatch(id)?.purpose != purpose else { return }
        apply("Turn To \(purpose.title)") { $0.choosePurpose(purpose, ofPalette: id) }
        refreshPrintCondition()
    }

    /// The values the cards show for a purpose a palette serves.
    func setLabels(_ labels: [ColourFormat], for purpose: Purpose, ofPalette id: UUID) {
        apply("Set \(purpose.title) Labels") { $0.setPurposeSettings(purpose, ofPalette: id) { $0.labels = labels.map { $0.rawValue } } }
    }

    func profile(forProject id: UUID) -> (profile: ColourProfile, origin: ProfileOrigin) {
        library.profile(forProject: id, house: houseProfiles, houseDefault: ColourProfiles.houseDefault)
    }

    /// Gives a palette a profile of its own; nil goes back to its project's or the house's.
    /// On a purpose's tab it is that purpose's profile that is set.
    func setProfile(_ profile: ColourProfile?, ofPalette id: UUID) {
        if let purpose = shownPurpose(for: id) {
            apply("Set \(purpose.title) Profile") { $0.setProfile(profile, for: purpose, ofPalette: id) }
            return
        }
        apply("Set Colour Profile") { $0.setProfile(profile, ofPalette: id) }
    }

    /// Puts a purpose on a palette, or takes it off.
    func setPurpose(_ purpose: Purpose, on: Bool, ofPalette id: UUID) {
        apply(on ? "Set Up For \(purpose.title)" : "Remove \(purpose.title) Settings") { $0.setPurpose(purpose, on: on, ofPalette: id) }
        // A purpose just put on is the one to look at; one taken off while on show gives way to Overview.
        if on { show(purpose, forPalette: id) } else if shownPurpose(for: id) == purpose { show(nil, forPalette: id) }
    }

    func setProfile(_ profile: ColourProfile?, ofProject id: UUID) {
        apply("Set Colour Profile") { $0.setProfile(profile, ofProject: id) }
    }

    /// A project's details are on its Overview page.
    func editProject(_ id: UUID) {
        guard library.project(id) != nil else { return }
        onShow?(.overview(id), false)
    }

    /// Keeps the name and details typed into a project's Overview page.
    func saveProject(_ id: UUID, name: String, details: [String: String]) {
        apply("Edit Project Details") { lib in
            lib.renameProject(id, to: name)
            lib.setProjectDetails(id, details)
        }
    }

    /// The project form fills the page; with no page to fill (no window wiring) it falls back to a sheet.
    private func showProjectForm(mode: ProjectFormController.Mode, name: String, values: [String: String],
                                 onSave: @escaping (String, [String: String]) -> Void) {
        guard let cover = onCover else {
            if let window = window { ProjectFormController.present(over: window, mode: mode, name: name, values: values, onSave: onSave) }
            return
        }
        let form = ProjectFormController(mode: mode, name: name, values: values, onSave: onSave)
        form.onClose = { cover(nil, false) }
        cover(form, false)
    }

    @objc func manageProjectTemplates() {
        if let window = window { ProjectTemplatesController.present(over: window) }
    }

    /// What the window is showing; set by the window so project creation can use it.
    var current: Selection? { didSet { if current != oldValue { NotificationCenter.default.post(name: .selectionDidChange, object: self) } } }

    /// The project the page showing belongs to, if any.
    var currentProject: UUID? {
        if case .palette(let id)? = current { return library.swatch(id)?.projectID }
        if case .overview(let id)? = current { return id }
        return nil
    }

    func renameProject(_ id: UUID) {
        guard let p = library.project(id) else { return }
        let a = NSAlert()
        a.messageText = "Rename \u{201C}\(p.name)\u{201D}"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = p.name
        a.accessoryView = field
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        apply("Rename Project") { $0.renameProject(id, to: name) }
    }

    func delete(project id: UUID) {
        guard let p = library.project(id) else { return }
        let count = library.palettes(in: id).count
        guard count > 0 else { apply("Delete Project") { $0.deleteProject(id) }; return }
        SwissConfirm.ask(over: window, title: "Delete \(SchemaTrial.memberName(of: SchemaTrial.collection(of: id)))",
                         note: "You are about to delete \(p.name). Its \(plural(count, "palette")) move to the Palettes list; nothing leaves the catalogue. Slide across to go on.",
                         commit: "Delete") { [weak self] in self?.apply("Delete Project") { $0.deleteProject(id) } }
    }

    /// Asks a question in the middle of the page; set by the window. Title, message, answers (the last is the way out).
    var onAsk: ((String, String, [ModalChoice]) -> Void)?

    /// Puts a palette at a place in a list. Within its own list that is a move. Into a project,
    /// between projects, or back to the Palettes list, it goes as a copy: a project owns its
    /// palettes outright, so its notes, lock and history are its own and the original is untouched.
    /// A palette with notes asks first whether the copy takes them.
    func move(palette id: UUID, to project: UUID?, index: Int) {
        guard let s = library.swatch(id) else { return }
        if s.projectID == project {
            apply("Move Palette") { $0.move(id, to: project, index: index) }
            return
        }
        let place: (Bool) -> Void = { [weak self] notes in
            guard let self = self else { return }
            var copy: UUID?
            self.apply("Copy Palette") { copy = $0.copyPalette(id, to: project, index: index, withNotes: notes) }
            guard let made = copy, self.library.swatch(made) != nil else { return }   // refused: the project is locked
            let home = project.flatMap { self.library.project($0)?.name }
            self.flash(home.map { "Copied \(s.name) Into \($0)" + (notes ? ", With Its Notes" : "") } ?? "Copied \(s.name) To Palettes")
            self.onShow?(.palette(made), false)
        }
        // Notes may be wanted in the copy or not, so when there are some the user is asked, whichever way the copy goes.
        guard library.hasNotes(id), let ask = onAsk else { place(false); return }
        let from = s.projectID.flatMap { library.project($0)?.name } ?? "Palettes"
        let to = project.flatMap { library.project($0)?.name } ?? "Palettes"
        ask("Copy The Notes Across?",
            "\(s.name) has notes written on its colours. The copy going into \(to) can take them with it or start clean. The notes on the original in \(from) stay as they are either way.",
            [ModalChoice(title: "Copy With Notes", symbol: "doc.on.doc.fill") { place(true) },
             ModalChoice(title: "Copy Without Notes", symbol: "doc.on.doc") { place(false) },
             ModalChoice(title: "Cancel", symbol: "xmark") {}])
    }

    func placeProjects(_ ids: [UUID]) { apply("Arrange Projects") { $0.placeProjects(ids) } }
    func placeFavourites(_ ids: [UUID]) { apply("Arrange Favourites") { $0.placeFavourites(ids) } }
    func placeInList(_ ids: [UUID]) { apply("Arrange Palettes") { $0.placeInList(ids) } }

    // MARK: Tags

    /// `scoped` are the new tags that were given to a project as they were typed.
    func setTags(ofPalette id: UUID, _ tags: [String], scoped: [String: UUID] = [:]) {
        apply("Tag Palette") { lib in
            // Scopes first, so that a new project tag is held to its project like any other.
            for tag in tags { if let project = scoped[tag.lowercased()] { lib.setTag(tag, colour: nil, project: project) } }
            lib.setTags(ofPalette: id, tags)
        }
        let kept = Set((library.swatch(id)?.tagList ?? []).map { $0.lowercased() })
        sayRefused(tags.filter { !kept.contains($0.lowercased()) })
    }

    /// Tells the user which project tags were not added, and why.
    private func sayRefused(_ tags: [String]) {
        guard let first = tags.first else { return }
        let home = library.project(ofTag: first).flatMap { library.project($0)?.name } ?? "another project"
        flash(tags.count == 1 ? "\u{201C}\(first)\u{201D} belongs to \(home), so it was not added here"
                              : "\(tags.count) project tags were not added: they belong to other projects")
    }

    func setTags(ofSwatches hexes: [String], _ tags: [String], scoped: [String: UUID] = [:]) {
        apply("Tag Swatches") { lib in
            for tag in tags { if let project = scoped[tag.lowercased()] { lib.setTag(tag, colour: nil, project: project) } }
            for h in hexes { lib.setTags(ofColour: h, tags) }
        }
        // A tag counts as refused if any of the swatches could not take it.
        sayRefused(tags.filter { tag in
            hexes.contains { h in !(library.colours.first { $0.hex == h }?.tags ?? []).contains { $0.lowercased() == tag.lowercased() } }
        })
    }

    /// Gives a colour the user's own name within one palette; blank puts the standard name back.
    func rename(swatch hex: String, in palette: UUID, to name: String?) {
        apply("Rename Colour") { $0.setName(name, of: hex, in: palette) }
        flash(library.customName(of: hex, in: palette).map { "Named \(ColourKeys.label(hex)) \u{201C}\($0)\u{201D}" } ?? "\(ColourKeys.label(hex)) is \(colourName(hex)) again")
    }

    /// Writes why a colour is in a palette; blank removes the description.
    func describe(swatch hex: String, in palette: UUID, as note: String?) {
        apply("Describe Colour") { $0.setNote(note, of: hex, in: palette) }
    }

    func setTag(_ name: String, colour: String?, project: UUID?, group: UUID?? = nil) { apply("Edit Tag") { $0.setTag(name, colour: colour, project: project, group: group) } }
    func renameTag(_ old: String, to new: String) { apply("Rename Tag") { $0.renameTag(old, to: new) } }
    func deleteTag(_ name: String) { apply("Delete Tag") { $0.deleteTag(name) } }
    func deleteTags(_ names: [String]) { apply("Delete Tags") { lib in for name in names { lib.deleteTag(name) } } }

    /// Makes an unused tag with a name of its own and returns that name.
    @discardableResult
    func newTag() -> String {
        let name = uniqueName("New Tag", among: library.allTags)
        apply("New Tag") { $0.setTag(name, colour: nil, project: nil) }
        return name
    }

    /// Opens the tag editor over the page, with one tag's name ready to type over if asked.
    @objc func showTagEditor() { showTagEditor(focusing: nil) }

    func showTagEditor(focusing name: String?) {
        guard let cover = onCover else { return }
        let editor = TagEditorController(library: self, focus: name)
        editor.onClose = { cover(nil, false) }
        cover(editor, true)
    }

    /// Creates a palette holding `hexes` and opens it.
    @discardableResult
    func createPalette(named name: String, hexes: [String], custom: Bool = false, rename: Bool = false) -> UUID? {
        var id: UUID?
        apply("Create Palette") { lib in
            let target = lib.activeSwatchID
            id = lib.createSwatch(named: name, hexes: hexes, custom: custom)
            if custom { lib.activeSwatchID = target } // building a palette doesn't redirect picks
        }
        if let id = id { onShow?(.palette(id), rename) }
        return id
    }

    func rename(_ id: UUID, to name: String) {
        // Deferred: this is called while a name field is still ending its edit.
        DispatchQueue.main.async { [weak self] in self?.apply("Rename Palette") { $0.renameSwatch(id, to: name) } }
    }

    func toggleFavourite(_ id: UUID) {
        guard let s = library.swatch(id) else { return }
        apply(s.favourite ? "Unstar Palette" : "Star Palette") { $0.setFavourite(id, !s.favourite) }
        flash(s.favourite ? "Removed \(s.name) from Favourites" : "Added \(s.name) to Favourites")
    }

    /// Stars every palette in a project, or unstars them all when every one is starred already.
    func toggleFavourites(inProject id: UUID) {
        let palettes = library.palettes(in: id)
        guard let p = library.project(id), !palettes.isEmpty else { return }
        let on = !palettes.allSatisfy { $0.favourite }
        apply(on ? "Star Palettes" : "Unstar Palettes") { lib in for s in palettes { lib.setFavourite(s.id, on) } }
        flash(on ? "Added the palettes in \(p.name) to Favourites" : "Removed the palettes in \(p.name) from Favourites")
    }

    /// Whether picks go into this project: its palette that has them, if any.
    func picksGo(to project: UUID) -> Bool { library.activeSwatchID.flatMap { library.swatch($0) }?.projectID == project }

    /// Sends picks into the project, or stops: to the palette there that has them, or its first colour
    /// palette, or a new one made for it; nothing happens to a locked project that has no palette yet.
    func togglePicks(to project: UUID) {
        if picksGo(to: project) { setTarget(nil); return }
        if let first = library.swatches.first(where: { $0.projectID == project && !$0.isTypography }) { setTarget(first.id); return }
        guard library.project(project)?.isLocked != true else { return }
        addPalette(to: project)
        if let made = library.swatches.last(where: { $0.projectID == project && !$0.isTypography }) { setTarget(made.id) }
    }

    func setTarget(_ id: UUID?) {
        apply("Send Picks To Palette") { $0.activeSwatchID = id }
        flash(library.activeSwatch.map { "Picks now go to \($0.name)" } ?? "Picks now go to the library only")
    }

    func duplicate(_ id: UUID) {
        guard let s = library.swatch(id) else { return }
        if let styles = s.styles {
            // A Typography palette is copied with its pairings, each under a new id.
            var copy: UUID?
            apply("Duplicate Palette") { lib in
                let new = lib.createTypography(named: "\(s.name) copy", in: s.projectID)
                for style in styles {
                    lib.setStyle(TypeStyle(id: UUID(), name: style.name, ink: style.ink, paper: style.paper, heading: style.heading,
                                           body: style.body, headingFont: style.headingFont, bodyFont: style.bodyFont), in: new)
                }
                copy = new
            }
            if let copy = copy { onShow?(.palette(copy), false) }
            return
        }
        createPalette(named: "\(s.name) copy", hexes: library.hexes(inSwatch: id, by: .oldest), custom: s.custom)
    }

    /// A copy of the palette in another project (or loose), independent from then on. The original stays.
    func copy(palette id: UUID, to project: UUID?) { move(palette: id, to: project, index: Int.max) }

    func delete(palette id: UUID) {
        guard let s = library.swatch(id) else { return }
        guard !s.entries.isEmpty else { apply("Delete Palette") { $0.deleteSwatch(id) }; return }
        SwissConfirm.ask(over: window, title: "Delete Palette",
                         note: "You are about to delete \(s.name). Its \(plural(s.entries.count, "colour")) stay in the catalogue. Slide across to go on.",
                         commit: "Delete") { [weak self] in self?.apply("Delete Palette") { $0.deleteSwatch(id) } }
    }

    func add(_ hexes: [String], to id: UUID) {
        var added = 0
        apply("Add Colours") { added = $0.add(hexes, toSwatch: id) }
        let name = library.swatch(id)?.name ?? "palette"
        flash(added == 0 ? "Already in \(name)" : "Added \(plural(added, "swatch", "swatches")) to \(name)")
    }

    /// Set by the window: opens the Analysis page for some colours, named for the palette or swatch they are.
    var onAnalysis: ((String, [String]) -> Void)?

    /// The Analysis page for a whole palette, in the order its page shows.
    func analyse(palette id: UUID) {
        guard let swatch = library.swatch(id) else { return }
        onAnalysis?(swatch.name, hexes(in: id))
    }

    /// The Analysis page for one swatch.
    func analyse(swatch hex: String, in palette: UUID?) {
        onAnalysis?(library.name(of: hex, in: palette), [hex])
    }

    /// Set by the window: shows the New Colour sheet for a palette, or for All Swatches when there is none.
    var onNewColour: ((UUID?, NewColourStart?) -> Void)?

    /// A colour typed in as P3, CMYK, Lab or hex: into the palette showing, or All Swatches.
    @objc func newColour() { startColour(nil) }

    /// `start` opens the sheet on one kind of colour: what a group's own blank swatch asks for.
    func startColour(_ start: NewColourStart?) {
        var palette: UUID?
        if case .palette(let id)? = current, library.swatch(id)?.styles == nil { palette = id }
        onNewColour?(palette, start)
    }

    func add(colour definition: ColourDefinition, to palette: UUID?) {
        var key: String?
        apply("New Colour") { lib in
            key = lib.addColour(definition)
            if let key = key, let palette = palette { lib.add([key], toSwatch: palette) }
        }
        guard let added = key, library.colours.contains(where: { $0.hex == added }) else { return }
        if palette == nil { onReveal?(added) }
        let into = palette.flatMap { library.swatch($0)?.name }.map { " to \($0)" } ?? ""
        flash("Added \(colourName(added))  \(ColourKeys.label(added))\(into)")
    }

    func remove(_ hexes: [String], from id: UUID) {
        guard !hexes.isEmpty else { return }
        apply("Remove Colours") { $0.remove(Set(hexes), fromSwatch: id) }
    }

    func deleteFromLibrary(_ list: [String]) {
        let hexes = Set(list)
        guard !hexes.isEmpty else { return }
        let used = library.swatchCount(containingAnyOf: hexes)
        guard used > 0 else { apply("Delete Colours") { $0.deleteColours(hexes) }; return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete \(plural(hexes.count, "swatch", "swatches")) from the library?"
        a.informativeText = "This also removes \(hexes.count == 1 ? "it" : "them") from \(plural(used, "palette"))."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        present(a) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.apply("Delete Colours") { $0.deleteColours(hexes) } }
        }
    }

    func makePalette(_ harmony: Harmony, from hex: String) {
        let colours = harmony.colours(from: hex)
        guard !colours.isEmpty else { return }
        createPalette(named: "\(colourName(hex)) \u{2014} \(harmony.title)", hexes: colours, custom: true)
        flash("Made \(harmony.title) from \(ColourKeys.label(hex))")
    }

    // MARK: Bringing colours in

    @objc func paletteFromImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Create Palette"
        panel.message = "Choose an image to build a palette from"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            if r == .OK, let url = panel.url { self?.importPalette(from: url) }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    func importPalette(from url: URL) {
        guard let image = loadCGImage(url) else {
            flash("Couldn\u{2019}t read \(url.lastPathComponent) as an image")
            return
        }
        let hexes = extractPalette(from: image, count: Prefs.imagePaletteSize)
        guard !hexes.isEmpty else { flash("No colours found in \(url.lastPathComponent)"); return }
        let id = createPalette(named: url.deletingPathExtension().lastPathComponent, hexes: hexes)
        let name = id.flatMap { library.swatch($0)?.name } ?? "palette"
        flash("Created \(name) with \(plural(hexes.count, "swatch", "swatches")) from the image")
    }

    /// Finds every hex colour in whatever text is on the clipboard — CSS, JSON, a message.
    @objc func paletteFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let hexes = hexColours(in: text)
        guard !hexes.isEmpty else { flash("No hex colours found on the clipboard"); return }
        createPalette(named: "Pasted colours", hexes: hexes, rename: true)
        flash("Made a palette of \(plural(hexes.count, "swatch", "swatches")) from the clipboard")
    }

    @objc func importFromV2() {
        #if APPSTORE
        // The sandbox cannot see the earlier app's folder: the user picks its library file.
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose the earlier app's library.json, in Library \u{25B8} Application Support \u{25B8} MMFFDev Colour 2"
        panel.directoryURL = Catalogues.realApplicationSupport.appendingPathComponent("MMFFDev Colour 2")
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url), let previous = try? JSONDecoder.library.decode(Library.self, from: data) else {
                self.flash("That is not an MMFFDev Colour 2 library"); return
            }
            self.importEarlier(previous)
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
        #else
        guard let previous = store.loadPrevious() ?? Catalogues.standard.store(for: Catalogues.mainName).loadPrevious() else {
            flash("No MMFFDev Colour 2 library found")
            return
        }
        importEarlier(previous)
        #endif
    }

    private func importEarlier(_ previous: Library) {
        var gained = LibraryChange()
        apply("Import Earlier Library") { lib in
            let merged = mergeLibraries(local: lib, remote: previous)
            gained = change(from: lib, to: merged)
            lib = merged
        }
        flash(gained.isEmpty ? "Nothing new to import from MMFFDev Colour 2"
                             : "Imported from MMFFDev Colour 2: " + gained.lines.joined(separator: ", "))
    }

    // MARK: Exporting

    func exportPalettes(for selection: Selection) -> [ExportPalette] {
        switch selection {
        case .palette(let id): return library.exportPalette(id, by: paletteSort).map { [$0] } ?? []
        case .all: return [library.exportEverything(named: catalogue == Catalogues.mainName ? "All Swatches" : catalogue, by: .colour)]
        case .tag(let t):
            let hexes = library.catalogueHexes(by: .colour).filter { library.hexes(tagged: t).contains($0) }
            return [ExportPalette(name: "Tagged \(t)", colours: hexes.map { ExportColour(name: colourName($0), hex: displayHex($0)) })]
        case .lab: return labPalette.map { [$0] } ?? []
        case .contrast: return contrastPalette.map { [$0] } ?? []
        // From a project's Overview, the export is the project: each of its palettes of colours.
        case .overview(let id): return library.palettes(in: id).filter { !$0.isTypography }.compactMap { library.exportPalette($0.id, by: paletteSort) }
        }
    }

    // MARK: Design pack

    func exportDesignPack(project id: UUID) {
        guard let p = library.project(id) else { return }
        exportDesignPack(library.designPack(named: p.name, projects: [id], owner: Prefs.licenceOwner, licence: Prefs.licenceText, order: paletteSort))
    }

    func exportDesignPack(for selection: Selection) {
        let pack: DesignPack
        switch selection {
        case .palette(let id):
            guard let s = library.swatch(id) else { return }
            pack = library.designPack(named: s.name, palettes: [id], owner: Prefs.licenceOwner, licence: Prefs.licenceText, order: paletteSort)
        case .overview(let id):
            exportDesignPack(project: id)
            return
        case .all, .tag, .lab, .contrast:
            pack = library.designPack(named: catalogue == Catalogues.mainName ? "Colour Library" : catalogue,
                                      owner: Prefs.licenceOwner, licence: Prefs.licenceText, order: paletteSort)
        }
        exportDesignPack(pack)
    }

    /// Chooses a folder, writes the pack into it, and offers a git commit and push when the folder is in a repository.
    private func exportDesignPack(_ pack: DesignPack) {
        guard pack.palettes.contains(where: { !$0.swatches.isEmpty }) else { flash("Nothing to put in a design pack yet"); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put \u{201C}\(pack.folderName)\u{201D} \u{2014} a git checkout, a shared drive, any folder"
        let git = NSButton(checkboxWithTitle: "Commit and push with git when the folder is in a repository", target: nil, action: nil)
        git.state = .off
        let row = NSStackView(views: [git])
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        panel.accessoryView = gitAvailable ? row : nil
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let folder = panel.url else { return }
            do {
                let out = try writeDesignPack(pack, into: folder, options: Prefs.exportOptions)
                var note = "Exported \(out.lastPathComponent)"
                if git.state == .on, let repo = gitRoot(of: folder) {
                    let result = gitCommitAndPush(repo: repo, path: out, message: "Design pack: \(pack.name)")
                    note += result.ok ? " and pushed" : " \u{2014} git failed: \(result.message)"
                    if !result.ok { self.show(NSError(domain: "git", code: 1, userInfo: [NSLocalizedDescriptionKey: result.message])) }
                } else if git.state == .on {
                    note += " \u{2014} not a git repository, so nothing was pushed"
                }
                self.flash(note)
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                self.show(error)
            }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Save panel with a format chooser.
    func export(_ palettes: [ExportPalette]) {
        guard let first = palettes.first, palettes.contains(where: { !$0.colours.isEmpty }) else {
            flash("Nothing to export yet")
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.message = palettes.count == 1 ? "Export \u{201C}\(first.name)\u{201D}" : "Export \(palettes.count) palettes"

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: ExportFormat.allCases.map { $0.title })
        popup.selectItem(at: ExportFormat.allCases.firstIndex(of: Prefs.exportFormat) ?? 0)
        let chooser = FormatChooser(panel: panel, popup: popup, palettes: palettes)
        popup.target = chooser
        popup.action = #selector(FormatChooser.changed)
        panel.delegate = chooser
        chooser.onSystemFolder = { [weak self] format, url in self?.exportAsAdministrator(format, palettes, to: url) }
        let row = NSStackView(views: [caption("Format:", size: 13), popup])
        row.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        panel.accessoryView = row
        chooser.changed()

        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            let format = chooser.format
            Prefs.exportFormat = format
            do {
                try writeExport(format, palettes, to: url, options: Prefs.exportOptions)
                self.flash("Exported \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                self.show(error)
            }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// The save panel refuses a folder the system owns. This writes the file somewhere the user owns
    /// and has macOS copy it across as an administrator, behind its own password dialog.
    private func exportAsAdministrator(_ format: ExportFormat, _ palettes: [ExportPalette], to url: URL) {
        let folder = url.deletingLastPathComponent()
        let copy = { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            let staging = fm.temporaryDirectory.appendingPathComponent("MMFFDev Colour 3 Export")
            let file = staging.appendingPathComponent(url.lastPathComponent)
            do {
                try? fm.removeItem(at: staging)
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try writeExport(format, palettes, to: file, options: Prefs.exportOptions)
                let prompt = "\(Brand.name) wants to save \u{201C}\(file.lastPathComponent)\u{201D} in the \u{201C}\(folder.lastPathComponent)\u{201D} folder."
                switch try copyIntoFolder([file], folder, prompt: prompt) {
                case .copied:
                    Prefs.exportFormat = format
                    self.flash("Exported \(url.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .cancelled:
                    NSWorkspace.shared.open(folder)
                    NSWorkspace.shared.activateFileViewerSelecting([file])
                    self.flash("Not saved \u{2014} drag \u{201C}\(file.lastPathComponent)\u{201D} into \u{201C}\(folder.lastPathComponent)\u{201D} and Finder will ask for your password")
                }
            } catch {
                self.show(error)
            }
        }
        guard FileManager.default.fileExists(atPath: url.path) else { copy(); return }
        let alert = NSAlert()
        alert.messageText = "\u{201C}\(url.lastPathComponent)\u{201D} already exists. Do you want to replace it?"
        alert.informativeText = "A file with the same name already exists in the folder \u{201C}\(folder.lastPathComponent)\u{201D}. Replacing it will overwrite its current contents."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        present(alert) { if $0 == .alertFirstButtonReturn { DispatchQueue.main.async(execute: copy) } }
    }

    /// Saves the palette where the system colour panel looks, so it shows up in every Mac app.
    func addToColourPanel(_ palettes: [ExportPalette]) {
        #if APPSTORE
        // The sandbox turns ~/Library/Colors into the app's own copy, which no other app reads. The user
        // points at the real one once; from then on it is remembered and the files go straight in.
        let real = Catalogues.realHome.appendingPathComponent("Library/Colors")
        if !FolderAccess.covers(real) {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.directoryURL = real
            panel.prompt = "Add Here"
            panel.message = "Choose the Colors folder in your Library, where the colour panel of every app looks"
            let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
                guard let self = self, r == .OK, let url = panel.url else { return }
                FolderAccess.remember(url)
                self.writeColourLists(palettes, into: url)
            }
            if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
            return
        }
        writeColourLists(palettes, into: real)
        #else
        writeColourLists(palettes, into: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Colors"))
        #endif
    }

    private func writeColourLists(_ palettes: [ExportPalette], into dir: URL) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for p in palettes where !p.colours.isEmpty {
                try p.colourList().write(to: dir.appendingPathComponent(filesystemName(p.name) + ".clr"))
            }
            flash("Added to the macOS colour panel \u{2014} reopen the panel to see it")
        } catch {
            show(error)
        }
    }

    /// Puts each palette in the folder where an Adobe app keeps its own libraries, so it is listed in
    /// that app's menus. The folder belongs to the system, so macOS asks for an administrator's password.
    func addToAdobe(_ palettes: [ExportPalette], at destination: AdobeDestination) {
        let palettes = palettes.filter { !$0.colours.isEmpty }
        guard !palettes.isEmpty else { flash("Nothing to export yet"); return }
        let fm = FileManager.default
        // A folder the user owns: where the files stay if the password is not given.
        let staging = fm.temporaryDirectory.appendingPathComponent("MMFFDev Colour 3 for Adobe")
        do {
            try? fm.removeItem(at: staging)
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var files: [URL] = []
            for p in palettes {
                let url = staging.appendingPathComponent(uniqueName(destination.fileName(for: p), among: files.map { $0.lastPathComponent }))
                try writeExport(destination.format, [p], to: url, options: Prefs.exportOptions)
                files.append(url)
            }
            let what = files.count == 1 ? "\u{201C}\(files[0].lastPathComponent)\u{201D}" : "\(files.count) files"
            let prompt = "MMFFDev Colour 3 wants to add \(what) to the \u{201C}\(destination.folder.lastPathComponent)\u{201D} folder of \(destination.app)."
            switch try copyIntoFolder(files, destination.folder, prompt: prompt) {
            case .copied:
                flash("Added to \(destination.app) \u{2014} restart it to see \(files.count == 1 ? "the library" : "the libraries")")
            case .cancelled:
                // Nothing was written. Finder can ask for the password itself if the files are dragged across.
                // In the Store build this is the only way in: the sandbox cannot write to a folder the system owns.
                NSWorkspace.shared.open(destination.folder)
                NSWorkspace.shared.activateFileViewerSelecting(files)
                #if APPSTORE
                flash("Drag \(what) into \u{201C}\(destination.folder.lastPathComponent)\u{201D} of \(destination.app) \u{2014} Finder will ask for your password")
                #else
                flash("Not added \u{2014} drag \(what) into \u{201C}\(destination.folder.lastPathComponent)\u{201D} and Finder will ask for your password")
                #endif
            }
        } catch {
            show(error)
        }
    }

    /// Whole library: library.json plus a text file per palette, in a new folder.
    @objc func exportLibrary() {
        if library.colours.isEmpty { flash("Nothing to export yet"); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose where to put the export folder"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let folder = panel.url else { return }
            do {
                let out = try writeExport(self.library, to: folder, by: .oldest)
                let all = self.paletteOrder.compactMap { self.library.exportPalette($0.id, by: .oldest) }.filter { !$0.colours.isEmpty }
                let format = Prefs.exportFormat
                if !all.isEmpty {
                    try writeExport(format, all, to: out.appendingPathComponent(format.fileName(for: all)),
                                    options: Prefs.exportOptions)
                }
                self.flash("Exported \(plural(self.library.colours.count, "swatch", "swatches")) to \(out.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } catch {
                self.show(error)
            }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Text and a picture, for the share sheet.
    func shareItems(for selection: Selection) -> [Any] {
        let palettes = exportPalettes(for: selection).filter { !$0.colours.isEmpty }
        guard let first = palettes.first else { return [] }
        var items: [Any] = [first.name + "\n" + first.colours.map { "\($0.hex)  \($0.name)" }.joined(separator: "\n")]
        if let png = swatchSheet(palettes) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(slug(first.name) + ".png")
            if (try? png.write(to: url, options: .atomic)) != nil { items.append(url) }
        }
        return items
    }

    // MARK: Catalogues

    /// Catalogues on this Mac, plus any in the sync folder that this Mac hasn't opened yet.
    func availableCatalogues() -> [String] {
        var names = Catalogues.standard.names()
        if let folder = SyncSettings.folder {
            for n in SyncEngine.catalogues(in: folder).sorted() where !names.contains(n) { names.append(n) }
        }
        return names
    }

    func open(catalogue requested: String) {
        guard requested != catalogue || store.root.standardizedFileURL != Catalogues.standard.directory(for: requested).standardizedFileURL else { return }
        stopPicking()
        var name = requested
        if !Catalogues.standard.names().contains(name) { // so far it only exists in the sync folder
            do { name = try Catalogues.standard.create(name) } catch { show(error); return }
        }
        catalogue = name
        Catalogues.currentName = name
        store = Catalogues.standard.store(for: name)
        reportedQuarantine = nil
        syncPaused = false
        lastSyncComplaint = nil
        syncStatus = "Not synced yet."
        reload()
        onShow?(.all, false)
        flash("Opened \(name)")
        sync()
        stateChanged()
    }

    /// Renames a catalogue here and in the sync folder. The other Mac follows on its next sync.
    func rename(catalogue old: String, to raw: String) {
        let new = filesystemName(raw)
        guard new.lowercased() != old.lowercased() else { return }
        if let folder = SyncSettings.folder {
            if SyncEngine.catalogues(in: folder).contains(where: { $0.lowercased() == new.lowercased() }) {
                show(CatalogueError.nameTaken(new)); return
            }
            do { try SyncEngine.rename(in: folder, from: old, to: new) } catch { show(error); return }
        }
        let name: String
        do { name = try Catalogues.standard.rename(old, to: new) } catch { show(error); return }
        if old == catalogue { switchStore(to: name) }
        flash("Renamed \(old) to \(name)")
        stateChanged()
    }

    @objc func renameCatalogue() {
        let a = NSAlert()
        a.messageText = "Rename \u{201C}\(catalogue)\u{201D}"
        a.informativeText = "The catalogue's folder is renamed here and in the sync folder. Your other Mac picks the new name up the next time it syncs."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = catalogue
        a.accessoryView = field
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        rename(catalogue: catalogue, to: name)
    }

    /// Points this controller at a catalogue that already exists, without a reload.
    private func switchStore(to name: String) {
        catalogue = name
        Catalogues.currentName = name
        store = Catalogues.standard.store(for: name)
    }

    @objc func newCatalogue() {
        let a = NSAlert()
        a.messageText = "New Catalogue"
        a.informativeText = "A catalogue is a separate library with its own swatches and palettes."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Catalogue name"
        a.accessoryView = field
        a.addButton(withTitle: "Create")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do { open(catalogue: try Catalogues.standard.create(name)) } catch { show(error) }
    }

    @objc func openCatalogueFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Open as Catalogue"
        panel.message = "Choose a library.json from an export or a backup. It is copied, never changed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { open(catalogue: try Catalogues.standard.importFile(url)) } catch { show(error) }
    }

    // MARK: Sync

    private func engine() -> SyncEngine? {
        SyncSettings.folder.map {
            SyncEngine(store: store, chosenFolder: $0, catalogue: catalogue,
                       machine: SyncSettings.machineName, backupsToKeep: SyncSettings.backupsToKeep)
        }
    }

    /// File ▸ Sync Now, and the button in Settings. Also un-pauses after "Not Now".
    @objc func syncNow() {
        syncPaused = false
        lastSyncComplaint = nil
        guard SyncSettings.folder != nil else { flash("Choose a sync folder in Settings first"); return }
        sync(loud: true)
    }

    func syncTurnedOff() {
        syncPaused = false
        syncStatus = "Not synced yet."
        stateChanged()
    }

    /// Runs after launch, on returning to the window, and after every change.
    /// `loud` reports problems in a sheet; otherwise they only show in the status bar.
    func sync(loud: Bool = false) {
        guard let engine = engine(), !syncAsking, !picking, !syncPaused || loud else { return }
        do {
            switch try engine.check() {
            case .renamed(let new):
                followRename(to: new)
            case .firstSync:
                try engine.push(try store.load())
                synced("Saved \(catalogue) to the sync folder", announce: true)
            case .inSync:
                synced(nil, announce: loud)
            case .quiet(let plan):
                try engine.settle(plan)
                if !plan.incoming.isEmpty || canonical(plan.merged) != canonical(plan.local) { reloadAfterSync() }
                synced(plan.incoming.isEmpty ? nil : "Loaded \(catalogue) from the sync folder",
                       announce: loud || !plan.incoming.isEmpty)
            case .incoming(let plan):
                if SyncSettings.askBeforeMerging { ask(plan) } else { finish(.merge) }
            }
        } catch {
            complain(error, loud: loud)
        }
    }

    /// The other Mac renamed this catalogue; rename it here and carry on under the new name.
    private func followRename(to new: String) {
        let old = catalogue
        if Catalogues.standard.names().contains(where: { $0.lowercased() == new.lowercased() && $0 != old }) {
            syncStatus = "Paused \u{2014} this catalogue was renamed to \u{201C}\(new)\u{201D} on another Mac, but a catalogue of that name already exists here."
            syncPaused = true
            stateChanged()
            return
        }
        do {
            let name = try Catalogues.standard.rename(old, to: new)
            switchStore(to: name)
            flash("This catalogue was renamed to \(name) on another Mac")
            stateChanged()
            sync()
        } catch {
            complain(error, loud: false)
        }
    }

    private func ask(_ plan: SyncPlan) {
        syncAsking = true
        func bullets(_ c: LibraryChange) -> String { c.lines.map { "   \u{2022} \($0)" }.joined(separator: "\n") }
        var text = "From the synced copy:\n" + bullets(plan.incoming)
        if !plan.outgoing.isEmpty { text += "\n\nFrom this Mac:\n" + bullets(plan.outgoing) }
        text += "\n\nMerge keeps everything from both. Whatever you choose, both copies are backed up first."

        let a = NSAlert()
        a.messageText = "The synced copy of \u{201C}\(catalogue)\u{201D} has changes"
        a.informativeText = text
        a.addButton(withTitle: "Merge")
        a.addButton(withTitle: "Use Synced Copy")
        a.addButton(withTitle: "Keep This Mac\u{2019}s")
        a.addButton(withTitle: "Not Now")
        present(a) { [weak self] response in
            guard let self = self else { return }
            self.syncAsking = false
            switch response {
            case .alertFirstButtonReturn: self.finish(.merge)
            case .alertSecondButtonReturn: self.finish(.useSynced)
            case .alertThirdButtonReturn: self.finish(.keepLocal)
            default:
                self.syncPaused = true
                self.syncStatus = "Paused \u{2014} the synced copy has changes. Choose Sync Now to decide."
                self.stateChanged()
            }
        }
    }

    /// Checks again first, so the decision is applied to what is there now, not when the question was asked.
    private func finish(_ choice: SyncChoice) {
        guard let engine = engine() else { return }
        do {
            switch try engine.check() {
            case .renamed(let new):
                followRename(to: new)
            case .incoming(let plan), .quiet(let plan):
                try engine.perform(choice, plan: plan)
                reloadAfterSync()
                switch choice {
                case .merge: synced("Merged: " + (plan.incoming.lines + plan.outgoing.lines.map { $0 + " sent" }).joined(separator: ", "), announce: true)
                case .useSynced: synced("Now using the synced copy", announce: true)
                case .keepLocal: synced("Kept this Mac\u{2019}s copy", announce: true)
                }
            case .firstSync:
                try engine.push(try store.load())
                synced(nil, announce: false)
            case .inSync:
                synced(nil, announce: false)
            }
        } catch {
            complain(error, loud: true)
        }
    }

    private func reloadAfterSync() {
        let before = library
        do { library = try store.load() } catch { show(error) }
        loadedStamp = store.modificationDate
        if library != before { recordStep("Sync", before: before) }
        changed()
    }

    private func synced(_ message: String?, announce: Bool) {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        syncStatus = "In sync \u{2014} last checked \(f.string(from: Date()))."
        lastSyncComplaint = nil
        syncPaused = false
        if announce { flash(message ?? "\(catalogue) is in sync") }
        stateChanged()
    }

    private func complain(_ error: Error, loud: Bool) {
        let text = error.localizedDescription
        syncStatus = "Not synced: \(text)"
        stateChanged()
        if loud { show(error) }
        else if text != lastSyncComplaint { flash("Sync: \(text)") } // once, not on every change
        lastSyncComplaint = text
    }
}

/// Keeps the save panel's file name and type in step with the format popup, and steps in when the
/// chosen folder belongs to the system, which the panel itself would only refuse.
final class FormatChooser: NSObject, NSOpenSavePanelDelegate {
    /// Called, once the panel has gone, with the file the user asked for in a folder they may not write to.
    var onSystemFolder: ((ExportFormat, URL) -> Void)?

    private let panel: NSSavePanel
    private let popup: NSPopUpButton
    private let palettes: [ExportPalette]

    init(panel: NSSavePanel, popup: NSPopUpButton, palettes: [ExportPalette]) {
        self.panel = panel
        self.popup = popup
        self.palettes = palettes
        super.init()
        objc_setAssociatedObject(panel, Unmanaged.passUnretained(self).toOpaque(), self, .OBJC_ASSOCIATION_RETAIN)
    }

    var format: ExportFormat { ExportFormat.allCases[max(0, popup.indexOfSelectedItem)] }

    func panel(_ sender: Any, userEnteredFilename filename: String, confirmed okFlag: Bool) -> String? {
        guard okFlag, let folder = panel.directoryURL, !FileManager.default.isWritableFile(atPath: folder.path) else { return filename }
        let format = self.format
        let name = (filename as NSString).pathExtension.isEmpty ? "\(filename).\(format.fileExtension)" : filename
        // Returning nil stops the panel's own save, and with it the refusal. Close it, then take over.
        DispatchQueue.main.async {
            self.panel.cancel(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.onSystemFolder?(format, folder.appendingPathComponent(name)) }
        }
        return nil
    }

    @objc func changed() {
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        panel.nameFieldStringValue = format.fileName(for: palettes)
    }
}

// MARK: Palette files in and out

extension LibraryController {
    /// What an import panel is for: the app's own palette files, or variables and tokens from other tools.
    enum ImportKind {
        case paletteFiles, tokens
        var title: String { self == .paletteFiles ? "Import Palette Files" : "Import CSS Tokens" }
        var message: String {
            self == .paletteFiles ? "Choose .colpal or .coltyp files. Each becomes a palette, or merges into one of the same name."
                : "Choose CSS, SCSS or design-token JSON files. Their colours merge in; duplicates are skipped."
        }
        var extensions: [String] { self == .paletteFiles ? [ColourFiles.palette, ColourFiles.typography, ColourFiles.legacyPalette] : ["css", "scss", "json", "txt"] }
    }

    /// Reads the chosen files into the palettes of `project`, or the stock list when nil, and says what happened.
    func importPalettes(_ kind: ImportKind, into project: UUID?) {
        if let p = project, library.project(p)?.isLocked == true { flash("Locked: unlock the \(SchemaTrial.memberName(of: SchemaTrial.collection(of: p)).lowercased()) first"); return }
        let panel = NSOpenPanel()
        panel.title = kind.title
        panel.message = kind.message
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = kind.extensions.compactMap { UTType(filenameExtension: $0) }
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, !panel.urls.isEmpty else { return }
            var imported: [ImportedPalette] = [], unread: [String] = []
            for url in panel.urls {
                let found = (try? Data(contentsOf: url)).map { PaletteImport.read($0, fallback: url.deletingPathExtension().lastPathComponent) } ?? []
                if found.isEmpty { unread.append(url.lastPathComponent) } else { imported += found }
            }
            guard !imported.isEmpty else { self.flash("No colours found in \(unread.joined(separator: ", "))"); return }
            var outcome = ImportOutcome()
            self.apply(kind.title) { outcome = $0.merge(imported, into: project) }
            let where_ = project.flatMap { self.library.project($0)?.name } ?? "Palettes"
            self.flash("Imported into \(where_): \(outcome.summary)" + (unread.isEmpty ? "" : ". Nothing read from \(unread.joined(separator: ", "))"))
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Every palette of colours in `project` (nil: the stock list), in one file of the chosen format.
    func exportPalettes(in project: UUID?) {
        export(library.palettes(in: project).filter { !$0.isTypography }.compactMap { library.exportPalette($0.id, by: paletteSort) })
    }

    /// One palette as a .colpal, or a .coltyp for a typography palette, the app's own file, for another catalogue to import.
    func exportPaletteFile(_ id: UUID) {
        guard let s = library.swatch(id) else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.message = "Export \u{201C}\(s.name)\u{201D} as a palette file"
        panel.allowedContentTypes = [UTType(filenameExtension: CatalogueTree.fileExtension(of: s))].compactMap { $0 }
        panel.nameFieldStringValue = filesystemName(s.name) + "." + CatalogueTree.fileExtension(of: s)
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                guard let file = try self.paletteFiles([s]).first else { return }
                try file.data.write(to: url, options: .atomic)
                self.flash("Exported \(url.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { self.show(error) }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Every palette of colours in `project` (nil: the stock list) as .colpalette files in a chosen folder.
    func exportPaletteFiles(in project: UUID?) {
        let palettes = library.palettes(in: project).filter { !$0.isTypography && !$0.entries.isEmpty }
        guard !palettes.isEmpty else { flash("Nothing to export yet"); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Each palette becomes a .colpalette file in the folder you choose"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let folder = panel.url else { return }
            do {
                var written: [URL] = []
                for file in try self.paletteFiles(palettes) {
                    let url = folder.appendingPathComponent(file.name)
                    try file.data.write(to: url, options: .atomic)
                    written.append(url)
                }
                self.flash("Exported \(plural(written.count, "palette file", "palette files")) to \(folder.lastPathComponent)")
                NSWorkspace.shared.activateFileViewerSelecting(written)
            } catch { self.show(error) }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// The palette files for some palettes, each on its own (no project), named for the palette.
    private func paletteFiles(_ palettes: [Swatch]) throws -> [(name: String, data: Data)] {
        var taken: [String] = []
        return try palettes.map { palette in
            let name = uniqueName(filesystemName(palette.name), among: taken)
            taken.append(name)
            return (name: name + "." + CatalogueTree.fileExtension(of: palette), data: try ColourFiles.encoder().encode(CatalogueTree.paletteDocument(palette, in: library, member: nil, file: name)))
        }
    }
}

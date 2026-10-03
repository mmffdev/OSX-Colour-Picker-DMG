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
}

final class LibraryController: NSObject {
    private(set) var store: LibraryStore
    private(set) var library = Library()
    private(set) var catalogue: String
    weak var window: NSWindow?

    /// Asks the window to show something. `rename` puts the palette's name into edit mode.
    var onShow: ((Selection, _ rename: Bool) -> Void)?
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
    }

    // MARK: Reading

    var favourites: [Swatch] { library.orderedFavourites }
    /// Every palette of colours once, in sidebar order: project by project, then the loose ones.
    /// Typography palettes are left out: colours are not added to them, and they have a list of their own.
    var paletteOrder: [Swatch] {
        (library.orderedProjects.flatMap { library.palettes(in: $0.id) } + library.palettes(in: nil)).filter { !$0.isTypography }
    }

    var paletteSort: SortOrder {
        get { SortOrder(rawValue: preferences.object(forKey: "paletteSort") as? Int ?? SortOrder.oldest.rawValue) ?? .oldest }
        set { preferences.set(newValue.rawValue, forKey: "paletteSort"); changed() }
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
    func apply(_ title: String = "Change", _ body: (inout Library) -> Void) {
        let before = library
        do {
            library = try store.mutate { lib in
                var trial = lib
                body(&trial)
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
        writeProjectFilesSoon()
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

    /// Takes the library back (or forward) to a step. Not a step itself.
    func goToStep(_ index: Int) {
        guard let lib = history.go(to: index) else { return }
        do { try store.save(lib); library = lib; loadedStamp = store.modificationDate } catch { show(error); return }
        historyChanged()
        changed()
        sync()
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
        writeProjectFilesSoon()
    }

    // MARK: Project files

    private var projectFilesWritten: [UUID: Data] = [:]
    private var projectFilesTimer: Timer?

    /// Each project's own file follows the library, a moment after it changes.
    private func writeProjectFilesSoon() {
        projectFilesTimer?.invalidate()
        projectFilesTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in self?.writeProjectFiles() }
    }

    /// Projects whose file has existed and cannot be found, with why.
    private(set) var lostProjects: [UUID: ProjectFiles.Loss] = [:]

    func writeProjectFiles() {
        do {
            let done = try ProjectFiles.write(library, library: store.url, master: ProjectFiles.folder,
                                              history: Prefs.projectHistory && historyEnabled ? history : nil, written: &projectFilesWritten)
            if !done.firstTime.isEmpty {
                // Remembered without becoming a step: it is bookkeeping, not a change the user made.
                library = try store.mutate { lib in for id in done.firstTime { lib.markProjectFile(id, known: true) } }
                loadedStamp = store.modificationDate
            }
        } catch { flash("Could not write a project file: \(error.localizedDescription)") }
        let lost = ProjectFiles.lost(in: library, library: store.url, master: ProjectFiles.folder)
        let changed = lost != lostProjects
        lostProjects = lost
        if changed { NotificationCenter.default.post(name: .projectFilesDidChange, object: self) }
    }

    /// The project's file, where it should be.
    func projectFileURL(_ id: UUID) -> URL? { library.project(id).map { ProjectFiles.url(for: $0, library: store.url, master: ProjectFiles.folder) } }
    func projectFolderURL(_ id: UUID) -> URL? { library.project(id).map { ProjectFiles.root(for: $0, library: store.url, master: ProjectFiles.folder) } }

    /// Gives the project a folder of its own, or nil to put it back under the master folder, moving its folder.
    func setProjectLocked(_ id: UUID, _ on: Bool) {
        apply(on ? "Lock Project" : "Unlock Project") { $0.setProjectLocked(id, on) }
    }

    func isLocked(palette id: UUID) -> Bool {
        library.swatch(id)?.projectID.flatMap { library.project($0)?.isLocked } ?? false
    }

    func setProjectFolder(_ id: UUID, _ folder: URL?) {
        guard let p = library.project(id) else { return }
        let old = ProjectFiles.root(for: p, library: store.url, master: ProjectFiles.folder)
        apply("Keep Project In") { $0.setProjectFolder(id, folder?.path) }
        projectFilesWritten[id] = nil
        if let new = projectFolderURL(id), new != old, FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.removeItem(at: new)
            try? FileManager.default.moveItem(at: old, to: new)
        }
        writeProjectFiles()
    }

    /// Lets the user point at the project's file after it was moved; the folder structure is built round it if need be.
    func relocateProject(_ id: UUID) {
        guard let p = library.project(id) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: ProjectFiles.fileExtension) ?? .data]
        panel.prompt = "Use This"
        panel.message = "Find \u{201C}\(p.name)\u{201D}: its \(ProjectFiles.fileExtension) file, or the folder holding it"
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                let root = try ProjectFiles.adopt(url, for: p)
                let under = ProjectFiles.master(library: self.store.url, master: ProjectFiles.folder)
                let inMaster = root.deletingLastPathComponent().resolvingSymlinksInPath() == under.resolvingSymlinksInPath()
                let own: String? = inMaster && root.lastPathComponent == filesystemName(p.name) ? nil : root.path
                self.apply("Find Project File") { $0.setProjectFolder(id, own) }
                self.projectFilesWritten[id] = nil
                self.writeProjectFiles()
                self.flash("\u{201C}\(p.name)\u{201D} found")
                self.onCover?(nil, false)
            } catch {
                self.show(error)
            }
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Writes a lost project's file afresh from the library, because the user asked.
    func rewriteProjectFile(_ id: UUID) {
        guard library.project(id) != nil else { return }
        library = (try? store.mutate { $0.markProjectFile(id, known: false) }) ?? library
        projectFilesWritten[id] = nil
        writeProjectFiles()
        onCover?(nil, false)
    }

    /// The page shown for a project whose file is gone.
    func showLostProject(_ id: UUID) {
        guard let p = library.project(id), let loss = lostProjects[id] else { return }
        onCover?(LostProjectController(library: self, project: p, loss: loss), true)
    }

    @objc func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Keep Projects Here"
        panel.message = "Choose the folder where project files are kept"
        if let current = ProjectFiles.folder { panel.directoryURL = current }
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            ProjectFiles.folder = url
            self.projectFilesWritten = [:]
            self.writeProjectFiles()
            self.stateChanged()
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    /// Lets the user pick a folder of the project's own.
    func moveProject(_ id: UUID) {
        guard let p = library.project(id) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Keep Project Here"
        panel.message = "Choose where the \u{201C}\(p.name)\u{201D} folder should live"
        panel.directoryURL = ProjectFiles.root(for: p, library: store.url, master: ProjectFiles.folder).deletingLastPathComponent()
        let done: (NSApplication.ModalResponse) -> Void = { [weak self] r in
            guard r == .OK, let url = panel.url else { return }
            self?.setProjectFolder(id, url.appendingPathComponent(filesystemName(p.name)))
            self?.flash("\u{201C}\(p.name)\u{201D} is kept in \(url.lastPathComponent)")
        }
        if let w = window { panel.beginSheetModal(for: w, completionHandler: done) } else { done(panel.runModal()) }
    }

    func showProjectFile(_ id: UUID) {
        writeProjectFiles()
        if let url = projectFileURL(id), FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else if let root = projectFolderURL(id) { NSWorkspace.shared.activateFileViewerSelecting([root]) }
    }
    private func stateChanged() { NotificationCenter.default.post(name: .appStateDidChange, object: self) }

    func flash(_ text: String) {
        NotificationCenter.default.post(name: .statusMessage, object: self, userInfo: ["text": text])
    }

    func show(_ error: Error) { present(NSAlert(error: error)) }

    private func present(_ alert: NSAlert, then: ((NSApplication.ModalResponse) -> Void)? = nil) {
        if let w = window { alert.beginSheetModal(for: w) { then?($0) } }
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
            guard let color = color, let hex = hexOf(color), !self.clickLandedOnThisWindow() else {
                self.stopPicking()
                return
            }
            playShutter()
            copyToClipboard(Prefs.copyText(hex))
            self.apply("Pick Colour") { $0.addPick(hex) }
            self.onReveal?(hex)
            let into = self.library.activeSwatch.map { " \u{2192} \($0.name)" } ?? ""
            self.flash("Picked \(colourName(hex))  \(hex)\(into)")
            if Prefs.keepPicking { DispatchQueue.main.async { self.sampleNext() } }
            else { self.stopPicking() }
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

    /// The same, putting `palette` into the project once it is made.
    func startProject(moving palette: UUID?) {
        showProjectForm(mode: .newProject, name: "", values: [:]) { [weak self] name, values in
            guard let self = self else { return }
            var id: UUID?
            self.apply("New Project") { lib in
                let made = lib.createProject(named: name)
                lib.setProjectDetails(made, values)
                // The palette asked for moves in; failing that the open one, so the project is not born empty.
                if let palette = palette { lib.move(palette, to: made, index: 0) }
                else if case .palette(let open)? = self.current, lib.swatch(open)?.projectID == nil { lib.move(open, to: made, index: 0) }
                id = made
            }
            self.flash("Created project \(id.flatMap { self.library.project($0)?.name } ?? name)")
        }
    }

    /// Opens the project form on an existing project.
    func editProject(_ id: UUID) {
        guard let p = library.project(id) else { return }
        showProjectForm(mode: .project, name: p.name, values: p.details ?? [:]) { [weak self] name, values in
            self?.apply("Edit Project Details") { lib in
                lib.renameProject(id, to: name)
                lib.setProjectDetails(id, values)
            }
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
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete the project \u{201C}\(p.name)\u{201D}?"
        a.informativeText = "Its \(plural(count, "palette")) will move to the Palettes list. Nothing is deleted from the library."
        a.addButton(withTitle: "Delete Project")
        a.addButton(withTitle: "Cancel")
        present(a) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.apply("Delete Project") { $0.deleteProject(id) } }
        }
    }

    func move(palette id: UUID, to project: UUID?, index: Int) {
        apply("Move Palette") { $0.move(id, to: project, index: index) }
        let name = library.swatch(id)?.name ?? "palette"
        flash(project.flatMap { library.project($0)?.name }.map { "Moved \(name) to \($0)" } ?? "Moved \(name) out of its project")
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
        flash(library.customName(of: hex, in: palette).map { "Named \(hex) \u{201C}\($0)\u{201D}" } ?? "\(hex) is \(colourName(hex)) again")
    }

    func setTag(_ name: String, colour: String?, project: UUID?) { apply("Edit Tag") { $0.setTag(name, colour: colour, project: project) } }
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
    func copy(palette id: UUID, to project: UUID?) {
        guard let s = library.swatch(id) else { return }
        let home = project.flatMap { library.project($0)?.name }
        let name = home.map { "\(s.name) (\($0))" } ?? "\(s.name) copy"
        var copy: UUID?
        apply("Copy To Project") { lib in
            if let styles = s.styles {
                let new = lib.createTypography(named: name, in: project)
                for style in styles {
                    lib.setStyle(TypeStyle(id: UUID(), name: style.name, ink: style.ink, paper: style.paper, heading: style.heading,
                                           body: style.body, headingFont: style.headingFont, bodyFont: style.bodyFont), in: new)
                }
                copy = new
            } else {
                let new = lib.createSwatch()
                _ = lib.renameSwatch(new, to: name)
                _ = lib.add(lib.hexes(inSwatch: id, by: .oldest), toSwatch: new)
                for hex in lib.hexes(inSwatch: id, by: .oldest) {
                    if let own = lib.swatch(id)?.entries.first(where: { $0.hex == hex })?.name { lib.setName(own, of: hex, in: new) }
                }
                if let tags = s.tags { lib.setTags(ofPalette: new, tags) }
                lib.move(new, to: project, index: Int.max)
                copy = new
            }
        }
        if let copy = copy { onShow?(.palette(copy), false) }
    }

    func delete(palette id: UUID) {
        guard let s = library.swatch(id) else { return }
        guard !s.entries.isEmpty else { apply("Delete Palette") { $0.deleteSwatch(id) }; return }
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Delete \u{201C}\(s.name)\u{201D}?"
        a.informativeText = "Its \(plural(s.entries.count, "swatch", "swatches")) will stay in your library."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        present(a) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.apply("Delete Palette") { $0.deleteSwatch(id) } }
        }
    }

    func add(_ hexes: [String], to id: UUID) {
        var added = 0
        apply("Add Colours") { added = $0.add(hexes, toSwatch: id) }
        let name = library.swatch(id)?.name ?? "palette"
        flash(added == 0 ? "Already in \(name)" : "Added \(plural(added, "swatch", "swatches")) to \(name)")
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
        flash("Made \(harmony.title) from \(hex)")
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
        guard let previous = store.loadPrevious() ?? Catalogues.standard.store(for: Catalogues.mainName).loadPrevious() else {
            flash("No MMFFDev Colour 2 library found")
            return
        }
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
            return [ExportPalette(name: "Tagged \(t)", colours: hexes.map { ExportColour(name: colourName($0), hex: $0) })]
        case .lab: return labPalette.map { [$0] } ?? []
        case .contrast: return contrastPalette.map { [$0] } ?? []
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
                let prompt = "MMFFDev Colour 3 wants to save \u{201C}\(file.lastPathComponent)\u{201D} in the \u{201C}\(folder.lastPathComponent)\u{201D} folder."
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
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Colors")
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
                NSWorkspace.shared.open(destination.folder)
                NSWorkspace.shared.activateFileViewerSelecting(files)
                flash("Not added \u{2014} drag \(what) into \u{201C}\(destination.folder.lastPathComponent)\u{201D} and Finder will ask for your password")
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
        guard requested != catalogue else { return }
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

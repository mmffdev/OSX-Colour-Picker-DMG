import AppKit

// ---------- A project's Overview page ----------
//
// Every project has an Information bucket at the top of its tree, and in it one page to begin
// with: Overview. It is part of the scaffold a project is made with, so it is there for every
// project, old or new. The page is the project's form: its name and its details, section by
// section, with the templates that fill them. A project is made by name alone and its details are
// filled in here, at any time, and kept with Save.

final class OverviewViewController: NSViewController {
    private let library: LibraryController
    private let header = PageHeader()
    private let host = NSView()
    /// The colour profile the project's palettes work to, unless one has its own.
    private let profile = NSPopUpButton(frame: .zero, pullsDown: false)
    private var form: ProjectFormController?
    private(set) var projectID: UUID?
    /// What the form on show was built from; a change to any of it builds the form afresh.
    private var built: Built?
    private struct Built: Equatable { let id: UUID; let name: String; let details: [String: String]; let locked: Bool }
    /// The actions a palette's page has, for the project as a whole; greyed where there is nothing yet for them to act on.
    private var newPalette: NSButton!, target: NSButton!, lock: NSButton!, copyAll: NSButton!, pack: NSButton!, file: NSButton!

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        profile.controlSize = .small
        profile.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        profile.target = self
        profile.action = #selector(profileChanged)
        newPalette = symbolButton("plus.rectangle.on.rectangle", tooltip: "New palette in this project", target: self, action: #selector(newPaletteTapped))
        target = symbolButton("eyedropper", tooltip: "Send picks here", target: self, action: #selector(targetTapped))
        lock = symbolButton("lock.open", tooltip: "Lock the project so nothing in it can change", target: self, action: #selector(lockTapped))
        copyAll = symbolButton("doc.on.doc", tooltip: "Copy every colour in this project", target: self, action: #selector(copyAllTapped))
        pack = symbolButton("square.and.arrow.up", tooltip: "Export a design pack of this project", target: self, action: #selector(packTapped))
        file = symbolButton("folder", tooltip: "Show the project's files in Finder", target: self, action: #selector(fileTapped))
        for b in [newPalette, target, lock, copyAll, pack, file] as [NSButton] { header.bar.addArrangedSubview(b) }
        header.bar.setCustomSpacing(12, after: pack)
        header.bar.addArrangedSubview(profile)
        for v in [header, host] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
            host.topAnchor.constraint(equalTo: header.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func fillProfiles(for project: Project) {
        let house = library.profile(forPalette: nil)
        profile.removeAllItems()
        profile.addItem(withTitle: "House Profile: " + house.profile.name)
        profile.menu?.addItem(.separator())
        for p in library.offeredProfiles {
            profile.addItem(withTitle: p.name)
            profile.lastItem?.representedObject = p.id.uuidString
            profile.lastItem?.toolTip = p.summary
        }
        let own = project.profile.flatMap { id in profile.itemArray.firstIndex { ($0.representedObject as? String) == id.uuidString } }
        profile.selectItem(at: own ?? 0)
        profile.isEnabled = !project.isLocked
        profile.toolTip = "The colour profile this project's palettes are proofed for: \(library.profile(forProject: project.id).profile.summary)"
    }

    @objc private func profileChanged() {
        guard let id = projectID else { return }
        let chosen = (profile.selectedItem?.representedObject as? String).flatMap(UUID.init(uuidString:))
        library.setProfile(chosen.flatMap { want in library.offeredProfiles.first { $0.id == want } }, ofProject: id)
    }

    @objc private func newPaletteTapped() { if let id = projectID { library.addPalette(to: id) } }
    @objc private func targetTapped() { if let id = projectID { library.togglePicks(to: id) } }
    @objc private func lockTapped() { if let id = projectID, let p = library.library.project(id) { library.setProjectLocked(id, !p.isLocked) } }
    @objc private func copyAllTapped() {
        guard let id = projectID else { return }
        var seen = Set<String>(), hexes: [String] = []
        for s in library.library.swatches where s.projectID == id { for h in library.hexes(in: s.id) where seen.insert(h).inserted { hexes.append(h) } }
        library.copy(hexes, from: library.library.project(id)?.name)
    }
    @objc private func packTapped() { if let id = projectID { library.exportDesignPack(project: id) } }
    @objc private func fileTapped() { if let id = projectID { library.showProjectFile(id) } }

    func show(_ id: UUID) {
        projectID = id
        reload()
    }

    func reload() {
        _ = view
        guard let id = projectID, let project = library.library.project(id) else { return }
        header.title.stringValue = "Overview"
        header.subtitle.stringValue = "Information"
        // A page of a project wears the project's marks: its name as a pill, stripes behind the title, its padlock.
        header.setProject(project.name) { [weak self] in self?.library.onRevealProject?(id) }
        header.striped = true
        header.lock = project.isLocked
        fillProfiles(for: project)
        // What each action has to work on: nothing to copy or pack until there is a colour; nothing new in a locked project.
        let palettes = library.library.swatches.filter { $0.projectID == id }
        let colours = palettes.flatMap { $0.entries.map { $0.hex } }
        let sending = library.picksGo(to: id)
        newPalette.isEnabled = !project.isLocked
        target.isEnabled = sending || palettes.contains { !$0.isTypography } || !project.isLocked
        target.image = symbol(sending ? "eyedropper.full" : "eyedropper", "Picks")
        target.toolTip = sending ? "Picks go here. Click to stop" : "Send picks here"
        lock.image = symbol(project.isLocked ? "lock.fill" : "lock.open", "Lock")
        lock.contentTintColor = project.isLocked ? .systemOrange : .secondaryLabelColor
        lock.toolTip = project.isLocked ? "Locked: nothing in the project can change. Click to unlock" : "Lock the project so nothing in it can change"
        copyAll.isEnabled = !colours.isEmpty
        pack.isEnabled = !palettes.isEmpty
        file.isEnabled = true

        // The form is left alone while what it shows is unchanged, so typing is not lost to an unrelated change.
        let now = Built(id: id, name: project.name, details: project.details ?? [:], locked: project.isLocked)
        guard now != built else { return }
        built = now
        if let old = form {
            old.templates.removeFromSuperview()
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let new = ProjectFormController(mode: .overview, name: now.name, values: now.details) { [weak self] name, details in
            guard let self = self else { return }
            // What is about to be saved is what the form already shows: no need to build it again.
            self.built = Built(id: id, name: name, details: details, locked: now.locked)
            self.library.saveProject(id, name: name, details: details)
        }
        new.locked = now.locked
        addChild(new)
        new.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(new.view)
        NSLayoutConstraint.activate([
            new.view.topAnchor.constraint(equalTo: host.topAnchor),
            new.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            new.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            new.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        header.bar.addArrangedSubview(new.templates)   // Fill from Template, on the action bar's right
        form = new
    }
}

import AppKit
import UniformTypeIdentifiers

// ---------- The setup assistant ----------
//
// Shown once, before the main window, on the first open after install, and again from the app
// menu whenever wanted. It settles the things that should never be buried in a settings pane:
//
//   1. welcome: the steps to come, and what macOS will ask, granted right there
//   2. where the app keeps its own data (Application Support is the seed; it can move)
//   3. a catalogue brought in from elsewhere, read through group by group as it comes in
//   4. the first catalogue: its name and where it lives
//   5. the schema: what a collection is called, and what one of its members is called
//   6. the first member, and where its files go
//   7. ready: everything once more; Create is the only point the catalogue is made
//   8. the halo trainer, then the app opens
//
// The window, the proof strip, the animation between steps and the draft are SetupFrame's, which
// every version of the app shares; the steps are this app's. A relaunch, which macOS asks for once
// Screen Recording is allowed, carries on from the draft at step 2.

final class SetupAssistant: NSWindowController, NSTextFieldDelegate {
    /// Called once the assistant has done its work, with the catalogue to open.
    private let completion: (String) -> Void
    private static var keep: SetupAssistant?

    static func show(completion: @escaping (String) -> Void) {
        let c = SetupAssistant(completion: completion)
        keep = c
        c.window?.center()
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: What the user has chosen

    private var home: URL = Catalogues.standard.root
    /// A catalogue brought in on the Bring In step, by the name it is now listed under.
    private var imported: String?
    private var useImported = true
    /// A catalogue already on this Mac, chosen to open instead of making one.
    private var existing: String?
    /// Catalogues already here, apart from an empty Main a fresh install starts with.
    private var alreadyHere: [String] {
        Catalogues.standard.names().filter { ($0 != Catalogues.mainName || Catalogues.holdsCatalogue(Catalogues.standard.root)) && $0 != imported }
    }
    private var catalogueName = ""
    /// Documents, unless this is a trial run (MMFFDEV_COLOUR3_HOME set), which keeps everything in its own home.
    private var catalogueParent = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_HOME"].map { URL(fileURLWithPath: $0) }
        ?? SetupAssistant.usualCatalogueParent
    /// Documents. The welcome step asks macOS for it up front, so its question never arrives out of nowhere.
    static var usualCatalogueParent: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents") }
    private var collectionName = SchemaTrial.collections[0].name
    private var memberName = SchemaTrial.memberName(of: SchemaTrial.collections[0])
    private var firstMember = ""
    /// Where the first member's folder goes; nil is the default under the catalogue.
    private var firstMemberParent: URL?
    /// The catalogue opened when the assistant closes: set at Create.
    private var created: String?
    private var trainer: HaloTrainer?

    // MARK: The steps

    private var step = 0
    static let steps = ["Welcome", "App Data", "Bring In", "Catalogue", "Schema", "First One", "Ready", "The Halo"]
    /// One line each, for the welcome page's list.
    static let reasons = ["", "Settings, colour profiles and the list of your catalogues.", "A catalogue from another Mac or an earlier version.",
                          "Its name, and the folder it lives in.", "Your word for a collection, and for one of its members.",
                          "Its name, and where its files go.", "Everything once more. The catalogue is made when you press Create.",
                          "The dial every colour, palette and project opens."]
    enum Step { static let welcome = 0, home = 1, bringIn = 2, catalogue = 3, schema = 4, firstOne = 5, ready = 6, halo = 7 }

    // MARK: The window

    private let setup = SetupFrame(steps: SetupAssistant.steps, ink: Brand.master)
    private var titleLabel: NSTextField { setup.titleLabel }
    private var body: NSStackView { setup.body }
    private var back: ThemedButton { setup.back }
    private var next: ThemedButton { setup.primary }
    private var skip: ThemedButton { setup.skip }

    private init(completion: @escaping (String) -> Void) {
        self.completion = completion
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: SetupFrame.size), styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "Set Up \(Brand.name)"
        win.isReleasedWhenClosed = false
        super.init(window: win)
        win.contentView = setup
        for b in [back, next, skip] { b.target = self }
        back.action = #selector(goBack)
        next.action = #selector(goOn)
        skip.action = #selector(skipStep)
        setup.strip.onPick = { [weak self] i in
            guard let self = self, self.step != Step.halo else { return }
            self.show(step: i)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged), name: .permissionsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        step = restoreDraft()
        show(step: step)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func show(step new: Int) {
        let direction = new == step ? 0 : (new > step ? 1 : -1)
        if step == Step.halo && new != Step.halo { trainer?.stop() }
        step = new
        setup.strip.set(step: new, animated: direction != 0)
        setup.go(direction: direction) {
            body.arrangedSubviews.forEach { $0.removeFromSuperview() }
            back.isHidden = step == Step.welcome || step == Step.halo
            skip.isHidden = true
            skip.title = "Skip"
            next.isEnabled = true
            next.title = "Continue"
            next.keyEquivalent = "\r"
            setup.hint.stringValue = Self.steps[step]
            switch step {
            case Step.welcome: welcomeStep()
            case Step.home: homeStep()
            case Step.bringIn: importStep()
            case Step.catalogue: catalogueStep()
            case Step.schema: schemaStep()
            case Step.firstOne: firstMemberStep()
            case Step.ready: readyStep()
            default: haloStep()
            }
        }
        saveDraft()
        // The step's name field, when it has one, is ready to type into.
        if let first = body.arrangedSubviews.first(where: { $0 is NSTextField && ($0 as! NSTextField).isEditable }) { window?.makeFirstResponder(first) }
    }

    @objc private func goBack() { if step > 0 && step != Step.halo { show(step: step - 1) } }
    @objc private func skipStep() {
        switch step {
        case Step.bringIn: imported = nil
        case Step.firstOne: firstMember = ""
        case Step.halo: finishAndOpen(); return
        default: break
        }
        show(step: step + 1)
    }
    @objc private func goOn() {
        switch step {
        case Step.welcome where ScreenAccess.restartNeeded:
            restartAndContinue(); return
        case Step.catalogue where chosenCatalogue == nil:
            catalogueName = nameField?.stringValue ?? catalogueName
            let name = catalogueName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { complain("Give the catalogue a name."); return }
            guard !Catalogues.holdsCatalogue(catalogueParent.appendingPathComponent(filesystemName(name))) else {
                complain("There is already a catalogue at \(place(catalogueParent.appendingPathComponent(filesystemName(name)))). Choose another name or folder."); return
            }
        case Step.schema:
            guard !collectionName.trimmingCharacters(in: .whitespaces).isEmpty, !memberName.trimmingCharacters(in: .whitespaces).isEmpty else {
                complain("Both names are needed."); return
            }
        case Step.firstOne:
            firstMember = memberField?.stringValue ?? firstMember
        case Step.ready:
            create(); return
        case Step.halo:
            finishAndOpen(); return
        default: break
        }
        show(step: step + 1)
    }

    private func complain(_ text: String) {
        guard let w = window else { return }
        let a = NSAlert()
        a.messageText = text
        a.beginSheetModal(for: w)
    }

    // MARK: The draft, kept across a relaunch

    private struct Draft: Codable {
        var step: Int
        var home: URL
        var imported: String?
        var useImported: Bool
        var existing: String?
        var catalogueName: String
        var catalogueParent: URL
        var collectionName: String
        var memberName: String
        var firstMember: String
        var firstMemberParent: URL?
    }
    static let draftKey = "setupDraft"

    private func saveDraft(at s: Int? = nil) {
        guard created == nil else { return }
        SetupDraft.save(Draft(step: s ?? step, home: home, imported: imported, useImported: useImported, existing: existing,
                              catalogueName: catalogueName, catalogueParent: catalogueParent, collectionName: collectionName,
                              memberName: memberName, firstMember: firstMember, firstMemberParent: firstMemberParent), key: Self.draftKey)
    }

    /// Takes up a draft left by a relaunch; returns the step to open on.
    private func restoreDraft() -> Int {
        guard let d = SetupDraft.load(Draft.self, key: Self.draftKey) else { return Step.welcome }
        home = d.home
        imported = d.imported.flatMap { Catalogues.standard.names().contains($0) ? $0 : nil }
        useImported = d.useImported
        existing = d.existing
        catalogueName = d.catalogueName
        catalogueParent = d.catalogueParent
        collectionName = d.collectionName
        memberName = d.memberName
        firstMember = d.firstMember
        firstMemberParent = d.firstMemberParent
        return max(Step.welcome, min(d.step, Step.ready))
    }

    /// Screen Recording was allowed: macOS applies it only to a fresh copy, so start one, at step 2.
    private func restartAndContinue() {
        saveDraft(at: Step.home)
        Relaunch.now()
    }

    // MARK: Pieces every step is built from

    private func story(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = NSFont.systemFont(ofSize: TextSize.body)
        l.preferredMaxLayoutWidth = 584
        return l
    }

    private func place(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    /// A caption, the path it names in full, and a button to change it.
    private func pathRow(_ label: String, _ url: URL, change: Selector) -> (row: NSView, path: NSTextField) {
        let cap = caption(label)
        let path = NSTextField(wrappingLabelWithString: place(url))
        path.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        path.preferredMaxLayoutWidth = 440
        let button = NSButton(title: "Change\u{2026}", target: self, action: change)
        button.bezelStyle = .rounded
        let text = NSStackView(views: [cap, path])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [text, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .top
        row.widthAnchor.constraint(equalToConstant: 584).isActive = true
        return (row, path)
    }

    private func field(_ placeholder: String, _ value: String, action: Selector) -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.font = NSFont.systemFont(ofSize: TextSize.body)
        f.target = self
        f.action = action
        f.delegate = self
        f.widthAnchor.constraint(equalToConstant: 320).isActive = true
        return f
    }

    /// The path under a name field follows it as it is typed.
    func controlTextDidChange(_ note: Notification) {
        guard let f = note.object as? NSTextField, let action = f.action else { return }
        NSApp.sendAction(action, to: self, from: f)
    }

    private func chooseFolder(_ message: String, start: URL?, done: @escaping (URL) -> Void) {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = start
        panel.prompt = "Use This Folder"
        panel.message = message
        panel.beginSheetModal(for: w) { r in if r == .OK, let u = panel.url { done(u) } }
    }

    // MARK: 1. Where the app's data lives

    private var homePath: NSTextField?

    private func homeStep() {
        titleLabel.stringValue = "Where The App Keeps Its Data"
        body.addArrangedSubview(story("Its settings, colour profiles and the list of your catalogues. It starts in Application Support, which is fine for most people. Choose a folder of your own and everything there moves to it, catalogues included."))
        let (row, path) = pathRow("App data", home, change: #selector(changeHome))
        homePath = path
        body.addArrangedSubview(row)
    }

    @objc private func changeHome() {
        chooseFolder("Choose an empty folder, or make a new one, for the app's data", start: home.deletingLastPathComponent()) { [weak self] u in
            self?.home = u
            self?.homePath?.stringValue = self?.place(u) ?? ""
        }
    }

    // MARK: 2. Bring in a catalogue

    private var loader: OnboardingView?

    private func importStep() {
        titleLabel.stringValue = "Bring In A Catalogue"
        skip.isHidden = false
        next.isEnabled = imported != nil
        body.addArrangedSubview(story("Already have a catalogue, from another Mac or an earlier version? Choose its .colcatalogue file and it is opened where it is, nothing copied. A library.json from an export or a backup is brought in as a new catalogue."))
        let choose = NSButton(title: "Choose Catalogue File\u{2026}", target: self, action: #selector(chooseCatalogue))
        choose.bezelStyle = .rounded
        choose.controlSize = .large
        body.addArrangedSubview(choose)
        let view = OnboardingView(memberWord: memberName)
        loader = view
        body.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: 584).isActive = true
        if let name = imported { view.finished(summaryFor: name) }
    }

    @objc private func chooseCatalogue() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: ColourFiles.catalogue) ?? .data, .json]
        panel.prompt = "Bring In"
        panel.beginSheetModal(for: w) { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            do {
                let name = url.pathExtension.lowercased() == ColourFiles.catalogue
                    ? try Catalogues.standard.adopt(url) : try Catalogues.standard.importFile(url)
                self.imported = name
                self.next.isEnabled = false
                self.loader?.load(catalogue: name, over: w) { [weak self] in self?.next.isEnabled = true }
            } catch { self.complain(error.localizedDescription) }
        }
    }

    private func summaryFor(_ name: String) -> String { "\u{201C}\(name)\u{201D} is ready." }

    // MARK: 3. The first catalogue

    private var cataloguePath: NSTextField?
    private var nameField: NSTextField?

    private func catalogueStep() {
        let here = alreadyHere
        titleLabel.stringValue = imported == nil && here.isEmpty ? "Your First Catalogue" : "Which Catalogue To Open"
        if imported == nil && existing == nil, let first = here.first { existing = Catalogues.currentName.isEmpty ? first : Catalogues.currentName; useImported = true }
        if imported != nil || !here.isEmpty {
            body.addArrangedSubview(story("Open a catalogue you already have, or make a new one. A catalogue is one body of work: its members, their palettes, typography and tags, as plain files in a folder you choose."))
            if let name = imported {
                let use = NSButton(radioButtonWithTitle: "Open \u{201C}\(name)\u{201D}, just brought in", target: self, action: #selector(pickUseImported))
                use.state = useImported && existing == nil ? .on : .off
                body.addArrangedSubview(use)
            }
            if !here.isEmpty {
                let open = NSButton(radioButtonWithTitle: "Open one already on this Mac:", target: self, action: #selector(pickExisting))
                open.state = useImported && (existing != nil || imported == nil) ? .on : .off
                let popup = NSPopUpButton()
                popup.addItems(withTitles: here)
                popup.selectItem(withTitle: existing ?? here[0])
                popup.target = self
                popup.action = #selector(existingChosen)
                let row = NSStackView(views: [open, popup])
                row.orientation = .horizontal
                row.spacing = 8
                body.addArrangedSubview(row)
            }
            let make = NSButton(radioButtonWithTitle: "Make a new catalogue", target: self, action: #selector(pickMakeNew))
            make.state = useImported ? .off : .on
            body.addArrangedSubview(make)
        } else {
            useImported = false
            body.addArrangedSubview(story("A catalogue is one body of work: its members, their palettes, typography and tags. It is a folder you choose, named for the catalogue, and everything in it is plain files you can open and move."))
        }
        let name = field("Catalogue name", catalogueName, action: #selector(nameTyped))
        nameField = name
        let (row, path) = pathRow("Kept in", catalogueParent.appendingPathComponent(filesystemName(catalogueName.isEmpty ? "Catalogue Name" : catalogueName)), change: #selector(changeCatalogueParent))
        cataloguePath = path
        body.addArrangedSubview(name)
        body.addArrangedSubview(row)
        name.isEnabled = chosenCatalogue == nil
        row.alphaValue = chosenCatalogue == nil ? 1 : 0.4
    }

    @objc private func pickUseImported() { useImported = true; existing = nil; show(step: Step.catalogue) }
    @objc private func pickExisting() { useImported = true; existing = existing ?? alreadyHere.first; show(step: Step.catalogue) }
    @objc private func existingChosen(_ p: NSPopUpButton) { existing = p.titleOfSelectedItem; useImported = true; show(step: Step.catalogue) }
    @objc private func pickMakeNew() { useImported = false; show(step: Step.catalogue) }
    @objc private func nameTyped(_ f: NSTextField) {
        catalogueName = f.stringValue
        cataloguePath?.stringValue = place(catalogueParent.appendingPathComponent(filesystemName(catalogueName.isEmpty ? "Catalogue Name" : catalogueName)))
    }
    @objc private func changeCatalogueParent() {
        catalogueName = nameField?.stringValue ?? catalogueName
        chooseFolder("Choose the folder the catalogue's own folder goes in", start: catalogueParent) { [weak self] u in
            guard let self = self else { return }
            self.catalogueParent = u
            self.cataloguePath?.stringValue = self.place(u.appendingPathComponent(filesystemName(self.catalogueName.isEmpty ? "Catalogue Name" : self.catalogueName)))
        }
    }

    // MARK: 4. The schema

    private func schemaStep() {
        titleLabel.stringValue = "What You Call Things"
        catalogueName = nameField?.stringValue ?? catalogueName
        body.addArrangedSubview(story("The catalogue lists its members under a heading. Call the heading what you call that body of work, and a member what one of them is. Every member holds Information, Palettes, Typography and Tags; the whole map can be shaped later in Settings \u{25B8} Schema."))
        let collection = combo("Projects", collectionName, SchemaTrial.collectionNames, action: #selector(collectionTyped))
        let member = combo("Project", memberName, SchemaTrial.primaryNames, action: #selector(memberTyped))
        let grid = NSGridView(views: [[caption("The heading"), collection], [caption("One member"), member]])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.setContentHuggingPriority(.required, for: .horizontal)
        body.addArrangedSubview(grid)
    }

    private func combo(_ placeholder: String, _ value: String, _ names: [String], action: Selector) -> NSComboBox {
        let c = NSComboBox()
        c.addItems(withObjectValues: names)
        c.stringValue = value
        c.placeholderString = placeholder
        c.font = NSFont.systemFont(ofSize: TextSize.body)
        c.target = self
        c.action = action
        c.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return c
    }
    @objc private func collectionTyped(_ c: NSComboBox) { collectionName = c.stringValue }
    @objc private func memberTyped(_ c: NSComboBox) { memberName = c.stringValue }

    // MARK: 5. The first member

    private var memberPath: NSTextField?
    private var memberField: NSTextField?

    /// Where the catalogue being set up will be.
    /// The catalogue to open: one already here, one brought in, or nil for the one being made.
    private var chosenCatalogue: String? { useImported ? (existing ?? imported) : nil }

    private var catalogueFolder: URL {
        if let name = chosenCatalogue { return Catalogues.standard.directory(for: name) }
        return catalogueParent.appendingPathComponent(filesystemName(catalogueName))
    }

    private func memberFolder() -> URL {
        let name = filesystemName(firstMember.isEmpty ? "\(memberName) Name" : firstMember)
        return (firstMemberParent ?? catalogueFolder.appendingPathComponent(filesystemName(collectionName))).appendingPathComponent(name)
    }

    private func firstMemberStep() {
        titleLabel.stringValue = "Your First \(memberName)"
        skip.isHidden = false
        skip.title = "Skip For Now"
        body.addArrangedSubview(story("A \(memberName.lowercased()) is a folder of its own holding everything in it, so it can be handed over or moved as one. It goes under the catalogue unless you put it somewhere else, such as a client's own drive."))
        let name = field("\(memberName) name", firstMember, action: #selector(memberNameTyped))
        memberField = name
        let (row, path) = pathRow("Kept in", memberFolder(), change: #selector(changeMemberParent))
        memberPath = path
        body.addArrangedSubview(name)
        body.addArrangedSubview(row)
    }

    @objc private func memberNameTyped(_ f: NSTextField) { firstMember = f.stringValue; memberPath?.stringValue = place(memberFolder()) }
    @objc private func changeMemberParent() {
        firstMember = memberField?.stringValue ?? firstMember
        chooseFolder("Choose the folder the \(memberName.lowercased())'s own folder goes in", start: firstMemberParent ?? catalogueFolder) { [weak self] u in
            self?.firstMemberParent = u
            self?.memberPath?.stringValue = self?.place(self?.memberFolder() ?? u) ?? ""
        }
    }

    // MARK: 0. Welcome

    private func welcomeStep() {
        titleLabel.stringValue = "Set Up \(Brand.name)"
        body.addArrangedSubview(story("Seven short steps after this one. You choose where your data lives, bring in anything you already have and name your first catalogue, which is only made when you press Create on the Ready step. The last step teaches you the halo."))

        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 7
        for (i, name) in Self.steps.enumerated().dropFirst() {
            let n = NSTextField(labelWithString: String(format: "%02d", i + 1))
            n.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
            n.textColor = .secondaryLabelColor
            n.widthAnchor.constraint(equalToConstant: 20).isActive = true
            let title = NSTextField(labelWithString: name)
            title.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
            let why = NSTextField(wrappingLabelWithString: Self.reasons[i])
            why.font = NSFont.systemFont(ofSize: TextSize.caption)
            why.textColor = .secondaryLabelColor
            why.preferredMaxLayoutWidth = 206
            let words = NSStackView(views: [title, why])
            words.orientation = .vertical
            words.alignment = .leading
            words.spacing = 1
            let row = NSStackView(views: [n, words])
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8
            list.addArrangedSubview(row)
        }
        let left = NSStackView(views: [caption("The Steps"), list])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10
        left.widthAnchor.constraint(equalToConstant: 236).isActive = true

        let perms = PermissionsView(textWidth: 300, spacing: 16) { [weak self] e in self?.complain(e.localizedDescription) }
        let note = NSTextField(wrappingLabelWithString: "Each is optional. Settings \u{25B8} Permissions has the same switches later.")
        note.font = NSFont.systemFont(ofSize: TextSize.caption)
        note.textColor = .secondaryLabelColor
        let right = NSStackView(views: [caption("What macOS Will Ask"), perms, note])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 10
        right.setCustomSpacing(16, after: perms)

        let cols = NSStackView(views: [left, right])
        cols.orientation = .horizontal
        cols.alignment = .top
        cols.spacing = 28
        cols.identifier = SetupFrame.cascade
        body.addArrangedSubview(cols)
        updateWelcomeButtons()
    }

    /// Screen Recording allowed while this copy runs: the way on is a restart, or on without it.
    private func updateWelcomeButtons() {
        let restart = ScreenAccess.restartNeeded
        next.title = restart ? "Restart And Continue" : "Begin Setup"
        skip.isHidden = !restart
        skip.title = "Continue Without Restarting"
        setup.hint.stringValue = restart ? "\(Brand.name) reopens here, at step 2" : Self.steps[Step.welcome]
    }

    @objc private func permissionsChanged() { if step == Step.welcome { updateWelcomeButtons() } }

    // MARK: 6. Ready

    private func readyStep() {
        firstMember = memberField?.stringValue ?? firstMember
        titleLabel.stringValue = "Ready To Create"
        next.title = chosenCatalogue == nil ? "Create And Continue" : "Open And Continue"
        setup.hint.stringValue = chosenCatalogue == nil ? "Makes the catalogue, then teaches the halo" : "Opens the catalogue, then teaches the halo"
        var lines = ["App data: \(place(home))"]
        if let name = chosenCatalogue { lines.append("Catalogue: \u{201C}\(name)\u{201D}, where it is") }
        else { lines.append("Catalogue: \u{201C}\(catalogueName)\u{201D} in \(place(catalogueFolder))") }
        lines.append("Heading: \(collectionName) \u{00B7} One member: \(memberName)")
        if !firstMember.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("First \(memberName.lowercased()): \u{201C}\(firstMember)\u{201D} in \(place(memberFolder()))") }
        let allowed = Permission.all.filter { $0.state() == .on }.map { $0.title }
        lines.append("Allowed: " + (allowed.isEmpty ? "nothing yet. Settings \u{25B8} Permissions has every switch." : allowed.joined(separator: ", ")))
        lines.append("All of this can be changed later in Settings.")
        for line in lines { body.addArrangedSubview(story(line)) }
    }

    /// Everything the steps decided, done in order: the home first, so the catalogue lands in the
    /// right place. The only point the assistant writes anything of its own.
    private func create() {
        do {
            if home != Catalogues.standard.root { try Catalogues.moveHome(to: home) }
            let name: String
            if let have = chosenCatalogue {
                name = have
            } else {
                name = try Catalogues.standard.create(catalogueName, under: catalogueParent)
            }
            Catalogues.currentName = name
            SchemaTrial.changeCollection(SchemaTrial.collections[0].id) { c in
                c.name = collectionName.trimmingCharacters(in: .whitespaces)
                c.stack.name = memberName.trimmingCharacters(in: .whitespaces)
            }
            let member = firstMember.trimmingCharacters(in: .whitespacesAndNewlines)
            if !member.isEmpty {
                let store = Catalogues.standard.store(for: name)
                let folder = memberFolder()
                try store.mutate { lib in
                    let id = lib.createProject(named: member)
                    lib.setProjectFolder(id, ProjectFiles.keep(folder, beside: store.url))
                }
            }
            Prefs.assistantDone = true
            Prefs.setupDone = true      // the permissions were offered on the welcome page
            SetupDraft.clear(key: Self.draftKey)
            created = name
            show(step: Step.halo)
        } catch {
            complain(error.localizedDescription)
        }
    }

    // MARK: 7. The halo

    private func haloStep() {
        titleLabel.stringValue = "Meet The Halo"
        body.addArrangedSubview(story("Every colour, palette and project opens a halo: a dial of what you can do with it. Four quick moves and you know it. Nothing here touches your catalogue."))
        let t = trainer ?? HaloTrainer(colour: Brand.master, name: Brand.masterName, hex: Brand.masterHex)
        trainer = t
        t.onChange = { [weak self] in self?.updateHaloButtons() }
        body.addArrangedSubview(t)
        next.title = "Open \(Brand.name)"
        updateHaloButtons()
    }

    private func updateHaloButtons() {
        guard let t = trainer else { return }
        let p = HaloTrainer.progress(t.learned)
        skip.isHidden = t.allLearned
        // Return chooses on the halo while it is being learned, so it must not also close the setup.
        next.keyEquivalent = t.allLearned ? "\r" : ""
        skip.title = "Skip"
        setup.hint.stringValue = t.allLearned ? "You know the halo" : "\(p.done) of \(p.of) learned"
    }

    private func finishAndOpen() {
        trainer?.stop()
        Self.keep = nil
        window?.close()
        completion(created ?? Catalogues.currentName)
    }
}

// MARK: - Reading a catalogue in, as it happens

/// Two lines that follow a catalogue being read: the group being fetched, and the file inside it,
/// at the speed it really happens. Anything that cannot be found is listed under them, each with
/// Find and Skip, and the whole ends in one line that stays.
final class OnboardingView: NSView {
    private let group = NSTextField(labelWithString: "")
    private let item = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let misses = NSStackView()
    private let memberWord: String
    private var missesHeight: NSLayoutConstraint?
    private lazy var skipAll = NSButton(title: "Skip All", target: self, action: #selector(skipAllTapped))

    /// A member whose files were not where the catalogue says.
    private struct Miss { let ref: ProjectRef; let expected: URL }

    init(memberWord: String) {
        self.memberWord = memberWord
        super.init(frame: .zero)
        group.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        item.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        item.textColor = .secondaryLabelColor
        item.lineBreakMode = .byTruncatingMiddle
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        summary.font = NSFont.systemFont(ofSize: TextSize.body)
        summary.preferredMaxLayoutWidth = 584
        misses.orientation = .vertical
        misses.alignment = .leading
        misses.spacing = 6
        misses.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.documentView = misses
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.heightAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
        missesHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
        missesHeight?.isActive = true
        misses.widthAnchor.constraint(equalTo: scroll.widthAnchor).isActive = true
        skipAll.bezelStyle = .rounded
        skipAll.controlSize = .small
        skipAll.isHidden = true
        let column = NSStackView(views: [group, item, bar, scroll, skipAll, summary])
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.setCustomSpacing(12, after: bar)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.widthAnchor.constraint(equalTo: column.widthAnchor), item.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    private var index: URL?
    private weak var host: NSWindow?
    private var done: (() -> Void)?
    private var found = (members: 0, palettes: 0, typography: 0, tags: 0, missing: 0)

    func finished(summaryFor text: String) {
        isHidden = false
        group.stringValue = ""
        item.stringValue = ""
        bar.isHidden = true
        summary.stringValue = text
    }

    /// Reads the catalogue member by member, off the main thread, telling the lines what it is on.
    func load(catalogue name: String, over host: NSWindow, done: @escaping () -> Void) {
        let dir = Catalogues.standard.directory(for: name)
        guard let index = CatalogueFiles.index(in: dir) else { finished(summaryFor: "\u{201C}\(name)\u{201D} is from an earlier version and will be read when it opens."); done(); return }
        self.index = index
        self.host = host
        self.done = done
        isHidden = false
        bar.isHidden = false
        bar.doubleValue = 0
        summary.stringValue = ""
        misses.arrangedSubviews.forEach { $0.removeFromSuperview() }
        found = (0, 0, 0, 0, 0)
        let master = ProjectFiles.folder, word = memberWord
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let doc = (try? Data(contentsOf: index)).flatMap { try? ColourFiles.decoder().decode(CatalogueDocument.self, from: $0) }
            let refs = doc?.projects ?? []
            var missing: [Miss] = []
            var tally = (members: 0, palettes: 0, typography: 0, tags: 0)
            for (at, ref) in refs.enumerated() {
                let stub = Project(id: ref.id, name: ref.name, createdAt: ref.createdAt, folder: ref.folder, fileKnown: true)
                let root = ProjectFiles.root(for: stub, library: index, master: master)
                self?.say(group: "Fetching \(word) \(at + 1) of \(refs.count): \(ref.name)", item: "", progress: Double(at) / Double(max(refs.count, 1)))
                guard let file = ProjectFiles.existingFile(in: root, name: ref.name), let whole = try? ProjectFiles.read(file) else {
                    missing.append(Miss(ref: ref, expected: ProjectFiles.configURL(in: root, name: ref.name)))
                    self?.say(group: nil, item: "Not found: \(ProjectFiles.configURL(in: root, name: ref.name).lastPathComponent)", progress: nil)
                    continue
                }
                tally.members += 1
                tally.tags += whole.tags.count
                for (n, palette) in whole.palettes.enumerated() {
                    if palette.isTypography { tally.typography += 1 } else { tally.palettes += 1 }
                    let pct = Int((Double(n + 1) / Double(whole.palettes.count)) * 100)
                    self?.say(group: nil, item: "Fetching \(palette.isTypography ? "Typography" : "Palette") \(palette.name)   \(pct)%", progress: nil)
                }
            }
            let unfiled = CatalogueFiles.unfiledFolder(beside: index).appendingPathComponent(ProjectFiles.palettesFolder)
            let loose = ((try? FileManager.default.contentsOfDirectory(atPath: unfiled.path)) ?? []).filter { !$0.hasPrefix(".") }
            self?.say(group: "Fetching Unfiled", item: "\(loose.count) files", progress: 1)
            DispatchQueue.main.async { self?.complete(tally: tally, missing: missing) }
        }
    }

    private func say(group: String?, item: String?, progress: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let g = group { self.group.stringValue = g }
            if let i = item { self.item.stringValue = i }
            if let p = progress { self.bar.doubleValue = p }
        }
    }

    private func complete(tally: (members: Int, palettes: Int, typography: Int, tags: Int), missing: [Miss]) {
        found = (tally.members, tally.palettes, tally.typography, tally.tags, missing.count)
        for miss in missing { misses.addArrangedSubview(row(for: miss)) }
        settle()
    }

    /// The list of misses takes the room it needs, up to a scrolling height, and none when it is empty.
    private func fitMisses() {
        let rows = misses.arrangedSubviews.count
        missesHeight?.constant = rows == 0 ? 0 : min(CGFloat(rows) * 42, 180)
        skipAll.isHidden = rows < 2
        // The first miss at the top, not the last: the stack is not flipped, so the top is the far end.
        misses.layoutSubtreeIfNeeded()
        if let scroll = misses.enclosingScrollView { scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, misses.frame.height - scroll.contentView.bounds.height))) }
    }

    @objc private func skipAllTapped() {
        for miss in Array(pending.values) where rows[miss.ref.id] != nil { resolved(miss, foundIt: false) }
    }

    /// The line that stays, and the way out once nothing is left to find.
    private func settle() {
        fitMisses()
        let plural = SchemaTrial.plural(memberWord)
        var parts = ["Found \(found.members) \(found.members == 1 ? memberWord : plural)", "\(found.palettes) palettes", "\(found.typography) typography sets", "\(found.tags) tags"]
        if found.missing > 0 { parts.append("\(found.missing) to find") }
        group.stringValue = "Done"
        item.stringValue = ""
        bar.doubleValue = 1
        summary.stringValue = parts.joined(separator: " \u{00B7} ")
        if found.missing == 0 { done?(); done = nil }
    }

    private func row(for miss: Miss) -> NSView {
        let name = NSTextField(labelWithString: miss.ref.name)
        name.font = NSFont.systemFont(ofSize: TextSize.body)
        let where_ = NSTextField(labelWithString: (miss.expected.path as NSString).abbreviatingWithTildeInPath)
        where_.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
        where_.textColor = .secondaryLabelColor
        where_.lineBreakMode = .byTruncatingMiddle
        let find = NSButton(title: "Find\u{2026}", target: self, action: #selector(findTapped))
        let skip = NSButton(title: "Skip", target: self, action: #selector(skipTapped))
        for b in [find, skip] { b.bezelStyle = .rounded; b.controlSize = .small }
        let text = NSStackView(views: [name, where_])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [text, NSView(), find, skip])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: 584 - 20).isActive = true   // room for the scroller
        where_.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
        pending[ObjectIdentifier(find)] = miss
        pending[ObjectIdentifier(skip)] = miss
        rows[miss.ref.id] = row
        return row
    }
    private var pending: [ObjectIdentifier: Miss] = [:]
    private var rows: [UUID: NSView] = [:]

    private func resolved(_ miss: Miss, foundIt: Bool) {
        rows[miss.ref.id]?.removeFromSuperview()
        rows[miss.ref.id] = nil
        found.missing -= 1
        if foundIt { found.members += 1 }
        settle()
    }

    @objc private func skipTapped(_ b: NSButton) { if let miss = pending[ObjectIdentifier(b)] { resolved(miss, foundIt: false) } }

    /// Points the catalogue at the member where it is now: the index is rewritten with the folder, nothing else touched.
    @objc private func findTapped(_ b: NSButton) {
        guard let miss = pending[ObjectIdentifier(b)], let host = host, let index = index else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [ColourFiles.project, ColourFiles.earlierProject, ColourFiles.legacyProject].map { UTType(filenameExtension: $0) ?? .data }
        panel.prompt = "Use This"
        panel.message = "Find \u{201C}\(miss.ref.name)\u{201D}: its .\(ColourFiles.project) file, or the folder holding it"
        panel.beginSheetModal(for: host) { [weak self] r in
            guard let self = self, r == .OK, let url = panel.url else { return }
            let stub = Project(id: miss.ref.id, name: miss.ref.name, createdAt: miss.ref.createdAt, folder: miss.ref.folder, fileKnown: true)
            guard let root = try? ProjectFiles.adopt(url, for: stub),
                  var doc = (try? Data(contentsOf: index)).flatMap({ try? ColourFiles.decoder().decode(CatalogueDocument.self, from: $0) }),
                  let at = doc.projects.firstIndex(where: { $0.id == miss.ref.id }) else { return }
            doc.projects[at].folder = ProjectFiles.keep(root, beside: index)
            if let data = try? ColourFiles.encoder().encode(doc) { try? data.write(to: index, options: .atomic) }
            self.resolved(miss, foundIt: true)
        }
    }
}

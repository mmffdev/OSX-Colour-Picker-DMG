import AppKit
#if DEBUG
import SwiftUI
#endif
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

    /// The setup's frame at one step, for Xcode's canvas: open this file, show the canvas
    /// (Editor ▸ Canvas), and every edit renders there without relaunching the app.
    static func preview(step: Int) -> NSView {
        let c = SetupAssistant(completion: { _ in })
        keep = c
        c.show(step: max(0, min(step - 1, Step.halo)))
        return c.window!.contentView!
    }

    static func show(completion: @escaping (String) -> Void) {
        let c = SetupAssistant(completion: completion)
        keep = c
        c.window?.center()
        c.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The assistant opened part way in: at the Catalogue step when the app finds no catalogue to work in.
    static func show(from step: Int, completion: @escaping (String) -> Void) {
        let c = SetupAssistant(completion: completion)
        keep = c
        if c.catalogueName.isEmpty { c.catalogueName = "Studio" }
        c.show(step: step)
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
    /// Documents, which the welcome step asks macOS for up front; under the sandbox (the Store build) the app's own Catalogues folder, since Documents is out of reach until chosen.
    static var usualCatalogueParent: URL {
        #if APPSTORE
        return Catalogues.standard.folder
        #else
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        #endif
    }
    private var collectionName = (SchemaTrial.collections.first ?? SchemaTrial.SchemaFile.fresh.collections[0]).name
    private var memberName = SchemaTrial.memberName(of: SchemaTrial.collections.first ?? SchemaTrial.SchemaFile.fresh.collections[0])
    private var firstMember = ""
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

    private let setup = SetupFrame(steps: SetupAssistant.steps)
    private var body: NSStackView { setup.body }
    /// The width the words column gives a step's pieces.
    private var width: CGFloat { setup.wide ? Design.Wizard.span(1, 12) : Design.Wizard.span(7, 12) }
    private var back: SwissButton { setup.back }
    private var next: SwissButton { setup.primary }
    private var skip: SwissButton { setup.skip }

    private init(completion: @escaping (String) -> Void) {
        self.completion = completion
        let win = SetupWindow(contentRect: NSRect(origin: .zero, size: Design.Wizard.size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.title = "Set Up \(Brand.edition)"
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        super.init(window: win)
        win.contentView = setup
        for b in [back, next, skip, setup.skipSetup] { b.target = self }
        back.action = #selector(goBack)
        next.action = #selector(goOn)
        skip.action = #selector(skipStep)
        setup.skipSetup.action = #selector(skipSetup)
        setup.cards.onPick = { [weak self] i in
            guard let self = self, self.step != Step.halo else { return }
            self.show(step: i)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged), name: .permissionsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        step = restoreDraft()
        show(step: step)
        DispatchQueue.main.async { [weak self] in self?.setup.cards.enter() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func show(step new: Int) {
        let direction = new == step ? 0 : (new > step ? 1 : -1)
        if step == Step.halo && new != Step.halo { trainer?.stop() }
        step = new
        setup.setStep(new, of: Self.steps.count, animated: direction != 0)
        setup.go(direction: direction) {
            body.arrangedSubviews.forEach { $0.removeFromSuperview() }
            setup.aside.arrangedSubviews.forEach { $0.removeFromSuperview() }
            setup.wide = false
            setup.slim = step == Step.halo
            setup.skipSetup.isHidden = step == Step.ready || step == Step.halo
            back.isHidden = step == Step.welcome || step == Step.halo
            skip.isHidden = true
            skip.title = "Skip"
            next.isEnabled = true
            next.title = "Continue"
            next.keyEquivalent = "\r"
            hint("")
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
    /// Skip Setup: straight to Ready with the defaults, so the app can be made and opened.
    @objc private func skipSetup() { if step < Step.ready { show(step: Step.ready) } }
    private func hint(_ s: String) { setup.hint.attributedStringValue = Design.attributed(s, .caption, colour: Design.quiet) }
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
        Diagnostics.log("setup step \(step + 1)", text)
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
    }
    static let draftKey = "setupDraft"

    private func saveDraft(at s: Int? = nil) {
        guard created == nil else { return }
        SetupDraft.save(Draft(step: s ?? step, home: home, imported: imported, useImported: useImported, existing: existing,
                              catalogueName: catalogueName, catalogueParent: catalogueParent, collectionName: collectionName,
                              memberName: memberName, firstMember: firstMember), key: Self.draftKey)
    }

    /// Takes up a draft left by a relaunch; returns the step to open on. "--step 3" on the command
    /// line opens on that step with the defaults, for looking at one screen without clicking through.
    private func restoreDraft() -> Int {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--step"), args.indices.contains(i + 1), let n = Int(args[i + 1]) {
            if catalogueName.isEmpty { catalogueName = "Studio" }
            if n - 1 >= Step.halo { created = Catalogues.currentName }
            return max(Step.welcome, min(n - 1, Step.halo))
        }
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
        return max(Step.welcome, min(d.step, Step.ready))
    }

    /// Screen Recording was allowed: macOS applies it only to a fresh copy, so start one, at step 2.
    private func restartAndContinue() {
        saveDraft(at: Step.home)
        Relaunch.now()
    }

    // MARK: Pieces every step is built from

    /// The first words of a step, in the Lead style.
    private func lead(_ text: String) -> NSTextField { SetupFrame.lead(text, width: width) }
    /// A paragraph in the Body style.
    private func story(_ text: String) -> NSTextField { SetupFrame.body(text, width: width) }

    private func place(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    /// A caption, the path it names, and Change on the same baseline: the design's field. Its rule
    /// above goes when it follows a field, whose own underline is the rule between them.
    private func pathRow(_ label: String, _ url: URL, change: Selector, afterField: Bool = false) -> (row: NSView, path: NSTextField) {
        let (row, value) = SetupFrame.field(label, place(url), action: "Change", target: self, selector: change, width: width, rule: !afterField)
        return (row, value)
    }

    private func field(_ placeholder: String, _ value: String, action: Selector) -> NSTextField {
        let (row, f) = SetupFrame.entry(placeholder, value, placeholder: placeholder, width: min(320, width), target: self, action: action)
        f.delegate = self
        body.addArrangedSubview(row)
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
        panel.beginSheetModal(for: w) { r in if r == .OK, let u = panel.url { FolderAccess.remember(u); done(u) } }
    }

    // MARK: 1. Where the app's data lives

    private var homePath: NSTextField?

    private func homeStep() {
        setup.title("Where Your Data", "Lives")
        body.addArrangedSubview(lead("Settings, colour profiles and the list of your catalogues. Application Support suits most people."))
        body.addArrangedSubview(story("Choose a folder of your own and everything moves to it, catalogues included."))
        let (row, path) = pathRow("App Data Folder", home, change: #selector(changeHome))
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

    private var broughtIn: ChoiceRow?

    private func importStep() {
        setup.title("Bring In", "A Catalogue")
        next.isEnabled = imported != nil
        body.addArrangedSubview(lead("Already have a catalogue, from another Mac or an earlier version? Open it where it is. Or start fresh."))
        let have = ChoiceRow("I Have A Catalogue",
                             imported.map { "\u{201C}\($0)\u{201D} is in. Continue to open it." }
                                ?? "Choose its .colcatalogue file and it is opened where it is, nothing copied. A library.json from an export or a backup comes in as a new catalogue.",
                             button: SwissButton("Choose File\u{2026}", .secondary, target: self, action: #selector(chooseCatalogue)), width: width)
        have.button.trailing = imported == nil ? .none : .tick
        broughtIn = have
        let fresh = ChoiceRow("Start Fresh", "Make a new catalogue on the next step. Anything you have can still be brought in later, from the File menu.",
                              button: SwissButton("Start Fresh", .secondary, target: self, action: #selector(skipStep)), width: width)
        fresh.button.trailing = .arrow
        let rows = NSStackView(views: [have, fresh])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = Design.beat(3)
        rows.identifier = SetupFrame.cascade
        body.addArrangedSubview(rows)
        let view = OnboardingView(memberWord: memberName)
        loader = view
        body.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        if let name = imported { view.finished(summaryFor: name) }
    }

    @objc private func chooseCatalogue() {
        guard let w = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: ColourFiles.catalogue) ?? .data, UTType(filenameExtension: ColourFiles.legacyCatalogue) ?? .data, .json]
        panel.prompt = "Bring In"
        #if APPSTORE
        // The sandbox grants what is picked: a catalogue is its folder, so the folder is what is picked.
        panel.canChooseDirectories = true
        panel.message = "Choose a catalogue's folder (the one holding its .\(ColourFiles.catalogue) file), or a library file to copy in"
        // The download edition's data, if this Mac had it: opened where it is, nothing copied or moved.
        panel.directoryURL = Catalogues.realApplicationSupport.appendingPathComponent("MMFFDev Colour 3")
        #endif
        panel.beginSheetModal(for: w) { [weak self] r in
            guard let self = self, r == .OK, var url = panel.url else { return }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                guard let index = CatalogueFiles.index(in: url) else { self.complain("That folder holds no catalogue."); return }
                FolderAccess.remember(url)
                url = index
            }
            do {
                let name = [ColourFiles.catalogue, ColourFiles.legacyCatalogue].contains(url.pathExtension.lowercased())
                    ? try Catalogues.standard.adopt(url) : try Catalogues.standard.importFile(url)
                self.imported = name
                self.next.isEnabled = false
                self.broughtIn?.set(detail: "\u{201C}\(name)\u{201D} is in. Continue to open it.")
                self.broughtIn?.button.trailing = .tick
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
        if imported == nil && here.isEmpty { setup.title("Your First", "Catalogue") } else { setup.title("Which Catalogue", "To Open") }
        if imported == nil && existing == nil, let first = here.first { existing = Catalogues.currentName.isEmpty ? first : Catalogues.currentName; useImported = true }
        if imported != nil || !here.isEmpty {
            body.addArrangedSubview(lead("Open a catalogue you already have, or make a new one. A catalogue is one body of work: its members, their palettes, typography and tags."))
            let rows = NSStackView()
            rows.orientation = .vertical
            rows.alignment = .leading
            rows.spacing = Design.beat(3)
            rows.identifier = SetupFrame.cascade
            var options: [(String, String, Selector)] = []
            if let name = imported { options.append((name, "Just brought in. Opened where it is.", #selector(pickUseImported))) }
            for name in here { options.append((name, "Already on this Mac, at \(place(Catalogues.standard.directory(for: name))).", #selector(pickExistingNamed(_:)))) }
            for (name, detail, sel) in options {
                let chosen = chosenCatalogue == name
                let b = SwissButton(chosen ? "Opens" : "Open This", .secondary, target: self, action: sel)
                b.identifier = NSUserInterfaceItemIdentifier(name)
                b.trailing = chosen ? .tick : .none
                rows.addArrangedSubview(ChoiceRow(name, detail, button: b, width: width))
            }
            let make = SwissButton(chosenCatalogue == nil ? "Making It" : "Make New", .secondary, target: self, action: #selector(pickMakeNew))
            make.trailing = chosenCatalogue == nil ? .tick : .none
            rows.addArrangedSubview(ChoiceRow("A New Catalogue", "Named and placed below.", button: make, width: width))
            body.addArrangedSubview(rows)
        } else {
            useImported = false
            body.addArrangedSubview(lead("A catalogue is one body of work: its members, their palettes, typography and tags, as plain files in a folder you choose."))
        }
        let name = field("Catalogue Name", catalogueName, action: #selector(nameTyped))
        nameField = name
        let (row, path) = pathRow("Kept In", catalogueParent.appendingPathComponent(filesystemName(catalogueName.isEmpty ? "Catalogue Name" : catalogueName)), change: #selector(changeCatalogueParent), afterField: true)
        cataloguePath = path
        body.addArrangedSubview(row)
        #if !APPSTORE
        // Documents is macOS's to guard: kept there by default, the first touch (at Create) makes it ask once.
        // A folder chosen through the panel is granted with the choice and never asks.
        if chosenCatalogue == nil && DocumentsAccess.inside(catalogueParent) && DocumentsAccess.current != .on {
            let note = Design.text("macOS asks once whether \(Brand.name) may use Documents, when the catalogue is made. A folder chosen through Change never asks.", .caption, colour: Design.quiet, wraps: true)
            note.preferredMaxLayoutWidth = width
            body.addArrangedSubview(note)
        }
        #endif
        name.isEnabled = chosenCatalogue == nil
        name.superview?.alphaValue = chosenCatalogue == nil ? 1 : 0.4
        row.alphaValue = chosenCatalogue == nil ? 1 : 0.4
    }

    @objc private func pickUseImported() { useImported = true; existing = nil; show(step: Step.catalogue) }
    @objc private func pickExistingNamed(_ b: NSButton) { existing = b.identifier?.rawValue; useImported = true; show(step: Step.catalogue) }
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
        setup.title("What You", "Call Things")
        catalogueName = nameField?.stringValue ?? catalogueName
        body.addArrangedSubview(lead("The catalogue lists its members under a heading. Call the heading what you call that body of work, and a member what one of them is."))
        body.addArrangedSubview(story("Every member holds Information, Palettes, Typography and Tags. The whole map can be shaped later in Settings \u{25B8} Schema."))
        let half = (width - Design.Wizard.gutter) / 2
        let collection = SwissDropdown("The Heading", value: collectionName, options: SchemaTrial.collectionNames, width: half)
        collection.onChange = { [weak self] in self?.collectionName = $0 }
        let member = SwissDropdown("One Member", value: memberName, options: SchemaTrial.primaryNames, width: half)
        member.onChange = { [weak self] in self?.memberName = $0 }
        let pair = NSStackView(views: [collection, member])
        pair.orientation = .horizontal
        pair.alignment = .top
        pair.spacing = Design.Wizard.gutter
        body.addArrangedSubview(pair)
    }

    // MARK: 5. The first member

    private var memberField: NSTextField?

    /// Where the catalogue being set up will be.
    /// The catalogue to open: one already here, one brought in, or nil for the one being made.
    private var chosenCatalogue: String? { useImported ? (existing ?? imported) : nil }

    private var catalogueFolder: URL {
        if let name = chosenCatalogue { return Catalogues.standard.directory(for: name) }
        return catalogueParent.appendingPathComponent(filesystemName(catalogueName))
    }

    private func firstMemberStep() {
        setup.title("Your First", memberName)
        skip.isHidden = false
        skip.title = "Skip For Now"
        body.addArrangedSubview(lead("A \(memberName.lowercased()) is a folder of its own inside the catalogue, under \(collectionName), so it can be handed over or moved as one."))
        body.addArrangedSubview(story("Its folders follow the shape you chose: Information, Palettes, Typography and Tags. Skip this and make the first one in the app."))
        let name = field("\(memberName) Name", firstMember, action: #selector(memberNameTyped))
        memberField = name
    }

    @objc private func memberNameTyped(_ f: NSTextField) { firstMember = f.stringValue }

    // MARK: 0. Welcome

    private func welcomeStep() {
        setup.title("Set Up", Brand.edition)
        body.addArrangedSubview(lead("Eight short steps. Nothing is written until you press Create, and the last one teaches you the halo."))
        body.addArrangedSubview(story("\(Brand.edition) manages colour for design, print, video and three-dimensional work. A catalogue holds your clients, their palettes, typography and tags, as plain files you can open, move and hand over. Everything here can be changed later in Settings."))
        // The row is the words column: the text takes what the button and one gutter leave.
        let perms = PermissionsView(textWidth: width - PermissionRow.buttonWidth - Design.Wizard.gutter, spacing: Design.beat(3)) { [weak self] e in self?.complain(e.localizedDescription) }
        perms.translatesAutoresizingMaskIntoConstraints = false
        perms.widthAnchor.constraint(equalToConstant: width).isActive = true
        perms.arrangedSubviews.forEach { $0.widthAnchor.constraint(equalTo: perms.widthAnchor).isActive = true }
        perms.identifier = SetupFrame.cascade
        body.addArrangedSubview(perms)
        updateWelcomeButtons()
    }

    /// Screen Recording allowed while this copy runs: the way on is a restart, or on without it.
    private func updateWelcomeButtons() {
        let restart = ScreenAccess.restartNeeded
        next.title = restart ? "Restart And Continue" : "Begin Setup"
        skip.isHidden = !restart
        skip.title = "Continue Without Restarting"
        hint(restart ? "\(Brand.name) reopens here, at step 2" : "")
    }

    @objc private func permissionsChanged() { if step == Step.welcome { updateWelcomeButtons() } }

    // MARK: 6. Ready

    private func readyStep() {
        firstMember = memberField?.stringValue ?? firstMember
        setup.title("Ready", "To Create")
        next.title = chosenCatalogue == nil ? "Create" : "Open"
        hint(chosenCatalogue == nil ? "Makes the catalogue, then teaches the halo" : "Opens the catalogue, then teaches the halo")
        body.addArrangedSubview(lead("Everything you chose, once more. Nothing has been written yet."))
        var rows: [(String, String)] = [("App Data", place(home))]
        if let name = chosenCatalogue { rows.append(("Catalogue", "\u{201C}\(name)\u{201D}, where it is")) }
        else { rows.append(("Catalogue", "\u{201C}\(catalogueName)\u{201D} in \(place(catalogueFolder))")) }
        rows.append(("Heading And Member", "\(collectionName) \u{00B7} \(memberName)"))
        if !firstMember.trimmingCharacters(in: .whitespaces).isEmpty { rows.append(("First \(memberName)", "\u{201C}\(firstMember)\u{201D} under \(collectionName)")) }
        let allowed = Permission.all.filter { $0.state() == .on }.map { $0.title }
        rows.append(("Allowed", allowed.isEmpty ? "Nothing yet. Settings has every switch." : allowed.joined(separator: ", ")))
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = Design.beat(2)
        list.identifier = SetupFrame.cascade
        for (i, (k, v)) in rows.enumerated() { list.addArrangedSubview(SetupFrame.field(k, v, action: nil, target: nil, selector: nil, width: width, rule: i == 0, oneLine: true).row) }
        body.addArrangedSubview(list)
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
            // The schema chosen here is the new catalogue's own: point the store at its folder before writing it.
            SchemaTrial.use(directory: Catalogues.standard.directory(for: name))
            SchemaTrial.changeCollection(SchemaTrial.homeForNewMember().id) { c in
                c.name = collectionName.trimmingCharacters(in: .whitespaces)
                c.stack.name = memberName.trimmingCharacters(in: .whitespaces)
            }
            let member = firstMember.trimmingCharacters(in: .whitespacesAndNewlines)
            if !member.isEmpty {
                try Catalogues.standard.store(for: name).mutate { lib in _ = lib.createProject(named: member) }
            }
            Prefs.assistantDone = true
            Prefs.setupDone = true      // the permissions were offered on the welcome page
            SetupDraft.clear(key: Self.draftKey)
            created = name
            show(step: Step.halo)
        } catch {
            Diagnostics.log("setup create", error: error)
            complain(error.localizedDescription)
        }
    }

    // MARK: 7. The halo

    private func haloStep() {
        setup.title("Meet", "The Halo")
        let t = trainer ?? HaloTrainer(colour: Brand.master, name: Brand.masterName, hex: Brand.masterHex)
        trainer = t
        t.onChange = { [weak self] in self?.updateHaloButtons() }
        // The words in the title's columns, the dial whole in the words' columns: exactly its reach with the second ring open.
        let words = Design.text("Every colour, palette and project opens a halo: a dial of what you can do with it. Three moves and you know it. Nothing here touches your catalogue.", .lead, wraps: true)
        words.preferredMaxLayoutWidth = Design.Wizard.span(1, 5)
        setup.aside.addArrangedSubview(words)
        setup.aside.addArrangedSubview(t.instruction)
        t.translatesAutoresizingMaskIntoConstraints = false
        t.widthAnchor.constraint(equalToConstant: width).isActive = true
        body.addArrangedSubview(t)
        next.title = "Open \(Brand.name)"
        updateHaloButtons()
        // The dial grows from the middle once the page has arrived.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak t] in if self?.step == Step.halo { t?.begin() } }
    }

    private func updateHaloButtons() {
        guard let t = trainer else { return }
        let p = HaloTrainer.progress(t.learned)
        skip.isHidden = t.allLearned
        // Return chooses on the halo while it is being learned, so it must not also close the setup.
        next.keyEquivalent = t.allLearned ? "\r" : ""
        skip.title = "Skip"
        hint(t.allLearned ? "You know the halo" : "\(p.done) of \(p.of) learned")
    }

    private func finishAndOpen() {
        trainer?.stop()
        Self.keep = nil
        window?.close()
        completion(created ?? Catalogues.currentName)
    }
}

// MARK: - Reading a catalogue in, as it happens

/// Two lines that follow a catalogue being read: what is being done, and the member or file in hand, at the
/// speed it really happens; then one line that stays. A catalogue laid out by an earlier version is brought
/// across first, with a backup beside it, and that is said here too.
final class OnboardingView: NSView {
    private let group = NSTextField(labelWithString: "")
    private let item = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let memberWord: String

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
        let column = NSStackView(views: [group, item, bar, summary])
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

    func finished(summaryFor text: String) {
        isHidden = false
        group.stringValue = ""
        item.stringValue = ""
        bar.isHidden = true
        summary.stringValue = text
    }

    /// Reads the catalogue off the main thread, telling the lines what it is on.
    func load(catalogue name: String, over host: NSWindow, done: @escaping () -> Void) {
        isHidden = false
        bar.isHidden = false
        bar.doubleValue = 0
        summary.stringValue = ""
        let word = memberWord
        let store = Catalogues.standard.store(for: name)
        let bringing = Migration.needed(in: store.root)
        say(group: bringing ? "Backing up \(name), then bringing it across into its own tree of folders" : "Reading \(name)", item: "", progress: 0.05)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let read: Result<Library, Error> = Result { try store.load() }
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch read {
                case .failure(let error):
                    self.finished(summaryFor: error.localizedDescription)
                    Diagnostics.log("setup", error: error)
                case .success(let lib):
                    let members = lib.orderedProjects
                    for (at, p) in members.enumerated() { self.say(group: "Fetching \(word) \(at + 1) of \(members.count): \(p.name)", item: "", progress: Double(at + 1) / Double(max(members.count, 1))) }
                    let plural = SchemaTrial.plural(word)
                    let palettes = lib.swatches.filter { !$0.isTypography }.count, typography = lib.swatches.filter { $0.isTypography }.count
                    let tags = lib.tagInfo.filter { $0.removed != true }.count
                    var parts = ["Found \(members.count) \(members.count == 1 ? word : plural)", "\(palettes) palettes", "\(typography) typography sets", "\(tags) tags"]
                    if let report = store.takeMigration() { parts.append("brought across, the old folders kept in \(report.backup.lastPathComponent)") }
                    self.group.stringValue = "Done"
                    self.item.stringValue = ""
                    self.bar.doubleValue = 1
                    self.summary.stringValue = parts.joined(separator: " \u{00B7} ")
                }
                done()
            }
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
}

// MARK: - Xcode canvas
// Only Xcode's toolchain has the preview macros; build.sh compiles Release with the command-line tools.
#if DEBUG
#Preview("Setup 01 Welcome", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 1) }
#Preview("Setup 02 App Data", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 2) }
#Preview("Setup 03 Bring In", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 3) }
#Preview("Setup 04 Catalogue", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 4) }
#Preview("Setup 05 Schema", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 5) }
#Preview("Setup 06 First One", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 6) }
#Preview("Setup 07 Ready", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 7) }
#Preview("Setup 08 The Halo", traits: .fixedLayout(width: Design.Wizard.size.width, height: Design.Wizard.size.height)) { SetupAssistant.preview(step: 8) }
#endif

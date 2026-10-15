import AppKit

/// A machine-local development preference. It never marks a workspace complete or bypasses validation.
enum DevelopmentLaunch {
    static let key = "developmentResumeWorkspaceV1"
    static let defaults = UserDefaults(suiteName: "com.mmffdev.colorgain.development")!
    static var enabled: Bool { defaults.bool(forKey: key) }
    static func setEnabled(_ value: Bool) { defaults.set(value, forKey: key) }
    static func configure(_ arguments: [String], in defaults: UserDefaults = DevelopmentLaunch.defaults) {
        if arguments.contains("--dev-off") { defaults.set(false, forKey: key) }
        else if arguments.contains("--dev-on") { defaults.set(true, forKey: key) }
    }
    static func canResume(_ inventory: WorkspaceInventory, enabled: Bool) -> Bool {
        enabled && inventory.setupComplete && inventory.lastUsed?.state == .ready
    }
}

struct WorkspaceCatalogue {
    enum State: Equatable {
        case ready, migration, missing, access, invalid
        var label: String {
            switch self {
            case .ready: return "Ready"
            case .migration: return "Update required"
            case .missing: return "Files unavailable"
            case .access: return "Folder access required"
            case .invalid: return "Invalid catalogue"
            }
        }
    }
    var name: String
    var folder: URL
    var id: UUID?
    var state: State
    var issue: String?
    var recovery: FileRecoveryReport? = nil
    var canOpen: Bool { state == .ready || state == .migration }
}

/// Strict, read-only discovery. Unknown/inaccessible entries remain visible instead of becoming an empty list.
struct WorkspaceInventory {
    let root: URL
    let catalogues: [WorkspaceCatalogue]
    let lastName: String?
    let lastID: UUID?
    let setupComplete: Bool
    var lastUsed: WorkspaceCatalogue? {
        if let lastID { return catalogues.first { $0.id == lastID } }
        let matches=catalogues.filter { $0.name == lastName }
        return matches.count == 1 ? matches.first : nil
    }
    var genuinelyEmpty: Bool { catalogues.isEmpty }

    static func root(for selection: URL) throws -> URL {
        let directory = try selection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if directory { return selection }
        guard selection.lastPathComponent == "colorgain.coldata" else {
            throw failure("Choose colorgain.coldata or the app-data folder containing it.")
        }
        return selection.deletingLastPathComponent()
    }
    static func read(root: URL) throws -> WorkspaceInventory {
        try FileOperationTransaction.recover(home: root)
        let manifestURL = root.appendingPathComponent("colorgain.coldata")
        let bytes = try Handler_File_Manager.shared.read(manifestURL)
        guard bytes.count <= 16 * 1024 * 1024,
              let manifest = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              manifest["version"] as? Int == 1 else { throw failure("This app-data file is invalid or from a newer version. It has not been changed.") }
        let raw = manifest["catalogues"] ?? []
        let references = try Handler_File_Manager.shared.handler(for: manifestURL).references(manifest, at: manifestURL)
        var referenceIssues: [FileIssue] = []
        for reference in references {
            do { _ = try Handler_File_Manager.shared.read(reference.url) }
            catch { referenceIssues.append(FileIssue.wrapping(error, at: reference.url)) }
        }
        if !referenceIssues.isEmpty { throw FileRecoveryReport(root: root, issues: referenceIssues) }
        let registry = try JSONDecoder().decode([Catalogues.Entry].self, from: JSONSerialization.data(withJSONObject: raw))
        guard registry.count <= 2000 else { throw failure("The app-data catalogue list is too large.") }
        var entries: [WorkspaceCatalogue] = [], paths = Set<String>(), identities = Set<UUID>()
        let detached = Set(manifest["detachedCatalogues"] as? [String] ?? [])
        let detachedIDs = Set((manifest["detachedCatalogueIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:)))
        func append(_ name: String, _ folder: URL, expected: UUID? = nil) {
            guard !detached.contains(folder.standardizedFileURL.path), !detached.contains(folder.resolvingSymlinksInPath().path) else { return }
            guard paths.insert(folder.resolvingSymlinksInPath().path).inserted else { return }
            var entry = probe(name: name, folder: folder)
            if let expected, let actual = entry.id, actual != expected {
                let issue = FileIssue(url: CatalogueFiles.index(in: folder) ?? folder, state: .identityMismatch, message: "This folder belongs to a different catalogue. Locate the original or explicitly detach its registration.")
                entry.state = .invalid; entry.issue = issue.message
                entry.recovery = FileRecoveryReport(root: folder, issues: [issue])
            }
            if let id = entry.id, detachedIDs.contains(id) { return }
            let canonical=folder.resolvingSymlinksInPath().path
            if canonical == root.appendingPathComponent("Assets").resolvingSymlinksInPath().path || canonical.hasPrefix(root.appendingPathComponent("Backups").resolvingSymlinksInPath().path+"/") {
                entry.state = .invalid;entry.issue="This is an internal assets or backup location. Locate the user catalogue itself."
            }
            if let id = entry.id, !identities.insert(id).inserted { return }
            entries.append(entry)
        }
        for link in registry {
            guard !link.name.isEmpty, !link.path.isEmpty else { throw failure("The app-data catalogue list contains an invalid location.") }
            let folder: URL
            if link.path.hasPrefix("/") { folder = URL(fileURLWithPath: link.path) }
            else {
                guard !link.path.split(separator: "/").contains("..") else { throw failure("Invalid relative catalogue location.") }
                folder = root.appendingPathComponent(link.path)
            }
            append(link.name, folder, expected: link.id)
        }
        let local = root.appendingPathComponent("Catalogues")
        do {
            let folders = try FileManager.default.contentsOfDirectory(at: local, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try folder.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      folder.lastPathComponent != TreeFiles.backups else { continue }
                // Inspect only each catalogue's own index: never recursively harvest Assets or Backups.
                let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                if files.contains(where: { ["colcat","colcatalogue"].contains($0.pathExtension.lowercased()) || $0.lastPathComponent == "library.json" }) {
                    append(folder.lastPathComponent, folder)
                }
            }
        } catch {
            let error = error as NSError
            guard isMissing(error) else { throw failure("The app-data folder is open, but its Catalogues folder cannot be read. Choose the app-data folder again to restore access. \(error.localizedDescription)") }
        }
        // Preserve an older Main catalogue at the app-home root; exclude app-wide/internal indices.
        let rootFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        if rootFiles.contains(where: { ["colcat","colcatalogue"].contains($0.pathExtension.lowercased()) && !["Global","Assets"].contains($0.deletingPathExtension().lastPathComponent) }) {
            append(Catalogues.mainName, root)
        }
        let settings = manifest["settings"] as? [String: Any] ?? [:]
        let savedDefault = manifest["defaultCatalogue"] as? [String: Any]
        return WorkspaceInventory(root: root, catalogues: entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                                  lastName: (savedDefault?["name"] as? String) ?? (settings[Catalogues.currentKey] as? String),
                                  lastID: ((savedDefault?["id"] as? String) ?? (settings["currentCatalogueID"] as? String)).flatMap(UUID.init(uuidString:)),
                                  setupComplete: settings["assistantDone"] as? Bool == true)
    }
    static func isMissing(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(error.code)) || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
    }
    static func probe(name: String, folder: URL) -> WorkspaceCatalogue {
        var entry = WorkspaceCatalogue(name: name, folder: folder, state: .invalid)
        do {
            guard try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw failure("Choose the catalogue folder, not a file.") }
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            let modern = files.filter { $0.pathExtension.lowercased() == "colcat" }
            let named = modern.first { $0.deletingPathExtension().lastPathComponent == name || $0.deletingPathExtension().lastPathComponent == folder.lastPathComponent }
            if modern.count > 1 && named == nil { throw failure("This folder contains several catalogue indices. Choose each catalogue's own folder.") }
            if let index = named ?? modern.first {
                let bytes = try Data(contentsOf: index)
                guard bytes.count <= 32 * 1024 * 1024,
                      let header = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], header["format"] as? String == "colour-catalogue" else { throw failure("The catalogue index is invalid.") }
                guard header["version"] as? Int == 3, let doc = CatalogueTree.decode(bytes) else { throw failure("This catalogue requires a supported version-3 index. Its files have not been changed.") }
                entry.name = doc.name; entry.id = doc.id; entry.state = .ready
                try Handler_File_Manager.shared.requireAvailableCatalogue(index)
            } else if files.contains(where: { $0.pathExtension.lowercased() == "colcatalogue" || $0.lastPathComponent == "library.json" }) {
                entry.state = .migration; entry.issue = "A backup and catalogue update are required before opening."
            } else { entry.state = .missing; entry.issue = "No catalogue index was found here. Locate the folder containing its .colcat file." }
        } catch {
            if let report = error as? FileRecoveryReport { entry.recovery = report; entry.state = report.issues.allSatisfy { $0.state == .missing } ? .missing : .invalid }
            let error = error as NSError
            if isMissing(error) { entry.state = .missing }
            else if (error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code)) || (error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES)) { entry.state = .access }
            entry.issue = error.localizedDescription
        }
        return entry
    }
}

final class WorkspaceStartupController: NSWindowController, NSWindowDelegate {
    let content: WorkspaceStartupView
    private let cancel: () -> Void
    private var finished=false
    init(root: URL, selection: URL? = nil, ready: @escaping (URL, WorkspaceCatalogue) -> Void, create: @escaping (URL, String) -> Void, cancel: @escaping () -> Void) {
        self.cancel=cancel
        content = WorkspaceStartupView(root: root, ready: ready, create: create)
        let window = StudioWindow(contentRect: NSRect(origin: .zero,size:Design.App.size),styleMask:[.closable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Open Colorgain Workspace"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.backgroundColor = Design.card; window.minSize = Design.App.least
        let scroll=WorkspaceStartupScroll()
        scroll.documentView=content;scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.scrollerStyle = .overlay
        scroll.frame=NSRect(origin:.zero,size:Design.App.size);scroll.autoresizingMask=[.width,.height]
        window.contentView=scroll;window.center()
        super.init(window: window)
        window.delegate=self
        content.onCancel = { [weak self] in self?.close() }
        content.initialSelection = selection
    }
    required init?(coder:NSCoder) { fatalError() }
    func windowWillClose(_ notification:Notification) { if !finished { cancel() } }
    func finishClosing() { finished=true;close() }
    func start() {
        if content.resumeCompletedWorkspace() { return }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        content.start(); NSApp.activate(ignoringOtherApps:true)
    }
}

private final class WorkspaceStartupScroll: FittedScrollView {
    override func layout() {
        super.layout()
        documentView?.frame=NSRect(x:0,y:0,width:contentSize.width,height:max(contentSize.height,Design.App.header+27*Design.App.unit))
    }
}

/// Existing-workspace recovery precedes catalogue creation. Uses the incumbent Swiss grid and controls.
final class WorkspaceStartupView: NSView {
    private enum Stage { case workspace, catalogues, create }
    private var stage = Stage.workspace
    private var root: URL
    private var inventory: WorkspaceInventory?
    private var selected = 0
    private var message = ""
    var initialSelection: URL?
    var onCancel: (() -> Void)?
    var onWorkspaceSelected: ((URL) -> Void)?
    private let ready: (URL, WorkspaceCatalogue) -> Void
    private let create: (URL, String) -> Void
    private let openData = SwissButton("Open Existing App Data…", .primary)
    private let newData = SwissButton("Create App Data Folder…", .secondary)
    private let switchData = SwissButton("Choose Another Workspace…", .secondary)
    private let openCat = SwissButton("Open Catalogue", .primary)
    private let locateCat = SwissButton("Locate Catalogue…", .secondary)
    private let createCat = SwissButton("Create Catalogue…", .secondary)
    private let buildCat = SwissButton("Create And Set Up Catalogue", .primary)
    private let back = SwissButton("Back", .secondary)
    private let cancel = SwissButton("Cancel", .secondary)
    private let name = NSTextField(string: "")
    private var chooser: SwissDropdown?
    private var options: [String] = []
    private var gridWidth: CGFloat { window?.contentView?.bounds.width ?? bounds.width }
    private var x: CGFloat { Design.App.column(7,in:gridWidth) }
    private var w: CGFloat { Design.App.span(7,12,in:gridWidth) }
    private var u: CGFloat { Design.App.unit }
    private func y(_ row: CGFloat) -> CGFloat { Design.App.header + 1 + row*u }
    override var isFlipped: Bool { true }
    init(root: URL, ready: @escaping (URL, WorkspaceCatalogue) -> Void, create: @escaping (URL, String) -> Void) {
        self.root=root; self.ready=ready; self.create=create
        super.init(frame:.zero)
        for (button,action) in [(openData,#selector(chooseData)),(newData,#selector(makeData)),(switchData,#selector(chooseData)),(openCat,#selector(openSelected)),(locateCat,#selector(locate)),(createCat,#selector(showCreate)),(buildCat,#selector(build)),(back,#selector(goBack)),(cancel,#selector(cancelPressed))] {
            button.target=self;button.action=action;addSubview(button)
        }
        name.placeholderAttributedString=Design.attributed("Catalogue name",.body,colour:Design.quiet)
        name.font=Design.Text.body.font();name.textColor=Design.ink;name.isBordered=false;name.drawsBackground=false;name.focusRingType = .none
        name.setAccessibilityLabel("New catalogue name");addSubview(name)
        setAccessibilityLabel("Workspace and catalogue chooser")
    }
    required init?(coder:NSCoder) { fatalError() }
    func start() {
        if let initialSelection {
            do {
                if ["colcat","colcatalogue"].contains(initialSelection.pathExtension.lowercased()) {
                    var parent = initialSelection.deletingLastPathComponent()
                    for _ in 0..<8 {
                        if FileManager.default.fileExists(atPath:parent.appendingPathComponent("colorgain.coldata").path) { root=parent;break }
                        parent=parent.deletingLastPathComponent()
                    }
                    try openWorkspace(root)
                    try validateAndOpen(WorkspaceInventory.probe(name:initialSelection.deletingPathExtension().lastPathComponent,folder:initialSelection.deletingLastPathComponent()))
                } else {
                    let folder=try WorkspaceInventory.root(for:initialSelection)
                    try FolderAccess.authorize(folder);try openWorkspace(folder)
                }
            } catch { fail(error) }
        } else {
            do { try openWorkspace(root) }
            catch { if Catalogues.home != nil || !WorkspaceInventory.isMissing(error as NSError) { fail(error) } }
        }
    }
    func resumeCompletedWorkspace() -> Bool {
        guard initialSelection == nil, let inventory = try? WorkspaceInventory.read(root:root), inventory.setupComplete, inventory.lastUsed?.state == .ready, let entry=inventory.lastUsed else { return false }
        do { try validateAndOpen(entry); return true } catch { fail(error); return false }
    }
    private func fail(_ error: Error) { message=error.localizedDescription;needsDisplay=true;needsLayout=true }
    private func openWorkspace(_ folder: URL) throws {
        let value=try WorkspaceInventory.read(root:folder)
        root=folder;inventory=value;message=""
        onWorkspaceSelected?(folder)
        if value.genuinelyEmpty { name.stringValue="" }
        selected=value.lastUsed.flatMap { entry in value.catalogues.firstIndex(where: { $0.folder == entry.folder }) } ?? value.catalogues.firstIndex(where: { $0.canOpen }) ?? 0
        stage=value.genuinelyEmpty ? .create : .catalogues
        rebuildChooser();needsLayout=true;needsDisplay=true
        window?.makeFirstResponder(stage == .create ? name : self)
    }
    private func rebuildChooser() {
        chooser?.removeFromSuperview();chooser=nil
        guard let inventory, !inventory.catalogues.isEmpty else { return }
        options=inventory.catalogues.enumerated().map { "\($0.offset+1). \($0.element.name) · \($0.element.state.label)" }
        let dropdown=SwissDropdown("Catalogue",value:options[min(selected,options.count-1)],options:options,allowsOwn:false,width:max(280,w))
        dropdown.onChange = { [weak self] value in guard let self,let index=self.options.firstIndex(of:value) else { return };self.selected=index;self.message="";self.needsLayout=true;self.needsDisplay=true }
        addSubview(dropdown);chooser=dropdown
    }
    override func layout() {
        super.layout()
        setAccessibilityHelp("App data: " + root.path + (message.isEmpty ? "" : ". " + message))
        for view in [openData,newData,switchData,openCat,locateCat,createCat,buildCat,back,name,cancel] { view.isHidden=true }
        chooser?.isHidden=stage != .catalogues
        func place(_ button:SwissButton,_ row:CGFloat) { button.isHidden=false;button.frame=NSRect(x:x,y:SettingsSheet.buttonTop(baseline:y(row)+Design.App.textBaseline),width:button.intrinsicContentSize.width,height:SwissButton.height) }
        switch stage {
        case .workspace:
            newData.title="Create App Data Folder…"
            place(openData,9);place(newData,12)
        case .catalogues:
            chooser?.frame=NSRect(x:x,y:y(7),width:w,height:56)
            place(openCat,14);place(locateCat,17);place(createCat,20);place(switchData,23)
            openCat.isEnabled=inventory?.catalogues.indices.contains(selected) == true && (inventory!.catalogues[selected].canOpen || inventory!.catalogues[selected].recovery != nil)
            if let inventory,inventory.catalogues.indices.contains(selected) {
                let entry=inventory.catalogues[selected],pending=CatalogueSetupSession.load()
                openCat.title = !inventory.setupComplete && pending.createdName == entry.name && pending.createdFolder?.standardizedFileURL == entry.folder.standardizedFileURL ? "Continue Catalogue Setup" : "Open Catalogue"
                if entry.recovery != nil { openCat.title = "Recover Catalogue…" }
            }
            place(openCat,14)
            newData.title="New Workspace…";place(newData,23)
            newData.frame.origin.x=switchData.frame.maxX+Design.App.gutter
            if newData.frame.maxX > x+w { newData.frame.origin.x=x;newData.frame.origin.y += 2*u }
        case .create:
            name.isHidden=false;name.frame=NSRect(x:x,y:y(9),width:w,height:32)
            place(buildCat,14);place(locateCat,17);place(switchData,20)
            if inventory?.genuinelyEmpty == false { place(back,23) }
        }
        cancel.isHidden=false
        cancel.frame=NSRect(x:Design.App.margin,y:SettingsSheet.buttonTop(baseline:y(23)+Design.App.textBaseline),width:cancel.intrinsicContentSize.width,height:SwissButton.height)
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityValue() -> Any? { "App data: " + root.path + (message.isEmpty ? "" : ". " + message) }
    override func draw(_ dirtyRect:NSRect) {
        fill(bounds,Design.card);Logo.draw(x:Design.App.margin,baseline:StudioHeader.baseline)
        Design.attributed("Colorgain Workspace",.heading).draw(x:Design.App.margin,baseline:y(1)+Design.App.textBaseline,width:Design.App.span(1,6,in:gridWidth))
        let caption = stage == .workspace ? "App data first." : "App Data Folder"
        Design.attributed(caption,.bodyStrong).draw(x:Design.App.margin,baseline:y(4)+Design.App.textBaseline,width:Design.App.span(1,6,in:gridWidth))
        SettingsSheet.paragraph(root.path,x:Design.App.margin,firstBaseline:y(6)+Design.App.textBaseline,width:Design.App.span(1,6,in:gridWidth)-32,height:3*u,colour:Design.quiet)
        let title=stage == .workspace ? "Open your workspace." : stage == .catalogues ? "Choose a catalogue." : inventory?.genuinelyEmpty == true ? "Your first catalogue." : "Create a catalogue."
        Design.attributed(title,SettingsSheet.titleStyle).draw(x:x,baseline:y(2)+Design.App.textBaseline,width:w)
        let explanation=stage == .workspace ? "Open colorgain.coldata or its app-data folder to restore your settings and catalogue list. Create a new folder only for a new workspace." : stage == .catalogues ? "Your app data is open. Choose a saved catalogue to continue with its existing structure." : (inventory?.genuinelyEmpty == true ? "No catalogues are registered or found here. Create your first catalogue, or locate an existing one." : "Choose a name for a new catalogue. Its structure is set up next.")
        SettingsSheet.paragraph(explanation,x:x,firstBaseline:y(4)+Design.App.textBaseline,width:w,height:3*u)
        if stage == .catalogues, let inventory, inventory.catalogues.indices.contains(selected) {
            let entry=inventory.catalogues[selected]
            SettingsSheet.paragraph(entry.folder.path,x:x,firstBaseline:y(10)+Design.App.textBaseline,width:w,height:2*u,colour:Design.quiet)
            Design.attributed(entry.issue ?? "Validated catalogue index · Existing contents retained",.body).draw(x:x,baseline:y(12)+Design.App.textBaseline,width:w)
            Design.attributed("\(inventory.catalogues.count) catalogue locations",.body).draw(x:Design.App.margin,baseline:y(10)+Design.App.textBaseline,width:Design.App.span(1,6,in:gridWidth))
        }
        if stage == .create {
            Design.attributed("Catalogue Name",.caption).draw(x:x,baseline:y(8)+Design.App.textBaseline,width:w)
            hairline(x:x,y:y(10)+4,width:w,Design.rule)
            SettingsSheet.paragraph("The catalogue will be created inside this workspace’s Catalogues folder. Its structure is set up next.",x:x,firstBaseline:y(12)+Design.App.textBaseline,width:w,height:2*u,colour:Design.quiet)
        }
        if !message.isEmpty { SettingsSheet.paragraph(message,x:Design.App.margin,firstBaseline:y(14)+Design.App.textBaseline,width:Design.App.span(1,6,in:gridWidth)-32,height:6*u) }
    }
    @objc private func cancelPressed() { onCancel?() }
    @objc private func chooseData() {
        let panel=NSOpenPanel();panel.canChooseFiles=true;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false
        panel.title="Open Existing App Data";panel.prompt="Open Workspace";panel.message="Choose colorgain.coldata, or the app-data folder containing it.";panel.directoryURL=root
        guard let window else { return }
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self,result == .OK,let selection=panel.url else { return }
            do {
                let folder=try WorkspaceInventory.root(for:selection);try FolderAccess.authorize(folder)
                if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("colorgain.coldata").path), FileManager.default.fileExists(atPath: folder.appendingPathComponent("catalogues.json").path) {
                    let modal = SwissFocusModal(title: "Update Legacy Workspace?", message: "Create a current workspace manifest from the legacy catalogue list. The original list and catalogue files are retained.")
                    modal.button("Update Workspace", primary: true) {
                        do { try AppDataStore(root: folder).migrateLegacy(); try AppHomeSeed.ensure(at: folder); modal.dismissOverlay(); try self.openWorkspace(folder) }
                        catch { self.fail(error) }
                    }
                    modal.button("Cancel") { modal.dismissOverlay() }; modal.present(over: self); return
                }
                try self.openWorkspace(folder)
            } catch { self.fail(error) }
        }
    }
    @objc private func makeData() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true;panel.allowsMultipleSelection=false
        panel.title="Create App Data Folder";panel.prompt="Create Workspace";panel.message="Choose a new or empty folder. Existing app data will not be moved or overwritten."
        guard let window else { return }
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self,result == .OK,let folder=panel.url else { return }
            do {
                try FolderAccess.authorize(folder)
                let files=try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:[.skipsHiddenFiles])
                guard files.isEmpty else { throw failure("This folder already contains files. Use Open Existing App Data to open a workspace, or choose an empty folder.") }
                try AppHomeSeed.ensure(at:folder);try self.openWorkspace(folder)
            } catch { self.fail(error) }
        }
    }
    @objc private func showCreate() { stage = .create;message="";needsLayout=true;needsDisplay=true;window?.makeFirstResponder(name) }
    @objc private func goBack() { stage = .catalogues;message="";needsLayout=true;needsDisplay=true }
    @objc private func build() {
        guard inventory != nil else { return }
        do {
            let name=try CatalogueSetup.createBlank(self.name.stringValue,under:root.appendingPathComponent("Catalogues"),catalogues:Catalogues(root:root,legacyURL:nil))
            create(root,name)
        } catch { fail(error) }
    }
    @objc private func locate() {
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false
        panel.title="Locate Existing Catalogue";panel.prompt="Open Catalogue";panel.message="Choose the catalogue folder containing its .colcat file.";panel.directoryURL=root.appendingPathComponent("Catalogues")
        guard let window else { return }
        panel.beginSheetModal(for:window) { [weak self] result in
            guard let self,result == .OK,let folder=panel.url else { return }
            do { try FolderAccess.authorize(folder);try self.validateAndOpen(WorkspaceInventory.probe(name:folder.lastPathComponent,folder:folder)) } catch { self.fail(error) }
        }
    }
    @objc private func openSelected() {
        guard let inventory,inventory.catalogues.indices.contains(selected) else { return }
        let entry=inventory.catalogues[selected],pending=CatalogueSetupSession.load()
        if let report = entry.recovery, let window {
            FileRecoveryPresenter.present(report, over: window, retry: { [weak self] in guard let self else { return }; do { try self.openWorkspace(self.root) } catch { self.fail(error) } }, relinked: { [weak self] in guard let self else { return }; do { try self.openWorkspace(self.root) } catch { self.fail(error) } })
            return
        }
        if !inventory.setupComplete,pending.createdName == entry.name,pending.createdFolder?.standardizedFileURL == entry.folder.standardizedFileURL {
            create(root,entry.name);return
        }
        do { try validateAndOpen(entry) } catch { fail(error) }
    }
    private func validateAndOpen(_ entry: WorkspaceCatalogue) throws {
        let folder=entry.folder.resolvingSymlinksInPath().path
        guard folder != root.appendingPathComponent("Assets").resolvingSymlinksInPath().path,
              !folder.hasPrefix(root.appendingPathComponent("Backups").resolvingSymlinksInPath().path+"/") else { throw failure("App-wide assets and backups are not user catalogues. Choose the original catalogue folder.") }
        guard entry.canOpen else { throw failure(entry.issue ?? entry.state.label) }
        if entry.state == .migration {
            let modal=SwissFocusModal(title:"Update This Catalogue?",message:"Keep a backup and update “\(entry.name)” before opening. Existing contents are retained.")
            modal.button("Back Up And Open",primary:true) { [weak self,weak modal] in
                guard let self else { return }
                do { try Migration.run(root:entry.folder,name:entry.name);modal?.dismissOverlay();try self.validateAndOpen(WorkspaceInventory.probe(name:entry.name,folder:entry.folder)) } catch { self.fail(error) }
            }
            modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() };modal.present(over:self);return
        }
        if let index = CatalogueFiles.index(in: entry.folder) { try Handler_File_Manager.shared.requireAvailableCatalogue(index) }
        _ = try CatalogueTree.read(root:entry.folder)
        try Catalogues(root:root,legacyURL:nil).registerChecked(entry.name,at:entry.folder)
        ready(root,entry)
    }
}

import AppKit
import WebKit

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
        let available=NSScreen.main?.visibleFrame.size ?? NSSize(width:1440,height:900)
        let width=min(1440,available.width-64,(available.height-64)*1440/875)
        let size=NSSize(width:width,height:width*875/1440)
        let window = SetupWindow(contentRect: NSRect(origin:.zero,size:size),styleMask:[.borderless,.resizable],backing:.buffered,defer:false)
        window.title = "Open Colorgain Workspace"
        window.isReleasedWhenClosed = false; window.backgroundColor = Design.card; window.minSize = Design.App.least
        window.minSize=NSSize(width:960,height:960*875/1440);window.contentAspectRatio=NSSize(width:1440,height:875)
        window.installSquareContent(content);window.center()
        super.init(window: window)
        window.delegate=self
        content.onCancel = { [weak self] in self?.close() }
        content.initialSelection = selection
    }
    required init?(coder:NSCoder) { fatalError() }
    func windowWillClose(_ notification:Notification) { if !finished { cancel() } }
    func finishClosing() { finished=true;close() }
    func start(chooseWorkspace: Bool = false) {
        if !chooseWorkspace && content.resumeCompletedWorkspace() { return }
        showWindow(nil); window?.makeKeyAndOrderFront(nil)
        if chooseWorkspace { content.showWorkspaceSelection() } else { content.start() }
        NSApp.activate(ignoringOtherApps:true)
    }
}

/// Recovery shares the approved setup shell; file validation remains native.
final class WorkspaceStartupView: NSView,WKNavigationDelegate {
    private let bridge=WorkspaceStartupBridge()
    private var appearanceIndex=AppearancePresets.selectedIndex
    private var web:WKWebView!
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
    private let name = NSTextField(string: "")
    private var options:[String]=[]
    override var isFlipped: Bool { true }
    init(root: URL, ready: @escaping (URL, WorkspaceCatalogue) -> Void, create: @escaping (URL, String) -> Void) {
        self.root=root; self.ready=ready; self.create=create
        super.init(frame:.zero)
        let config=WKWebViewConfiguration();config.userContentController.add(bridge,name:"setup")
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;addSubview(web);bridge.owner=self
        web.loadHTMLString(ApprovedWorkspaceHTML.document,baseURL:nil)
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
    /// An explicit Open Workspace action must never auto-resume the workspace being replaced.
    func showWorkspaceSelection() {
        initialSelection = nil
        inventory = nil
        stage = .workspace
        message = ""
        needsLayout = true
        needsDisplay = true
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
        window?.makeFirstResponder(web)
    }
    private func rebuildChooser(){options=inventory?.catalogues.enumerated().map { "\($0.offset+1). \($0.element.name) · \($0.element.state.label)" } ?? []}
    override func layout(){super.layout();web.frame=bounds;refreshPage()}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){refreshPage()}
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow:.cancel)}
    private func refreshPage(){
        let entry=inventory.flatMap{$0.catalogues.indices.contains(selected) ? $0.catalogues[selected]:nil}
        let pending=CatalogueSetupSession.load()
        let continuing=inventory?.setupComplete == false && pending.createdName == entry?.name && pending.createdFolder?.standardizedFileURL == entry?.folder.standardizedFileURL
        let values:[String:Any]=["stage":stage == .workspace ? "workspace":stage == .catalogues ? "catalogues":"create","root":root.path,"folder":entry?.folder.path ?? "","issue":entry?.issue ?? "","options":options,"selected":selected,"name":name.stringValue,"error":message,"canOpen":entry?.canOpen == true || entry?.recovery != nil,"openTitle":entry?.recovery != nil ? "Recover Catalogue…":continuing ? "Continue Catalogue Setup":"Open Catalogue"]
        guard let bytes=try? JSONSerialization.data(withJSONObject:values),let json=String(data:bytes,encoding:.utf8) else{return}
        web.evaluateJavaScript("window.restoreRecovery(\(json));window.setSetupAppearance(\(SetupAppearanceHTML.payload(index:appearanceIndex)))",completionHandler:nil)
    }
    fileprivate func receive(_ message:WKScriptMessage){
        guard message.frameInfo.isMainFrame,let value=message.body as? [String:Any],let action=value["action"] as? String else{return}
        if let text=value["name"] as? String{name.stringValue=text}
        switch action {
        case "cycleAppearance":appearanceIndex=AppearancePresets.next(after:appearanceIndex);web.evaluateJavaScript("window.setSetupAppearance(\(SetupAppearanceHTML.payload(index:appearanceIndex)))",completionHandler:nil)
        case "select":if let index=value["index"] as? Int,options.indices.contains(index){selected=index;self.message="";refreshPage()}
        case "openData","switchData":chooseData()
        case "newData":makeData()
        case "openCat":openSelected()
        case "locate":locate()
        case "create":showCreate()
        case "build":build()
        case "cancel":cancelPressed()
        default:break
        }
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
                self.create(folder,"")
            } catch { self.fail(error) }
        }
    }
    @objc private func showCreate() { stage = .create;message="";needsLayout=true;needsDisplay=true;window?.makeFirstResponder(web) }
    @objc private func goBack() { stage = .catalogues;message="";needsLayout=true;needsDisplay=true }
    @objc private func build() {
        guard inventory != nil else { return }
        do {
            try SimpleCatalogue.validateLabel(self.name.stringValue)
            create(root,self.name.stringValue)
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

private final class WorkspaceStartupBridge:NSObject,WKScriptMessageHandler {
    weak var owner:WorkspaceStartupView?
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){owner?.receive(message)}
}

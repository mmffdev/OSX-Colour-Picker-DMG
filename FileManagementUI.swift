import AppKit
import UniformTypeIdentifiers

private final class FileManagementDetailsDocument: NSView {
    let label: NSTextField
    override var isFlipped: Bool { true }
    init(_ text: String) {
        label = Design.text(text, .body)
        super.init(frame: NSRect(x: 0, y: 0, width: 424, height: 180))
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping; label.isSelectable = true
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func setFrameSize(_ size: NSSize) {
        let width = max(40, size.width)
        let height = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 100_000)).height ?? 180
        super.setFrameSize(NSSize(width: width, height: max(180, height + 16)))
        label.frame = bounds
    }
}
private func fileManagementDetails(_ text: String, height: CGFloat = 180) -> NSView {
    let scroll = FittedScrollView(frame: NSRect(x: 0, y: 0, width: 448, height: height))
    scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    let document = FileManagementDetailsDocument(text); scroll.documentView = document
    document.setFrameSize(NSSize(width: scroll.contentSize.width, height: height))
    return scroll
}

/// The sole recovery presenter. It consumes structured incidents; storage never creates an alert.
enum FileRecoveryPresenter {
    static func present(_ report: FileRecoveryReport, over window: NSWindow, retry: @escaping () -> Void, relinked: @escaping () -> Void) {
        guard let view = window.contentView else { return }
        let manager = Handler_File_Manager.shared
        let modal = SwissFocusModal(title: "Files Need Attention", message: "Your current work and file references have been retained. Recover the affected files before saving this catalogue.")
        modal.content(fileManagementDetails(report.root.path + "\n\n" + report.issues.map { ($0.errorDescription ?? $0.message) + "\n" + $0.url.path }.joined(separator: "\n\n")), height: 180)
        modal.button("Retry", primary: true) {
            modal.dismissOverlay(); FileIncidentCoordinator.shared.resolved(report.root); FolderAccess.restoreAll(); retry()
        }
        let workspace = Catalogues.standard.root
        let workspaceIssue = report.issues.contains { issue in
            issue.url.pathExtension == "coldata" || ["Assets", GlobalAssets.folderName, "Keys"].contains(where: { issue.url.standardizedFileURL.path.hasPrefix(workspace.appendingPathComponent($0).standardizedFileURL.path + "/") })
        }
        let registration = Catalogues.standard.registry.first { row in row.url(in: workspace) == report.root.standardizedFileURL }
        let catalogueName = registration?.name ?? (report.root.standardizedFileURL == workspace.standardizedFileURL ? Catalogues.mainName : report.root.lastPathComponent)
        let repairable = report.issues.filter { issue in
            guard let handler = try? manager.handler(for: issue.url) else { return issue.url.pathExtension.isEmpty }
            return !handler.descriptor.archive || issue.url.pathExtension.lowercased() == "colmanifest"
        }
        var selectedProblem = repairable.first
        if repairable.count > 1 {
            let options = repairable.enumerated().map { "\($0.offset + 1). " + $0.element.url.lastPathComponent }
            let picker = SwissDropdown("File To Recover", value: options[0], options: options, allowsOwn: false, width: 448)
            picker.onChange = { value in if let index = options.firstIndex(of: value) { selectedProblem = repairable[index] } }
            modal.content(picker, height: 56)
        }
        if !repairable.isEmpty || !FileManager.default.fileExists(atPath: report.root.path) {
        modal.button("Locate Or Restore Selected File…") {
            let problem = selectedProblem
            let rootExists = FileManager.default.fileExists(atPath: report.root.path)
            let fileRecovery = rootExists && problem.map { !$0.url.pathExtension.isEmpty } == true
            let panel = NSOpenPanel(); panel.canChooseFiles = fileRecovery; panel.canChooseDirectories = !fileRecovery
            panel.allowsMultipleSelection = false; panel.prompt = "Locate"
            panel.message = fileRecovery ? "Select the original file or a backup. You will review the source and destination before any replacement." : "Select the original catalogue or workspace folder. Existing references are retained unless recovery succeeds."
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let selected = panel.url else { return }
                do {
                    try FolderAccess.authorize(selected)
                    if fileRecovery, let problem {
                        let index = workspaceIssue ? AppDataStore(root: workspace).url : CatalogueFiles.index(in: report.root)
                        var expected = problem.url.pathExtension == "colcat" ? registration?.id?.uuidString : nil
                        if let index, index != problem.url, let bytes = try? manager.read(index), let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                            expected = try manager.handler(for: index).references(object, at: index).first { $0.url.standardizedFileURL == problem.url.standardizedFileURL }?.identity ?? expected
                        }
                        let revision = try FileRevision.read(problem.url)
                        let confirmation = SwissFocusModal(title: "Restore This File?", message: "The selected document must match its expected type and identity. An existing original is retained under Backups/Recovered Originals.")
                        confirmation.content(fileManagementDetails("Source\n" + selected.path + "\n\nDestination\n" + problem.url.path), height: 180)
                        confirmation.button("Restore File", primary: true) {
                            do {
                                try manager.restoreOwnedFile(at: problem.url, from: selected, expectedIdentity: expected, revision: revision, workspace: workspace)
                                confirmation.dismissOverlay(); modal.dismissOverlay(); FileIncidentCoordinator.shared.resolved(report.root); retry()
                            } catch { showFailure(error, over: window) }
                        }
                        confirmation.button("Cancel") { confirmation.dismissOverlay() }; confirmation.present(over: view)
                    } else if workspaceIssue {
                        modal.dismissOverlay(); (NSApp.delegate as? AppDelegate)?.application(NSApp, open: [selected])
                    } else {
                        try manager.relinkCatalogue(name: catalogueName, from: report.root, to: selected, workspace: workspace)
                        modal.dismissOverlay(); FileIncidentCoordinator.shared.resolved(report.root); relinked()
                    }
                } catch { showFailure(error, over: window) }
            }
        }
        }
        if report.issues.contains(where: { [.inaccessible, .accessExpired, .volumeUnavailable].contains($0.state) }) {
        modal.button("Grant Folder Access…") {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = report.root
            panel.prompt = "Grant Access"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let selected = panel.url else { return }
                do { try FolderAccess.authorize(selected, renew: true); modal.dismissOverlay(); FileIncidentCoordinator.shared.resolved(report.root); retry() }
                catch { showFailure(error, over: window) }
            }
        }
        }
        if !workspaceIssue {
            modal.button("Detach Catalogue…") {
                modal.dismissOverlay()
                FileCatalogueRemovalWizard(name: catalogueName, window: window) { success in
                    if success { (NSApp.delegate as? AppDelegate)?.runSetupAssistant() }
                }.start()
            }
        } else {
            modal.button("Open Workspace…") { modal.dismissOverlay(); (NSApp.delegate as? AppDelegate)?.runSetupAssistant() }
        }
        if report.issues.contains(where: { (try? manager.handler(for: $0.url)) == nil && !$0.url.pathExtension.isEmpty }) {
            modal.content(fileManagementDetails("Linked ASE, ICC and image originals remain external files. Reconnect ASE files in Appbridge and ICC profiles in Colour Profiles; restore other originals in Finder, then choose Retry.", height: 100), height: 100)
        }
        modal.button("Keep References And Close") { modal.dismissOverlay() }
        modal.present(over: view)
    }
    static func showFailure(_ error: Error, over window: NSWindow) {
        guard let view = window.contentView else { return }
        let modal = SwissFocusModal(title: "Operation Could Not Finish", message: "Your files have been retained. Review the details before trying again.")
        modal.content(fileManagementDetails(error.localizedDescription, height: 140), height: 140)
        modal.button("Close") { modal.dismissOverlay() }; modal.present(over: view)
    }
    static func creatorDetails(over window: NSWindow) {
        guard let view = window.contentView else { return }
        let modal = SwissFocusModal(title: "File Creator Details", message: "New files record your creator name, local account name, date and Colorgain version. Existing creation details are retained when you edit them.")
        let name = modal.field("Creator Name", value: preferences.string(forKey: "fileCreator.displayName") ?? NSFullUserName())
        modal.button("Save Creator Name", primary: true) {
            let value = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 160 else { return }
            preferences.set(value, forKey: "fileCreator.displayName"); modal.dismissOverlay()
        }
        modal.button("Cancel") { modal.dismissOverlay() }; modal.present(over: view)
    }
}

final class FileCatalogueRemovalWizard {
    private weak var window: NSWindow?
    private let name: String
    private let completion: (Bool) -> Void
    private var modal: SwissFocusModal?
    private var plan: FileCatalogueRemovalPlan?
    private var outcome: FileCatalogueRemovalPlan.Outcome = .detach
    private var target = ""
    private var createTarget = false
    private var targetRevision: FileRevision?
    private var reviewText = ""

    init(name: String, window: NSWindow, completion: @escaping (Bool) -> Void) { self.name = name; self.window = window; self.completion = completion }
    private func show(title: String, message: String, details: String = "") -> SwissFocusModal? {
        modal?.dismissOverlay()
        guard let root = window?.contentView else { return nil }
        let next = SwissFocusModal(title: title, message: message)
        if !details.isEmpty { next.content(fileManagementDetails(details), height: 180) }
        modal = next
        // Buttons/content are added by caller before present so the modal sizes itself once.
        _ = root
        return next
    }
    private func present(_ modal: SwissFocusModal) { if let root = window?.contentView { modal.present(over: root) } }
    func start() {
        guard let modal = show(title: "Inspecting Catalogue", message: "Checking files, ownership and references. Nothing is being changed.") else { return }
        modal.button("Cancel") { self.close(false) }; present(modal)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Handler_File_Manager.shared.prepareCatalogueRemoval(name: self.name, catalogues: .standard) }
            DispatchQueue.main.async {
                guard self.modal?.superview != nil else { return }
                switch result {
                case .success(let plan): self.plan = plan; self.chooseOutcome()
                case .failure(let error): self.close(false); if let window = self.window { FileRecoveryPresenter.showFailure(error, over: window) }
                }
            }
        }
    }
    private func chooseOutcome() {
        guard let plan, let modal = show(title: "01 — Remove Catalogue", message: "Choose what happens to \(name). Detaching leaves all files in place.", details: plan.summary + "\n\n" + plan.root.path + (plan.inventory.complete ? "" : "\n\nSome files could not be verified. Detach And Leave Files is available; recover the files before transferring, archiving or binning.")) else { return }
        let options = plan.canTransfer ? ["Detach And Leave Files", "Archive Then Detach", "Transfer To Another Catalogue", "Transfer To A New Catalogue", "Bin Owned Files Then Detach"] : ["Detach And Leave Files"]
        let choice = SwissDropdown("What Happens To The Files", value: options[0], options: options, allowsOwn: false, width: 448)
        modal.content(choice, height: 56)
        modal.button("Continue", primary: true) {
            switch choice.text {
            case "Archive Then Detach": self.chooseArchive()
            case "Transfer To Another Catalogue": self.createTarget = false; self.chooseTarget()
            case "Transfer To A New Catalogue": self.createTarget = true; self.chooseTarget()
            case "Bin Owned Files Then Detach": self.outcome = .binOwnedFiles; self.reviewText = "Move \(plan.ownedFiles.count) verified owned files to the Bin. Leave \(plan.otherFiles.count) other files and all external/global assets intact. Empty folders may remain."; self.review()
            default: self.outcome = .detach; self.reviewText = "Remove this catalogue from the workspace list. All files, folder structure, external links and shared assets remain on disk. You can open the catalogue again later."; self.review()
            }
        }
        modal.button("Cancel") { self.close(false) }; present(modal)
    }
    private func chooseArchive() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "colshr") ?? .data]
        panel.nameFieldStringValue = filesystemName(name) + ".colshr"
        panel.message = "Save a verified catalogue archive outside the source folder. Linked individual ASE files are copied into the archive. ICC references remain references; originals are retained."
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            self.outcome = .archive(url); self.reviewText = "Create and verify \(url.path), then detach the catalogue. Original files remain in place. ICC dependencies are referenced rather than bundled. Hidden files, Backups, other catalogues and app-wide Assets remain at the original location. Unavailable files prevent archival."; self.review()
        }
    }
    private func chooseTarget() {
        guard let modal = show(title: "02 — Destination", message: "Source collections and custom project schemas will be preserved as separate collections. Existing destination content is retained.") else { return }
        if createTarget {
            let field = modal.field("New Catalogue Name", value: name + " Retained")
            modal.button("Preview Structure", primary: true) { self.target = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); if !self.target.isEmpty { self.mapping() } }
        } else {
            let choices = Catalogues.standard.names().filter { $0 != name }
            guard let first = choices.first else { chooseOutcome(); return }
            let picker = SwissDropdown("Destination Catalogue", value: first, options: choices, allowsOwn: false, width: 448)
            modal.content(picker, height: 56)
            modal.button("Preview Structure", primary: true) { self.target = picker.text; self.mapping() }
        }
        modal.button("Back") { self.chooseOutcome() }; modal.button("Cancel") { self.close(false) }; present(modal)
    }
    private func mapping() {
        guard let plan else { return }
        do {
            let source = try CatalogueTree.read(root: plan.root)
            let targetRoot = Catalogues.standard.directory(for: target)
            if createTarget && Catalogues.standard.names().contains(where: { $0.caseInsensitiveCompare(target) == .orderedSame }) { throw CatalogueError.nameTaken(target) }
            let existing = createTarget ? nil : try CatalogueTree.read(root: targetRoot)
            targetRevision = createTarget ? nil : try CatalogueFiles.index(in: targetRoot).map { try FileRevision.read($0) }
            func outline(_ schema: SchemaTrial.SchemaFile) -> String {
                if schema.collections.isEmpty { return "No Collections" }
                return schema.collections.map { collection in
                    let rows = SchemaTrial.rows(of: collection.stack).map { String(repeating: "  ", count: $0.level) + $0.node.name }
                    return collection.name + "\n" + rows.joined(separator: "\n")
                }.joined(separator: "\n\n")
            }
            reviewText = "Destination: \(target)\n\nExisting Structure\n" + (existing.map { outline($0.schema) } ?? "New empty catalogue")
                + "\n\nSource Structure To Preserve\n" + outline(source.schema)
                + "\n\nCollections and member-specific schemas remain intact. Duplicate identities become independent copies; conflicting names receive available names. Original files remain on disk after detaching. Immediately Available: \(plan.verified["Palettes", default: 0]) palettes, \(plan.verified["Typography Palettes", default: 0]) typography palettes and source project schemas.\nArchive Only: history, proof files, ASE and other source files are retained in a verified archive in the destination's Library/Archives folder."
            guard let modal = show(title: "03 — Structure Mapping", message: "Preserve the source schema alongside the destination schema. No project is flattened into a different template.", details: reviewText) else { return }
            modal.button("Use This Structure", primary: true) { self.outcome = .transfer(target: self.target, create: self.createTarget, expected: self.targetRevision); self.review() }
            modal.button("Back") { self.chooseTarget() }; modal.button("Cancel") { self.close(false) }; present(modal)
        } catch { if let window { FileRecoveryPresenter.showFailure(error, over: window) } }
    }
    private func review() {
        guard let plan, let modal = show(title: "04 — Review Removal", message: "The workspace list changes only after the selected operation succeeds. Cancel keeps the current registration and files.", details: plan.summary + "\n\n" + reviewText) else { return }
        modal.button("Confirm And Continue", primary: true) { self.execute() }
        modal.button("Back") { self.chooseOutcome() }; modal.button("Cancel") { self.close(false) }; present(modal)
    }
    private func execute() {
        guard let plan, let modal = show(title: "Updating Catalogue", message: "Applying the reviewed plan and verifying its files. Keep Colorgain open until this finishes.") else { return }
        let cancellation = FileOperationCancellation()
        modal.onDismiss = { cancellation.cancel() }
        modal.button("Cancel") { cancellation.cancel() }
        present(modal)
        let selected = outcome
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Handler_File_Manager.shared.executeCatalogueRemoval(plan, outcome: selected, cancellation: cancellation) }
            DispatchQueue.main.async {
                let wasCancelled = cancellation.isCancelled
                self.modal?.onDismiss = nil
                self.close(result.isSuccess)
                if case .failure(let error) = result, !wasCancelled, let window = self.window { FileRecoveryPresenter.showFailure(error, over: window) }
                if result.isSuccess, let root = self.window?.contentView {
                    let complete = SwissFocusModal(title: "Catalogue Removed", message: "The reviewed operation finished and the workspace list was updated.")
                    complete.content(fileManagementDetails(self.reviewText + "\n\nOriginal Catalogue Location\n" + plan.root.path), height: 180)
                    complete.button("Done") { complete.dismissOverlay() }; complete.present(over: root)
                }
            }
        }
    }
    private func close(_ success: Bool) { modal?.dismissOverlay(); modal = nil; completion(success) }
}

private extension Result where Success == Void { var isSuccess: Bool { if case .success = self { return true }; return false } }


/// Catalogue-row menus share the same file-management operations as the settings journeys.
enum CatalogueRowAction: String, CaseIterable {
    case remove = "Remove", backup = "Backup", export = "Export"
    var symbol: String {
        switch self {case .remove: return "trash";case .backup: return "externaldrive";case .export: return "square.and.arrow.up"}
    }
}

enum CatalogueRowActions {
    static func perform(_ action: CatalogueRowAction, name: String, library: LibraryController, window: NSWindow, changed: @escaping () -> Void) {
        if action == .remove {
            FileCatalogueRemovalWizard(name:name,window:window) { success in
                guard success else{return}
                if library.catalogue == name {
                    if let next=Catalogues.standard.names().first {library.open(catalogue:next)}
                    else {(NSApp.delegate as? AppDelegate)?.runSetupAssistant()}
                }
                changed()
            }.start()
            return
        }
        let root=Catalogues.standard.root
        if action == .backup {
            let stamp=ISO8601DateFormatter().string(from:Date()).replacingOccurrences(of:":",with:"-")
            let destination=root.appendingPathComponent("Backups/Catalogues",isDirectory:true)
                .appendingPathComponent(filesystemName(name)+"-"+stamp+"-"+UUID().uuidString.prefix(8)+".colshr")
            archive(name:name,to:destination,window:window,backup:true)
        } else {
            let panel=NSSavePanel()
            panel.title="Export Catalogue";panel.prompt="Export"
            panel.nameFieldStringValue=filesystemName(name)+".colshr"
            panel.message="Save a verified catalogue archive. Your originals stay in place. Optionally include My Library palettes and typography; external ICC originals remain references."
            let includeShared=ClickCursorButton(checkboxWithTitle:"Include My Library Palettes And Typography",target:nil,action:nil)
            panel.accessoryView=includeShared
            panel.beginSheetModal(for:window) { result in
                guard result == .OK,let destination=panel.url else{return}
                guard destination.pathExtension.lowercased() == "colshr" else {
                    FileRecoveryPresenter.showFailure(failure("Use the .colshr extension for a catalogue archive."),over:window);return
                }
                archive(name:name,to:destination,window:window,backup:false,includeShared:includeShared.state == .on)
            }
        }
    }
    private static func archive(name:String,to destination:URL,window:NSWindow,backup:Bool,includeShared:Bool=false) {
        guard let view=window.contentView else{return}
        let progress=SwissFocusModal(title:backup ? "Backing Up Catalogue":"Exporting Catalogue",message:"Checking and archiving “\(name)”. The catalogue stays in place. Missing files will be reported instead of producing an incomplete archive.")
        progress.present(over:view)
        let catalogues=Catalogues.standard
        DispatchQueue.global(qos:.userInitiated).async {
            let result=Result {try Handler_File_Manager.shared.createCatalogueArchive(name:name,catalogues:catalogues,to:destination,includeShared:includeShared)}
            DispatchQueue.main.async {
                progress.dismissOverlay()
                switch result {
                case .success:
                    guard let view=window.contentView else{return}
                    let done=SwissFocusModal(title:backup ? "Backup Saved":"Catalogue Exported",message:"“\(name)” remains in your library.\n\n\(destination.path)\n\nMy Library assets are bundled only when selected. ICC dependencies remain links unless embedded in a proof; individual ASE files are included. Monitored ASE folders must be converted to individual links before archiving.")
                    done.button("Show In Finder") {NSWorkspace.shared.activateFileViewerSelecting([destination]);done.dismissOverlay()}
                    done.button("Close",primary:true) {done.dismissOverlay()};done.present(over:view)
                case .failure(let error):FileRecoveryPresenter.showFailure(error,over:window)
                }
            }
        }
    }
}

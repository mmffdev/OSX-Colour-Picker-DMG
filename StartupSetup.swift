import AppKit

/// The first-open session is independent of permissions and survives a normal relaunch.
final class CatalogueSetupSession: Codable {
    var home = Catalogues.standard.root
    var parent = Catalogues.standard.folder
    var name = ""
    var createdName: String?
    var createdFolder: URL?
    var step = 0
    var draft = SplashDraft()
    private static let key = "catalogueSetupSession"
    static func load() -> CatalogueSetupSession {
        SetupDraft.load(Self.self, key: key) ?? CatalogueSetupSession()
    }
    func save() { SetupDraft.save(self, key: Self.key) }
    static func clear() { SetupDraft.clear(key: key) }
}

enum CatalogueSetup {
    enum Failure: LocalizedError {
        case invalidName, incomplete, missingCatalogue, changedCatalogue
        var errorDescription: String? {
            switch self {
            case .invalidName: return "Give the catalogue a name without path separators."
            case .incomplete: return "Finish the collection, category, first name, stream and asset choices before building."
            case .missingCatalogue: return "The catalogue folder is unavailable. Reconnect its drive or choose the folder again."
            case .changedCatalogue: return "This catalogue already contains work. Open it instead of building a new structure over it."
            }
        }
    }
    static func createBlank(_ raw: String, under parent: URL, catalogues: Catalogues = .standard) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", filesystemName(name) == name else { throw Failure.invalidName }
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path), !catalogues.names().contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw CatalogueError.nameTaken(name)
        }
        let store = LibraryStore(directory: folder, legacyURL: nil, name: name)
        try store.save(Library(), schema: SchemaTrial.SchemaFile(collections: [], places: [:]))
        try catalogues.registerChecked(name, at: folder)
        return name
    }
    static func ready(_ draft: SplashDraft) -> Bool {
        !draft.parties.isEmpty && draft.everyoneCategorised && draft.anyoneNamed && draft.streamsAnswered && draft.everyLeafGrouped
    }
    /// Uses the established nesting compiler unchanged. Errors propagate to the review page.
    static func build(_ draft: SplashDraft, into store: LibraryStore, requireBlank: Bool = true) throws {
        guard ready(draft) else { throw Failure.incomplete }
        guard CatalogueFiles.index(in: store.root) != nil else { throw Failure.missingCatalogue }
        let loaded = try CatalogueTree.read(root: store.root)
        if requireBlank && (!loaded.library.projects.isEmpty || !loaded.library.swatches.isEmpty || !loaded.library.colours.isEmpty || !loaded.schema.collections.isEmpty) {
            throw Failure.changedCatalogue
        }
        var schema = loaded.schema, library = loaded.library
        schema.collections.removeAll { c in c.id == SchemaTrial.firstCollection && c.folders.isEmpty && !schema.places.values.contains { $0.collection == c.id } }
        draft.build(into: &schema, library: &library)
        try store.save(library, schema: schema)
    }
}

/// Location controls share the existing setup grid; the nesting pages remain their own views.
final class SplashAppData: SplashSection {
    private let session: CatalogueSetupSession
    private let change = SwissButton("Change Folder", .secondary)
    init(index: Int, session: CatalogueSetupSession) {
        self.session = session
        super.init(index: index)
        change.target = self; change.action = #selector(choose)
        addSubview(change)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); change.frame = NSRect(x: left, y: line(15), width: 180, height: 32) }
    override func arrive() { super.arrive(); change.isEnabled = session.createdName == nil }
    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(step: "App Data", first: "Where your", second: "app data lives")
        drawWords("The app keeps its settings files, profiles and catalogue list here. Keep the default or choose an empty folder. Your catalogue has a separate location on the next page.")
        Design.attributed("App Data Folder", .caption).draw(x: left, baseline: row(11), width: width)
        Design.attributed(session.home.path, .body).draw(x: left, baseline: row(13), width: width)
    }
    @objc private func choose() {
        guard let window = window else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"; panel.directoryURL = session.home
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self = self, result == .OK, let url = panel.url else { return }
            do {
                try FolderAccess.authorize(url)
                self.session.home = url; self.session.save(); self.needsDisplay = true
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
}

final class SplashCatalogueLocation: SplashSection, NSTextFieldDelegate {
    private let session: CatalogueSetupSession
    private let field = SplashSection.field("Catalogue name")
    private let change = SwissButton("Choose Folder", .secondary)
    private let existing = SwissButton("Use Existing Catalogue", .secondary)
    var onExisting: ((URL) -> Void)?
    init(index: Int, session: CatalogueSetupSession) {
        self.session = session
        super.init(index: index)
        field.stringValue = session.name; field.delegate = self
        change.target = self; change.action = #selector(chooseParent)
        existing.target = self; existing.action = #selector(chooseExisting)
        for v in [field, change, existing] as [NSView] { addSubview(v) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var firstField: NSView? { session.createdName == nil ? field : nil }
    override var canContinue: Bool { !session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    override var marks: [SplashTreeView.Target: Int] { [.catalogue: 0] }
    override func arrive() {
        super.arrive(); field.stringValue = session.name
        field.isEnabled = session.createdName == nil
        change.title = session.createdName == nil ? "Choose Folder" : "Locate Catalogue"
        existing.isHidden = session.createdName != nil
    }
    override func layout() {
        super.layout(); place(field, row: 12)
        change.frame = NSRect(x: left, y: line(18), width: 180, height: 32)
        existing.frame = NSRect(x: left, y: line(21), width: 250, height: 32)
    }
    override func draw(_ dirtyRect: NSRect) {
        drawQuestion(step: "Your Catalogue", first: "Name it and", second: "choose its home")
        drawWords(session.createdName == nil ? "Create a blank catalogue here, then shape its contents in the following pages. Or open an existing catalogue with its structure intact." : "Your empty catalogue is saved here. The following pages shape its contents; the final review builds them.")
        Design.attributed("Catalogue Name", .caption).draw(x: left, baseline: row(11), width: width)
        hairline(row: 12, live: field.currentEditor() != nil)
        Design.attributed("Catalogue Folder", .caption).draw(x: left, baseline: row(15), width: width)
        Design.attributed((session.createdFolder ?? session.parent.appendingPathComponent(session.name)).path, .body).draw(x: left, baseline: row(17), width: width)
    }
    func controlTextDidChange(_ obj: Notification) {
        session.name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        session.draft.catalogueName = session.name
        session.save(); needsDisplay = true; splash?.changed()
    }
    @objc private func chooseParent() { chooseFolder(existing: false) }
    @objc private func chooseExisting() { chooseFolder(existing: true) }
    private func chooseFolder(existing: Bool) {
        guard let window = window else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = !existing
        let reconnect = !existing && session.createdName != nil
        panel.prompt = existing || reconnect ? "Open Catalogue" : "Use This Folder"
        panel.message = existing || reconnect ? "Choose the folder containing the catalogue file." : "The named catalogue will be created inside this folder."
        panel.directoryURL = session.parent
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self = self, result == .OK, let url = panel.url else { return }
            do {
                try FolderAccess.authorize(url)
                if existing { self.onExisting?(url) }
                else if reconnect {
                    guard CatalogueFiles.index(in: url) != nil, let name = self.session.createdName else { throw CatalogueSetup.Failure.missingCatalogue }
                    let read = try CatalogueTree.read(root: url)
                    guard read.library.projects.isEmpty, read.library.swatches.isEmpty, read.library.colours.isEmpty, read.schema.collections.isEmpty else { throw CatalogueSetup.Failure.changedCatalogue }
                    try Catalogues.standard.registerChecked(name, at: url)
                    self.session.createdFolder = url; self.session.save(); self.needsDisplay = true
                } else { self.session.parent = url; self.session.save(); self.needsDisplay = true }
            } catch { NSAlert(error: error).beginSheetModal(for: window) }
        }
    }
}

final class SplashReview: SplashSection {
    private let draft: SplashDraft
    private let location: () -> (String, URL, URL)
    init(index: Int, draft: SplashDraft, location: @escaping () -> (String, URL, URL)) {
        self.draft = draft; self.location = location
        super.init(index: index)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canContinue: Bool { CatalogueSetup.ready(draft) }
    override func draw(_ dirtyRect: NSRect) {
        let (name, folder, home) = location()
        drawQuestion(step: "Review", first: "Everything ready", second: "to build")
        drawWords("Review the complete tree on the left. Go back to adjust any choice. Build Catalogue writes the collections, nested folders, first projects or products, streams and assets, then opens the app.")
        for (i, pair) in [("Catalogue", name), ("Catalogue Folder", folder.path), ("App Data Folder", home.path)].enumerated() {
            Design.attributed(pair.0, .caption).draw(x: left, baseline: row(11 + i * 4), width: width)
            Design.attributed(pair.1, .body).draw(x: left, baseline: row(13 + i * 4), width: width)
        }
    }
}

import AppKit

/// Explicit opt-in native fixture. Uses its own preferences domain and temporary workspace,
/// never the user's existing trial. Cleanup runs after the app's session is finished.
enum FileHandlerNativeQA {
    private static var fixture: FileHandlerFixture?
    private static var suite: String?
    static func prepare() {
        guard CommandLine.arguments.contains("--file-handler-qa") else { return }
        let name = "com.mmffdev.mmffdevcolour3.qa." + UUID().uuidString
        setenv("MMFFDEV_COLOUR3_QA_PREFERENCES", name, 1)
        suite = name
        do {
            let value = try FileHandlerFixture(); fixture = value
            setenv("MMFFDEV_COLOUR3_HOME", value.root.path, 1)
            preferences.set(value.root.path, forKey: Catalogues.homeKey)
            try AppDataStore(root: value.root).update { manifest in
                manifest["settings"] = ["assistantDone": true, "setupDone": true, "splash": false, "sounds": false]
                manifest["defaultCatalogue"] = ["name": "First", "id": value.catalogue.id.uuidString]
            }
            print("Native file QA workspace: \(value.root.path)")
        } catch { fputs("Could not create native file QA fixture: \(error)\n", stderr); exit(1) }
    }
    static func present(library: LibraryController, window: NSWindow?) {
        guard let fixture, let window else { return }
        window.setContentSize(CommandLine.arguments.contains("--qa-compact") ? NSSize(width: 800, height: 460) : CommandLine.arguments.contains("--qa-minimum") ? NSSize(width: 1200, height: 800) : Design.App.size)
        window.center()
        if CommandLine.arguments.contains("--qa-recovery") {
            do {
                let backup = fixture.root.appendingPathComponent("Recovery Source.colpal")
                try FileManager.default.moveItem(at: fixture.palette, to: backup)
                library.reload()
            } catch { FileRecoveryPresenter.showFailure(error, over: window) }
        } else {
            FileCatalogueRemovalWizard(name: "First", window: window) { _ in library.reload() }.start()
        }
    }
    static func cleanup() {
        fixture?.remove(); fixture = nil
        if let suite { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suite = nil
    }
}

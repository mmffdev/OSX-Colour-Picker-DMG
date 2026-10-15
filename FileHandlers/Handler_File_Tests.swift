import Foundation

func runFileRecoveryAndTransactionTests(check: (Bool, String) -> Void) {
    print("File inventory, incidents and transaction recovery")
    let fm = FileManager.default
    do {
        let fixture = try FileHandlerFixture()
        defer { fixture.remove() }
        let manager = Handler_File_Manager.shared
        let index = fixture.first.appendingPathComponent("First.colcat")
        check(manager.inspectCatalogue(index).complete, "Complete catalogue passes read-only inventory")
        let manifestBefore = try Data(contentsOf: AppDataStore(root: fixture.root).url)
        let filters = MetadataFilterStore(catalogueURL: index, appData: AppDataStore(root: fixture.root))
        _ = try filters.read(catalogueID: fixture.catalogue.id)
        check(try Data(contentsOf: AppDataStore(root: fixture.root).url) == manifestBefore, "Reading metadata filters does not repair or rewrite the manifest")
        let removedBytes = try Data(contentsOf: fixture.palette)
        try fm.removeItem(at: fixture.palette)
        let missing = manager.inspectCatalogue(index)
        check(!missing.complete && missing.issues.contains { $0.state == .missing }, "Missing child makes catalogue inventory explicitly incomplete")
        let coordinator = FileIncidentCoordinator()
        check(coordinator.shouldPresent(root: fixture.first, issues: missing.issues) && !coordinator.shouldPresent(root: fixture.first, issues: missing.issues), "Repeated unchanged file failures produce one incident")
        coordinator.resolved(fixture.first)
        check(coordinator.shouldPresent(root: fixture.first, issues: missing.issues), "A resolved incident can report a genuinely new recurrence")
        try removedBytes.write(to: fixture.palette)
        let existing = LibraryStore(directory: fixture.first, legacyURL: nil, assetsHome: fixture.root)
        _ = try existing.load()
        let relocated = fixture.root.appendingPathComponent("Offline First")
        try fm.moveItem(at: fixture.first, to: relocated)
        check((try? existing.load()) == nil && !fm.fileExists(atPath: fixture.first.path), "Opening a missing catalogue does not recreate its folder")
        try fm.moveItem(at: relocated, to: fixture.first)
        var denied = FileSystemAccess()
        denied.list = { _ in throw CocoaError(.fileReadNoPermission) }
        let blocked = Handler_File_Manager(filesystem: denied).inventory(root: fixture.first)
        check(!blocked.complete && blocked.issues.first?.state == .inaccessible, "Denied enumeration remains an access failure rather than an empty folder")

        let file = AppDataStore(root: fixture.root).url
        let original = try Data(contentsOf: file)
        let unrelated = fixture.root.appendingPathComponent("Added By Another App.txt")
        do {
            try manager.withTransaction(home: fixture.root) {
                try manager.update(file) { $0["transactionTest"] = "intermediate" }
                try Data("external".utf8).write(to: unrelated)
                throw failure("Injected failure after write")
            }
        } catch {}
        check(try Data(contentsOf: file) == original, "Failed operation restores only its touched manifest bytes")
        check(try Data(contentsOf: unrelated) == Data("external".utf8), "Rollback retains an unrelated file added during the operation")
        for phase in ["before-intent", "after-intent", "before-commit"] {
            do {
                try manager.withTransaction(home: fixture.root, fault: { if $0 == phase { throw failure("Injected " + phase) } }) {
                    try manager.update(file) { $0["phase"] = phase }
                }
            } catch {}
            check(try Data(contentsOf: file) == original, "Transaction interruption at \(phase) retains original content")
        }

        try manager.withTransaction(home: fixture.root, fault: { if $0 == "before-cleanup" { throw failure("Injected cleanup failure") } }) {
            try manager.update(file) { $0["committedDespiteCleanup"] = true }
        }
        let committedBytes = try Data(contentsOf: file)
        try FileOperationTransaction.recover(home: fixture.root)
        check(try Data(contentsOf: file) == committedBytes, "Cleanup failure retains committed data and restart cleanup never rolls it back")
        try original.write(to: file, options: .atomic) // Reset only this disposable fixture.

        let removedIndex = fixture.first.appendingPathComponent("First.colcat")
        let indexBytes = try Data(contentsOf: removedIndex)
        let interruptedRemoval = try FileOperationTransaction(home: fixture.root)
        try interruptedRemoval.prepare(removedIndex, after: nil)
        try fm.removeItem(at: removedIndex)
        _ = try WorkspaceInventory.read(root: fixture.root)
        check(try Data(contentsOf: removedIndex) == indexBytes, "Workspace startup replays recovery before classifying a journalled missing catalogue index")

        // Simulate abrupt process death: persist intent and published bytes, then use a fresh recovery reader.
        let pending = try FileOperationTransaction(home: fixture.root)
        var object = try JSONSerialization.jsonObject(with: original) as! [String: Any]
        object["restartTest"] = true
        let changed = try JSONSerialization.data(withJSONObject: object)
        try pending.prepare(file, after: Sharing.sha256(changed))
        try changed.write(to: file, options: .atomic)
        try FileOperationTransaction.recover(home: fixture.root)
        try FileOperationTransaction.recover(home: fixture.root)
        check(try Data(contentsOf: file) == original, "Restart recovery is repeatable and restores the journalled pre-operation file")

        let conflicted = try FileOperationTransaction(home: fixture.root)
        try conflicted.prepare(file, after: Sharing.sha256(changed))
        object["externalNewerChange"] = true
        let external = try JSONSerialization.data(withJSONObject: object)
        try external.write(to: file)
        do { try conflicted.rollback(); check(false, "External conflict must be retained") }
        catch { check(try Data(contentsOf: file) == external && fm.fileExists(atPath: conflicted.directory.path), "Rollback keeps an external edit and its recovery snapshot rather than overwriting either") }
        // Explicit test resolution; never a production fallback.
        try original.write(to: file)
        try conflicted.rollback()
    } catch { check(false, "File recovery/transactions: \(error)") }
}

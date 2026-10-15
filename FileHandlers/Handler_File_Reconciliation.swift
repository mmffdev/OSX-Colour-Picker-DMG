import Foundation

/// A proposed disk-to-index update. Observation never publishes it; acceptance is revision-bound.
struct FileCatalogueReconciliationPlan {
    let library: Library
    let schema: SchemaTrial.SchemaFile
    let notes: [String]
    let revisions: [String: FileRevision]
    let folders: Set<String>
    init(library: Library, schema: SchemaTrial.SchemaFile, notes: [String], inventory: FileInventory) throws {
        self.library = library; self.schema = schema; self.notes = notes
        revisions = try Dictionary(uniqueKeysWithValues: inventory.files.map { ($0.path, try FileRevision.read($0)) })
        folders = Set(inventory.folders.map(\.path))
    }
}

extension LibraryStore {
    func acceptDiskReconciliation() throws {
        guard let plan = pendingReconciliation else { return }
        let manager = Handler_File_Manager.shared
        try manager.withTransaction(home: assetsHome ?? root) {
            let observed = manager.inventory(root: root)
            guard observed.complete, Set(observed.files.map(\.path)) == Set(plan.revisions.keys), Set(observed.folders.map(\.path)) == plan.folders else { throw failure("The folders changed during review. Retry to inspect them again.") }
            for (path, revision) in plan.revisions where try FileRevision.read(URL(fileURLWithPath: path)) != revision { throw failure("A file changed during review. Retry before updating catalogue references.") }
            try save(plan.library, schema: plan.schema)
        }
    }
}

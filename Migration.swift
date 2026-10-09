import Foundation

// ---------- Bringing an earlier layout across ----------
//
// Until 2026-10-09 a catalogue was an index listing its members, each member a folder of Space,
// Config, History, Palettes and Channels, with Unfiled for what belonged to no member, a schema
// file beside the index, and a history of whole snapshots. Before that, one library.json held
// everything. The first time this version opens either, it copies the old folders whole into a
// backup, reads everything, clears the old layout and writes the tree. Nothing is read from the
// old layout after that; the backup is kept for the user to look at or go back to.
//
// Version 2, the tree of folders each with a file describing it, comes across in place: backed up the
// same way, read, written as version 3 into the same folders, which move and rename only where the
// structure says, and then the old documents of each level are taken out. Anything else the user put
// in the folders stays where it is.

enum Migration {
    struct Report: Equatable {
        var backup: URL
        var members: Int
        var palettes: Int
        /// Member folders the index did not list, whose palettes went to the Library.
        var orphans: [String]
        var notes: [String]
    }

    enum Fault: LocalizedError {
        case backupFailed(URL, Error)
        case backupIncomplete(URL)
        case unreadable(URL)
        var errorDescription: String? {
            switch self {
            case .backupFailed(let u, let e): return "The catalogue could not be backed up to \(u.path), so nothing was changed: \(e.localizedDescription)"
            case .backupIncomplete(let u): return "The backup at \(u.path) does not match the catalogue, so nothing was changed."
            case .unreadable(let u): return "\(u.path) could not be read, so the catalogue was not brought across."
            }
        }
    }

    private static let fm = FileManager.default
    /// What each catalogue's bringing across did, by its folder, until the controller that opens it takes the report: whichever
    /// store happened to read the catalogue first did the work, and the user is still told once.
    static var reports: [String: Report] = [:]
    /// What belongs to the app's home, not to the catalogue at its root.
    private static let homeItems: Set<String> = ["Catalogues", "catalogues.json", TreeFiles.backups]

    /// Whether a folder holds a catalogue in an earlier layout: a version 2 tree, a version 1 index, or the one file.
    static func needed(in root: URL) -> Bool {
        if CatalogueFiles.index(in: root) != nil { return false }
        if let url = CatalogueFiles.legacyIndex(in: root) {
            guard let data = try? Data(contentsOf: url) else { return false }
            if LegacyTree.decode(data) != nil { return true }
            return (try? ColourFiles.decoder().decode(CatalogueDocument.self, from: data))?.format == "colour-catalogue"
        }
        return fm.fileExists(atPath: root.appendingPathComponent("library.json").path)
    }
    /// Whether what is there is a version 2 tree.
    static func isVersion2(_ root: URL) -> Bool { LegacyTree.index(in: root) != nil }

    /// Brings the catalogue in `root` across: backup first, then read, clear, write.
    @discardableResult
    static func run(root: URL, name: String, now: Date = Date()) throws -> Report {
        if isVersion2(root) { return try runVersion2(root: root, name: name, now: now) }
        let backup = try backUp(root: root, name: name, now: now)
        var notes: [String] = [], orphans: [String] = []
        var lib: Library
        // The members, as the index knew them; an earlier version's one file; or nothing readable.
        if let index = CatalogueFiles.legacyIndex(in: root) {
            let master = root.standardizedFileURL == Catalogues.standard.root.standardizedFileURL ? ProjectFiles.folder : nil
            guard let loaded = try? CatalogueFiles.read(index: index, master: master) else { throw Fault.unreadable(index) }
            lib = loaded.library
            for id in loaded.unavailable {
                let name = lib.project(id)?.name ?? id.uuidString
                notes.append("\(name) could not be reached and was not brought across; it is in the backup as the index listed it")
                lib.projects.removeAll { $0.id == id }
            }
        } else {
            let one = root.appendingPathComponent("library.json")
            guard let data = try? Data(contentsOf: one), let read = try? JSONDecoder.library.decode(Library.self, from: data) else { throw Fault.unreadable(one) }
            lib = read
        }
        // Member folders the index did not list: their palettes go to the Library, named for where they were.
        let known = Set(lib.projects.map { $0.id })
        for (folder, file) in oldMemberFolders(under: root) {
            guard let whole = try? ProjectFiles.read(file), !known.contains(whole.project.id) else { continue }
            var taken = 0
            for var p in whole.palettes where lib.swatch(p.id) == nil {
                p.projectID = nil
                lib.swatches.append(p)
                taken += 1
            }
            for c in whole.colours where !lib.colours.contains(where: { $0.hex == c.hex }) { lib.colours.append(c) }
            for var t in whole.tags where t.projectID == whole.project.id && lib.info(forTag: t.name) == nil {
                t.projectID = nil
                lib.tagInfo.append(t)
            }
            let where_ = folder.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
            orphans.append("\(whole.project.name) in \(where_)")
            notes.append("\(whole.project.name) in \(where_) was not in the index: its \(plural(taken, "palette")) went to the Library")
        }
        // Every member lives in the tree now: a folder of its own elsewhere is left in the backup.
        for i in lib.projects.indices { lib.projects[i].folder = nil; lib.projects[i].fileKnown = nil }
        // The schema, from its file beside the index; every member follows its Master Template unless it had a tree of its own.
        let schema = legacySchema(in: root)
        // The old layout goes, now that the backup holds it whole.
        for item in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where !homeItems.contains(item) && !item.hasPrefix(".") {
            try fm.removeItem(at: root.appendingPathComponent(item))
        }
        let index = root.appendingPathComponent(filesystemName(name) + "." + ColourFiles.catalogue)
        try CatalogueTree.write(lib, schema: schema, index: index, name: name, now: now)
        Diagnostics.log("migration", "\(name): \(lib.projects.count) members, \(lib.swatches.count) palettes, backup at \(backup.path)" + (notes.isEmpty ? "" : "; " + notes.joined(separator: "; ")))
        let report = Report(backup: backup, members: lib.projects.count, palettes: lib.swatches.count, orphans: orphans, notes: notes)
        reports[root.standardizedFileURL.path] = report
        return report
    }

    /// A version 2 tree brought across in place: backup, read, write version 3 into the same folders, then the old documents go.
    private static func runVersion2(root: URL, name: String, now: Date) throws -> Report {
        guard let legacy = CatalogueFiles.legacyIndex(in: root) else { throw Fault.unreadable(root) }
        let backup = try backUp(root: root, name: name, now: now)
        guard let loaded = try? LegacyTree.read(root: root) else { throw Fault.unreadable(legacy) }
        let carry = LegacyTree.describe(root: root, loaded: loaded)
        let index = root.appendingPathComponent(filesystemName(name) + "." + ColourFiles.catalogue)
        // The history keeps its steps; only its extension changes.
        let oldHistory = legacy.deletingPathExtension().appendingPathExtension(ColourFiles.legacyHistory)
        let newHistory = HistoryStore.url(beside: index)
        if fm.fileExists(atPath: oldHistory.path) && !fm.fileExists(atPath: newHistory.path) { try fm.moveItem(at: oldHistory, to: newHistory) }
        try CatalogueTree.write(loaded.library, schema: loaded.schema, index: index, name: name, now: now, carry: carry)
        // Each level's own document, the Library's lists and the template files: the structure file holds all of it now.
        let old: Set<String> = [LegacyTree.collection, LegacyTree.workGroup, LegacyTree.assets, LegacyTree.template]
        func clear(_ dir: URL, depth: Int) {
            guard depth < 16 else { return }
            for name in CatalogueTree.names(in: dir) {
                let url = dir.appendingPathComponent(name)
                if CatalogueTree.isFolder(url) { if !(depth == 0 && homeItems.contains(name)) { clear(url, depth: depth + 1) }; continue }
                if old.contains((name as NSString).pathExtension.lowercased()) { try? fm.removeItem(at: url) }
            }
        }
        clear(root, depth: 0)
        try? fm.removeItem(at: legacy)
        let templates = root.appendingPathComponent(TreeFiles.templates)
        if CatalogueTree.isFolder(templates) && CatalogueTree.names(in: templates).isEmpty { try? fm.removeItem(at: templates) }
        let lib = loaded.library
        Diagnostics.log("migration", "\(name): version 2 to 3, \(lib.projects.count) members, \(lib.swatches.count) palettes, backup at \(backup.path)")
        let report = Report(backup: backup, members: lib.projects.count, palettes: lib.swatches.count, orphans: [], notes: loaded.notes)
        reports[root.standardizedFileURL.path] = report
        return report
    }

    /// The schema an earlier version kept beside the index, or a fresh one.
    static func legacySchema(in root: URL) -> SchemaTrial.SchemaFile {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("schema.colschema")),
              let read = try? JSONDecoder().decode(SchemaTrial.SchemaFile.self, from: data), !read.collections.isEmpty else { return .fresh }
        var f = read
        f.templates = nil
        return f
    }

    /// Folders under the root, three deep, that hold a member's file as an earlier version wrote it.
    static func oldMemberFolders(under root: URL) -> [(folder: URL, file: URL)] {
        var out: [(URL, URL)] = []
        func walk(_ dir: URL, depth: Int) {
            guard depth <= 3 else { return }
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !name.hasPrefix(".") {
                let sub = dir.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue else { continue }
                if homeItems.contains(sub.lastPathComponent) && depth == 0 { continue }
                for home in [ProjectFiles.projectFolder, ProjectFiles.earlierProjectFolder, ProjectFiles.configFolder] {
                    let inside = sub.appendingPathComponent(home)
                    if let file = ((try? fm.contentsOfDirectory(at: inside, includingPropertiesForKeys: nil)) ?? []).first(where: { ProjectFiles.isProjectFile($0) }) {
                        out.append((sub, file))
                        break
                    }
                }
                walk(sub, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return out
    }

    /// Copies the catalogue's own files and folders whole into a folder named for it and the date: beside the
    /// catalogue when it has a folder of its own, under Backups when it sits at the app's home. Counts and sizes are
    /// checked before anything else happens.
    static func backUp(root: URL, name: String, now: Date = Date()) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        let isHome = fm.fileExists(atPath: root.appendingPathComponent("catalogues.json").path) || fm.fileExists(atPath: root.appendingPathComponent("Catalogues").path)
        let label = "\(isHome ? name : root.lastPathComponent) Before Migration \(f.string(from: now))"
        let parent = isHome ? root.appendingPathComponent(TreeFiles.backups) : root.deletingLastPathComponent()
        let dest = parent.appendingPathComponent(uniqueName(label, among: (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []))
        let items = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { !homeItems.contains($0) && !$0.hasPrefix(".") }
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for item in items { try fm.copyItem(at: root.appendingPathComponent(item), to: dest.appendingPathComponent(item)) }
        } catch {
            try? fm.removeItem(at: dest)
            throw Fault.backupFailed(dest, error)
        }
        let before = items.reduce((0, 0)) { let m = measure(root.appendingPathComponent($1)); return ($0.0 + m.0, $0.1 + m.1) }
        let after = measure(dest)
        guard before == after else { try? fm.removeItem(at: dest); throw Fault.backupIncomplete(dest) }
        return dest
    }

    /// How many files there are under a path, and their bytes together.
    static func measure(_ url: URL) -> (files: Int, bytes: Int) {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return (0, 0) }
        if !isDir.boolValue {
            return (1, (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        }
        return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.reduce((0, 0)) { let m = measure(url.appendingPathComponent($1)); return ($0.0 + m.0, $0.1 + m.1) }
    }
}

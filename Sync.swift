import AppKit

// ---------- Merging two copies of a library ----------
//
// Nothing is dropped unless one side deliberately deleted it *after* the other side last
// added it. Everything else from both sides is kept.

/// Combines both copies. Order follows `local`, with anything new from `remote` after it.
func mergeLibraries(local: Library, remote: Library) -> Library {
    var out = Library()
    out.version = max(local.version, remote.version)

    // Latest deletion per thing.
    var buried: [String: Tombstone] = [:]
    var buriedOrder: [String] = []
    for t in local.deleted + remote.deleted {
        let k = "\(t.kind.rawValue)|\(t.key)"
        if let seen = buried[k] { if t.deletedAt > seen.deletedAt { buried[k] = t } }
        else { buried[k] = t; buriedOrder.append(k) }
    }
    out.deleted = buriedOrder.map { buried[$0]! }
    func deletedAt(_ kind: Tombstone.Kind, _ key: String) -> Date { buried["\(kind.rawValue)|\(key)"]?.deletedAt ?? .distantPast }

    // Projects: union, newer name, position and details win, deleted ones stay deleted.
    var projectIDs: [UUID] = []
    var projectSides: [UUID: (Project?, Project?)] = [:]
    for p in local.projects { projectIDs.append(p.id); projectSides[p.id] = (p, nil) }
    for p in remote.projects {
        if projectSides[p.id] == nil { projectIDs.append(p.id); projectSides[p.id] = (nil, p) } else { projectSides[p.id]!.1 = p }
    }
    for id in projectIDs {
        let (l, r) = projectSides[id]!
        var p = (l ?? r)!
        guard deletedAt(.project, id.uuidString) < p.createdAt else { continue }
        if let l = l, let r = r {
            if (r.nameChangedAt ?? r.createdAt) > (l.nameChangedAt ?? l.createdAt) { p.name = r.name; p.nameChangedAt = r.nameChangedAt }
            if (r.positionChangedAt ?? .distantPast) > (l.positionChangedAt ?? .distantPast) { p.position = r.position; p.positionChangedAt = r.positionChangedAt }
            if (r.detailsChangedAt ?? .distantPast) > (l.detailsChangedAt ?? .distantPast) { p.details = r.details; p.detailsChangedAt = r.detailsChangedAt }
            if (r.profileChangedAt ?? .distantPast) > (l.profileChangedAt ?? .distantPast) { p.profile = r.profile; p.profileChangedAt = r.profileChangedAt }
        }
        out.projects.append(p)
    }

    // What is known about each tag: one record per name, the newer one kept.
    var infos: [String: TagInfo] = [:]
    for t in local.tagInfo + remote.tagInfo {
        let k = t.name.lowercased()
        if let have = infos[k], have.changedAt >= t.changedAt { continue }
        infos[k] = t
    }
    out.tagInfo = infos.values.sorted { $0.name.lowercased() < $1.name.lowercased() }

    // Swatches that survive, local order first.
    var swatchIDs: [UUID] = []
    var sides: [UUID: (local: Swatch?, remote: Swatch?)] = [:]
    for s in local.swatches { swatchIDs.append(s.id); sides[s.id] = (s, nil) }
    for s in remote.swatches {
        if sides[s.id] == nil { swatchIDs.append(s.id); sides[s.id] = (nil, s) } else { sides[s.id]!.remote = s }
    }
    swatchIDs.removeAll { id in
        let created = (sides[id]!.local ?? sides[id]!.remote)!.createdAt
        return deletedAt(.swatch, id.uuidString) >= created
    }

    for id in swatchIDs {
        let (l, r) = sides[id]!
        let base = (l ?? r)!
        var name = base.name, changed = base.nameChangedAt
        if let l = l, let r = r, (r.nameChangedAt ?? r.createdAt) > (l.nameChangedAt ?? l.createdAt) {
            name = r.name; changed = r.nameChangedAt
        }
        var favourite = base.isFavourite, favouriteChanged = base.favouriteChangedAt
        if let l = l, let r = r, (r.favouriteChangedAt ?? .distantPast) > (l.favouriteChangedAt ?? .distantPast) {
            favourite = r.isFavourite; favouriteChanged = r.favouriteChangedAt
        }
        var placed = (project: base.projectID, position: base.position, at: base.placedAt)
        if let l = l, let r = r, (r.placedAt ?? .distantPast) > (l.placedAt ?? .distantPast) {
            placed = (r.projectID, r.position, r.placedAt)
        }
        if let p = placed.project, !out.projects.contains(where: { $0.id == p }) { placed.project = nil } // its project is gone
        var tags = (list: base.tags, at: base.tagsChangedAt)
        if let l = l, let r = r, (r.tagsChangedAt ?? .distantPast) > (l.tagsChangedAt ?? .distantPast) { tags = (r.tags, r.tagsChangedAt) }
        // Its place under Favourites and in the Palettes list: each is its own arrangement, newer wins.
        var starred = (position: base.favouritePosition, at: base.favouritePlacedAt)
        if let l = l, let r = r, (r.favouritePlacedAt ?? .distantPast) > (l.favouritePlacedAt ?? .distantPast) { starred = (r.favouritePosition, r.favouritePlacedAt) }
        var listed = (position: base.listPosition, at: base.listPlacedAt)
        if let l = l, let r = r, (r.listPlacedAt ?? .distantPast) > (l.listPlacedAt ?? .distantPast) { listed = (r.listPosition, r.listPlacedAt) }
        // A Typography palette's pairings: the newer list whole, as with tags.
        var styles = (list: base.styles, at: base.stylesChangedAt)
        if let l = l, let r = r, (r.stylesChangedAt ?? .distantPast) > (l.stylesChangedAt ?? .distantPast) { styles = (r.styles, r.stylesChangedAt) }
        var order: [String] = [], dates: [String: Date] = [:]
        var names: [String: (name: String?, at: Date?)] = [:]   // the newer of the two names for each colour
        var notes: [String: (note: String?, at: Date?)] = [:]   // and the newer of the two descriptions
        for e in (l?.entries ?? []) + (r?.entries ?? []) {
            let cutoff = max(deletedAt(.entry, Library.entryKey(id, e.hex)), deletedAt(.colour, e.hex))
            guard e.addedAt > cutoff else { continue }
            if let seen = dates[e.hex] { dates[e.hex] = min(seen, e.addedAt) }
            else { dates[e.hex] = e.addedAt; order.append(e.hex) }
            if names[e.hex] == nil || (e.nameChangedAt ?? .distantPast) > (names[e.hex]?.at ?? .distantPast) { names[e.hex] = (e.name, e.nameChangedAt) }
            if notes[e.hex] == nil || (e.noteChangedAt ?? .distantPast) > (notes[e.hex]?.at ?? .distantPast) { notes[e.hex] = (e.note, e.noteChangedAt) }
        }
        out.swatches.append(Swatch(id: id, name: name, createdAt: base.createdAt,
                                   entries: order.map { SwatchEntry(hex: $0, addedAt: dates[$0]!, name: names[$0]?.name, nameChangedAt: names[$0]?.at, note: notes[$0]?.note, noteChangedAt: notes[$0]?.at) },
                                   nameChangedAt: changed, isFavourite: favourite,
                                   favouriteChangedAt: favouriteChanged,
                                   isCustom: l?.isCustom ?? r?.isCustom,
                                   projectID: placed.project, position: placed.position, placedAt: placed.at,
                                   tags: tags.list, tagsChangedAt: tags.at,
                                   favouritePosition: starred.position, favouritePlacedAt: starred.at,
                                   listPosition: listed.position, listPlacedAt: listed.at,
                                   styles: styles.list, stylesChangedAt: styles.at,
                                   copiedFrom: l?.copiedFrom ?? r?.copiedFrom,
                                   bucketID: ((l?.placedAt ?? .distantPast) >= (r?.placedAt ?? .distantPast) ? l ?? r : r ?? l)?.bucketID,
                                   claim: l?.claim ?? r?.claim))
        out.swatches[out.swatches.count - 1].review = PaletteAssetHandler.mergedReview(l?.review,r?.review)
        let metadataPick=(l?.metadata?.changedAt ?? .distantPast) >= (r?.metadata?.changedAt ?? .distantPast) ? l?.metadata:r?.metadata
        out.swatches[out.swatches.count - 1].metadata=metadataPick
        // The colour profile: the newer choice.
        let pick = (l?.profileChangedAt ?? .distantPast) >= (r?.profileChangedAt ?? .distantPast) ? l ?? r : r ?? l
        out.swatches[out.swatches.count - 1].profile = pick?.profile
        out.swatches[out.swatches.count - 1].profileChangedAt = pick?.profileChangedAt
        // What the palette is for: each purpose as it was last changed, on either Mac.
        out.swatches[out.swatches.count - 1].purposes = Library.merged(l?.purposes, r?.purposes)
        // The purpose it is turned to: the newer choice.
        let turned = (l?.purposeChangedAt ?? .distantPast) >= (r?.purposeChangedAt ?? .distantPast) ? l ?? r : r ?? l
        out.swatches[out.swatches.count - 1].purpose = turned?.purpose
        out.swatches[out.swatches.count - 1].purposeChangedAt = turned?.purposeChangedAt
    }

    // Colours: kept if picked after their last deletion, or still in use by a surviving swatch.
    var order: [String] = [], dates: [String: Date] = [:]
    func keep(_ hex: String, _ date: Date) {
        guard date > deletedAt(.colour, hex) else { return }
        if let seen = dates[hex] { dates[hex] = min(seen, date) } else { dates[hex] = date; order.append(hex) }
    }
    for c in local.colours + remote.colours { keep(c.hex, c.pickedAt) }
    for s in out.swatches { for e in s.entries where dates[e.hex] == nil { keep(e.hex, e.addedAt) } }
    out.colours = order.map { hex in
        let l = local.colours.first { $0.hex == hex }, r = remote.colours.first { $0.hex == hex }
        var tags = (l ?? r)?.tags, at = (l ?? r)?.tagsChangedAt
        if let l = l, let r = r, (r.tagsChangedAt ?? .distantPast) > (l.tagsChangedAt ?? .distantPast) { tags = r.tags; at = r.tagsChangedAt }
        let metadata=(l?.metadata?.changedAt ?? .distantPast) >= (r?.metadata?.changedAt ?? .distantPast) ? l?.metadata:r?.metadata
        return Colour(hex: hex, pickedAt: dates[hex]!, tags: tags, tagsChangedAt: at,
                      source: (l ?? r)?.source, master: (l ?? r)?.master, kind: (l ?? r)?.kind,metadata:metadata)
    }

    // Colour profiles: one copy of each, the newer kept.
    for profile in local.colourProfiles + remote.colourProfiles {
        if let i = out.colourProfiles.firstIndex(where: { $0.id == profile.id }) {
            if profile.changedAt > out.colourProfiles[i].changedAt { out.colourProfiles[i] = profile }
        } else {
            out.colourProfiles.append(profile)
        }
    }

    if let active = local.activeSwatchID, out.swatch(active) != nil { out.activeSwatchID = active }
    return out
}

/// `winner`, plus a record that everything only `loser` had was deliberately dropped —
/// so the choice holds when the other Mac next syncs.
func replacing(_ loser: Library, with winner: Library, at date: Date = Date()) -> Library {
    var out = winner
    let kept = Set(winner.colours.map { $0.hex })
    for c in loser.colours where !kept.contains(c.hex) { out.bury(.colour, c.hex, at: date) }
    for p in loser.projects where winner.project(p.id) == nil { out.bury(.project, p.id.uuidString, at: date) }
    for s in loser.swatches {
        guard let w = winner.swatch(s.id) else { out.bury(.swatch, s.id.uuidString, at: date); continue }
        let entries = Set(w.entries.map { $0.hex })
        for e in s.entries where !entries.contains(e.hex) { out.bury(.entry, Library.entryKey(s.id, e.hex), at: date) }
    }
    // Anything the loser had deleted but the winner keeps counts as re-created just after that
    // deletion, so the other Mac's deletion record no longer outranks it.
    for t in loser.deleted {
        let revived = t.deletedAt.addingTimeInterval(1)
        switch t.kind {
        case .colour:
            if let i = out.colours.firstIndex(where: { $0.hex == t.key }), out.colours[i].pickedAt <= t.deletedAt { out.colours[i].pickedAt = revived }
        case .swatch:
            if let i = out.swatches.firstIndex(where: { $0.id.uuidString == t.key }), out.swatches[i].createdAt <= t.deletedAt { out.swatches[i].createdAt = revived }
        case .project:
            if let i = out.projects.firstIndex(where: { $0.id.uuidString == t.key }), out.projects[i].createdAt <= t.deletedAt { out.projects[i].createdAt = revived }
        case .entry:
            let parts = t.key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let i = out.swatches.firstIndex(where: { $0.id.uuidString == parts[0] }),
                  let e = out.swatches[i].entries.firstIndex(where: { $0.hex == parts[1] }) else { continue }
            if out.swatches[i].entries[e].addedAt <= t.deletedAt { out.swatches[i].entries[e].addedAt = revived }
        }
    }
    if let active = loser.activeSwatchID, out.swatch(active) != nil { out.activeSwatchID = active }
    return out
}

/// The same library regardless of ordering or which swatch is the pick target on this Mac.
func canonical(_ lib: Library) -> Library {
    var out = lib
    out.activeSwatchID = nil
    out.colours.sort { $0.hex < $1.hex }
    out.projects.sort { $0.id.uuidString < $1.id.uuidString }
    out.tagInfo.sort { $0.name.lowercased() < $1.name.lowercased() }
    out.swatches.sort { $0.id.uuidString < $1.id.uuidString }
    for i in out.swatches.indices { out.swatches[i].entries.sort { $0.hex < $1.hex } }
    out.deleted.sort { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }
    return out
}

/// What a person would notice changing between two copies.
struct LibraryChange: Equatable {
    var coloursAdded = 0, coloursRemoved = 0
    var swatchesAdded = 0, swatchesRemoved = 0, swatchesChanged = 0
    var projectsAdded = 0, projectsRemoved = 0

    var isEmpty: Bool { self == LibraryChange() }

    var lines: [String] {
        var out: [String] = []
        if coloursAdded > 0 { out.append("\(plural(coloursAdded, "new colour"))") }
        if swatchesAdded > 0 { out.append("\(plural(swatchesAdded, "new swatch", "new swatches"))") }
        if swatchesChanged > 0 { out.append("\(plural(swatchesChanged, "changed swatch", "changed swatches"))") }
        if coloursRemoved > 0 { out.append("\(plural(coloursRemoved, "colour")) deleted") }
        if swatchesRemoved > 0 { out.append("\(plural(swatchesRemoved, "swatch", "swatches")) deleted") }
        if projectsAdded > 0 { out.append("\(plural(projectsAdded, "new project"))") }
        if projectsRemoved > 0 { out.append("\(plural(projectsRemoved, "project")) deleted") }
        return out
    }
}

func change(from a: Library, to b: Library) -> LibraryChange {
    var c = LibraryChange()
    let ah = Set(a.colours.map { $0.hex }), bh = Set(b.colours.map { $0.hex })
    c.coloursAdded = bh.subtracting(ah).count
    c.coloursRemoved = ah.subtracting(bh).count
    for s in b.swatches {
        guard let old = a.swatch(s.id) else { c.swatchesAdded += 1; continue }
        if old.name != s.name || Set(old.entries.map { $0.hex }) != Set(s.entries.map { $0.hex }) { c.swatchesChanged += 1 }
    }
    c.swatchesRemoved = a.swatches.filter { b.swatch($0.id) == nil }.count
    c.projectsAdded = b.projects.filter { a.project($0.id) == nil }.count
    c.projectsRemoved = a.projects.filter { b.project($0.id) == nil }.count
    return c
}

// ---------- Catalogues ----------
//
// A catalogue is a whole library — colours and swatches — kept in its own folder.
// "Main" is the original library, left exactly where it always was.

struct Catalogues {
    static let mainName = "Main"
    static let currentKey = "currentCatalogue"
    /// Where the app keeps its own data, when the user has chosen somewhere other than Application Support.
    static let homeKey = "appHome"

    let root: URL
    /// The v1 colour list and the v2 library. Read once to seed Main, never written.
    let legacyURL: URL?
    var previousURL: URL? = nil

    /// The user's own home folder, even under the sandbox, where the usual call gives the app's container instead.
    static var realHome: URL {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }
    static var realApplicationSupport: URL { realHome.appendingPathComponent("Library/Application Support") }

    /// Application Support, which is where the app's data starts; the seed the setup assistant offers to move.
    static var seedRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MMFFDev Colour 3")
    }

    /// The folder the user chose for the app's data, or nil while it is still in Application Support.
    static var home: URL? {
        get { preferences.string(forKey: homeKey).map { URL(fileURLWithPath: $0) } }
        set { preferences.set(newValue?.path, forKey: homeKey) }
    }

    /// Read afresh each time, so a home chosen in the setup assistant takes effect before anything loads.
    static var standard: Catalogues {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // MMFFDEV_COLOUR3_HOME points the app at another folder, for trying things without touching real data.
        let override = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_HOME"].map { URL(fileURLWithPath: $0) }
        // A trial home is a brand-new Mac: it never seeds Main from the earlier versions' libraries here.
        return Catalogues(
            root: home ?? override ?? seedRoot,
            legacyURL: override == nil ? support.appendingPathComponent("MMFFDev Colour").appendingPathComponent("library.json") : nil,
            previousURL: override == nil ? support.appendingPathComponent("MMFFDev Colour 2").appendingPathComponent("library.json") : nil)
    }

    /// Moves the app's data to a folder of the user's choosing, catalogues inside it and all, and
    /// remembers the new home. The folder must be empty or not yet there. Anything that will not
    /// move stays where it was and is reported.
    static func moveHome(to dest: URL) throws {
        try relocateHome(from: standard.root, to: dest)
        home = dest
    }

    /// A verified relocation retains the old workspace as a recovery copy. External links keep their locations.
    static func relocateHome(from: URL, to dest: URL) throws {
        let manager = Handler_File_Manager.shared
        let source = from.resolvingSymlinksInPath().standardizedFileURL, target = dest.resolvingSymlinksInPath().standardizedFileURL
        guard source != target else { return }
        guard !source.path.hasPrefix(target.path + "/"), !target.path.hasPrefix(source.path + "/") else { throw failure("Choose a separate folder outside the current workspace.") }
        _ = try AppDataStore(root: source).read()
        let revision = try manager.copySnapshot(source)
        if FileManager.default.fileExists(atPath: target.path), !(try manager.filesystem.list(target)).isEmpty { throw CatalogueError.notEmpty(target) }
        try manager.withTransaction(home: source) {
            try manager.copyVerified(source, to: target)
            guard try manager.copySnapshot(source) == revision else { throw failure("The source workspace changed during relocation. Retry after other operations finish. The original remains in place.") }
            try AppDataStore(root: target).update { manifest in
                func rebased(_ path: String) -> String {
                    guard path.hasPrefix("/") else { return path }
                    return path == source.path ? target.path : path.hasPrefix(source.path + "/") ? target.path + path.dropFirst(source.path.count) : path
                }
                var rows = manifest["catalogues"] as? [[String: Any]] ?? []
                for index in rows.indices { if let path = rows[index]["path"] as? String { rows[index]["path"] = rebased(path.hasPrefix("/") ? URL(fileURLWithPath: path).resolvingSymlinksInPath().path : path) } }
                manifest["catalogues"] = rows
                manifest["detachedCatalogues"] = (manifest["detachedCatalogues"] as? [String] ?? []).map(rebased)
            }
            let manifest = try AppDataStore(root: target).read()
            for reference in try Handler_File_App_Data().references(manifest, at: AppDataStore(root: target).url) { _ = try manager.read(reference.url) }
        }
    }

    // MARK: Where each catalogue is

    /// A catalogue kept somewhere of its own: its name, and the folder holding its file.
    struct Entry: Codable, Equatable {
        var name: String
        var path: String
        var id: UUID? = nil

        func url(in root: URL) -> URL? {
            if path.hasPrefix("/") { return URL(fileURLWithPath: path).standardizedFileURL }
            guard !path.isEmpty, !path.split(separator: "/").contains("..") else { return nil }
            let candidate = root.appendingPathComponent(path).standardizedFileURL
            guard candidate.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
            return candidate
        }
    }

    private func registryPath(for directory: URL) -> String {
        let home = root.standardizedFileURL.path + "/"
        let path = directory.standardizedFileURL.path
        return path.hasPrefix(home) ? String(path.dropFirst(home.count)) : path
    }

    var registryURL: URL { AppDataStore(root: root).url }
    var registry: [Entry] {
        get {
            do {
                let rows = try AppDataStore(root: root).read()["catalogues"] ?? []
                return try JSONDecoder().decode([Entry].self, from: JSONSerialization.data(withJSONObject: rows))
            } catch { NSLog("Catalogue index: %@", error.localizedDescription); return [] }
        }
        nonmutating set {
            do { try writeRegistry(newValue) } catch { FileIncidentCoordinator.report(error, at: registryURL) }
        }
    }
    private func writeRegistry(_ entries: [Entry]) throws {
        try AppDataStore(root: root).update { manifest in
            let previous = manifest["catalogues"] as? [[String: Any]] ?? []
            manifest["catalogues"] = entries.map { entry -> [String: Any] in
                var row = previous.first { $0["path"] as? String == entry.path || $0["name"] as? String == entry.name } ?? [:]
                row["name"] = entry.name; row["path"] = entry.path
                if let id = entry.id { row["id"] = id.uuidString }
                return row
            }
            let activeIDs = Set(entries.compactMap(\.id))
            manifest["detachedCatalogueIDs"] = (manifest["detachedCatalogueIDs"] as? [String] ?? []).filter { UUID(uuidString: $0).map { !activeIDs.contains($0) } ?? true }
            let activePaths = Set(entries.compactMap { $0.url(in: root) }.flatMap { [$0.standardizedFileURL.path, $0.resolvingSymlinksInPath().path] })
            manifest["detachedCatalogues"] = (manifest["detachedCatalogues"] as? [String] ?? []).filter { !activePaths.contains($0) }
        }
    }

    /// Puts a catalogue that lives in `dir` on the list under `name`, replacing an entry of that name.
    func register(_ name: String, at dir: URL) {
        var all = registry.filter { $0.name != name }
        all.append(Entry(name: name, path: registryPath(for: dir), id: CatalogueTree.catalogue(in: dir)?.id))
        registry = all
    }

    /// Setup must know that the catalogue's location was saved before proceeding.
    func registerChecked(_ name: String, at dir: URL) throws {
        var all = registry.filter { $0.name != name }
        all.append(Entry(name: name, path: registryPath(for: dir), id: CatalogueTree.catalogue(in: dir)?.id))
        try writeRegistry(all)
    }

    func unregister(_ name: String) { registry = registry.filter { $0.name != name } }

    /// The catalogue last opened on this Mac.
    static var currentName: String {
        get {
            if CommandLine.arguments.contains("--self-test") {
                return AppPreferences.shared.string(forKey: currentKey) ?? mainName
            }
            let names = standard.names()
            let manifest = try? AppDataStore.current.read()
            let saved = ((manifest?["defaultCatalogue"] as? [String: Any])?["name"] as? String)
                ?? AppPreferences.shared.string(forKey: currentKey) ?? mainName
            return names.contains(saved) ? saved : (names.first ?? mainName)
        }
        set {
            if CommandLine.arguments.contains("--self-test") {
                AppPreferences.shared.rememberDefaultCatalogue(newValue, id: nil)
                return
            }
            let id = WorkspaceInventory.probe(name: newValue, folder: standard.directory(for: newValue)).id?.uuidString
            AppPreferences.shared.rememberDefaultCatalogue(newValue, id: id)
        }
    }

    var folder: URL { root.appendingPathComponent("Catalogues") }

    /// The folder a catalogue's file is in: the one it was registered at, or its folder under Catalogues.
    func directory(for name: String) -> URL {
        if let own = registry.first(where: { $0.name == name }), let location = own.url(in: root) { return location }
        return name == Catalogues.mainName ? root : folder.appendingPathComponent(filesystemName(name))
    }

    /// Earlier versions' libraries seed Main on a fresh install only — never after a rename.
    func store(for name: String) -> LibraryStore {
        let fresh = name == Catalogues.mainName && !hasMain && others().isEmpty
        return LibraryStore(directory: directory(for: name), legacyURL: fresh ? legacyURL : nil,
                            previousURL: fresh ? previousURL : nil, name: name, assetsHome: root)
    }

    private var detachedRoots: Set<String> { Set((try? AppDataStore(root: root).read()["detachedCatalogues"] as? [String]) ?? []) }
    private var detachedIDs: Set<UUID> { Set(((try? AppDataStore(root: root).read()["detachedCatalogueIDs"] as? [String]) ?? []).compactMap(UUID.init(uuidString:))) }
    private var hasMain: Bool { !detachedRoots.contains(root.standardizedFileURL.path) && !detachedRoots.contains(root.resolvingSymlinksInPath().path) && !(CatalogueTree.catalogue(in: root).map { detachedIDs.contains($0.id) } ?? false) && Catalogues.holdsCatalogue(root) }
    /// No catalogue on this Mac at all: nothing at the root, nothing under Catalogues, nothing registered.
    var isEmpty: Bool { !hasMain && others().isEmpty }

    /// Takes away a Main at the root that holds nothing: no colours, palettes or members. Anything in it stays.
    func dropEmptyMain() {
        guard hasMain, let lib = try? store(for: Catalogues.mainName).load(), lib.colours.isEmpty, lib.swatches.isEmpty, lib.projects.isEmpty else { return }
        // Empty catalogues still own user folders. Removing them uses the same explicit retention workflow.
    }

    /// What at the app's home belongs to the catalogue kept there, Main: its index and history, its Library and Templates, its
    /// collections' folders, and whatever an earlier layout left. Never the other catalogues or the registry.
    static func catalogueItems(at root: URL) -> [String] {
        let fm = FileManager.default
        var items = [CatalogueFiles.index(in: root)?.lastPathComponent, CatalogueFiles.index(in: root).map { HistoryStore.url(beside: $0).lastPathComponent },
                     "library.json", "library.history.json", "schema.colschema", TreeFiles.library, "Support", TreeFiles.templates, TreeFiles.backups, CatalogueFiles.unfiled, "Projects"].compactMap { $0 }
        // The collections' folders, as the structure file names them, or as an earlier version marked them with a file of their own.
        items += (CatalogueTree.catalogue(in: root)?.collections.map { $0.folder } ?? []).filter { !items.contains($0) }
        if let legacy = CatalogueFiles.legacyIndex(in: root) { items.append(legacy.lastPathComponent) }
        for sub in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where !items.contains(sub) && sub != "Catalogues" {
            if fm.fileExists(atPath: root.appendingPathComponent(sub).appendingPathComponent(sub + "." + LegacyTree.collection).path) { items.append(sub) }
        }
        return items
    }

    /// Whether a folder holds a catalogue: its file, or the one file of an earlier version.
    static func holdsCatalogue(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return CatalogueFiles.anyIndex(in: dir) != nil || fm.fileExists(atPath: dir.appendingPathComponent("library.json").path)
            || fm.fileExists(atPath: dir.appendingPathComponent(".library.json.icloud").path)
    }

    /// Every catalogue but Main: those found under Catalogues, and those registered elsewhere whose folder is reachable.
    private func others() -> [String] {
        let detached = detachedRoots
        let excludedIDs = detachedIDs
        var names = Catalogues.subfoldersHoldingLibraries(in: folder).filter {
            let url = folder.appendingPathComponent($0)
            return !detached.contains(url.standardizedFileURL.path) && !detached.contains(url.resolvingSymlinksInPath().path) && !(CatalogueTree.catalogue(in: url).map { excludedIDs.contains($0.id) } ?? false)
        }
        // A registered name for a folder already on the list, under Catalogues or by another entry, is a ghost: one folder, one name.
        var dirs = Set(names.map { folder.appendingPathComponent(filesystemName($0)).standardizedFileURL.path })
        for entry in registry where !names.contains(entry.name) {
            guard let location = entry.url(in: root) else { continue }
            let dir = location.standardizedFileURL.path
            if detached.contains(dir) || detached.contains(location.resolvingSymlinksInPath().path) { continue }
            guard !dirs.contains(dir) else { continue }
            dirs.insert(dir); names.append(entry.name)
        }
        return names.filter { $0 != Catalogues.mainName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Main first (while it exists), then the rest alphabetically. A fresh install has just Main.
    func names() -> [String] {
        let rest = others()
        return hasMain || rest.isEmpty && !FileManager.default.fileExists(atPath: registryURL.path) ? [Catalogues.mainName] + rest : rest
    }

    /// Moves a catalogue to the Bin and takes it off the list. Main keeps its files at the home's root,
    /// so they are gathered into a folder of their own under Catalogues first and that folder goes; the
    /// home itself, and a folder another listed catalogue still points at, are never binned.
    func bin(_ name: String) throws {
        let manager = Handler_File_Manager.shared
        let plan = try manager.prepareCatalogueRemoval(name: name, catalogues: self)
        try manager.executeCatalogueRemoval(plan, outcome: .binOwnedFiles)
    }

    /// Moves the catalogue's folder. Main lives at the root, so renaming it moves its files into a
    /// folder of their own. Returns the name as it was actually used.
    @discardableResult
    func rename(_ old: String, to raw: String) throws -> String {
        let new = filesystemName(raw)
        guard names().contains(old) else { throw CatalogueError.missing(old) }
        guard new.lowercased() != old.lowercased() else { return old }
        guard !new.isEmpty, !names().contains(where: { $0.lowercased() == new.lowercased() }) else { throw CatalogueError.nameTaken(new) }
        let manager = Handler_File_Manager.shared, from = directory(for: old)
        guard let originalIndex = CatalogueFiles.index(in: from) else { throw CatalogueError.missing(old) }
        try manager.requireAvailableCatalogue(originalIndex)
        let dest = from.standardizedFileURL == root.standardizedFileURL ? folder.appendingPathComponent(new) : from.deletingLastPathComponent().appendingPathComponent(new)
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw CatalogueError.notEmpty(dest) }
        return try manager.withTransaction(home: root) {
            if from.standardizedFileURL == root.standardizedFileURL {
                try manager.createDirectory(dest)
                for item in Catalogues.catalogueItems(at: root) where item != "Backups" {
                    let source = root.appendingPathComponent(item)
                    if FileManager.default.fileExists(atPath: source.path) { try manager.move(source, to: dest.appendingPathComponent(item)) }
                }
            } else { try manager.move(from, to: dest) }
            guard let index = CatalogueFiles.index(in: dest) else { throw CatalogueError.missing(old) }
            let named = dest.appendingPathComponent(new + "." + ColourFiles.catalogue)
            let history = HistoryStore.url(beside: index), historyNamed = HistoryStore.url(beside: named)
            if index != named { try manager.move(index, to: named) }
            if history != historyNamed, FileManager.default.fileExists(atPath: history.path) {
                try manager.move(history, to: historyNamed)
                try manager.update(named) { if $0["history"] != nil { $0["history"] = historyNamed.lastPathComponent } }
            }
            let identity = try ColourFiles.decoder().decode(CatalogueFile.self, from: manager.read(named)).id
            try AppDataStore(root: root).update { manifest in
                var rows = manifest["catalogues"] as? [[String: Any]] ?? []
                var row = rows.first { $0["name"] as? String == old } ?? [:]
                rows.removeAll { $0["name"] as? String == old }
                row["name"] = new; row["path"] = registryPath(for: dest); row["id"] = identity.uuidString; rows.append(row)
                manifest["catalogues"] = rows
                var settings = manifest["settings"] as? [String: Any] ?? [:]
                if settings[Catalogues.currentKey] as? String == old { settings[Catalogues.currentKey] = new; manifest["settings"] = settings }
                if var selected = manifest["defaultCatalogue"] as? [String: Any], selected["name"] as? String == old { selected["name"] = new; manifest["defaultCatalogue"] = selected }
            }
            try ASERegistry.seed(dest, name: new)
            return new
        }
    }

    static func subfoldersHoldingLibraries(in dir: URL) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { name in holdsCatalogue(dir.appendingPathComponent(name)) }
    }

    /// Creates an empty catalogue. The name is made unique and safe for a folder. With `under`, the
    /// catalogue is a folder named for it inside that folder, wherever the user chose, instead of
    /// under Catalogues in the app's home.
    @discardableResult
    func create(_ raw: String, holding library: Library = Library(), under parent: URL? = nil) throws -> String {
        try AppHomeSeed.ensure(at: root)
        let name = uniqueName(filesystemName(raw), among: names())
        let dir = parent.map { $0.appendingPathComponent(name) } ?? directory(for: name)
        guard !Catalogues.holdsCatalogue(dir) else { throw CatalogueError.nameTaken(name) }
        return try Handler_File_Manager.shared.withTransaction(home: root) {
            try Handler_File_Manager.shared.createDirectory(dir)
            try LibraryStore(directory: dir, legacyURL: nil, name: name, assetsHome: root).save(library)
            try registerChecked(name, at: dir)
            return name
        }
    }

    /// Opens a catalogue where it is: the folder holding a .colcatalogue file is put on the list
    /// under the file's name. Nothing is copied or changed. Returns the name as it is now listed.
    @discardableResult
    func adopt(_ index: URL) throws -> String {
        let dir = index.deletingLastPathComponent()
        guard Catalogues.holdsCatalogue(dir) else { throw SyncError.unreadable(index) }
        if index.pathExtension.lowercased() == "colcat" { try Handler_File_Manager.shared.requireAvailableCatalogue(index) }
        // Already on the list, by the registry or by sitting under Catalogues: that name, not a second one for the same folder.
        if let already = names().first(where: { directory(for: $0).standardizedFileURL == dir.standardizedFileURL }) { return already }
        let name = uniqueName(filesystemName(index.deletingPathExtension().lastPathComponent), among: names())
        try registerChecked(name, at: dir)
        return name
    }

    /// Opens a library file from anywhere — an export, a backup — as a new catalogue. The file is only read.
    @discardableResult
    func importFile(_ url: URL, named raw: String? = nil) throws -> String {
        let data = try Data(contentsOf: url)
        guard let lib = try? JSONDecoder.library.decode(Library.self, from: data) else { throw SyncError.unreadable(url) }
        let fallback = url.deletingLastPathComponent().lastPathComponent
        return try create(raw ?? fallback, holding: lib)
    }
}

enum CatalogueError: LocalizedError {
    case missing(String)
    case nameTaken(String)
    case notEmpty(URL)

    var errorDescription: String? {
        switch self {
        case .missing(let n): return "There is no catalogue called \u{201C}\(n)\u{201D}."
        case .nameTaken(let n): return "There is already a catalogue called \u{201C}\(n)\u{201D}. Choose another name."
        case .notEmpty(let u): return "\u{201C}\(u.lastPathComponent)\u{201D} already has things in it. Choose an empty folder, or a new one."
        }
    }
}

// ---------- Sync ----------

enum SyncError: LocalizedError {
    case folderMissing(URL)
    case stillDownloading(URL)
    case unreadable(URL)
    case backupFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .folderMissing(let u):
            return "The sync folder isn\u{2019}t available: \(u.path). Nothing was changed."
        case .stillDownloading(let u):
            return "\(u.lastPathComponent) is still downloading from the cloud. Try Sync Now in a moment."
        case .unreadable(let u):
            let kind = [ColourFiles.catalogue, ColourFiles.legacyCatalogue].contains(u.pathExtension.lowercased()) ? "catalogue" : "library"
            return "\(u.lastPathComponent) could not be opened as a \(kind). The file has been left untouched.\n\nLocation: \(u.path)"
        case .backupFailed(let u, let e):
            return "Could not write a backup to \(u.path), so nothing was changed: \(e.localizedDescription)"
        }
    }
}

struct SyncPlan {
    let local: Library, remote: Library, merged: Library
    /// What this Mac would gain or lose by merging.
    let incoming: LibraryChange
    /// What the synced copy would gain or lose.
    let outgoing: LibraryChange
    /// Conflicted copies left by the cloud service, already folded into `remote`.
    let strays: [URL]
}

enum SyncState {
    /// The other Mac renamed this catalogue; this Mac should follow before syncing.
    case renamed(to: String)
    /// Nothing in the sync folder yet for this catalogue.
    case firstSync
    /// Both sides already hold the same thing.
    case inSync
    /// Nothing for the user to decide — just bring the two files level.
    case quiet(SyncPlan)
    /// The synced copy has changes this Mac hasn't seen.
    case incoming(SyncPlan)
}

enum SyncChoice { case merge, useSynced, keepLocal }

final class SyncEngine {
    static let folderName = "MMFFDev Colour 3 Sync"

    let store: LibraryStore
    /// The "MMFFDev Colour 3 Sync" folder.
    let syncRoot: URL
    let catalogue: String
    let machine: String
    /// 0 keeps every backup.
    var backupsToKeep: Int

    init(store: LibraryStore, chosenFolder: URL, catalogue: String, machine: String, backupsToKeep: Int = 50) {
        self.store = store
        self.syncRoot = SyncEngine.root(in: chosenFolder)
        self.catalogue = catalogue
        self.machine = filesystemName(machine)
        self.backupsToKeep = backupsToKeep
    }

    /// The user may pick the cloud folder, or the sync folder inside it — both work.
    static func root(in chosen: URL) -> URL {
        chosen.lastPathComponent == folderName ? chosen : chosen.appendingPathComponent(folderName)
    }

    /// Catalogues present in the sync folder, whether or not this Mac has opened them.
    static func catalogues(in chosenFolder: URL) -> [String] {
        Catalogues.subfoldersHoldingLibraries(in: root(in: chosenFolder))
    }

    var folder: URL { syncRoot.appendingPathComponent(filesystemName(catalogue)) }

    /// Left behind in a renamed catalogue's old folder, holding the new name, so the other Mac follows.
    static let renamedMarker = "renamed-to.txt"

    static func renamedName(in chosen: URL, of catalogue: String) -> String? {
        let marker = root(in: chosen).appendingPathComponent(filesystemName(catalogue)).appendingPathComponent(renamedMarker)
        return (try? String(contentsOf: marker, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renames the catalogue's folder in the sync location and leaves a marker in the old one.
    /// Nothing to do if the catalogue has never been synced.
    static func rename(in chosen: URL, from old: String, to new: String) throws {
        let fm = FileManager.default
        let root = root(in: chosen)
        let from = root.appendingPathComponent(filesystemName(old)), to = root.appendingPathComponent(filesystemName(new))
        guard fm.fileExists(atPath: from.path) else { return }
        guard fm.fileExists(atPath: root.deletingLastPathComponent().path) else { throw SyncError.folderMissing(root.deletingLastPathComponent()) }
        if fm.fileExists(atPath: to.path) {
            // Only a marker-only folder (an earlier rename away from this name) may be reused.
            guard !Catalogues.subfoldersHoldingLibraries(in: root).contains(filesystemName(new)),
                  fm.fileExists(atPath: to.appendingPathComponent(renamedMarker).path) else { throw CatalogueError.nameTaken(new) }
            try fm.removeItem(at: to)
        }
        try fm.moveItem(at: from, to: to)
        try fm.createDirectory(at: from, withIntermediateDirectories: true)
        try new.write(to: from.appendingPathComponent(renamedMarker), atomically: true, encoding: .utf8)
    }
    var remoteURL: URL { folder.appendingPathComponent("library.json") }
    var remoteBackups: URL { folder.appendingPathComponent("Backups") }
    var localBackups: URL { store.url.deletingLastPathComponent().appendingPathComponent("Backups") }

    // MARK: Reading

    /// The synced copy with any conflicted copies folded in, or nil if there is none yet.
    func readRemote() throws -> (library: Library, strays: [URL])? {
        let fm = FileManager.default
        let parent = syncRoot.deletingLastPathComponent()
        guard fm.fileExists(atPath: parent.path) else { throw SyncError.folderMissing(parent) }

        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        if let placeholder = names.first(where: { $0.hasPrefix(".library") && $0.hasSuffix(".icloud") }) {
            try? fm.startDownloadingUbiquitousItem(at: remoteURL)
            throw SyncError.stillDownloading(folder.appendingPathComponent(placeholder))
        }

        // "library (conflicted copy).json", "library 2.json" … whatever the cloud service left behind.
        let strays = names
            .filter { $0.lowercased().hasPrefix("library") && $0.lowercased().hasSuffix(".json") && $0 != "library.json" }
            .sorted().map { folder.appendingPathComponent($0) }

        var found: Library?
        for url in (fm.fileExists(atPath: remoteURL.path) ? [remoteURL] : []) + strays {
            guard let data = try? Data(contentsOf: url),
                  let lib = try? JSONDecoder.library.decode(Library.self, from: data) else { throw SyncError.unreadable(url) }
            found = found.map { mergeLibraries(local: $0, remote: lib) } ?? lib
        }
        return found.map { ($0, strays) }
    }

    func check() throws -> SyncState {
        try check(local:store.load())
    }

    /// Pure merge planning against a caller-owned snapshot. Remote I/O and merge work can
    /// happen off the main thread; callers must revalidate local disk before applying a plan.
    func check(local:Library) throws -> SyncState {
        if let new = SyncEngine.renamedName(in: syncRoot, of: catalogue), new != catalogue { return .renamed(to: new) }
        guard let (remote, strays) = try readRemote() else { return .firstSync }
        let merged = mergeLibraries(local: local, remote: remote)
        let plan = SyncPlan(local: local, remote: remote, merged: merged,
                            incoming: change(from: local, to: merged),
                            outgoing: change(from: remote, to: merged), strays: strays)

        if strays.isEmpty && canonical(local) == canonical(remote) { return .inSync }
        // A catalogue this Mac has never used simply takes the synced copy.
        let untouched = local.colours.isEmpty && local.swatches.isEmpty && local.deleted.isEmpty
        return plan.incoming.isEmpty || untouched ? .quiet(plan) : .incoming(plan)
    }

    // MARK: Writing

    /// Saves this Mac's library into the sync folder. Only for `.firstSync`.
    func push(_ lib: Library) throws {
        let parent = syncRoot.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { throw SyncError.folderMissing(parent) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder.library.encode(lib).write(to: remoteURL, options: .atomic)
    }

    /// Brings both sides level without asking. Backs up the synced copy first if it is about to lose anything.
    @discardableResult
    func settle(_ plan: SyncPlan, at date: Date = Date()) throws -> Library {
        if plan.outgoing.coloursRemoved + plan.outgoing.swatchesRemoved > 0 || !plan.strays.isEmpty {
            try backup(plan.remote, label: "synced copy", at: date)
        }
        return try write(plan.merged, plan: plan, at: date)
    }

    /// Backs up both sides, then applies the choice to this Mac and the sync folder.
    @discardableResult
    func perform(_ choice: SyncChoice, plan: SyncPlan, at date: Date = Date()) throws -> Library {
        try backup(plan.local, label: "this Mac (\(machine))", at: date)
        try backup(plan.remote, label: "synced copy", at: date)
        let result: Library
        switch choice {
        case .merge: result = plan.merged
        case .useSynced: result = replacing(plan.local, with: plan.remote, at: date)
        case .keepLocal: result = replacing(plan.remote, with: plan.local, at: date)
        }
        return try write(result, plan: plan, at: date)
    }

    private func write(_ lib: Library, plan: SyncPlan, at date: Date) throws -> Library {
        if canonical(lib) != canonical(plan.local) || lib.activeSwatchID != plan.local.activeSwatchID { try store.save(lib) }
        try push(lib)
        // Conflicted copies are now part of the library; move them out of the way, never delete them.
        for stray in plan.strays {
            try? FileManager.default.createDirectory(at: remoteBackups, withIntermediateDirectories: true)
            let name = uniqueName("\(stamp(date)) \(stray.deletingPathExtension().lastPathComponent)",
                                  among: existing(in: remoteBackups))
            try? FileManager.default.moveItem(at: stray, to: remoteBackups.appendingPathComponent(name + ".json"))
        }
        prune()
        return lib
    }

    // MARK: Backups

    private func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: date)
    }

    private func existing(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }
    }

    /// Written to the sync folder and to this Mac, so a problem with either still leaves a copy.
    func backup(_ lib: Library, label: String, at date: Date = Date()) throws {
        let data = try JSONEncoder.library.encode(lib)
        for dir in [remoteBackups, localBackups] {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let name = uniqueName("\(stamp(date)) \(filesystemName(label))", among: existing(in: dir))
                try data.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
            } catch {
                throw SyncError.backupFailed(dir, error)
            }
        }
    }

    func backups(in dir: URL) -> [URL] {
        existing(in: dir).sorted().map { dir.appendingPathComponent($0 + ".json") }
    }

    /// Removes the oldest backups beyond the limit. Names start with the date, so name order is age order.
    func prune() {
        guard backupsToKeep > 0 else { return }
        for dir in [remoteBackups, localBackups] {
            for old in backups(in: dir).dropLast(backupsToKeep) { try? FileManager.default.removeItem(at: old) }
        }
    }
}

// ---------- Settings (per Mac) ----------

/// Preferences for this Mac. A trial run (MMFFDEV_COLOUR3_HOME set) gets its own, so it can
/// never pick up — or sync into — the real sync folder. The bare binary Xcode runs from the build
/// folder has no bundle identifier, so .standard would be an empty domain of its own and the app would
/// forget its catalogue and its projects folder; it reads the installed app's domain instead.
let selfTestPreferencesDomain = "com.mmffdev.mmffdevcolour3.selftest." + UUID().uuidString
let preferences: UserDefaults = {
    if let suite = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_QA_PREFERENCES"], suite.hasPrefix("com.mmffdev.mmffdevcolour3.qa.") { return UserDefaults(suiteName: suite)! }
    if CommandLine.arguments.contains("--self-test") {
        return UserDefaults(suiteName: selfTestPreferencesDomain)!
    }
    if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_HOME"] != nil {
        return UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3.trial") ?? .standard
    }
    if Bundle.main.bundleIdentifier == nil {
        return UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3") ?? .standard
    }
    return .standard
}()

enum SyncSettings {
    private static let d = AppPreferences.shared

    /// The folder the user chose — the cloud folder, or the sync folder inside it. nil = sync off.
    static var folder: URL? {
        get { d.string(forKey: "syncFolder").map { URL(fileURLWithPath: $0) } }
        set { d.set(newValue?.path, forKey: "syncFolder") }
    }

    /// false = merge without asking.
    static var askBeforeMerging: Bool {
        get { d.object(forKey: "syncAsk") as? Bool ?? true }
        set { d.set(newValue, forKey: "syncAsk") }
    }

    /// 0 = keep all.
    static var backupsToKeep: Int {
        get { d.object(forKey: "backupsToKeep") as? Int ?? 50 }
        set { d.set(newValue, forKey: "backupsToKeep") }
    }

    static var machineName: String { Host.current().localizedName ?? "Mac" }
}

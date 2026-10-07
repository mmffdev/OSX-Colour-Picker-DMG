import Foundation

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
                                   copiedFrom: l?.copiedFrom ?? r?.copiedFrom))
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
        return Colour(hex: hex, pickedAt: dates[hex]!, tags: tags, tagsChangedAt: at,
                      source: (l ?? r)?.source, master: (l ?? r)?.master, kind: (l ?? r)?.kind)
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
            root: override ?? home ?? seedRoot,
            legacyURL: override == nil ? support.appendingPathComponent("MMFFDev Colour").appendingPathComponent("library.json") : nil,
            previousURL: override == nil ? support.appendingPathComponent("MMFFDev Colour 2").appendingPathComponent("library.json") : nil)
    }

    /// Moves the app's data to a folder of the user's choosing, catalogues inside it and all, and
    /// remembers the new home. The folder must be empty or not yet there. Anything that will not
    /// move stays where it was and is reported.
    static func moveHome(to dest: URL) throws {
        let fm = FileManager.default, from = standard.root
        guard from != dest else { return }
        if fm.fileExists(atPath: dest.path) {
            guard ((try? fm.contentsOfDirectory(atPath: dest.path)) ?? []).filter({ !$0.hasPrefix(".") }).isEmpty else { throw CatalogueError.notEmpty(dest) }
        } else {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        }
        for item in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where !item.hasPrefix(".") {
            try fm.moveItem(at: from.appendingPathComponent(item), to: dest.appendingPathComponent(item))
        }
        home = dest
    }

    // MARK: Where each catalogue is

    /// A catalogue kept somewhere of its own: its name, and the folder holding its file.
    struct Entry: Codable, Equatable {
        var name: String
        var path: String
    }

    /// "catalogues.json" in the app's home: the catalogues that live outside it. Those inside are found by looking.
    var registryURL: URL { root.appendingPathComponent("catalogues.json") }

    var registry: [Entry] {
        get { (try? Data(contentsOf: registryURL)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
        nonmutating set {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let data = try? ColourFiles.encoder().encode(newValue) { try? data.write(to: registryURL, options: .atomic) }
        }
    }

    /// Puts a catalogue that lives in `dir` on the list under `name`, replacing an entry of that name.
    func register(_ name: String, at dir: URL) {
        var all = registry.filter { $0.name != name }
        all.append(Entry(name: name, path: dir.path))
        registry = all
    }

    func unregister(_ name: String) { registry = registry.filter { $0.name != name } }

    /// The catalogue last opened on this Mac.
    static var currentName: String {
        get {
            let names = standard.names()
            let saved = preferences.string(forKey: currentKey) ?? mainName
            return names.contains(saved) ? saved : (names.first ?? mainName)
        }
        set { preferences.set(newValue, forKey: currentKey) }
    }

    var folder: URL { root.appendingPathComponent("Catalogues") }

    /// The folder a catalogue's file is in: the one it was registered at, or its folder under Catalogues.
    func directory(for name: String) -> URL {
        if let own = registry.first(where: { $0.name == name }) { return URL(fileURLWithPath: own.path) }
        return name == Catalogues.mainName ? root : folder.appendingPathComponent(filesystemName(name))
    }

    /// Earlier versions' libraries seed Main on a fresh install only — never after a rename.
    func store(for name: String) -> LibraryStore {
        let fresh = name == Catalogues.mainName && !hasMain && others().isEmpty
        // Only the real catalogues use the Projects folder chosen in Settings; any other set of
        // catalogues keeps its projects beside itself.
        let chosen = root == Catalogues.standard.root ? ProjectFiles.folder : nil
        return LibraryStore(directory: directory(for: name), legacyURL: fresh ? legacyURL : nil,
                            previousURL: fresh ? previousURL : nil, name: name, projectsFolder: chosen)
    }

    private var hasMain: Bool { Catalogues.holdsCatalogue(root) }
    /// No catalogue on this Mac at all: nothing at the root, nothing under Catalogues, nothing registered.
    var isEmpty: Bool { !hasMain && others().isEmpty }

    /// Takes away a Main at the root that holds nothing: no colours, palettes or members. Anything in it stays.
    func dropEmptyMain() {
        guard hasMain, let lib = try? store(for: Catalogues.mainName).load(), lib.colours.isEmpty, lib.swatches.isEmpty, lib.projects.isEmpty else { return }
        let fm = FileManager.default
        for item in [CatalogueFiles.index(in: root)?.lastPathComponent, "library.json", "library.history.json", CatalogueFiles.unfiled].compactMap({ $0 }) {
            try? fm.removeItem(at: root.appendingPathComponent(item))
        }
    }

    /// Whether a folder holds a catalogue: its file, or the one file of an earlier version.
    static func holdsCatalogue(_ dir: URL) -> Bool {
        let fm = FileManager.default
        return CatalogueFiles.index(in: dir) != nil || fm.fileExists(atPath: dir.appendingPathComponent("library.json").path)
            || fm.fileExists(atPath: dir.appendingPathComponent(".library.json.icloud").path)
    }

    /// Every catalogue but Main: those found under Catalogues, and those registered elsewhere whose folder is reachable.
    private func others() -> [String] {
        var names = Catalogues.subfoldersHoldingLibraries(in: folder)
        // A registered name for a folder already on the list, under Catalogues or by another entry, is a ghost: one folder, one name.
        var dirs = Set(names.map { folder.appendingPathComponent(filesystemName($0)).standardizedFileURL.path })
        for entry in registry where Catalogues.holdsCatalogue(URL(fileURLWithPath: entry.path)) && !names.contains(entry.name) {
            let dir = URL(fileURLWithPath: entry.path).standardizedFileURL.path
            guard !dirs.contains(dir) else { continue }
            dirs.insert(dir); names.append(entry.name)
        }
        return names.filter { $0 != Catalogues.mainName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Main first (while it exists), then the rest alphabetically. A fresh install has just Main.
    func names() -> [String] {
        let rest = others()
        return hasMain || rest.isEmpty ? [Catalogues.mainName] + rest : rest
    }

    /// Moves a catalogue to the Bin and takes it off the list. Main keeps its files at the home's root,
    /// so they are gathered into a folder of their own under Catalogues first and that folder goes; the
    /// home itself, and a folder another listed catalogue still points at, are never binned.
    func bin(_ name: String) throws {
        let fm = FileManager.default
        let home = root.standardizedFileURL
        var dir = directory(for: name).standardizedFileURL
        if dir == home {
            var dest = folder.appendingPathComponent(filesystemName(name))
            var n = 2
            while fm.fileExists(atPath: dest.path) { dest = folder.appendingPathComponent(filesystemName(name) + " \(n)"); n += 1 }
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            let index = CatalogueFiles.index(in: root)?.lastPathComponent
            for item in [index, "library.json", "library.history.json", "Backups", CatalogueFiles.unfiled, "Projects"].compactMap({ $0 }) {
                let from = root.appendingPathComponent(item)
                if fm.fileExists(atPath: from.path) { try fm.moveItem(at: from, to: dest.appendingPathComponent(item)) }
            }
            dir = dest.standardizedFileURL
        }
        let shared = names().contains { $0 != name && directory(for: $0).standardizedFileURL == dir }
        unregister(name)
        guard dir != home, !home.path.hasPrefix(dir.path + "/"), !shared, Catalogues.holdsCatalogue(dir) else { return }
        try fm.trashItem(at: dir, resultingItemURL: nil)
    }

    /// Moves the catalogue's folder. Main lives at the root, so renaming it moves its files into a
    /// folder of their own. Returns the name as it was actually used.
    @discardableResult
    func rename(_ old: String, to raw: String) throws -> String {
        let new = filesystemName(raw)
        guard names().contains(old) else { throw CatalogueError.missing(old) }
        guard new.lowercased() != old.lowercased() else { return old }
        guard !names().contains(where: { $0.lowercased() == new.lowercased() }) else { throw CatalogueError.nameTaken(new) }
        let fm = FileManager.default
        let dest = directory(for: new)
        if old == Catalogues.mainName {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            let index = CatalogueFiles.index(in: root)?.lastPathComponent
            for item in [index, "library.json", "library.history.json", "Backups", CatalogueFiles.unfiled, "Projects"].compactMap({ $0 }) {
                let from = root.appendingPathComponent(item)
                if fm.fileExists(atPath: from.path) { try fm.moveItem(at: from, to: dest.appendingPathComponent(item)) }
            }
        } else if let own = registry.first(where: { $0.name == old }) {
            // Kept somewhere of its own: the folder is renamed where it is.
            let was = URL(fileURLWithPath: own.path), now = was.deletingLastPathComponent().appendingPathComponent(new)
            try fm.moveItem(at: was, to: now)
            unregister(old)
            register(new, at: now)
        } else {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.moveItem(at: directory(for: old), to: dest)
        }
        // The catalogue's file carries the catalogue's name.
        if let index = CatalogueFiles.index(in: directory(for: new)) {
            let dest = directory(for: new)
            let named = dest.appendingPathComponent(new + "." + ColourFiles.catalogue)
            if index.lastPathComponent != named.lastPathComponent { try? fm.moveItem(at: index, to: named) }
        }
        if Catalogues.currentName == old || preferences.string(forKey: Catalogues.currentKey) == old {
            Catalogues.currentName = new
        }
        return new
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
        let name = uniqueName(filesystemName(raw), among: names())
        if let parent = parent {
            let dir = parent.appendingPathComponent(name)
            guard !Catalogues.holdsCatalogue(dir) else { throw CatalogueError.nameTaken(name) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            register(name, at: dir)
        }
        let dir = directory(for: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try store(for: name).save(library)
        return name
    }

    /// Opens a catalogue where it is: the folder holding a .colcatalogue file is put on the list
    /// under the file's name. Nothing is copied or changed. Returns the name as it is now listed.
    @discardableResult
    func adopt(_ index: URL) throws -> String {
        let dir = index.deletingLastPathComponent()
        guard Catalogues.holdsCatalogue(dir) else { throw SyncError.unreadable(index) }
        // Already on the list, by the registry or by sitting under Catalogues: that name, not a second one for the same folder.
        if let already = names().first(where: { directory(for: $0).standardizedFileURL == dir.standardizedFileURL }) { return already }
        let name = uniqueName(filesystemName(index.deletingPathExtension().lastPathComponent), among: names())
        register(name, at: dir)
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
            return "\(u.path) could not be read as a library. It has been left untouched."
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
        if let new = SyncEngine.renamedName(in: syncRoot, of: catalogue), new != catalogue { return .renamed(to: new) }
        let local = try store.load()
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
let preferences: UserDefaults = {
    if ProcessInfo.processInfo.environment["MMFFDEV_COLOUR3_HOME"] != nil {
        return UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3.trial") ?? .standard
    }
    if Bundle.main.bundleIdentifier == nil {
        return UserDefaults(suiteName: "com.mmffdev.mmffdevcolour3") ?? .standard
    }
    return .standard
}()

enum SyncSettings {
    private static let d = preferences

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

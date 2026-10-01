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
        var order: [String] = [], dates: [String: Date] = [:]
        for e in (l?.entries ?? []) + (r?.entries ?? []) {
            let cutoff = max(deletedAt(.entry, Library.entryKey(id, e.hex)), deletedAt(.colour, e.hex))
            guard e.addedAt > cutoff else { continue }
            if let seen = dates[e.hex] { dates[e.hex] = min(seen, e.addedAt) }
            else { dates[e.hex] = e.addedAt; order.append(e.hex) }
        }
        out.swatches.append(Swatch(id: id, name: name, createdAt: base.createdAt,
                                   entries: order.map { SwatchEntry(hex: $0, addedAt: dates[$0]!) },
                                   nameChangedAt: changed))
    }

    // Colours: kept if picked after their last deletion, or still in use by a surviving swatch.
    var order: [String] = [], dates: [String: Date] = [:]
    func keep(_ hex: String, _ date: Date) {
        guard date > deletedAt(.colour, hex) else { return }
        if let seen = dates[hex] { dates[hex] = min(seen, date) } else { dates[hex] = date; order.append(hex) }
    }
    for c in local.colours + remote.colours { keep(c.hex, c.pickedAt) }
    for s in out.swatches { for e in s.entries where dates[e.hex] == nil { keep(e.hex, e.addedAt) } }
    out.colours = order.map { Colour(hex: $0, pickedAt: dates[$0]!) }

    if let active = local.activeSwatchID, out.swatch(active) != nil { out.activeSwatchID = active }
    return out
}

/// `winner`, plus a record that everything only `loser` had was deliberately dropped —
/// so the choice holds when the other Mac next syncs.
func replacing(_ loser: Library, with winner: Library, at date: Date = Date()) -> Library {
    var out = winner
    let kept = Set(winner.colours.map { $0.hex })
    for c in loser.colours where !kept.contains(c.hex) { out.bury(.colour, c.hex, at: date) }
    for s in loser.swatches {
        guard let w = winner.swatch(s.id) else { out.bury(.swatch, s.id.uuidString, at: date); continue }
        let entries = Set(w.entries.map { $0.hex })
        for e in s.entries where !entries.contains(e.hex) { out.bury(.entry, Library.entryKey(s.id, e.hex), at: date) }
    }
    if let active = loser.activeSwatchID, out.swatch(active) != nil { out.activeSwatchID = active }
    return out
}

/// The same library regardless of ordering or which swatch is the pick target on this Mac.
func canonical(_ lib: Library) -> Library {
    var out = lib
    out.activeSwatchID = nil
    out.colours.sort { $0.hex < $1.hex }
    out.swatches.sort { $0.id.uuidString < $1.id.uuidString }
    for i in out.swatches.indices { out.swatches[i].entries.sort { $0.hex < $1.hex } }
    out.deleted.sort { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }
    return out
}

/// What a person would notice changing between two copies.
struct LibraryChange: Equatable {
    var coloursAdded = 0, coloursRemoved = 0
    var swatchesAdded = 0, swatchesRemoved = 0, swatchesChanged = 0

    var isEmpty: Bool { self == LibraryChange() }

    var lines: [String] {
        var out: [String] = []
        if coloursAdded > 0 { out.append("\(plural(coloursAdded, "new colour"))") }
        if swatchesAdded > 0 { out.append("\(plural(swatchesAdded, "new swatch", "new swatches"))") }
        if swatchesChanged > 0 { out.append("\(plural(swatchesChanged, "changed swatch", "changed swatches"))") }
        if coloursRemoved > 0 { out.append("\(plural(coloursRemoved, "colour")) deleted") }
        if swatchesRemoved > 0 { out.append("\(plural(swatchesRemoved, "swatch", "swatches")) deleted") }
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
    return c
}

// ---------- Catalogues ----------
//
// A catalogue is a whole library — colours and swatches — kept in its own folder.
// "Main" is the original library, left exactly where it always was.

struct Catalogues {
    static let mainName = "Main"
    static let currentKey = "currentCatalogue"

    let root: URL
    let legacyURL: URL?

    static let standard: Catalogues = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // MMFFDEV_COLOUR2_HOME points the app at another folder, for trying things without touching real data.
        let override = ProcessInfo.processInfo.environment["MMFFDEV_COLOUR2_HOME"].map { URL(fileURLWithPath: $0) }
        return Catalogues(
            root: override ?? support.appendingPathComponent("MMFFDev Colour 2"),
            legacyURL: support.appendingPathComponent("MMFFDev Colour").appendingPathComponent("library.json"))
    }()

    /// The catalogue last opened on this Mac.
    static var currentName: String {
        get {
            let saved = preferences.string(forKey: currentKey) ?? mainName
            return standard.names().contains(saved) ? saved : mainName
        }
        set { preferences.set(newValue, forKey: currentKey) }
    }

    var folder: URL { root.appendingPathComponent("Catalogues") }

    func directory(for name: String) -> URL {
        name == Catalogues.mainName ? root : folder.appendingPathComponent(filesystemName(name))
    }

    func store(for name: String) -> LibraryStore {
        LibraryStore(directory: directory(for: name), legacyURL: name == Catalogues.mainName ? legacyURL : nil)
    }

    /// Main first, then the rest alphabetically.
    func names() -> [String] {
        [Catalogues.mainName] + Catalogues.subfoldersHoldingLibraries(in: folder)
            .filter { $0 != Catalogues.mainName }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func subfoldersHoldingLibraries(in dir: URL) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { name in
            let d = dir.appendingPathComponent(name)
            return fm.fileExists(atPath: d.appendingPathComponent("library.json").path)
                || fm.fileExists(atPath: d.appendingPathComponent(".library.json.icloud").path)
        }
    }

    /// Creates an empty catalogue. The name is made unique and safe for a folder.
    @discardableResult
    func create(_ raw: String, holding library: Library = Library()) throws -> String {
        let name = uniqueName(filesystemName(raw), among: names())
        let dir = directory(for: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try LibraryStore(directory: dir, legacyURL: nil).save(library)
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
    static let folderName = "MMFFDev Colour 2 Sync"

    let store: LibraryStore
    /// The "MMFFDev Colour 2 Sync" folder.
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

/// Preferences for this Mac. A trial run (MMFFDEV_COLOUR2_HOME set) gets its own, so it can
/// never pick up — or sync into — the real sync folder.
let preferences: UserDefaults = {
    guard ProcessInfo.processInfo.environment["MMFFDEV_COLOUR2_HOME"] != nil else { return .standard }
    return UserDefaults(suiteName: "com.mmffdev.mmffdevcolour2.trial") ?? .standard
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

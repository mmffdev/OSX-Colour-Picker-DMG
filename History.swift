import Foundation

// ---------- History ----------
//
// Every change to the library is a step, like Photoshop's History panel: a title, a time, and what
// the change did. Since 2026-10-09 a step holds the change itself, not the whole library after it:
// each record, palette, colour and tag the step touched, as it was before and as it is after, and
// the schema when that changed. Going back applies the steps' inverses to the library as it
// stands; going forward applies them again. A long history stays small, and a rename undone puts
// the old name back on disk, because every state the history reaches is written as the tree.

/// One thing as it was before a step and as it is after. Absent before: it was made. Absent after: it was removed.
struct Change<T: Codable & Equatable>: Codable, Equatable {
    var before: T?
    var after: T?
    var inverse: Change<T> { Change(before: after, after: before) }
}

/// What one step did to the library.
struct LibraryDelta: Codable, Equatable {
    var projects: [String: Change<Project>] = [:]
    var swatches: [String: Change<Swatch>] = [:]
    var colours: [String: Change<Colour>] = [:]
    var tags: [String: Change<TagInfo>] = [:]
    var profiles: [String: Change<ColourProfile>] = [:]
    /// The order of each list, by key, when things on both sides changed places: "projects", "swatches", "colours", "tags", "profiles".
    var order: [String: Change<[String]>] = [:]
    /// Where each thing added sits in its list after the step, by list and key, so it goes back to the same place.
    var placed: [String: [String: Int]] = [:]
    /// Where each thing removed sat in its list before the step, by list and key.
    var unplaced: [String: [String: Int]] = [:]
    var active: Change<UUID>?
    var version: Change<Int>?
    var deleted: Change<[Tombstone]>?
    var schema: Change<SchemaTrial.SchemaFile>?

    var isEmpty: Bool {
        projects.isEmpty && swatches.isEmpty && colours.isEmpty && tags.isEmpty && profiles.isEmpty && order.isEmpty
            && active == nil && version == nil && deleted == nil && schema == nil
    }

    static func tagKey(_ t: TagInfo) -> String { t.name.lowercased() + "|" + (t.projectID?.uuidString ?? "") }

    /// The change from `a` to `b`.
    static func between(_ a: Library, _ b: Library) -> LibraryDelta {
        var d = LibraryDelta()
        func diff<T: Equatable>(_ x: [T], _ y: [T], _ name: String, key: (T) -> String) -> [String: Change<T>] {
            let mx = Dictionary(x.map { (key($0), $0) }, uniquingKeysWith: { f, _ in f }), my = Dictionary(y.map { (key($0), $0) }, uniquingKeysWith: { f, _ in f })
            var out: [String: Change<T>] = [:]
            for k in Set(mx.keys).union(my.keys) where mx[k] != my[k] { out[k] = Change(before: mx[k], after: my[k]) }
            // The order is recorded only when things on both sides changed places; what was added or removed keeps its place by index.
            let ox = x.map(key), oy = y.map(key)
            let both = Set(ox).intersection(oy)
            if ox.filter({ both.contains($0) }) != oy.filter({ both.contains($0) }) { d.order[name] = Change(before: ox, after: oy) }
            for (i, k) in oy.enumerated() where mx[k] == nil { d.placed[name, default: [:]][k] = i }
            for (i, k) in ox.enumerated() where my[k] == nil { d.unplaced[name, default: [:]][k] = i }
            return out
        }
        d.projects = diff(a.projects, b.projects, "projects") { $0.id.uuidString }
        d.swatches = diff(a.swatches, b.swatches, "swatches") { $0.id.uuidString }
        d.colours = diff(a.colours, b.colours, "colours") { $0.hex }
        d.tags = diff(a.tagInfo, b.tagInfo, "tags", key: tagKey)
        d.profiles = diff(a.colourProfiles, b.colourProfiles, "profiles") { $0.id.uuidString }
        if a.activeSwatchID != b.activeSwatchID { d.active = Change(before: a.activeSwatchID, after: b.activeSwatchID) }
        if a.version != b.version { d.version = Change(before: a.version, after: b.version) }
        if a.deleted != b.deleted { d.deleted = Change(before: a.deleted, after: b.deleted) }
        return d
    }

    /// The library after this change.
    func applied(to lib: Library) -> Library {
        var out = lib
        func apply<T>(_ list: inout [T], _ changes: [String: Change<T>], _ name: String, key: (T) -> String) {
            guard !changes.isEmpty || order[name] != nil else { return }
            var map = Dictionary(list.map { (key($0), $0) }, uniquingKeysWith: { f, _ in f })
            var ids = list.map(key)
            var added: [(String, Int)] = []
            for (k, c) in changes {
                if let after = c.after { if map[k] == nil { added.append((k, placed[name]?[k] ?? Int.max)) }; map[k] = after }
                else { map[k] = nil; ids.removeAll { $0 == k } }
            }
            for (k, at) in added.sorted(by: { $0.1 < $1.1 }) { ids.insert(k, at: min(at, ids.count)) }
            if let o = order[name]?.after {
                let known = Set(o)
                ids = o.filter { map[$0] != nil } + ids.filter { !known.contains($0) }
            }
            list = ids.compactMap { map[$0] }
        }
        apply(&out.projects, projects, "projects") { $0.id.uuidString }
        apply(&out.swatches, swatches, "swatches") { $0.id.uuidString }
        apply(&out.colours, colours, "colours") { $0.hex }
        apply(&out.tagInfo, tags, "tags", key: LibraryDelta.tagKey)
        apply(&out.colourProfiles, profiles, "profiles") { $0.id.uuidString }
        if let a = active { out.activeSwatchID = a.after }
        if let v = version?.after { out.version = v }
        if let t = deleted?.after { out.deleted = t }
        return out
    }

    /// The same change the other way.
    var inverse: LibraryDelta {
        var d = LibraryDelta()
        d.projects = projects.mapValues { $0.inverse }
        d.swatches = swatches.mapValues { $0.inverse }
        d.colours = colours.mapValues { $0.inverse }
        d.tags = tags.mapValues { $0.inverse }
        d.profiles = profiles.mapValues { $0.inverse }
        d.order = order.mapValues { $0.inverse }
        d.placed = unplaced
        d.unplaced = placed
        d.active = active?.inverse
        d.version = version?.inverse
        d.deleted = deleted?.inverse
        d.schema = schema?.inverse
        return d
    }

    /// This change followed by `next`, as one.
    func followed(by next: LibraryDelta) -> LibraryDelta {
        func join<T>(_ a: [String: Change<T>], _ b: [String: Change<T>]) -> [String: Change<T>] {
            var out: [String: Change<T>] = [:]
            for k in Set(a.keys).union(b.keys) {
                let before = a[k].map { $0.before } ?? b[k]!.before, after = b[k].map { $0.after } ?? a[k]!.after
                if before != after { out[k] = Change(before: before, after: after) }
            }
            return out
        }
        func joinOne<T>(_ a: Change<T>?, _ b: Change<T>?) -> Change<T>? {
            guard a != nil || b != nil else { return nil }
            let before = a.map { $0.before } ?? b?.before, after = b.map { $0.after } ?? a?.after
            return before == after ? nil : Change(before: before, after: after)
        }
        var d = LibraryDelta()
        d.projects = join(projects, next.projects)
        d.swatches = join(swatches, next.swatches)
        d.colours = join(colours, next.colours)
        d.tags = join(tags, next.tags)
        d.profiles = join(profiles, next.profiles)
        d.order = join(order, next.order)
        // What the joined step adds sits where the later step put it, or the earlier one; what it removes sat where the earlier step had it.
        func places<T>(_ joined: [String: Change<T>], _ name: String) {
            for (k, c) in joined {
                if c.before == nil, let at = next.placed[name]?[k] ?? placed[name]?[k] { d.placed[name, default: [:]][k] = at }
                if c.after == nil, let at = unplaced[name]?[k] ?? next.unplaced[name]?[k] { d.unplaced[name, default: [:]][k] = at }
            }
        }
        places(d.projects, "projects"); places(d.swatches, "swatches"); places(d.colours, "colours"); places(d.tags, "tags"); places(d.profiles, "profiles")
        d.active = joinOne(active, next.active)
        d.version = joinOne(version, next.version)
        d.deleted = joinOne(deleted, next.deleted)
        d.schema = joinOne(schema, next.schema)
        return d
    }

    /// The one project the change touched, by its record or its palettes; nil when none or several did.
    var projectTouched: UUID? {
        var touched = Set(projects.keys.compactMap { UUID(uuidString: $0) })
        for c in swatches.values { for p in [c.before?.projectID, c.after?.projectID].compactMap({ $0 }) { touched.insert(p) } }
        return touched.count == 1 ? touched.first : nil
    }
}

struct HistoryStep: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    /// The project the step touched, when exactly one did.
    let project: UUID?
    /// What the step did.
    var delta: LibraryDelta
}

struct StepHistory: Codable, Equatable {
    var steps: [HistoryStep] = []
    /// The step the library matches now; -1 while there are none.
    var current: Int = -1

    var isEmpty: Bool { steps.isEmpty }

    /// Adds a step. Taken from an earlier step, the ones after it go. `limit` 0 keeps every step. The first step of a
    /// history, with nothing before it, is a marker: the library as it was when the history began.
    mutating func record(_ title: String, library: Library, before: Library?, schema: (before: SchemaTrial.SchemaFile, after: SchemaTrial.SchemaFile)? = nil, limit: Int, at date: Date = Date()) {
        if current < steps.count - 1 { steps.removeSubrange((current + 1)...) }
        var delta = before.map { LibraryDelta.between($0, library) } ?? LibraryDelta()
        if let s = schema, s.before != s.after { delta.schema = Change(before: s.before, after: s.after) }
        steps.append(HistoryStep(id: UUID(), date: date, title: title, project: delta.projectTouched, delta: delta))
        if limit > 0, steps.count > limit { steps.removeFirst(steps.count - limit) }
        current = steps.count - 1
    }

    /// The library and schema as they were at the step, worked out from how they stand now; the step becomes the current one.
    mutating func go(to index: Int, from library: Library, schema: SchemaTrial.SchemaFile) -> (library: Library, schema: SchemaTrial.SchemaFile)? {
        guard steps.indices.contains(index), current >= 0 else { return nil }
        var lib = library, sch = schema
        if index < current {
            for i in stride(from: current, to: index, by: -1) {
                let back = steps[i].delta.inverse
                lib = back.applied(to: lib)
                if let s = back.schema?.after { sch = s }
            }
        } else if index > current {
            for i in (current + 1)...index {
                lib = steps[i].delta.applied(to: lib)
                if let s = steps[i].delta.schema?.after { sch = s }
            }
        }
        current = index
        return (lib, sch)
    }

    /// Takes a step out. Its change folds into the step after it, so the chain still adds up; the last step simply goes.
    mutating func delete(at index: Int) {
        guard steps.indices.contains(index) else { return }
        if index + 1 < steps.count { steps[index + 1].delta = steps[index].delta.followed(by: steps[index + 1].delta) }
        steps.remove(at: index)
        if current >= index { current -= 1 }
        if current < 0, !steps.isEmpty { current = 0 }
    }

    /// The steps that touched one project, oldest first.
    func steps(in project: UUID) -> [HistoryStep] { steps.filter { $0.project == project } }

    /// The steps that changed one palette, oldest first.
    func steps(changing palette: UUID) -> [HistoryStep] { steps.filter { $0.delta.swatches[palette.uuidString] != nil } }
}

/// One thing that happened to one colour in one palette: the step, and what it did, in words.
struct SwatchStep: Equatable {
    /// The step's place in the whole history.
    let index: Int
    let step: HistoryStep
    let what: String
    /// The colour's name and description in the palette after the step; nil once it has gone.
    let entry: SwatchEntry?
}

extension StepHistory {
    /// Everything that happened to a colour in a palette, oldest first: added, renamed, described,
    /// tagged, removed. Read off what each step did.
    func steps(changing hex: String, in palette: UUID) -> [SwatchStep] {
        var out: [SwatchStep] = []
        for (i, step) in steps.enumerated() {
            let change = step.delta.swatches[palette.uuidString]
            let was = change?.before?.entries.first { $0.hex == hex }
            let now = change?.after?.entries.first { $0.hex == hex }
            var what: [String] = []
            if change != nil {
                switch (was, now) {
                case (nil, nil): break
                case (nil, _?): what.append("Added")
                case (_?, nil): what.append("Removed")
                case let (w?, n?):
                    if w.name != n.name { what.append(n.name.map { "Renamed \u{201C}\($0)\u{201D}" } ?? "Standard Name Restored") }
                    if w.note != n.note { what.append(n.note == nil ? "Description Removed" : w.note == nil ? "Description Written" : "Description Edited") }
                }
            }
            if let c = step.delta.colours[hex], c.before != nil, c.after != nil, (c.before?.tags ?? []) != (c.after?.tags ?? []), was != nil || now != nil || change == nil {
                let tagsNow = c.after?.tags ?? []
                what.append(tagsNow.isEmpty ? "Tags Removed" : "Tagged " + tagsNow.joined(separator: ", "))
            }
            if !what.isEmpty { out.append(SwatchStep(index: i, step: step, what: what.joined(separator: "  \u{00B7}  "), entry: now)) }
        }
        return out
    }
}

/// What a step did to the colours.
struct StepChange: Equatable {
    var added: [String] = []
    var removed: [String] = []
    var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

extension StepHistory {
    /// Colours the step brought in or took out: new to the library, or new to or gone from a palette.
    func change(at index: Int) -> StepChange {
        guard steps.indices.contains(index) else { return StepChange() }
        let d = steps[index].delta
        var change = StepChange()
        let made = d.colours.filter { $0.value.before == nil && $0.value.after != nil }.map { $0.key }
        change.added = made.sorted { (d.placed["colours"]?[$0] ?? Int.max, $0) < (d.placed["colours"]?[$1] ?? Int.max, $1) }
        change.removed = d.colours.filter { $0.value.before != nil && $0.value.after == nil }.map { $0.key }.sorted()
        if change.isEmpty {
            // Within palettes: a colour added to or removed from one.
            for key in d.swatches.keys.sorted() {
                let c = d.swatches[key]!
                let was = Set(c.before?.entries.map { $0.hex } ?? []), now = c.after?.entries.map { $0.hex } ?? []
                for hex in now where !was.contains(hex) { change.added.append(hex) }
                let nowSet = Set(now)
                for e in c.before?.entries ?? [] where !nowSet.contains(e.hex) { change.removed.append(e.hex) }
            }
        }
        return change
    }
}

private let stepClock: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()
private let stepDayAndClock: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    f.doesRelativeDateFormatting = true
    return f
}()

/// When a step happened, as shown beside it: the time today, the day as well before that.
func stepStamp(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? stepClock.string(from: date) : stepDayAndClock.string(from: date)
}

/// The symbol for a step, by what its title says it did.
func stepSymbol(for title: String) -> String {
    let t = title.lowercased()
    if t.hasPrefix("opened") { return "clock" }
    if t.hasPrefix("sync") { return "arrow.triangle.2.circlepath" }
    if t.hasPrefix("pick") { return "eyedropper" }
    if t.contains("send picks") { return "scope" }
    if t.hasPrefix("add colour") || t.hasPrefix("keep colours") || t.hasPrefix("create palette") { return "plus.circle" }
    if t.hasPrefix("remove") || t.hasPrefix("delete colour") { return "minus.circle" }
    if t.hasPrefix("delete") { return "trash" }
    if t.hasPrefix("rename") { return "pencil" }
    if t.hasPrefix("describe") { return "text.alignleft" }
    if t.contains("colour profile") { return "dial.medium" }
    if t.contains("star") { return "star" }
    if t.contains("tag") { return "tag" }
    if t.contains("pairing") || t.contains("typography") || t.contains("font") { return "textformat" }
    if t.contains("schema") || t.contains("template") { return "square.stack.3d.up" }
    if t.contains("brought across") || t.contains("migrat") { return "arrow.up.doc" }
    if t.contains("project") { return "folder" }
    if t.hasPrefix("arrange") || t.hasPrefix("move") { return "arrow.up.arrow.down" }
    if t.contains("palette") { return "swatchpalette" }
    if t.contains("import") { return "square.and.arrow.down" }
    if t.contains("export") { return "square.and.arrow.up" }
    return "circle"
}

/// Where the history goes: "Rick 001.colhistory" beside the catalogue's index.
enum HistoryStore {
    struct File: Codable {
        var format = "colour-history"
        var version = 2
        var generator = ColourFiles.generator
        var steps: [HistoryStep]
        var current: Int
    }

    static func url(beside index: URL) -> URL { index.deletingPathExtension().appendingPathExtension(ColourFiles.history) }

    static func load(beside index: URL) -> StepHistory {
        guard let data = try? Data(contentsOf: url(beside: index)), let f = try? ColourFiles.decoder().decode(File.self, from: data), f.format == "colour-history", f.version >= 2 else { return StepHistory() }
        return StepHistory(steps: f.steps, current: min(f.current, f.steps.count - 1))
    }

    static func save(_ history: StepHistory, beside index: URL) throws {
        try ColourFiles.encoder().encode(File(steps: history.steps, current: history.current)).write(to: url(beside: index), options: .atomic)
    }
}

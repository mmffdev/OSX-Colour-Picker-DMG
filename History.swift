import Foundation

// ---------- History ----------
//
// Every change to the library is a step, like Photoshop's History panel: a title, a time, and the
// library as it was after the change. Clicking a step takes the library back to it; the later steps
// stay until a new change is made from there, which cuts them off. Steps hold only metadata (names,
// colours, order, tags), so even a long history is small.

struct HistoryStep: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    /// The project the step touched, when exactly one did.
    let project: UUID?
    /// The library after the step.
    let library: Library
}

struct StepHistory: Codable, Equatable {
    var steps: [HistoryStep] = []
    /// The step the library matches now; -1 while there are none.
    var current: Int = -1

    var isEmpty: Bool { steps.isEmpty }

    /// Adds a step. Taken from an earlier step, the ones after it go. `limit` 0 keeps every step.
    mutating func record(_ title: String, library: Library, before: Library?, limit: Int, at date: Date = Date()) {
        if current < steps.count - 1 { steps.removeSubrange((current + 1)...) }
        let project = before.flatMap { library.projectTouched(since: $0) }
        steps.append(HistoryStep(id: UUID(), date: date, title: title, project: project, library: library))
        if limit > 0, steps.count > limit { steps.removeFirst(steps.count - limit) }
        current = steps.count - 1
    }

    /// The library as it was at the step, now the current one.
    mutating func go(to index: Int) -> Library? {
        guard steps.indices.contains(index) else { return nil }
        current = index
        return steps[index].library
    }

    mutating func delete(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
        if current >= index { current -= 1 }
        if current < 0, !steps.isEmpty { current = 0 }
    }

    /// The steps that touched one project, oldest first.
    func steps(in project: UUID) -> [HistoryStep] { steps.filter { $0.project == project } }

    /// The steps that changed one palette's colours or name, oldest first, each paired with the step before it.
    func steps(changing palette: UUID) -> [HistoryStep] {
        var out: [HistoryStep] = []
        var previous: Swatch?
        for (i, step) in steps.enumerated() {
            let now = step.library.swatch(palette)
            if i > 0, now != previous { out.append(step) }
            previous = now
        }
        return out
    }
}

/// What a step did to the colours, read off the libraries before and after it.
struct StepChange: Equatable {
    var added: [String] = []
    var removed: [String] = []
    var isEmpty: Bool { added.isEmpty && removed.isEmpty }
}

extension StepHistory {
    /// Colours the step brought in or took out: new to the library, or new to or gone from a palette.
    func change(at index: Int) -> StepChange {
        guard index > 0, steps.indices.contains(index) else { return StepChange() }
        let before = steps[index - 1].library, after = steps[index].library
        var change = StepChange()
        let had = Set(before.colours.map { $0.hex }), has = Set(after.colours.map { $0.hex })
        change.added = after.colours.map { $0.hex }.filter { !had.contains($0) }
        change.removed = before.colours.map { $0.hex }.filter { !has.contains($0) }
        if change.isEmpty {
            // Within palettes: a colour added to or removed from one.
            for s in after.swatches {
                let was = Set(before.swatch(s.id)?.entries.map { $0.hex } ?? [])
                for e in s.entries where !was.contains(e.hex) { change.added.append(e.hex) }
            }
            for s in before.swatches {
                let now = Set(after.swatch(s.id)?.entries.map { $0.hex } ?? [])
                for e in s.entries where !now.contains(e.hex) { change.removed.append(e.hex) }
            }
        }
        return change
    }
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
    if t.contains("star") { return "star" }
    if t.contains("tag") { return "tag" }
    if t.contains("pairing") || t.contains("typography") || t.contains("font") { return "textformat" }
    if t.contains("project") { return "folder" }
    if t.hasPrefix("arrange") || t.hasPrefix("move") { return "arrow.up.arrow.down" }
    if t.contains("palette") { return "swatchpalette" }
    if t.contains("import") { return "square.and.arrow.down" }
    return "circle"
}

extension Library {
    /// The one project whose record or palettes differ from `old`; nil when none or several do.
    func projectTouched(since old: Library) -> UUID? {
        var touched = Set<UUID>()
        for id in Set((projects + old.projects).map { $0.id }) {
            if project(id) != old.project(id) || palettes(in: id) != old.palettes(in: id) { touched.insert(id) }
        }
        return touched.count == 1 ? touched.first : nil
    }
}

/// Where the history goes: a sidecar file beside the library, "library.history.json".
enum HistoryStore {
    static func url(beside library: URL) -> URL { library.deletingLastPathComponent().appendingPathComponent("library.history.json") }

    static func load(beside library: URL) -> StepHistory {
        guard let data = try? Data(contentsOf: url(beside: library)), let h = try? JSONDecoder.library.decode(StepHistory.self, from: data) else { return StepHistory() }
        return h
    }

    static func save(_ history: StepHistory, beside library: URL) throws {
        try JSONEncoder.library.encode(history).write(to: url(beside: library), options: .atomic)
    }
}

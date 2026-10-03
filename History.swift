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

import Foundation

// ---------- What the project form remembers ----------
//
// A small local store of what has been typed into project forms on this Mac, so it need not be
// typed again. Two things are kept each time a form is saved:
//
//   - every field's value, under that field, newest first: Company remembers "ACME Company";
//   - every section as a whole, under the name of its leading field: the Client section is kept
//     as "ACME Company", with the contact, email, address and the rest that went with it.
//
// A section saved again under the same name replaces what was kept. Plain JSON, one file beside
// the catalogues ("form-memory.json"); it belongs to this Mac and is not part of any library.

struct FormMemory: Codable, Equatable {
    struct SectionRecord: Codable, Equatable {
        let id: UUID
        var name: String
        /// Field key to value, for the fields of the one section.
        var values: [String: String]
        /// When it was last saved. With the id, this is what a sync between Macs or with a server will go by.
        var savedAt: Date
    }

    /// Field key to the values typed there, newest first.
    var values: [String: [String]] = [:]
    /// Section name to the sets kept for it, newest first.
    var sections: [String: [SectionRecord]] = [:]

    /// How many values one field keeps before the oldest is dropped.
    static let limit = 40

    /// The field a section's record is named by; nil for sections that belong to one job only.
    static func lead(of section: ProjectField.Section) -> [ProjectField] {
        switch section {
        case .client: return [.clientCompany, .clientContact]
        case .studio: return [.ownerCompany, .ownerName]
        case .rights: return [.copyright]
        case .colour: return [.colourSpace]
        case .project, .notes: return []
        }
    }

    /// Whether a field keeps what is typed in it: text does, a fixed choice has nothing to remember.
    static func remembers(_ field: ProjectField) -> Bool {
        if case .choice = field.kind { return false }
        return true
    }

    func remembered(for field: ProjectField) -> [String] { values[field.rawValue] ?? [] }
    func records(for section: ProjectField.Section) -> [SectionRecord] { sections[section.rawValue] ?? [] }

    /// Takes in a saved form: each field's value, and each section under its leading field's value.
    mutating func remember(_ answers: [String: String], at date: Date = Date()) {
        func text(_ field: ProjectField) -> String { (answers[field.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        for field in ProjectField.allCases where FormMemory.remembers(field) {
            let value = text(field)
            guard !value.isEmpty else { continue }
            var list = remembered(for: field).filter { $0 != value }
            list.insert(value, at: 0)
            values[field.rawValue] = Array(list.prefix(FormMemory.limit))
        }
        for section in ProjectField.Section.allCases {
            guard let name = FormMemory.lead(of: section).map(text).first(where: { !$0.isEmpty }) else { continue }
            var kept: [String: String] = [:]
            for field in ProjectField.fields(in: section) where !text(field).isEmpty { kept[field.rawValue] = text(field) }
            var list = records(for: section)
            // The same name again is the same client, studio or terms: what was kept is replaced, its id stays.
            let id = list.first { $0.name.lowercased() == name.lowercased() }?.id ?? UUID()
            list.removeAll { $0.id == id }
            list.insert(SectionRecord(id: id, name: name, values: kept, savedAt: date), at: 0)
            sections[section.rawValue] = list
        }
    }

    mutating func forget(_ value: String, for field: ProjectField) {
        values[field.rawValue] = remembered(for: field).filter { $0 != value }
    }

    mutating func forget(record id: UUID, in section: ProjectField.Section) {
        sections[section.rawValue] = records(for: section).filter { $0.id != id }
    }

    /// A form's answers with one section replaced by a kept record: its fields take the record's
    /// values, and fields of the section the record has nothing for are cleared.
    func filling(_ answers: [String: String], with record: SectionRecord, in section: ProjectField.Section) -> [String: String] {
        var out = answers
        for field in ProjectField.fields(in: section) { out[field.rawValue] = record.values[field.rawValue] ?? "" }
        return out
    }
}

enum FormMemoryStore {
    static var url: URL { Catalogues.standard.root.appendingPathComponent("form-memory.json") }

    static func load(from url: URL = url) -> FormMemory {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: url), let memory = try? d.decode(FormMemory.self, from: data) else { return FormMemory() }
        return memory
    }

    static func save(_ memory: FormMemory, to url: URL = url) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .millisecondsSince1970   // whole numbers, so the file reads back exactly as written
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(memory).write(to: url, options: .atomic)
    }

    /// Reads, changes and writes in one go; a failure to write is reported to the caller.
    @discardableResult
    static func update(_ change: (inout FormMemory) -> Void) -> Bool {
        var memory = load()
        change(&memory)
        return (try? save(memory)) != nil
    }
}

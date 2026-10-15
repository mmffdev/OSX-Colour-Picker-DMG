import Foundation

struct FileApplicationIdentity: Codable, Equatable {
    var bundleIdentifier: String
    var name: String
    var version: String
    var build: String
    var commit: String?
    static func current(bundle: Bundle = .main) -> FileApplicationIdentity {
        FileApplicationIdentity(bundleIdentifier: bundle.bundleIdentifier ?? "com.mmffdev.mmffdevcolour3.development",
                                name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Brand.name,
                                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
                                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
                                commit: bundle.object(forInfoDictionaryKey: "ColourBuildCommit") as? String)
    }
}

struct FileCreatorIdentity: Codable, Equatable {
    var displayName: String
    var accountName: String?
    var actor: String = "Person"
}

/// Strings deliberately use ISO 8601 regardless of the domain codec's Date strategy.
struct FileDocumentHeader: Codable, Equatable {
    var metadataVersion = 1
    var documentID: String
    var createdAt: String?
    var createdBy: FileCreatorIdentity?
    var createdWith: FileApplicationIdentity?
    var lastSavedAt: String
    var lastSavedBy: FileCreatorIdentity
    var lastSavedWith: FileApplicationIdentity
    var derivedFrom: String?

    func validate() throws {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard metadataVersion == 1, !documentID.isEmpty, documentID.utf8.count <= 512,
              formatter.date(from: lastSavedAt) != nil, createdAt == nil || formatter.date(from: createdAt!) != nil,
              !lastSavedBy.displayName.isEmpty, lastSavedBy.displayName.count <= 512 else { throw failure("Invalid or unsupported file metadata. The original has been retained.") }
    }

    static func stamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    func forSharing(includePersonalNames: Bool) -> FileDocumentHeader {
        guard !includePersonalNames else { return self }
        var copy = self
        copy.createdBy = copy.createdBy.map { _ in FileCreatorIdentity(displayName: "Not Shared", accountName: nil) }
        copy.lastSavedBy = FileCreatorIdentity(displayName: "Not Shared", accountName: nil)
        return copy
    }
}

struct FileMetadataProvider {
    var now: () -> Date = { Date() }
    var identifier: () -> String = { UUID().uuidString }
    var application: () -> FileApplicationIdentity = { .current() }
    var creator: () -> FileCreatorIdentity = {
        let chosen = preferences.string(forKey: "fileCreator.displayName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FileCreatorIdentity(displayName: chosen.flatMap { $0.isEmpty ? nil : $0 } ?? NSFullUserName(), accountName: NSUserName())
    }

    func header(identity: String?, previous: [String: Any]?, existing: Bool, derivedFrom: String? = nil) throws -> [String: Any] {
        let date = FileDocumentHeader.stamp(now()), person = creator(), app = application()
        var header: FileDocumentHeader
        if let previous {
            header = try JSONDecoder().decode(FileDocumentHeader.self, from: JSONSerialization.data(withJSONObject: previous))
            guard header.metadataVersion == 1, identity == nil || header.documentID.caseInsensitiveCompare(identity!) == .orderedSame else { throw failure("File metadata identity does not match its contents.") }
            header.lastSavedAt = date; header.lastSavedBy = person; header.lastSavedWith = app
        } else {
            header = FileDocumentHeader(documentID: identity ?? identifier(), createdAt: existing ? nil : date,
                                        createdBy: existing ? nil : person, createdWith: existing ? nil : app,
                                        lastSavedAt: date, lastSavedBy: person, lastSavedWith: app, derivedFrom: derivedFrom)
        }
        var result = previous ?? [:]
        let values = try JSONSerialization.jsonObject(with: JSONEncoder().encode(header)) as! [String: Any]
        for (key, value) in values { result[key] = value }
        return result
    }
}

import Foundation

final class Handler_File_App_Data: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "App Data", extensions: ["coldata"], format: nil, versions: [1])) { data in
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["format"] == nil,
                  object["catalogues"] is [[String: Any]], object["settings"] is [String: Any] else { throw failure("Invalid workspace manifest. Historical project data must be imported through migration.") }
            return data // The manifest's open schema intentionally retains unrelated/future fields.
        }
    }
    override func identity(_ object: [String: Any]) -> String? { object["workspaceID"] as? String }
    override func references(_ object: [String: Any], at url: URL) throws -> [FileReference] {
        try ["keys", "assets", "history"].compactMap { key in
            guard let path = object[key] as? String else { return nil }
            return FileReference(url: try Handler_File_Manager.contained(path, under: url.deletingLastPathComponent()), identity: nil, kind: key)
        }
    }
}

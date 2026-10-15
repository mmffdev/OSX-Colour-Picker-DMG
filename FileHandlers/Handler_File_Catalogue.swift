import Foundation

final class Handler_File_Catalogue: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Catalogue", extensions: ["colcat"], format: "colour-catalogue", versions: [3])) {
            try Handler_File_JSON.codec(CatalogueFile.self, $0)
        }
    }
    override func references(_ object: [String: Any], at url: URL) throws -> [FileReference] {
        let root = url.deletingLastPathComponent()
        var result: [FileReference] = []
        func add(_ path: String, id: String?, kind: String) throws {
            result.append(FileReference(url: try Handler_File_Manager.contained(path, under: root), identity: id, kind: kind))
        }
        func assets(_ list: [[String: Any]]) throws {
            for item in list {
                guard let file = item["file"] as? String else { throw failure("An asset reference has no location.") }
                try add(file, id: item["id"] as? String, kind: item["kind"] as? String ?? "Asset")
            }
        }
        func members(_ list: [[String: Any]]) throws {
            for member in list {
                if let file = member["information"] as? String { try add(file, id: member["id"] as? String, kind: "Information") }
                try assets(member["assets"] as? [[String: Any]] ?? [])
            }
        }
        func groups(_ list: [[String: Any]], parent: String) throws {
            for group in list {
                let path = parent + "/" + (group["folder"] as? String ?? "")
                try add(path, id: group["id"] as? String, kind: "Folder")
                try members(group["members"] as? [[String: Any]] ?? [])
                try groups(group["groups"] as? [[String: Any]] ?? [], parent: path)
            }
        }
        try assets(object["libraryAssets"] as? [[String: Any]] ?? [])
        for key in ["swatches", "profiles", "history"] { if let path = object[key] as? String { try add(path, id: nil, kind: key) } }
        for collection in object["collections"] as? [[String: Any]] ?? [] {
            let path = collection["folder"] as? String ?? ""
            try add(path, id: collection["id"] as? String, kind: "Folder")
            try members(collection["members"] as? [[String: Any]] ?? [])
            try groups(collection["groups"] as? [[String: Any]] ?? [], parent: path)
        }
        return result
    }
}

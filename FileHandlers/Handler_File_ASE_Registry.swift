import Foundation

final class Handler_File_ASE_Registry: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "ASE Registry", extensions: ["colase"], format: nil, versions: [1])) { data in
            let document = try JSONDecoder().decode(ASERegistry.Document.self, from: data)
            guard document.sources.count <= 2000, Set(document.sources.map { $0.id }).count == document.sources.count else { throw failure("Invalid or duplicate ASE registry links.") }
            for source in document.sources where !source.path.hasPrefix("/") {
                guard source.path.hasPrefix(ASERegistry.directory + "/"), !source.path.split(separator: "/").contains("..") else { throw failure("Invalid relative ASE location.") }
            }
            return try Handler_File_JSON.codec(ASERegistry.Document.self, data, libraryDates: false)
        }
    }
}

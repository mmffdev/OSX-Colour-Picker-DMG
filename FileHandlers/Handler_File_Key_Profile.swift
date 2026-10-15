import Foundation

final class Handler_File_Key_Profile: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Key Profile", extensions: ["colkeys"], format: nil, versions: [1])) { data in
            let document = try ColourFiles.decoder().decode(KeyProfile.self, from: data)
            guard !document.name.isEmpty, document.name.count <= 120, document.description.count <= 2000 else { throw failure("Invalid key profile.") }

            return try Handler_File_JSON.codec(KeyProfile.self, data, libraryDates: true)
        }
    }
}

import Foundation

final class Handler_File_Information: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Information", extensions: ["colinf"], format: "colour-information", versions: [1])) { data in
            return try Handler_File_JSON.codec(InformationDocument.self, data, libraryDates: true)
        }
    }
}

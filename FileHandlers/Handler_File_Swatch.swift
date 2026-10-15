import Foundation

final class Handler_File_Swatch: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Swatch", extensions: ["colswatch"], format: "colour-swatch", versions: [1])) { data in
            return try Handler_File_JSON.codec(SwatchDocument.self, data, libraryDates: true)
        }
    }
}

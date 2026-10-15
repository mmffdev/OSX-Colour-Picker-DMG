import Foundation

final class Handler_File_Swatches: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Loose Swatches", extensions: ["colswa"], format: "colour-swatches", versions: [1])) { data in
            return try Handler_File_JSON.codec(SwatchesDocument.self, data, libraryDates: true)
        }
    }
}

import Foundation

final class Handler_File_Typography: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Typography", extensions: ["coltyp"], format: "colour-typography", versions: [1])) { data in
            let document = try ColourFiles.decoder().decode(PaletteDocument.self, from: data)
            guard (0...5).contains(document.palette.review?.rating ?? 0), Set(document.colours.map { $0.hex }).count == document.colours.count else { throw failure("Invalid palette metadata or duplicate colour identities.") }

            return try Handler_File_JSON.codec(PaletteDocument.self, data, libraryDates: true)
        }
    }
}

import Foundation

final class Handler_File_Palette: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Palette", extensions: ["colpal", "colpalette"], format: nil, versions: [1])) { data in
            let document = try ColourFiles.decoder().decode(PaletteDocument.self, from: data)
            guard ["colour-palette", "colour-typography"].contains(document.format) else { throw failure("Unsupported palette format.") }
            guard (0...5).contains(document.palette.review?.rating ?? 0), Set(document.colours.map { $0.hex }).count == document.colours.count else { throw failure("Invalid palette metadata or duplicate colour identities.") }

            return try ColourFiles.encoder().encode(document)
        }
    }

}

extension Handler_File_JSON {
    /// Catalogue inspection needs the validated document as well as its identity.
    /// Validate the envelope and payload once without producing unused canonical bytes.
    func inspectedDocument(_ data: Data, object: [String: Any], at url: URL) throws -> PaletteDocument {
        guard data.count <= descriptor.maximumBytes,
              let version = object["version"] as? Int,
              descriptor.versions.contains(version),
              descriptor.format == nil || object["format"] as? String == descriptor.format else {
            throw FileValidationError.unsupported(descriptor.name)
        }
        if let rawHeader = object["header"] {
            let header = try JSONDecoder().decode(FileDocumentHeader.self, from: JSONSerialization.data(withJSONObject: rawHeader))
            try header.validate()
            if let id = identity(object), header.documentID.caseInsensitiveCompare(id) != .orderedSame {
                throw failure("File metadata identity does not match its document.")
            }
        }
        let document = try PaletteAssetHandler.read(data, at: url)
        guard Set(document.colours.map(\.hex)).count == document.colours.count else {
            throw failure("Invalid palette metadata or duplicate colour identities.")
        }
        return document
    }
}

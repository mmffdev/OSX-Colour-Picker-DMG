import Foundation

final class Handler_File_QR: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Colour QR", extensions: ["colqr"], format: nil, versions: [1], maximumBytes: ColourQR.limit)) { data in
            _ = try ColourQR.document(data)
            return try ColourQR.knownDocumentBytes(data) // Preserve unknown fields separately from the supported projection.
        }
    }
}

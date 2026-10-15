import Foundation

final class Handler_File_Share: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name: "Share", extensions: ["colmanifest", "colshr", "colshare"], format: "colour-share", versions: [1, 2], maximumBytes: 256 * 1024 * 1024, archive: true)) { data in
            return try Handler_File_JSON.codec(ShareManifest.self, data, libraryDates: true)
        }
    }
    override func canonical(_ data: Data) throws -> Data {
        guard data.prefix(2) == Data([0x50, 0x4b]) else { return try super.canonical(data) }
        guard data.count <= descriptor.maximumBytes else { throw failure("This archive exceeds the supported size.") }
        let entries = try Zip.read(data: data, name: URL(fileURLWithPath: "Share.colshr"))
        guard let manifest = entries.first(where: { $0.path == ShareManifest.fileName }) else { throw failure("The archive has no share manifest.") }
        _ = try super.canonical(manifest.data)
        let document = try ColourFiles.decoder().decode(ShareManifest.self, from: manifest.data)
        let payload = entries.filter { $0.path != ShareManifest.fileName }
        guard Set(entries.map { $0.path.lowercased() }).count == entries.count,
              document.files.count == payload.count else { throw failure("The archive has duplicate or unlisted files.") }
        for file in document.files {
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains(".."),
                  let actual = payload.first(where: { $0.path == file.path }), actual.data.count == file.bytes,
                  Sharing.sha256(actual.data) == file.sha256 else { throw failure("An archive file does not match its manifest.") }
        }
        return data
    }
}

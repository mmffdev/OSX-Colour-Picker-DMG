import AppKit
import UniformTypeIdentifiers

/// A Designer drop is a transient image reference, never a Library import.
enum DesignerImageDrop {
    enum Payload {
        case file(URL)
        case imageData(Data)
        case remote(URL)

        var name:String {
            switch self {
            case .file(let url),.remote(let url):
                let value=url.deletingPathExtension().lastPathComponent
                return value.isEmpty ? "Dropped Image":value
            case .imageData:return "Dropped Image"
            }
        }
    }

    static let types:[NSPasteboard.PasteboardType]=[
        .fileURL,.png,.tiff,.URL,NSPasteboard.PasteboardType(UTType.image.identifier)
    ]

    static func supports(_ pasteboard:NSPasteboard)->Bool {
        imageFile(in:pasteboard) != nil || imageDataType(in:pasteboard) != nil || remoteURL(in:pasteboard) != nil
    }

    static func read(_ pasteboard:NSPasteboard)->Payload? {
        if let file=imageFile(in:pasteboard) {return .file(file)}
        if let type=imageDataType(in:pasteboard),let data=pasteboard.data(forType:type) {return .imageData(data)}
        if let image=NSImage(pasteboard:pasteboard),let data=image.tiffRepresentation {return .imageData(data)}
        if let url=remoteURL(in:pasteboard) {return .remote(url)}
        return nil
    }

    private static func imageFile(in pasteboard:NSPasteboard)->URL? {
        let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        return urls.first {url in
            url.isFileURL && (UTType(filenameExtension:url.pathExtension)?.conforms(to:.image) == true)
        }
    }

    private static func imageDataType(in pasteboard:NSPasteboard)->NSPasteboard.PasteboardType? {
        pasteboard.types?.first {type in
            type != .fileURL && UTType(type.rawValue)?.conforms(to:.image) == true
        }
    }

    private static func remoteURL(in pasteboard:NSPasteboard)->URL? {
        let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:nil) as? [URL] ?? []
        return urls.first {url in
            (url.scheme == "https" || url.scheme == "http") && url.host != nil
        }
    }
}

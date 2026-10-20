import Foundation

// Read-only bridge: this executable never opens source assets for writing.
let namespace = "urn:colorgain:metadata:1.0:"
struct ReaderError: Error, CustomStringConvertible { let description: String; init(_ s: String) { description = s } }
let limit = 16 * 1024 * 1024
final class Asset {
    let handle: FileHandle
    let size: UInt64
    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        size = try handle.seekToEnd()
    }
    deinit { try? handle.close() }
    func read(_ offset: UInt64, _ count: Int) throws -> Data {
        guard count >= 0, count <= limit, offset <= size, UInt64(count) <= size - offset else { throw ReaderError("Invalid or oversized metadata region") }
        try handle.seek(toOffset: offset)
        guard let data = try handle.read(upToCount: count), data.count == count else { throw ReaderError("Incomplete file read") }
        return data
    }
}
func embedded(_ url: URL) throws -> Data? {
    let f = try Asset(url)
    let h = try f.read(0, 8)
    let little = h[0] == 73 && h[1] == 73
    guard little || (h[0] == 77 && h[1] == 77) else { throw ReaderError("This prototype reads embedded XMP in DNG, CR2 and TIFF; other formats are not supported yet") }
    func number(_ b: Data, _ p: Int, _ n: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in 0..<n { let j = little ? n - 1 - i : i; v = (v << 8) | UInt64(b[p+j]) }
        return v
    }
    guard number(h,2,2) == 42 else { throw ReaderError("Unsupported TIFF variant") }
    var offset = number(h,4,4)
    var visited = Set<UInt64>()
    while offset != 0 {
        guard visited.insert(offset).inserted, visited.count <= 128 else { throw ReaderError("Invalid TIFF directory chain") }
        let n = Int(number(try f.read(offset,2),0,2))
        let table = try f.read(offset+2,n*12+4)
        for i in 0..<n where number(table,i*12,2) == 700 {
            let type = number(table,i*12+2,2)
            guard [1,7].contains(type) else { throw ReaderError("Unsupported XMP tag type") }
            let count = Int(number(table,i*12+4,4))
            let position = count <= 4 ? offset+2+UInt64(i*12+8) : number(table,i*12+8,4)
            return try f.read(position,count)
        }
        offset = number(table,n*12,4)
    }
    return nil
}
func properties(_ packet: Data) throws -> [String: String] {
    // XMP does not require a DTD. Reject it and all external entity loading.
    guard let xml = String(data: packet, encoding: .utf8) else { throw ReaderError("XMP is not UTF-8") }
    guard !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY") else { throw ReaderError("XMP entity declarations are not supported") }
    let document = try XMLDocument(xmlString: xml, options: [.nodeLoadExternalEntitiesNever])
    let nodes = try document.nodes(forXPath: "//@* | //*")
    var result: [String: String] = [:]
    for node in nodes where node.uri == namespace {
        guard let name = node.localName, let value = node.stringValue else { continue }
        guard result[name] == nil else { throw ReaderError("Ambiguous repeated Colorgain field: \(name)") }
        result[name] = value
    }
    return result
}
func encoded(_ s: String) -> String {
    // Encode all non-ASCII bytes as well, preserving UTF-8 in the Lua decoder.
    return s.utf8.map { b in b == 37 || b < 32 || b >= 127 ? String(format:"%%%02X",b) : String(UnicodeScalar(b)) }.joined()
}
var output: [String:String] = [:]
do {
    guard CommandLine.arguments.count == 2 else { throw ReaderError("Expected one source file path") }
    let url = URL(fileURLWithPath:CommandLine.arguments[1])
    guard FileManager.default.fileExists(atPath:url.path) else { throw ReaderError("Original file is unavailable. Reconnect its drive and refresh.") }
    let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
    var source: URL
    let packet: Data?
    if url.pathExtension.lowercased() == "xmp" || FileManager.default.fileExists(atPath:sidecar.path) {
        source = url.pathExtension.lowercased() == "xmp" ? url : sidecar
        let file = try Asset(source)
        guard file.size <= UInt64(limit) else { throw ReaderError("XMP exceeds the 16 MB read limit") }
        packet = try file.read(0,Int(file.size))
        output["storage"] = "External XMP"
    } else {
        source = url; packet = try embedded(url); output["storage"] = "Embedded XMP"
    }
    output["source"] = source.path
    var fields = try packet.map(properties) ?? [:]
    // For our custom namespace only, an ordinary Adobe-only sidecar must not hide
    // embedded Colorgain fields. A sidecar containing Colorgain fields wins as a unit.
    if fields.isEmpty && source != url {
        let ext = url.pathExtension.lowercased()
        if ["dng", "cr2", "tif", "tiff"].contains(ext), let embeddedPacket = try embedded(url) {
            let embeddedFields = try properties(embeddedPacket)
            if !embeddedFields.isEmpty {
                fields = embeddedFields
                source = url
                output["source"] = source.path
                output["storage"] = "Embedded XMP (no Colorgain fields in sidecar)"
            }
        }
    }
    output["status"] = fields.isEmpty ? "No Colorgain fields in this source" : "Read from file"
    output["value"] = fields["colorgain"] ?? ""
    output["application"] = fields["OriginatingApplication"] ?? ""
    output["testId"] = fields["RoundTripTestID"] ?? ""
    output["note"] = fields["StorageTest"] ?? fields["RoundTripNote"] ?? ""
    output["fields"] = fields.keys.sorted().map { "\($0): \(fields[$0]!)" }.joined(separator:"\n")
} catch {
    output = ["status":"Could not refresh", "error":String(describing:error)]
}
for key in output.keys.sorted() { print("\(key)\t\(encoded(output[key]!))") }

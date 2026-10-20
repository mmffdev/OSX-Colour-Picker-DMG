import Foundation
import Compression

// ---------- Zip, the app's own ----------
//
// A share is one zip file, so it travels through mail, chat and drives as one thing and opens with
// anything. The app writes and reads the format itself: deflate through the system's Compression
// framework, the headers and directory by hand, so the direct download and the Store build do the
// same work with no tool spawned and nothing vendored. Files only, names in UTF-8, no zip64: a
// catalogue of colours is nowhere near the limits.

enum Zip {
    /// File-backed entries keep camera originals out of the process heap.
    struct StreamEntry {
        let path: String
        let file: URL?
        let data: Data?
        init(path: String, file: URL) { self.path=path; self.file=file; self.data=nil }
        init(path: String, data: Data) { self.path=path; self.file=nil; self.data=data }
    }

    private static func le64(_ value: UInt64) -> Data {
        var result=Data();result.append(le32(UInt32(truncatingIfNeeded:value)));result.append(le32(UInt32(truncatingIfNeeded:value >> 32)));return result
    }
    private static func u64(_ bytes: Data, _ offset: Int) -> UInt64 {
        UInt64(u32(bytes,offset)) | (UInt64(u32(bytes,offset+4)) << 32)
    }

    /// ZIP64 stored entries. Photos are already compressed, so deflating them costs time and memory.
    static func writeStreaming(_ entries:[StreamEntry], to destination:URL) throws {
        guard entries.count <= 20_000 else {throw Fault.damaged("too many files")}
        let fm=FileManager.default
        let temporary=destination.deletingLastPathComponent().appendingPathComponent("." + destination.lastPathComponent + "." + UUID().uuidString + ".tmp")
        guard fm.createFile(atPath:temporary.path,contents:nil) else {throw Fault.damaged("the archive could not be created")}
        defer {try? fm.removeItem(at:temporary)}
        let output=try FileHandle(forWritingTo:temporary)
        defer {try? output.close()}
        var position:UInt64=0
        func put(_ bytes:Data) throws {try output.write(contentsOf:bytes);position += UInt64(bytes.count)}
        var directory=Data()
        let (time,day)=dosStamp(Date())
        var seen=Set<String>()
        for entry in entries {
            guard seen.insert(entry.path).inserted,
                  !entry.path.hasPrefix("/"),!entry.path.split(separator:"/").contains(".."),
                  !entry.path.isEmpty,entry.path.utf8.count <= 65_535 else {throw Fault.damaged("an unsafe or duplicate file name")}
            let name=Data(entry.path.utf8)
            let size:UInt64
            if let data=entry.data {size=UInt64(data.count)}
            else if let file=entry.file {
                let values=try file.resourceValues(forKeys:[.fileSizeKey,.isDirectoryKey,.isSymbolicLinkKey])
                guard values.isDirectory != true,values.isSymbolicLink != true,let count=values.fileSize,count >= 0 else {throw Fault.damaged("a source is not a regular file")}
                size=UInt64(count)
            } else {throw Fault.damaged("an entry has no bytes")}
            let offset=position
            // Fixed ZIP64 local extra allows the size to be patched after the stream and CRC are known.
            var extra=Data();extra.append(le16(1));extra.append(le16(16));extra.append(le64(size));extra.append(le64(size))
            var header=Data()
            header.append(le32(0x04034b50));header.append(le16(45));header.append(le16(0x0800));header.append(le16(0))
            header.append(le16(time));header.append(le16(day));header.append(le32(0));header.append(le32(UInt32.max));header.append(le32(UInt32.max))
            header.append(le16(UInt16(name.count)));header.append(le16(UInt16(extra.count)));header.append(name);header.append(extra)
            try put(header)
            var crc:UInt32=0xFFFFFFFF
            var consumed:UInt64=0
            func consume(_ chunk:Data) throws {
                for byte in chunk {crc=crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)}
                try put(chunk);consumed += UInt64(chunk.count)
            }
            if let data=entry.data {try consume(data)}
            else if let file=entry.file {
                let input=try FileHandle(forReadingFrom:file);defer{try? input.close()}
                while let chunk=try input.read(upToCount:1024*1024),!chunk.isEmpty {try consume(chunk)}
            }
            guard consumed == size else {throw Fault.damaged("a source changed during export")}
            crc ^= 0xFFFFFFFF
            let after=position
            try output.seek(toOffset:offset+14);try output.write(contentsOf:le32(crc));try output.seek(toOffset:after)
            var centralExtra=Data();centralExtra.append(le16(1));centralExtra.append(le16(24));centralExtra.append(le64(size));centralExtra.append(le64(size));centralExtra.append(le64(offset))
            directory.append(le32(0x02014b50));directory.append(le16(45));directory.append(le16(45));directory.append(le16(0x0800));directory.append(le16(0))
            directory.append(le16(time));directory.append(le16(day));directory.append(le32(crc));directory.append(le32(UInt32.max));directory.append(le32(UInt32.max))
            directory.append(le16(UInt16(name.count)));directory.append(le16(UInt16(centralExtra.count)));directory.append(le16(0));directory.append(le16(0));directory.append(le16(0))
            directory.append(le32(0));directory.append(le32(UInt32.max));directory.append(name);directory.append(centralExtra)
        }
        let directoryOffset=position
        try put(directory)
        let zip64Offset=position
        var ending=Data()
        ending.append(le32(0x06064b50));ending.append(le64(44));ending.append(le16(45));ending.append(le16(45));ending.append(le32(0));ending.append(le32(0))
        ending.append(le64(UInt64(entries.count)));ending.append(le64(UInt64(entries.count)));ending.append(le64(UInt64(directory.count)));ending.append(le64(directoryOffset))
        ending.append(le32(0x07064b50));ending.append(le32(0));ending.append(le64(zip64Offset));ending.append(le32(1))
        ending.append(le32(0x06054b50));ending.append(le16(0));ending.append(le16(0));ending.append(le16(UInt16.max));ending.append(le16(UInt16.max))
        ending.append(le32(UInt32.max));ending.append(le32(UInt32.max));ending.append(le16(0))
        try put(ending)
        try output.synchronize()
        guard !fm.fileExists(atPath:destination.path) else {throw Fault.damaged("the destination already exists")}
        try FileOperationTransaction.current?.prepare(destination,after:try FileRevision.read(temporary).digest)
        try fm.moveItem(at:temporary,to:destination)
    }

    /// Extract our stored ZIP64 archives without loading file payloads into memory.
    static func extractStreaming(_ archive:URL, to root:URL) throws -> [String] {
        let fm=FileManager.default
        let input=try FileHandle(forReadingFrom:archive);defer{try? input.close()}
        var position:UInt64=0
        var paths:[String]=[]
        var seen=Set<String>()
        func read(_ count:Int) throws -> Data {
            guard let bytes=try input.read(upToCount:count),bytes.count == count else {throw Fault.damaged("a file ends early")}
            position += UInt64(count);return bytes
        }
        while true {
            let signature=try read(4)
            if u32(signature,0) == 0x02014b50 {break}
            guard u32(signature,0) == 0x04034b50,paths.count < 20_000 else {throw Fault.damaged("a local file header is missing")}
            let header=try read(26)
            let flags=u16(header,2),method=u16(header,4),expectedCRC=u32(header,10)
            let nameLength=Int(u16(header,22)),extraLength=Int(u16(header,24))
            guard flags == 0x0800,method == 0,nameLength > 0,extraLength <= 65_535 else {throw Fault.damaged("unsupported streaming entry")}
            let nameBytes=try read(nameLength),extra=try read(extraLength)
            guard let path=String(data:nameBytes,encoding:.utf8),
                  !path.hasPrefix("/"),!path.split(separator:"/").contains(".."),
                  !path.hasSuffix("/"),seen.insert(path).inserted else {throw Fault.damaged("an unsafe or duplicate file name")}
            var size:UInt64?
            var at=0
            while at+4 <= extra.count {
                let kind=u16(extra,at),length=Int(u16(extra,at+2));at += 4
                guard at+length <= extra.count else {throw Fault.damaged("invalid ZIP64 extra")}
                if kind == 1 && length >= 16 {
                    let uncompressed=u64(extra,at),compressed=u64(extra,at+8)
                    guard uncompressed == compressed else {throw Fault.damaged("a stored entry has conflicting sizes")}
                    size=uncompressed
                }
                at += length
            }
            guard let size,size <= UInt64(Int64.max) else {throw Fault.damaged("an entry has no ZIP64 size")}
            let target=try Handler_File_Manager.contained(path,under:root)
            try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            guard fm.createFile(atPath:target.path,contents:nil) else {throw Fault.damaged("a staged file could not be created")}
            let output=try FileHandle(forWritingTo:target);defer{try? output.close()}
            var remaining=size,crc:UInt32=0xFFFFFFFF
            while remaining > 0 {
                let chunk=try read(Int(min(remaining,1024*1024)))
                for byte in chunk {crc=crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)}
                try output.write(contentsOf:chunk);remaining -= UInt64(chunk.count)
            }
            guard crc ^ 0xFFFFFFFF == expectedCRC else {throw Fault.damaged(path + " does not match its checksum")}
            paths.append(path)
        }
        return paths
    }
    struct Entry: Equatable {
        let path: String
        let data: Data
    }

    enum Fault: LocalizedError {
        case notAZip(URL)
        case damaged(String)
        var errorDescription: String? {
            switch self {
            case .notAZip(let u): return "\(u.lastPathComponent) is not a zip file."
            case .damaged(let what): return "The zip file is damaged: \(what)."
            }
        }
    }

    // MARK: Writing

    /// Writes the entries, in order, as a zip file.
    static func write(_ entries: [Entry], to url: URL, at date: Date = Date(), manager: Handler_File_Manager = .shared) throws {
        var entries = entries
        guard entries.count <= 20_000, entries.allSatisfy({ $0.path.utf8.count <= 65_535 && $0.data.count <= 40 * 1024 * 1024 }), entries.reduce(0, { $0 + $1.data.count }) <= 256 * 1024 * 1024 else { throw Fault.damaged("the archive exceeds supported limits") }
        if let index = entries.firstIndex(where: { $0.path == ShareManifest.fileName }) {
            entries[index] = Entry(path: ShareManifest.fileName, data: try manager.documentBytes(entries[index].data, extension: "colmanifest"))
        }
        var out = Data()
        var directory = Data()
        let (time, day) = dosStamp(date)
        for e in entries {
            let name = Data(e.path.utf8)
            let crc = crc32(e.data)
            let packed = deflate(e.data)
            let method: UInt16 = packed.count < e.data.count ? 8 : 0
            let body = method == 8 ? packed : e.data
            let offset = UInt32(out.count)
            // The local header, then the data.
            out.append(le32(0x04034b50)); out.append(le16(20)); out.append(le16(0x0800)); out.append(le16(method))
            out.append(le16(time)); out.append(le16(day)); out.append(le32(crc)); out.append(le32(UInt32(body.count))); out.append(le32(UInt32(e.data.count)))
            out.append(le16(UInt16(name.count))); out.append(le16(0)); out.append(name); out.append(body)
            // The central directory's record of it.
            directory.append(le32(0x02014b50)); directory.append(le16(20)); directory.append(le16(20)); directory.append(le16(0x0800)); directory.append(le16(method))
            directory.append(le16(time)); directory.append(le16(day)); directory.append(le32(crc)); directory.append(le32(UInt32(body.count))); directory.append(le32(UInt32(e.data.count)))
            directory.append(le16(UInt16(name.count))); directory.append(le16(0)); directory.append(le16(0)); directory.append(le16(0)); directory.append(le16(0)); directory.append(le32(0))
            directory.append(le32(offset)); directory.append(name)
        }
        let start = UInt32(out.count)
        out.append(directory)
        out.append(le32(0x06054b50)); out.append(le16(0)); out.append(le16(0)); out.append(le16(UInt16(entries.count))); out.append(le16(UInt16(entries.count)))
        out.append(le32(UInt32(directory.count))); out.append(le32(start)); out.append(le16(0))
        if ["colshr", "colshare"].contains(url.pathExtension.lowercased()) { try manager.write(out, to: url) }
        else { try manager.publishRaw(out, to: url) }
    }

    // MARK: Reading

    /// Reads every entry of a zip file, in the order the directory lists them.
    static func read(_ url: URL) throws -> [Entry] {
        let data: Data
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 256 * 1024 * 1024 else { throw Fault.notAZip(url) }
            data = try Data(contentsOf: url)
        } catch { throw Fault.notAZip(url) }
        return try read(data: data, name: url)
    }

    static func read(data: Data, name url: URL) throws -> [Entry] {
        guard data.count >= 22 else { throw Fault.notAZip(url) }
        // The end record is the last thing in the file, before a comment of up to 64K.
        var endAt: Int?
        var i = data.count - 22
        let floor = max(0, data.count - 22 - 65_535)
        while i >= floor {
            if u32(data, i) == 0x06054b50 { endAt = i; break }
            i -= 1
        }
        guard let end = endAt else { throw Fault.notAZip(url) }
        let count = Int(u16(data, end + 10)), dirSize = Int(u32(data, end + 12)), dirStart = Int(u32(data, end + 16))
        guard count <= 20_000, data.count <= 256 * 1024 * 1024, dirStart + dirSize <= end else { throw Fault.damaged("the directory is out of place or exceeds supported limits") }
        var entries: [Entry] = []
        var expandedBytes = 0
        var at = dirStart
        for _ in 0..<count {
            guard at + 46 <= end, u32(data, at) == 0x02014b50 else { throw Fault.damaged("a directory record is missing") }
            let method = u16(data, at + 10), crc = u32(data, at + 16), packedSize = Int(u32(data, at + 20)), size = Int(u32(data, at + 24))
            expandedBytes += size
            guard size <= 40 * 1024 * 1024, expandedBytes <= 256 * 1024 * 1024 else { throw Fault.damaged("the expanded archive exceeds supported limits") }
            let nameLen = Int(u16(data, at + 28)), extraLen = Int(u16(data, at + 30)), commentLen = Int(u16(data, at + 32))
            let offset = Int(u32(data, at + 42))
            guard at + 46 + nameLen <= end, let path = String(data: data[(at + 46)..<(at + 46 + nameLen)], encoding: .utf8) else { throw Fault.damaged("a name could not be read") }
            at += 46 + nameLen + extraLen + commentLen
            // The local header carries its own name and extra lengths; the data follows them.
            guard offset + 30 <= dirStart, u32(data, offset) == 0x04034b50 else { throw Fault.damaged("\(path) has no header") }
            let localName = Int(u16(data, offset + 26)), localExtra = Int(u16(data, offset + 28))
            let from = offset + 30 + localName + localExtra
            guard from + packedSize <= dirStart else { throw Fault.damaged("\(path) runs past the end") }
            let body = data.subdata(in: from..<(from + packedSize))
            let plain: Data
            switch method {
            case 0: plain = body
            case 8:
                guard let unpacked = inflate(body, size: size) else { throw Fault.damaged("\(path) could not be unpacked") }
                plain = unpacked
            default: throw Fault.damaged("\(path) is packed in a way the app does not read")
            }
            guard plain.count == size, crc32(plain) == crc else { throw Fault.damaged("\(path) does not match its record") }
            if !path.hasSuffix("/") { entries.append(Entry(path: path, data: plain)) }
        }
        return entries
    }

    // MARK: Deflate

    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + 64
        var out = Data(count: capacity)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, capacity, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return data }
        out.count = n
        return out
    }

    static func inflate(_ data: Data, size: Int) -> Data? {
        guard size > 0 else { return data.isEmpty ? Data() : nil }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == size else { return nil }
        return out
    }

    // MARK: Bytes

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }
    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]) }
    private static func u16(_ d: Data, _ i: Int) -> UInt16 { UInt16(d[d.startIndex + i]) | (UInt16(d[d.startIndex + i + 1]) << 8) }
    private static func u32(_ d: Data, _ i: Int) -> UInt32 { UInt32(u16(d, i)) | (UInt32(u16(d, i + 2)) << 16) }
    /// The date and time as a zip keeps them, in two-second steps from 1980.
    private static func dosStamp(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: date)
        let year = max(1980, c.year ?? 1980), month = c.month ?? 1, dayOfMonth = c.day ?? 1
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = (c.second ?? 0) / 2
        let time = (hour << 11) | (minute << 5) | second
        let day = ((year - 1980) << 9) | (month << 5) | dayOfMonth
        return (UInt16(time), UInt16(day))
    }
}

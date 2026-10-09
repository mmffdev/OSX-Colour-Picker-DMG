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
    static func write(_ entries: [Entry], to url: URL, at date: Date = Date()) throws {
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
        try out.write(to: url, options: .atomic)
    }

    // MARK: Reading

    /// Reads every entry of a zip file, in the order the directory lists them.
    static func read(_ url: URL) throws -> [Entry] {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw Fault.notAZip(url) }
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
        guard dirStart + dirSize <= end else { throw Fault.damaged("the directory is out of place") }
        var entries: [Entry] = []
        var at = dirStart
        for _ in 0..<count {
            guard at + 46 <= end, u32(data, at) == 0x02014b50 else { throw Fault.damaged("a directory record is missing") }
            let method = u16(data, at + 10), crc = u32(data, at + 16), packedSize = Int(u32(data, at + 20)), size = Int(u32(data, at + 24))
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

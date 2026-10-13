import AppKit
import CoreImage
import Vision
import CryptoKit
import Compression

/// Offline exchange carries the original source and the unrounded D50 master, never a sampled preview.
enum ColourQR {
    struct Entry: Codable, Equatable {
        var name: String
        var source: ColourSource
        var master: XYZ
        var kind: ColourKind
    }
    struct Document: Codable, Equatable {
        var version = 1
        var type: String
        var name: String
        var white = "D50"
        var observer = 2
        var scale = "Relative Y=1"
        var colours: [Entry]
    }
    static let prefix = "colorgain://qr/1/"
    static let limit = 65536
    static func validate(_ d: Document) throws {
        guard d.version == 1, ["swatch", "palette"].contains(d.type), d.white == "D50", d.observer == 2,
              d.scale == "Relative Y=1", !d.colours.isEmpty, d.colours.count <= 256,
              d.type != "swatch" || d.colours.count == 1, d.name.utf8.count <= 512 else { throw failure("Unsupported Colorgain colour exchange.") }
        for c in d.colours {
            let count = c.source.space == "cmyk" ? 4 : 3
            guard c.name.utf8.count <= 512, c.source.space.utf8.count <= 64, (c.source.press?.utf8.count ?? 0) <= 512,
                  c.source.values.count == count, c.source.values.allSatisfy({ $0.isFinite && abs($0) <= 1e9 }),
                  [c.master.x,c.master.y,c.master.z].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }) else { throw failure("Invalid colour values in this exchange.") }
            guard RGBSpace(rawValue:c.source.space) != nil || ["cmyk","lab","xyz"].contains(c.source.space) else { throw failure("Unrecognised source colour space.") }
        }
    }
    private struct XYZFile:Codable {
        var format="colorgain.xyz"
        var version=1
        var white="D50"
        var observer=2
        var scale="Relative Y=1"
        var type:String
        var name:String
        var colours:[XYZ]
    }
    private static func fromXYZ(type:String,name:String,masters:[XYZ]) throws -> Document {
        guard ["swatch","palette"].contains(type),!masters.isEmpty,masters.count<=256,name.utf8.count<=512,
              masters.allSatisfy({[$0.x,$0.y,$0.z].allSatisfy{$0.isFinite && abs($0)<=1e9}}) else{throw failure("Invalid XYZ colour exchange.")}
        let entries=masters.map{master in Entry(name:type=="swatch" ? name:colourName(RGBSpace.srgb.text(RGBSpace.srgb.values(of:master))),source:.init(space:"xyz",values:[master.x,master.y,master.z]),master:master,kind:.surface)}
        let d=Document(type:type,name:name,colours:entries);try validate(d);return d
    }
    static func data(_ d: Document) throws -> Data {
        _ = try fromXYZ(type:d.type,name:d.name,masters:d.colours.map{$0.master})
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(XYZFile(type:d.type,name:d.name,colours:d.colours.map{$0.master}))
        guard bytes.count <= limit else { throw failure("This exchange is too large. Use the catalogue export instead.") }
        return bytes
    }
    static func document(_ bytes: Data) throws -> Document {
        guard bytes.count <= limit else { throw failure("This colour exchange exceeds the import limit.") }
        if let file=try? JSONDecoder().decode(XYZFile.self,from:bytes) {
            guard file.format=="colorgain.xyz",file.version==1,file.white=="D50",file.observer==2,file.scale=="Relative Y=1" else{throw failure("Unsupported XYZ colour file.")}
            return try fromXYZ(type:file.type,name:file.name,masters:file.colours)
        }
        let d = try JSONDecoder().decode(Document.self, from:bytes); try validate(d); return d
    }
    @discardableResult static func insert(_ d:Document, into lib:inout Library, target:UUID? = nil) throws -> UUID {
        try validate(d)
        if let target, lib.swatch(target) == nil { throw failure("The selected destination is no longer available.") }
        let id=target ?? lib.createSwatch(named:d.name,hexes:[])
        for c in d.colours {
            let key=ColourKeys.make()
            lib.colours.append(Colour(hex:key,pickedAt:Date(),source:c.source,master:c.master,kind:c.kind))
            lib.add([key],toSwatch:id);lib.setName(c.name,of:key,in:id)
        }
        return id
    }
    /// Minimal sharing requested by the product: one name and XYZ triples only.
    private static func xyzBinary(_ d:Document) throws -> Data {
        guard d.version==1,d.white=="D50",d.observer==2,d.scale=="Relative Y=1",["swatch","palette"].contains(d.type),(d.type != "swatch" || d.colours.count==1),!d.colours.isEmpty,d.colours.count<=256,d.name.utf8.count<=512,
              d.colours.allSatisfy({[$0.master.x,$0.master.y,$0.master.z].allSatisfy{$0.isFinite && abs($0)<=1e9}}) else{throw failure("Invalid XYZ colour exchange.")}
        var bytes=Data([2,d.type == "palette" ? 1:0]) // Transport v2 fixes D50, 2°, relative Y=1.
        func integer(_ n:Int){bytes.append(UInt8(n & 255));bytes.append(UInt8((n >> 8) & 255))}
        let name=Data(d.name.utf8);integer(name.count);bytes.append(name);integer(d.colours.count)
        for c in d.colours{for n in [c.master.x,c.master.y,c.master.z]{var raw=n.bitPattern.littleEndian;withUnsafeBytes(of:&raw){bytes.append(contentsOf:$0)}}}
        return bytes
    }
    private static func readXYZ(_ bytes:Data) throws -> Document {
        let raw=Array(bytes);var offset=0
        func byte() throws -> UInt8{guard offset<raw.count else{throw failure("Incomplete XYZ QR.")};defer{offset+=1};return raw[offset]}
        func integer() throws -> Int{let lo=try byte();return Int(lo) | (Int(try byte()) << 8)}
        func number() throws -> Double{var bits:UInt64=0;for i in 0..<8{bits |= UInt64(try byte()) << (i*8)};return Double(bitPattern:bits)}
        guard try byte()==2 else{throw failure("Unsupported XYZ QR version.")};let type=try byte();guard type<=1 else{throw failure("Invalid XYZ QR type.")}
        let length=try integer();guard length<=512,offset+length<=raw.count,let name=String(bytes:raw[offset..<offset+length],encoding:.utf8) else{throw failure("Invalid XYZ QR name.")};offset+=length
        let count=try integer();guard count>0,count<=256,raw.count-offset==count*24 else{throw failure("Incomplete XYZ colour sequence.")}
        var masters:[XYZ]=[]
        for _ in 0..<count { masters.append(try XYZ(x:number(),y:number(),z:number())) }
        return try fromXYZ(type:type==1 ? "palette":"swatch",name:name,masters:masters)
    }

    static func text(_ d: Document) throws -> String {
        let bytes = try xyzBinary(d), packed = try (bytes as NSData).compressed(using:.zlib) as Data
        let digest = SHA256.hash(data:bytes).prefix(16).map { String(format:"%02x",$0) }.joined()
        return prefix + "x/" + digest + "/" + packed.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_")
    }
    static func decode(_ text: String) throws -> Document {
        guard text.hasPrefix(prefix), text.utf8.count <= 16000 else { throw failure("This is not a supported Colorgain QR code.") }
        let content=text.dropFirst(prefix.count)
        let xyz=content.hasPrefix("x/")
        let compact=xyz
        let zlib=compact || content.hasPrefix("z/")
        let parts=(zlib ? content.dropFirst(2) : content).split(separator:"/",maxSplits:1)
        guard parts.count == 2, parts[0].count == (compact ? 32:64), let packed = Data(base64Encoded:String(parts[1]).replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")), !packed.isEmpty else { throw failure("The colour QR is incomplete.") }
        var output = [UInt8](repeating:0,count:limit + 1)
        let n = packed.withUnsafeBytes { raw in output.withUnsafeMutableBytes { dst in
            compression_decode_buffer(dst.bindMemory(to:UInt8.self).baseAddress!,limit + 1,raw.bindMemory(to:UInt8.self).baseAddress!,packed.count,nil,zlib ? COMPRESSION_ZLIB : COMPRESSION_LZFSE)
        } }
        guard n > 0, n <= limit else { throw failure("The colour QR is damaged or too large.") }
        let bytes = Data(output.prefix(n)), digest = SHA256.hash(data:bytes).prefix(compact ? 16:32).map { String(format:"%02x",$0) }.joined()
        guard digest == parts[0] else { throw failure("The colour QR failed its integrity check.") }
        if xyz { return try readXYZ(bytes) }
        return try document(bytes)
    }
    static func scan(_ image: CGImage) throws -> String {
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
        guard let result = request.results?.compactMap({ $0.payloadStringValue }).first(where:{ $0.hasPrefix(prefix) }) else { throw failure("No Colorgain colour QR was found in this image.") }
        return result
    }
    /// Render crisp modules and verify the branded image before offering it to the user.
    static func image(_ text: String, branded: Bool = true) throws -> NSImage {
        guard text.utf8.count <= 1200 else { throw failure("This palette needs more space than a reliably scannable QR. Save its Colour File instead; no colours will be omitted.") }
        guard let filter = CIFilter(name:"CIQRCodeGenerator",parameters:["inputMessage":Data(text.utf8),"inputCorrectionLevel":"H"]), let qr = filter.outputImage,
              let cg = CIContext().createCGImage(qr,from:qr.extent) else { throw failure("Could not generate the colour QR.") }
        let step = max(4, 768 / (cg.width + 8)), side = (cg.width + 8) * step
        let out = NSImage(size:NSSize(width:CGFloat(side),height:CGFloat(side))); out.lockFocus()
        NSColor.white.setFill(); NSRect(x:0,y:0,width:CGFloat(side),height:CGFloat(side)).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage:cg,size:NSSize(width:CGFloat(cg.width),height:CGFloat(cg.height))).draw(in:NSRect(x:CGFloat(4*step),y:CGFloat(4*step),width:CGFloat(cg.width*step),height:CGFloat(cg.height*step)))
        if branded {
            let size = CGFloat(side) * 0.10, box = NSRect(x:(CGFloat(side)-size)/2,y:(CGFloat(side)-size)/2,width:size,height:size)
            NSColor.white.setFill(); box.insetBy(dx:-CGFloat(step),dy:-CGFloat(step)).fill()
            NSImage(named:NSImage.colorPanelName)?.draw(in:box)
        }
        out.unlockFocus()
        var rect = NSRect(origin:.zero,size:out.size)
        guard let rendered = out.cgImage(forProposedRect:&rect,context:nil,hints:nil), (try? scan(rendered)) == text else {
            if branded { return try image(text,branded:false) }
            throw failure("The generated QR could not be verified. Save the Colour File instead.")
        }
        return out
    }
}

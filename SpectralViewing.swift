import AppKit
import Foundation
import CryptoKit

/// Measured reflectance remains independent of the colour's existing source/master.
struct SpectralSample: Codable, Equatable, Identifiable {
    var id: String
    var objectID: String
    var name: String
    var start: Int
    var interval: Int
    var reflectance: [Double]
    var specification: String
    var metadata: [String: String]
    var fileDigest: String
    var fileName: String
    var end: Int { start + interval * (reflectance.count - 1) }
    func validate() throws {
        guard (300...400).contains(start), [1,2,5,10].contains(interval), (2...1024).contains(reflectance.count),
              start <= 380, end >= 730, end <= 900,
              reflectance.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw failure("\(name): use reflectance fractions from 0 to 1, at 1, 2, 5 or 10 nm intervals, covering at least 380–730 nm. Fluorescent, transmissive and emissive data are not supported.")
        }
    }
    func value(at wavelength: Int) -> Double {
        let position = Double(wavelength - start) / Double(interval)
        let low = Int(position.rounded(.down)), high = min(low + 1, reflectance.count - 1)
        return reflectance[low] + (reflectance[high] - reflectance[low]) * (position - Double(low))
    }
}

/// ICC-published LWL 10 nm tables; observer changes always recompute from the spectrum.
enum SpectralEngine {
    enum Observer: String, Codable, CaseIterable { case two = "1931", ten = "1964"
        var label: String { self == .two ? "CIE 1931 · 2°" : "CIE 1964 · 10°" }
    }
    struct Prediction {
        let xyz: XYZ
        let white: XYZ
        let displayMaster: XYZ
        let clipped: Bool
        var colour: NSColor { displayMaster.display }
    }
    private static let lock = NSLock()
    private static var tables: [String: [[Double]]] = [:]
    static func table(light: PaletteViewing.Illuminant, observer: Observer, end: Int) throws -> [[Double]] {
        guard light != .normal, [730,780].contains(end) else { throw failure("Choose D50, D65 or A.") }
        let name = "Wts-\(observer.rawValue)-\(light.rawValue)-380-10-\(end)nm"
        lock.lock(); defer { lock.unlock() }
        if let cached = tables[name] { return cached }
        var roots = [Bundle.main.resourceURL?.appendingPathComponent("ProofingResources/Spectral"), Bundle.main.resourceURL].compactMap { $0 }
        if CommandLine.arguments.contains("--self-test") { roots.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("ProofingResources/Spectral")) }
        guard let url = roots.map({ $0.appendingPathComponent(name + ".csv") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw failure("The bundled spectral reference tables are missing. Reinstall Colorgain.") }
        guard let hashesURL=roots.map({$0.appendingPathComponent("spectral-sha256.json")}).first(where:{FileManager.default.fileExists(atPath:$0.path)}),
              let hashes=try JSONSerialization.jsonObject(with:Data(contentsOf:hashesURL)) as? [String:String],
              let expected=hashes[name+".csv"],Sharing.sha256(try Data(contentsOf:url)) == expected else {throw failure("The spectral reference data failed its SHA-256 integrity check.")}
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\u{FEFF}", with: "")
        let rows = text.split(whereSeparator: \.isNewline).map { $0.split(separator: ",").compactMap { Double($0) } }
        guard rows.count == (end-380)/10+1, rows.enumerated().allSatisfy({ index, row in row.count == 4 && row[0] == Double(380+index*10) && row.allSatisfy(\.isFinite) }),
              abs(rows.reduce(0) { $0+$1[2] } - 100) < 0.01 else { throw failure("The spectral reference table failed validation.") }
        tables[name] = rows; return rows
    }
    static func validateReferenceTables() throws {
        for observer in Observer.allCases {for light in [PaletteViewing.Illuminant.d50,.d65,.a] {for end in [730,780] {_ = try table(light:light,observer:observer,end:end)}}}
    }
    static func predict(_ sample: SpectralSample, light: PaletteViewing.Illuminant, observer: Observer) throws -> Prediction {
        try sample.validate()
        let rows = try table(light: light, observer: observer, end: sample.end >= 780 ? 780 : 730)
        var values = [Double](repeating: 0, count: 3), white = values
        for row in rows { for i in 0..<3 { values[i] += row[i+1] * sample.value(at: Int(row[0])) / 100; white[i] += row[i+1] / 100 } }
        let xyz = XYZ(x:values[0],y:values[1],z:values[2])
        // A fixed D65 reference display shows the illuminant cast. This is NOT an ambient
        // adaptation/appearance model. Convert that D65 display context to the app's D50 master.
        let d65 = Illuminant.allCases.first { $0.name == "D65" && $0.observer == 2 }!.white
        let mapped = multiply(bradford(from: d65.chromaticity, to: XYZ.d50.chromaticity), values)
        let master = XYZ(x:mapped[0],y:mapped[1],z:mapped[2])
        return Prediction(xyz: xyz, white: XYZ(x:white[0],y:white[1],z:white[2]), displayMaster: master, clipped: !master.fits(.displayP3))
    }
}

/// Bounded, namespace-aware reader for the CxF3-core ReflectanceSpectrum subset.
/// This is semantic subset validation, not a full ISO/CxF XSD conformance claim.
enum CxFReflectance {
    static let maximumBytes = 4 * 1024 * 1024
    struct Import: Codable, Equatable {
        var digest: String
        var name: String
        var original: Data
        var samples: [SpectralSample]
    }
    private final class Node {
        let name: String
        let attributes: [String:String]
        let namespace: String
        var text = ""
        var children: [Node] = []
        init(_ name:String, _ attributes:[String:String], _ namespace:String) { self.name=name;self.attributes=attributes;self.namespace=namespace }
        func all(_ name:String) -> [Node] { children.flatMap { ($0.name == name ? [$0] : []) + $0.all(name) } }
        func first(_ name:String) -> Node? { all(name).first }
    }
    private final class Reader: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []
        var count = 0
        var problem: Error?
        func parser(_ parser:XMLParser,didStartElement elementName:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
            count += 1
            guard stack.count < 48, count <= 50000 else { problem=failure("The CxF document is too complex.");parser.abortParsing();return }
            let node=Node(elementName,attributes,namespaceURI ?? "")
            if let parent=stack.last {parent.children.append(node)} else {root=node}
            stack.append(node)
        }
        func parser(_ parser:XMLParser,foundCharacters string:String) { stack.last?.text += string }
        func parser(_ parser:XMLParser,didEndElement elementName:String,namespaceURI:String?,qualifiedName:String?) { if !stack.isEmpty {stack.removeLast()} }
        func parser(_ parser:XMLParser,resolveExternalEntityName name:String,systemID:String?) -> Data? { problem=failure("External XML entities are not supported.");parser.abortParsing();return nil }
    }
    static func read(_ data:Data, name:String) throws -> Import {
        guard data.count <= maximumBytes, !data.isEmpty else { throw failure("Choose a CxF file smaller than 4 MB.") }
        guard let xml=String(data:data,encoding:.utf8), !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY") else { throw failure("Use a UTF-8 CxF3 file without DTDs or external entities.") }
        let reader=Reader(), parser=XMLParser(data:data)
        parser.shouldProcessNamespaces=true;parser.shouldResolveExternalEntities=false;parser.delegate=reader
        guard parser.parse(),reader.problem == nil,let root=reader.root,root.name == "CxF",root.namespace == "http://colorexchangeformat.com/CxF3-core" else { throw reader.problem ?? failure("This is not a supported CxF3-core document, or its XML is malformed.") }
        let namespace=root.namespace
        guard root.all("ReflectanceSpectrum").allSatisfy({$0.namespace == namespace}) else { throw failure("Reflectance data uses an unsupported namespace.") }
        let specs=root.all("ColorSpecification")
        var specifications: [String:Node] = [:]
        for spec in specs {
            guard let id=spec.attributes["Id"],specifications[id] == nil else { throw failure("CxF colour specifications need unique IDs.") }
            specifications[id]=spec
        }
        let digest=Sharing.sha256(data)
        var samples: [SpectralSample]=[], identities=Set<String>()
        for object in root.all("Object") {
            let spectra=object.all("ReflectanceSpectrum")
            if spectra.isEmpty { continue }
            guard object.namespace == namespace, let id=object.attributes["Id"],!id.isEmpty,identities.insert(id).inserted else { throw failure("Measured objects need unique, non-empty IDs.") }
            let objectName=object.attributes["Name"] ?? id
            for (index,spectrum) in spectra.enumerated() {
                guard let ref=spectrum.attributes["ColorSpecification"],let spec=specifications[ref],spec.namespace == namespace,
                      let range=spec.first("WavelengthRange"),let start=Int(spectrum.attributes["StartWL"] ?? range.attributes["StartWL"] ?? ""),let interval=Int(range.attributes["Increment"] ?? "") else { throw failure("\(objectName): the spectral measurement needs a referenced colour specification and explicit wavelength range/increment.") }
                let type=spec.first("MeasurementType")?.text.trimmingCharacters(in:.whitespacesAndNewlines) ?? ""
                guard ["Spectrum_Reflectance","Colorimetric_Reflectance"].contains(type) else { throw failure("\(objectName): only reflectance measurements are supported.") }
                let tokens=spectrum.text.split(whereSeparator: \.isWhitespace)
                guard tokens.count <= 1024 else { throw failure("\(objectName): too many wavelength samples.") }
                let values=tokens.compactMap { Double($0) }
                guard values.count == tokens.count else { throw failure("\(objectName): invalid spectral numbers.") }
                var metadata: [String:String] = ["MeasurementType":type,"Units":"Reflectance Fraction (1 = 100%)","SpecificationID":ref]
                func collect(_ node:Node,_ path:String) {
                    for child in node.children {
                        let key=path.isEmpty ? child.name:path+"/"+child.name
                        if child.children.isEmpty { metadata[key]=String(child.text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(2048)) }
                        else { collect(child,key) }
                        for (attribute,value) in child.attributes { metadata[key+"/@"+attribute]=String(value.prefix(2048)) }
                    }
                }
                collect(spec,"")
                for node in spec.all("Fluorescence") + object.all("Fluorescence") + spec.all("Fluorescent") + object.all("Fluorescent") {
                    if !["false","0","no","none"].contains(node.text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()) {throw failure("\(objectName): declared fluorescence is outside this reflectance model.")}
                }
                if let date=spectrum.attributes["MeasureDate"] {metadata["MeasureDate"]=date}
                let sample=SpectralSample(id:digest+":"+id+":\(index)",objectID:id,name:objectName+(spectra.count > 1 ? " · Measurement \(index+1)":""),start:start,interval:interval,reflectance:values,specification:ref,metadata:metadata,fileDigest:digest,fileName:name)
                try sample.validate();samples.append(sample)
                guard samples.count <= 500 else { throw failure("A spectral import supports at most 500 measurements.") }
            }
        }
        guard !samples.isEmpty else { throw failure("This CxF file contains no supported reflectance spectra. RGB, Lab, transmission and emission values cannot enable Spectral Viewing.") }
        return Import(digest:digest,name:name,original:data,samples:samples)
    }
}

/// Measurements are workspace-owned assets in the existing .coldata open schema.
/// Writes use the native manager's transaction and preserve unrelated manifest fields.
final class SpectralStore {
    static let shared = SpectralStore()
    struct Stamp: Codable, Equatable {
        var source: ColourSource
        var master: XYZ
        var kind: ColourKind
        init(_ definition:ColourDefinition) {source=definition.source;master=definition.master;kind=definition.kind}
    }
    struct Link: Codable, Equatable {
        var sampleID: String
        var stamp: Stamp
        var materialConfirmed: Bool
        var linkedAt:Date? = Date()
    }
    struct State: Codable, Equatable {
        var version=1
        var enabled=false
        var observer=SpectralEngine.Observer.two
        var imports: [CxFReflectance.Import]=[]
        var links: [String:Link]=[:]
        var samples: [SpectralSample] { imports.flatMap(\.samples) }
    }
    private var cache: State?
    private var cacheRoot: URL?
    private let field="spectralViewing"
    private var observerToken:NSObjectProtocol?
    init() {
        observerToken=NotificationCenter.default.addObserver(forName:.appStateDidChange,object:nil,queue:.main){[weak self] _ in self?.cache=nil}
    }
    deinit {if let observerToken{NotificationCenter.default.removeObserver(observerToken)}}
    private(set) var problem: String?
    func load(from store:AppDataStore) throws -> State {
        let manifest=try store.read()
        guard let raw=manifest[field] else {return State()}
        try checkSchema(raw)
        let result=try JSONDecoder().decode(State.self,from:JSONSerialization.data(withJSONObject:raw))
        guard result.version == 1 else {throw failure("This spectral library needs a newer Colorgain version. It has not been changed.")}
        try validate(result)
        return result
    }
    private func validate(_ state:State) throws {
        guard state.imports.count <= 100, state.imports.reduce(0,{$0+$1.original.count}) <= 16*1024*1024 else {throw failure("The spectral library exceeds its supported size.")}
        var ids=Set<String>()
        for source in state.imports {
            guard source.original.count <= CxFReflectance.maximumBytes,Sharing.sha256(source.original) == source.digest,source.samples.count <= 500,try CxFReflectance.read(source.original,name:source.name).samples == source.samples else {throw failure("The retained spectral source failed its integrity check.")}
            for sample in source.samples {
                try sample.validate()
                guard sample.fileDigest == source.digest,ids.insert(sample.id).inserted else {throw failure("The spectral source has mismatched or duplicate sample identities.")}
            }
        }
        guard (!state.enabled || state.links.values.contains(where:{$0.materialConfirmed})),state.links.values.allSatisfy({ids.contains($0.sampleID)}) else {throw failure("A spectral link references a missing measurement. Original records retained.")}
    }
    /// Unknown future domain fields make this section read-only instead of being erased.
    private func checkSchema(_ raw:Any) throws {
        func keys(_ value:Any,_ allowed:Set<String>) throws {
            guard let dict=value as? [String:Any],Set(dict.keys).isSubset(of:allowed) else {throw failure("This spectral library contains newer fields. Update Colorgain; the original data is unchanged.")}
        }
        try keys(raw,["version","enabled","observer","imports","links"])
        let object=raw as! [String:Any]
        for source in object["imports"] as? [[String:Any]] ?? [] {
            try keys(source,["digest","name","original","samples"])
            for sample in source["samples"] as? [[String:Any]] ?? [] {try keys(sample,["id","objectID","name","start","interval","reflectance","specification","metadata","fileDigest","fileName"])}
        }
        for link in (object["links"] as? [String:[String:Any]] ?? [:]).values {
            try keys(link,["sampleID","stamp","materialConfirmed","linkedAt"])
            if let stamp=link["stamp"] as? [String:Any] {
                try keys(stamp,["source","master","kind"])
                if let source=stamp["source"] {try keys(source,["space","values","press"])}
                if let master=stamp["master"] {try keys(master,["x","y","z"])}
            }
        }
    }
    func reload() {cache=nil;_ = snapshot()}
    func snapshot() -> State {
        let root=AppDataStore.current.root
        if cacheRoot != root || cache == nil {
            cacheRoot=root
            do {cache=try load(from:AppDataStore.current);problem=nil}
            catch {cache=State();problem=error.localizedDescription}
        }
        return cache ?? State()
    }
    func update(in store:AppDataStore, _ change:(inout State)throws->Void) throws {
        var updated: State?
        try Handler_File_Manager.shared.withTransaction(home:store.root) {
            try store.update { manifest in
                var value:State
                if let raw=manifest[field] {try checkSchema(raw);value=try JSONDecoder().decode(State.self,from:JSONSerialization.data(withJSONObject:raw));try validate(value)}
                else {value=State()}
                guard value.version == 1 else {throw failure("Unsupported spectral library version; original data retained.")}
                try change(&value)
                try validate(value)
                guard value.imports.count <= 100,value.imports.reduce(0,{$0+$1.original.count}) <= 16*1024*1024 else {throw failure("The workspace spectral library is limited to 100 files / 16 MB of original data.")}
                manifest[field]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(value));updated=value
            }
        }
        if store.root == AppDataStore.current.root {cacheRoot=store.root;cache=updated;problem=nil;if updated?.enabled == false && PaletteViewing.illuminant != .normal {PaletteViewing.illuminant = .normal}}
        NotificationCenter.default.post(name:.prefsDidChange,object:nil)
    }
    func update(_ change:(inout State)throws->Void) throws {try update(in:AppDataStore.current,change)}
    static func key(catalogue:UUID,palette:UUID,colour:String) -> String { catalogue.uuidString+"/"+palette.uuidString+"/"+colour }
    func prediction(catalogue:UUID,palette:UUID,colour:String,definition:ColourDefinition,light:PaletteViewing.Illuminant) -> SpectralEngine.Prediction? {
        Self.prediction(in:snapshot(),catalogue:catalogue,palette:palette,colour:colour,definition:definition,light:light)
    }
    static func prediction(in state:State,catalogue:UUID,palette:UUID,colour:String,definition:ColourDefinition,light:PaletteViewing.Illuminant) -> SpectralEngine.Prediction? {
        guard state.enabled,definition.kind == .surface,let link=state.links[Self.key(catalogue:catalogue,palette:palette,colour:colour)],link.materialConfirmed,link.stamp == Stamp(definition),let sample=state.samples.first(where:{$0.id == link.sampleID}) else {return nil}
        return try? SpectralEngine.predict(sample,light:light,observer:state.observer)
    }
}

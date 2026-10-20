import AppKit

func runSpectralTests(check: (Bool,String)->Void) {
    print("Spectral measurements, CxF3 import and persistent swatch links")
    func fixture(values:[Double] = (0..<36).map { i in let w=Double(380+i*10);return 0.1+0.7*exp(-pow((w-540)/65,2)) }, start:Int=380, interval:Int=10) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <CxF xmlns="http://colorexchangeformat.com/CxF3-core"><Resources>
        <ObjectCollection><Object Id="patch-1" Name="Synthetic Green Reference"><ColorValues><ReflectanceSpectrum ColorSpecification="spec" MeasureDate="2026-10-17T00:00:00Z">\(values.map(String.init(describing:)).joined(separator:" "))</ReflectanceSpectrum></ColorValues></Object></ObjectCollection>
        <ColorSpecificationCollection><ColorSpecification Id="spec"><TristimulusSpec><Illuminant>D50</Illuminant><Observer>2_Degree</Observer></TristimulusSpec><MeasurementSpec><MeasurementType>Spectrum_Reflectance</MeasurementType><WavelengthRange StartWL="\(start)" Increment="\(interval)"/><Device><DeviceIllumination>M1</DeviceIllumination><Model>Fixture Only</Model></Device></MeasurementSpec></ColorSpecification></ColorSpecificationCollection>
        </Resources></CxF>
        """.utf8)
    }
    func rejected(_ data:Data) -> Bool { do { _ = try CxFReflectance.read(data,name:"invalid.cxf");return false } catch {return true} }
    do {
        let bytes=fixture(), imported=try CxFReflectance.read(bytes,name:"reference.cxf"), sample=imported.samples[0]
        check(imported.original == bytes && imported.samples.count == 1 && sample.reflectance.count == 36,"CxF import retains original bytes, explicit identity and full spectral precision")
        check(sample.metadata["MeasurementSpec/Device/DeviceIllumination"] == "M1" && sample.metadata["MeasureDate"] != nil,"CxF measurement conditions and timestamp are retained rather than inferred")
        check(try CxFReflectance.read(bytes,name:"renamed.cxf").samples[0].id == sample.id,"sample identity follows file content and object ID rather than filename")
        for observer in SpectralEngine.Observer.allCases {
            for light in [PaletteViewing.Illuminant.d50,.d65,.a] {
                for end in [730,780] {
                    let whiteImport=try CxFReflectance.read(fixture(values:Array(repeating:1,count:(end-380)/10+1)),name:"white.cxf")
                    let white=try SpectralEngine.predict(whiteImport.samples[0],light:light,observer:observer)
                    check(abs(white.xyz.y-1) < 1e-6,"perfect reflector normalises to Y=1 for \(observer.rawValue)/\(light.rawValue)/\(end)")
                    let black=try CxFReflectance.read(fixture(values:Array(repeating:0,count:(end-380)/10+1)),name:"black.cxf")
                    check(try SpectralEngine.predict(black.samples[0],light:light,observer:observer).xyz == XYZ(x:0,y:0,z:0),"zero reflectance remains black for \(observer.rawValue)/\(light.rawValue)/\(end)")
                }
            }
        }
        struct Reference:Decodable {let observer:String;let illuminant:String;let end:Int;let referenceXYZ:[Double];let iccXYZ:[Double];let tolerance:Double}
        let referenceURL=Bundle.main.url(forResource:"reference-values",withExtension:"json",subdirectory:"ProofingResources/Spectral") ?? Bundle.main.url(forResource:"reference-values",withExtension:"json") ?? URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("ProofingResources/Spectral/reference-values.json")
        let references=try JSONDecoder().decode([Reference].self,from:Data(contentsOf:referenceURL))
        for ref in references {
            let values=(0..<((ref.end-380)/10+1)).map { i -> Double in let w=Double(380+i*10);return 0.1+0.7*exp(-pow((w-540)/65,2)) }
            let specimen=try CxFReflectance.read(fixture(values:values),name:"synthetic.cxf").samples[0]
            let result=try SpectralEngine.predict(specimen,light:PaletteViewing.Illuminant(rawValue:ref.illuminant)!,observer:SpectralEngine.Observer(rawValue:ref.observer)!)
            let xyz=[result.xyz.x,result.xyz.y,result.xyz.z]
            check(zip(xyz,ref.iccXYZ).allSatisfy {abs($0-$1)<1e-12},"spectral calculation reproduces independently summed ICC weights: \(ref.observer)/\(ref.illuminant)/\(ref.end)")
            check(zip(xyz,ref.referenceXYZ).allSatisfy {abs($0-$1)<ref.tolerance},"10 nm prediction agrees with independent 1 nm CIE integration within stated 0.0012 XYZ tolerance: \(ref.observer)/\(ref.illuminant)/\(ref.end)")
        }
        let d50=try SpectralEngine.predict(sample,light:.d50,observer:.two), d65=try SpectralEngine.predict(sample,light:.d65,observer:.two), a=try SpectralEngine.predict(sample,light:.a,observer:.two), ten=try SpectralEngine.predict(sample,light:.d50,observer:.ten)
        check(d50.xyz != d65.xyz && d50.xyz != a.xyz && ten.xyz != d50.xyz,"illuminants and observers recompute from spectral data and change non-flat sample predictions")
        let mixed=PaletteViewing.rows(original:[.red,.blue],proof:nil,output:false,illuminant:.d50,spectral:[d50.colour,nil])
        check(mixed[1].cells?.count == 2 && mixed[1].cells?[0] != nil && mixed[1].cells?[1] == nil,"mixed palettes keep measured and unavailable swatches in their original positions")
        check(rejected(fixture(values:Array(repeating:50,count:36))),"percentage-like values are not silently rescaled or accepted as reflectance fractions")
        check(rejected(fixture(values:Array(repeating:1.01,count:36))),"reflectance beyond one is rejected instead of claiming fluorescence support")
        check(rejected(fixture(values:Array(repeating:0.2,count:31),start:400)),"incomplete wavelength coverage is rejected without inventing spectral tails")
        check(rejected(fixture(interval:20)),"unsupported coarse sampling is rejected with no unvalidated interpolation")
        check(rejected(Data(String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"0.1",with:"NaN").utf8)),"non-finite spectral numbers are rejected")
        check(rejected(Data(String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"spec\"",with:"missing\"",options:[],range:String(decoding:bytes,as:UTF8.self).range(of:"spec\"")).utf8)),"missing colour specification references cannot create a measurement")
        check(rejected(Data("<!DOCTYPE CxF [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><CxF/>".utf8)),"DTD and external entity input is rejected before XML parsing")
        check(rejected(Data("<CxF>".utf8)),"malformed XML is rejected")
        check(rejected(Data(String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"ReflectanceSpectrum",with:"ColorCIELab").utf8)),"Lab-only CxF cannot masquerade as spectral data")
        check(rejected(Data(String(decoding:bytes,as:UTF8.self).replacingOccurrences(of:"CxF3-core",with:"other").utf8)),"wrong CxF namespaces are rejected")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("Spectral-"+UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let app=AppDataStore(root:root), store=SpectralStore()
        try app.write(AppDataStore.initialManifest())
        try app.update {$0["unrelatedFutureField"]=["preserved":true]}
        let catalogue=UUID(),palette=UUID(),definition=ColourDefinition.of(hex:"#123456")!,key=SpectralStore.key(catalogue:catalogue,palette:palette,colour:"#123456")
        try store.update(in:app) {$0.imports=[imported];$0.links[key] = .init(sampleID:sample.id,stamp:.init(definition),materialConfirmed:true);$0.enabled=true}
        let saved=try store.load(from:app), reloaded=try SpectralStore().load(from:app)
        check(saved == reloaded && saved.imports[0].original == bytes,"measurement library, exact source and swatch links survive a fresh store/reload")
        check((try app.read())["unrelatedFutureField"] != nil,"spectral writes preserve unrelated and future workspace fields")
        check(SpectralStore.prediction(in:saved,catalogue:catalogue,palette:palette,colour:"#123456",definition:definition,light:.d50) != nil,"enabled confirmed swatch link produces a spectral prediction")
        check(SpectralStore.prediction(in:saved,catalogue:UUID(),palette:palette,colour:"#123456",definition:definition,light:.d50) == nil,"same hex in another catalogue cannot inherit a material measurement")
        check(SpectralStore.prediction(in:saved,catalogue:catalogue,palette:UUID(),colour:"#123456",definition:definition,light:.d50) == nil,"same hex in another palette cannot inherit a material measurement")
        check(SpectralStore.prediction(in:saved,catalogue:catalogue,palette:palette,colour:"#123456",definition:.lab(50,10,10),light:.d50) == nil,"editing the colour invalidates the old measurement link")
        var off=saved;off.enabled=false
        check(SpectralStore.prediction(in:off,catalogue:catalogue,palette:palette,colour:"#123456",definition:definition,light:.d50) == nil,"disabling the feature blocks all spectral predictions while retaining measurements")
        var unconfirmed=saved;unconfirmed.links[key]?.materialConfirmed=false
        check(SpectralStore.prediction(in:unconfirmed,catalogue:catalogue,palette:palette,colour:"#123456",definition:definition,light:.d50) == nil,"unconfirmed material model cannot produce a spectral prediction")
        let before=try Data(contentsOf:app.url)
        do {try store.update(in:app) {$0.imports=[]};check(false,"dangling links must be rejected")} catch {check(try Data(contentsOf:app.url)==before,"invalid update is atomic and retains original measurements and links")}
        try app.update { manifest in var section=manifest["spectralViewing"] as! [String:Any];section["futureCondition"]="retained";manifest["spectralViewing"]=section }
        let future=try Data(contentsOf:app.url)
        do {try store.update(in:app) {$0.enabled=false};check(false,"future spectral fields must not be discarded")} catch {check(try Data(contentsOf:app.url)==future,"newer spectral metadata remains byte-identical and read-only")}
    } catch { check(false,"spectral workflow: "+error.localizedDescription) }
}

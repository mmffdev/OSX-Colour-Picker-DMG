import AppKit

func runColourQRTests(check:(Bool,String)->Void) {
    print("Offline colour QR exchange")
    do {
        let definition=ColourDefinition.of(hex:"#F36D6E")!
        let hdr=ColourQR.Entry(name:"HDR master",source:.init(space:RGBSpace.acescg.rawValue,values:[2.123456789012345,0.4,0.2]),master:.init(x:1.23456789012345,y:2.34567890123456,z:0.12),kind:.light)
        let colour=ColourQR.Entry(name:"Sunglo",source:definition.source,master:definition.master,kind:.surface)
        let d=ColourQR.Document(type:"palette",name:"Shared Brand",colours:[colour,hdr])
        let text=try ColourQR.text(d)
        let decoded=try ColourQR.decode(text)
        check(decoded.name==d.name && decoded.colours.map{$0.master}==d.colours.map{$0.master},"minimal QR round trip retains its name, exact XYZ master and colour order")
        check(decoded.colours.allSatisfy{$0.source.space=="xyz" && $0.source.press==nil},"minimal QR excludes original RGB, CMYK, profile and proof data")
        let file=try ColourQR.document(ColourQR.data(d))
        check(file==decoded,"colour file and QR share the same minimal XYZ records")
        let small=ColourQR.Document(type:"swatch",name:"Sunglo",colours:[colour])
        check(try ColourQR.text(small).utf8.count < 220,"single swatch QR stays compact enough for phone-screen scanning")
        print("Named XYZ swatch QR: \(try ColourQR.text(small).utf8.count) UTF-8 bytes")
        let image=try ColourQR.image(ColourQR.text(small));var rect=NSRect(origin:.zero,size:image.size)
        let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil)!
        let scanned=try ColourQR.decode(ColourQR.scan(cg));check(scanned.name==small.name && scanned.colours[0].master==small.colours[0].master,"branded QR decodes back to its named XYZ swatch")
        var damaged=text;let at=damaged.index(damaged.startIndex,offsetBy:ColourQR.prefix.count + 2);damaged.replaceSubrange(at...at,with:damaged[at]=="0" ? "1":"0")
        do{_=try ColourQR.decode(damaged);check(false,"QR integrity rejects altered payload")}catch{check(true,"QR integrity rejects altered payload")}
        var invalid=d;invalid.colours[0].master.x = .nan
        do{_=try ColourQR.data(invalid);check(false,"QR rejects nonfinite XYZ values")}catch{check(true,"QR rejects nonfinite XYZ values")}
        var lib=Library();let id=try ColourQR.insert(d,into:&lib)
        let palette=lib.swatch(id)!
        check(palette.entries.count==2 && lib.name(of:palette.entries[1].hex,in:id)==hdr.name,"import creates one library palette with the complete named colour sequence")
        let stored=lib.colours.first{$0.hex==palette.entries[1].hex}!
        check(stored.source==hdr.source && stored.master==hdr.master && stored.kind==hdr.kind,"import persists the exact master and original source rather than quantising through hex")
        let before=lib
        do{_=try ColourQR.insert(d,into:&lib,target:UUID());check(false,"missing import destination writes nothing")}catch{check(lib==before,"missing import destination writes nothing")}
        let encoded=try JSONEncoder().encode(lib);let loaded=try JSONDecoder().decode(Library.self,from:encoded)
        check(loaded==lib,"QR imported records survive the catalogue schema round trip")
        var empty=d;empty.colours=[]
        do{_=try ColourQR.data(empty);check(false,"empty QR palettes cannot be exported")}catch{check(true,"empty QR palettes cannot be exported")}
    }catch {check(false,"colour QR regression: "+error.localizedDescription)}
}

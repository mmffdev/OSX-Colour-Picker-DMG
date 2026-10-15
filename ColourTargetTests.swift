import AppKit

func runColourTargetTests(check:(Bool,String)->Void){
    func near(_ a:Double,_ b:Double,_ tolerance:Double=1e-7)->Bool {abs(a-b) <= tolerance}
    func same(_ a:XYZ,_ b:XYZ)->Bool {near(a.x,b.x) && near(a.y,b.y) && near(a.z,b.z)}
    func scaled(_ white:XYZ,_ amount:Double)->XYZ {XYZ(x:white.x*amount,y:white.y*amount,z:white.z*amount)}
    let white=XYZ.d50,master=RGBSpace.srgb.master(of:[0.7,0.4,0.2])
    check(near(ColourTargetSpace.pqEncode(100),0.508078421517,1e-10) && near(ColourTargetSpace.pqEncode(1000),0.751827096247,1e-10) && near(ColourTargetSpace.pqEncode(10000),1),"PQ matches ST 2084 100, 1000 and 10000 nit reference signals")
    check(near(ColourTargetSpace.pqDecode(0.508078421517),100,1e-7) && near(ColourTargetSpace.pqDecode(0.751827096247),1000,1e-6),"PQ decodes independent reference code values to absolute luminance")
    let hlgWhite=ColourTargetSpace.hlg.values(of:white)
    check(hlgWhite.allSatisfy{near($0,0.75,0.001)} && same(ColourTargetSpace.hlg.master(of:hlgWhite),white),"HLG reference display maps 203-nit diffuse white to 75 percent signal and back")
    check(near(ColourTargetSpace.cctEncode(0),0.0729055341958355) && near(ColourTargetSpace.cctEncode(0.18),0.413588402492442,1e-10) && near(ColourTargetSpace.cctEncode(1),0.554794520547945,1e-10),"ACEScct matches Academy black, mid-grey and unity code values")
    check([-0.01,0,0.0078125,0.18,1,16].allSatisfy{near(ColourTargetSpace.cctDecode(ColourTargetSpace.cctEncode($0)),$0)},"ACEScct preserves negative values, its toe and scene highlights")
    check(ColourTargetSpace.allCases.filter{$0 != .grey22}.allSatisfy{same($0.master(of:$0.values(of:master)),master)},"every new three-component target round-trips its master without quantisation or clipping")
    let ap0red=ColourTargetSpace.aces2065.master(of:[1,0,0])
    let native=multiply(bradford(from:(0.34567,0.35850),to:(0.32168,0.33767)),[ap0red.x,ap0red.y,ap0red.z])
    check(near(native[0],0.9525523959) && near(native[1],0.3439664498) && near(native[2],0),"ACES2065-1 uses the published AP0 to XYZ matrix under D60")
    check(ColourTargetSpace.eciRGB.values(of:scaled(white,0.18)).allSatisfy{near($0,0.494961076102,1e-8)},"eciRGB v2 uses L-star rather than the old gamma 1.8 curve")
    let grey=ColourTargetSpace.grey22.master(of:[0.5])
    check(near(grey.y,0.217637640824,1e-10) && near(grey.lab.a,0,1e-8) && near(grey.lab.b,0,1e-8),"Grey Gamma 2.2 produces neutral D50 luminance rather than a three-channel colour")
    let cinema=ColourTargetSpace.dciXYZ.values(of:white)
    check(ColourTargetSpace.dciXYZ.text(cinema,legal:false).contains("3960") && same(ColourTargetSpace.dciXYZ.master(of:cinema),white),"DCP XYZ uses 48 nit reference luminance, 52.37 scaling and 12-bit cinema codes")
    let bright=scaled(white,5),definition=ColourDefinition(source:.init(space:"xyz",values:[bright.x,bright.y,bright.z]),master:bright,kind:.light)
    let pq=Rendering.of(definition,in:.init(space:ColourTargetSpace.pq.rawValue)),hlg=Rendering.of(definition,in:.init(space:ColourTargetSpace.hlg.rawValue))
    check(pq.inRange && pq.shown.map{same($0,bright)} == true && !hlg.inRange && (hlg.difference ?? 0) > 0 && hlg.differenceName == "ΔE ITP","HDR keeps highlights above diffuse white and reports the correct metric when the HLG reference peak clips")
    check(near(ColourTargetSpace.deltaITP(master,master),0) && near(ColourTargetSpace.deltaITP(master,white),ColourTargetSpace.deltaITP(white,master)) && ColourTargetSpace.deltaITP(master,white) > 0,"BT.2124 difference is zero for equality and symmetric for distinct colours")
    check(ColourProfiles.starters[1].channels.allSatisfy(\.isPrint) && !ColourProfiles.starters[1].holds(RGBSpace.srgb.rawValue),"Print starter contains no screen-space target")
    let every=ColourProfiles.starters[4]
    check(ColourTargetSpace.allCases.allSatisfy{every.holds($0.rawValue)} && ColourProfiles.starters[2].holds(ColourTargetSpace.pq.rawValue) && ColourProfiles.starters[6].holds(ColourTargetSpace.acescct.rawValue),"delivery presets include HDR, ACES and all new targets in Every Channel")
    check(WorkspaceChannelControls.previewTitle(.init(space:RGBSpace.displayP3.rawValue)).contains("Screen") && WorkspaceChannelControls.previewTitle(.init(space:RGBSpace.p3D65.rawValue)).contains("D65") && WorkspaceChannelControls.previewTitle(.init(space:RGBSpace.dciP3.rawValue)).contains("Cinema White"),"P3 target labels distinguish screen transfer, D65 cinema and projector white")
    let legacy=Data("{\"space\":\"print\",\"press\":\"Missing Press\"}".utf8)
    check((try? JSONDecoder().decode(ProfileChannel.self,from:legacy))?.blackOnly == nil,"old stored channels decode without invented K-only settings")
    let missing=Rendering.of(ColourDefinition.of(hex:"#123456")!,in:.init(space:ProfileChannel.print,press:"Missing ICC "+UUID().uuidString))
    check(missing.value == nil && missing.shown == nil,"a missing press ICC never falls back to Generic CMYK or a screen target")
    let alias=PressProfiles.Profile(name:"PSO Coated v3",path:"unused")
    check(PrintTargetStandards.all[1].installed(in:[alias]) && !PrintTargetStandards.all[2].installed(in:[alias]),"standard profile discovery recognises ICC display names without confusing coated and uncoated conditions")
    check(Rendering.of(ColourDefinition.of(hex:"#123456")!,in:.init(space:"unsupported-future-target")).value == nil,"unknown target spaces remain unavailable rather than becoming a generic press")
    if PressProfiles.space(named:PressProfiles.generic) != nil {
        let mono=Rendering.of(ColourDefinition.of(hex:"#808080")!,in:.init(space:ProfileChannel.print,press:PressProfiles.generic,blackOnly:true))
        check(mono.value?.hasPrefix("C 0  M 0  Y 0  K") == true && mono.shown != nil,"K-only separation keeps CMY at zero through the selected ICC transform")
    }
}

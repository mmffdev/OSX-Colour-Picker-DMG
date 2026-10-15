import AppKit

/// Encodings which are not the legacy display-RGB family. Masters remain XYZ D50.
/// HDR targets use 203 cd/m² diffuse white; HLG uses a 1,000 cd/m², gamma-1.2 reference display.
/// References: ITU-R BT.2100/2408/2124; Academy ACES encodings; SMPTE EG 432-1; ECI eciRGB v2.
enum ColourTargetSpace:String,CaseIterable {
    case pq="rec2100-pq",hlg="rec2100-hlg",aces2065="aces2065-1",acescct
    case linear2020="linear-rec2020",linearP3="linear-p3d65",dciXYZ="dci-xyz",eciRGB="ecirgb-v2",grey22="grey-gamma22"
    var name:String {
        switch self {
        case .pq:return "Rec. 2100 PQ"
        case .hlg:return "Rec. 2100 HLG"
        case .aces2065:return "ACES2065-1"
        case .acescct:return "ACEScct"
        case .linear2020:return "Linear Rec. 2020"
        case .linearP3:return "Linear P3-D65"
        case .dciXYZ:return "DCI XYZ"
        case .eciRGB:return "eciRGB v2"
        case .grey22:return "Grey Gamma 2.2"
        }
    }
    var hint:String {
        switch self {
        case .pq:return "HDR · 203 nit white"
        case .hlg:return "HDR · 1,000 nit display"
        case .aces2065:return "Linear · AP0 interchange"
        case .acescct:return "Log · AP1 grading"
        case .linear2020,.linearP3:return "Linear"
        case .dciXYZ:return "DCP · 48 nit cinema"
        case .eciRGB:return "D50 · L*"
        case .grey22:return "Monochrome · D50"
        }
    }
    var isHDR:Bool {self == .pq || self == .hlg}
    var open:Bool {[Self.aces2065,.acescct,.linear2020,.linearP3].contains(self)}
    private var matrix:Matrix3 {
        switch self {
        case .pq,.hlg,.linear2020:return RGBSpace.rec2020.toMaster
        case .acescct:return RGBSpace.acescg.toMaster
        case .linearP3:return RGBSpace.displayP3.toMaster
        case .aces2065:
            return multiply(bradford(from:(0.32168,0.33767),to:(0.34567,0.35850)),[[0.9525523959,0,0.0000936786],[0.3439664498,0.7281660966,-0.0721325464],[0,0,1.0088251844]])
        case .eciRGB:
            let raw:Matrix3=[[0.67/0.33,0.21/0.71,0.14/0.08],[1,1,1],[0,0.08/0.71,0.78/0.08]]
            let scales=multiply(inverse(raw),[XYZ.d50.x,1,XYZ.d50.z])
            return raw.map{zip($0,scales).map(*)}
        case .dciXYZ:return bradford(from:(0.314,0.351),to:(0.34567,0.35850))
        case .grey22:return [[1,0,0],[0,1,0],[0,0,1]]
        }
    }
    static func pqEncode(_ luminance:Double)->Double {
        let n=pow(max(0,luminance)/10000,2610.0/16384)
        return pow((3424.0/4096+(2413.0/128)*n)/(1+(2392.0/128)*n),2523.0/32)
    }
    static func pqDecode(_ signal:Double)->Double {
        let n=pow(max(0,signal),32.0/2523)
        return 10000*pow(max(0,n-3424.0/4096)/max(1e-15,2413.0/128-(2392.0/128)*n),16384.0/2610)
    }
    static func cctEncode(_ linear:Double)->Double {linear <= 0.0078125 ? 10.5402377416545*linear+0.0729055341958355:(log2(linear)+9.72)/17.52}
    static func cctDecode(_ signal:Double)->Double {signal <= 0.155251141552511 ? (signal-0.0729055341958355)/10.5402377416545:pow(2,signal*17.52-9.72)}
    private func encode(_ linear:Double)->Double {
        let a=abs(linear),sign=linear < 0 ? -1.0:1.0
        switch self {
        case .pq:return sign*Self.pqEncode(a*203)
        case .hlg:return sign*(a <= 1.0/12 ? sqrt(3*a):0.17883277*log(12*a-0.28466892)+0.55991073)
        case .acescct:return Self.cctEncode(linear)
        case .eciRGB:return sign*(a <= 216.0/24389 ? (24389.0/27)*a/100:(116*cbrt(a)-16)/100)
        case .dciXYZ:return sign*pow(a*48/52.37,1/2.6)
        default:return linear
        }
    }
    private func decode(_ signal:Double)->Double {
        let a=abs(signal),sign=signal < 0 ? -1.0:1.0
        switch self {
        case .pq:return sign*Self.pqDecode(a)/203
        case .hlg:return sign*(a <= 0.5 ? a*a/3:(exp((a-0.55991073)/0.17883277)+0.28466892)/12)
        case .acescct:return Self.cctDecode(signal)
        case .eciRGB:return sign*(a <= 0.08 ? 100*a/(24389.0/27):pow((100*a+16)/116,3))
        case .dciXYZ:return sign*pow(a,2.6)*52.37/48
        default:return signal
        }
    }
    func values(of master:XYZ)->[Double] {
        if self == .grey22 {return [pow(max(0,master.y),1/2.2)]}
        var values=multiply(inverse(matrix),[master.x,master.y,master.z])
        if self == .hlg {
            let display=values.map{$0*203/1000},y=max(1e-15,0.2627*display[0]+0.6780*display[1]+0.0593*display[2])
            values=display.map{$0*pow(y,(1-1.2)/1.2)}
        }
        return values.map(encode)
    }
    func master(of values:[Double])->XYZ {
        if self == .grey22 {let y=pow(max(0,values[0]),2.2);return XYZ(x:XYZ.d50.x*y,y:y,z:XYZ.d50.z*y)}
        var linear=values.map(decode)
        if self == .hlg {
            let y=max(0,0.2627*linear[0]+0.6780*linear[1]+0.0593*linear[2])
            linear=linear.map{$0*pow(y,0.2)*1000/203}
        }
        let xyz=multiply(matrix,linear);return XYZ(x:xyz[0],y:xyz[1],z:xyz[2])
    }
    func text(_ values:[Double],legal:Bool)->String {
        if isHDR {return values.map{"\(RGBSpace.videoCode($0,legal:legal))"}.joined(separator:", ")+(legal ? " · 10-bit legal":" · 10-bit full")}
        if self == .dciXYZ {return values.map{"\(Int((min(1,max(0,$0))*4095).rounded()))"}.joined(separator:", ")+" · 12-bit"}
        if self == .grey22 {return String(format:"%.2f%%",values[0]*100)}
        return values.map{String(format:"%.4f",$0)}.joined(separator:", ")
    }
    func render(_ definition:ColourDefinition,in channel:ProfileChannel)->Rendering {
        let raw=values(of:definition.master)
        guard raw.allSatisfy(\.isFinite) else{return Rendering(channel:channel,value:nil,shown:nil,difference:nil,inRange:false,detail:"Non-finite target value")}
        let held=open ? raw:raw.map{min(1,max(0,$0))},shown=master(of:held)
        let within=open || raw.allSatisfy{$0 >= -RGBSpace.slack && $0 <= 1+RGBSpace.slack}
        let delta=isHDR ? Self.deltaITP(definition.master,shown):deltaE2000(definition.master.lab,shown.lab)
        return Rendering(channel:channel,value:text(held,legal:channel.legal ?? false),shown:shown,difference:delta,inRange:within,detail:hint+(isHDR ? " · ΔE ITP · SDR display preview":""))
    }
    /// BT.2124, using BT.2100 PQ ICtCp at the stated 203-nit reference white.
    static func deltaITP(_ a:XYZ,_ b:XYZ)->Double {
        func itp(_ xyz:XYZ)->[Double] {
            let rgb=RGBSpace.rec2020.linearValues(of:xyz).map{$0*203}
            let lms=multiply([[1688.0/4096,2146.0/4096,262.0/4096],[683.0/4096,2951.0/4096,462.0/4096],[99.0/4096,309.0/4096,3688.0/4096]],rgb).map(pqEncode)
            return multiply([[0.5,0.5,0],[6610.0/8192,-13613.0/8192,7003.0/8192],[17933.0/4096,-17390.0/4096,-543.0/4096]],lms)
        }
        return 720*sqrt(zip(itp(a),itp(b)).map{pow($0-$1,2)}.reduce(0,+))
    }
}

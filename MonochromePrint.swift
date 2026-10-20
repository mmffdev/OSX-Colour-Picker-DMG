import AppKit

/// Monochrome proofs use the chosen installed ICC, never a generic screen-grey substitute.
enum MonochromePrint {
    static func render(_ definition:ColourDefinition,in channel:ProfileChannel)->Rendering {
        let name=channel.press ?? PressProfiles.generic,master=definition.master
        let intent=channel.intent ?? .relative
        guard let space=PressProfiles.space(named:name) else {return unavailable(channel,"Install the selected ICC profile: "+name)}
        if channel.space == ProfileChannel.printGrey {
            guard space.model == .monochrome,
                  let prediction=PCSConversion.predict(master,in:space,intent:intent,blackPoint:channel.blackPoint ?? false) else{return unavailable(channel,"The grey ICC transform is unavailable")}
            let shown=prediction.shown,delta=deltaE2000(master.lab,shown.lab)
            return Rendering(channel:channel,value:String(format:"Grey %.2f%%",prediction.values[0]*100),shown:shown,difference:delta,inRange:delta <= Rendering.visible,detail:name+" · "+intent.name)
        }
        guard space.model == .cmyk else{return unavailable(channel,"K-only requires a CMYK press profile")}
        var best:(k:Double,shown:XYZ,delta:Double)?
        func consider(_ k:Double){
            guard let shown=PCSConversion.decode([0,0,0,k],from:space,intent:intent == .absolute ? .absolute : .relative) else{return}
            let delta=deltaE2000(master.lab,shown.lab)
            if best == nil || delta < best!.delta {best=(k,shown,delta)}
        }
        for i in 0...32 {consider(Double(i)/32)}
        guard best != nil else{return unavailable(channel,"The press ICC transform is unavailable")}
        var step=1.0/32
        for _ in 0..<8 {let centre=best!.k;step/=2;consider(max(0,centre-step));consider(min(1,centre+step))}
        let result=best!
        return Rendering(channel:channel,value:String(format:"C 0  M 0  Y 0  K %.2f",result.k*100),shown:result.shown,difference:result.delta,inRange:result.delta <= Rendering.visible,detail:name+" · K-only · "+(channel.intent ?? .relative).name)
    }
    private static func unavailable(_ channel:ProfileChannel,_ detail:String)->Rendering {Rendering(channel:channel,value:nil,shown:nil,difference:nil,inRange:false,detail:detail)}
}

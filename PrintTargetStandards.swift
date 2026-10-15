import Foundation

/// Profile files stay on the user's Mac. These are publisher destinations, never bundled ICC payloads.
enum PrintTargetStandards {
    struct Standard {
        let name:String,aliases:[String],publisher:String,url:URL
        func installed(in profiles:[PressProfiles.Profile])->Bool {
            func key(_ text:String)->String {text.lowercased().filter{$0.isLetter || $0.isNumber}}
            return profiles.contains{profile in aliases.contains{key(profile.name).contains(key($0))}}
        }
    }
    static let all:[Standard]=[
        .init(name:"FOGRA39 · ISO Coated v2",aliases:["fogra39","isocoatedv2"],publisher:"ECI",url:URL(string:"https://eci.org/doku.php?id=en:downloads")!),
        .init(name:"FOGRA51 · PSO Coated v3",aliases:["fogra51","psocoatedv3"],publisher:"ECI",url:URL(string:"https://eci.org/doku.php?id=en:downloads")!),
        .init(name:"FOGRA52 · PSO Uncoated v3",aliases:["fogra52","psouncoatedv3"],publisher:"ECI",url:URL(string:"https://eci.org/doku.php?id=en:downloads")!),
        .init(name:"GRACoL 2013",aliases:["gracol2013","crpc6"],publisher:"PRINTING United",url:URL(string:"https://www.printing.org/library/standards/specifications-for-print-production/gracol")!),
        .init(name:"SWOP 2013",aliases:["swop2013","crpc5"],publisher:"PRINTING United",url:URL(string:"https://www.printing.org/library/standards/specifications-for-print-production/gracol")!),
        .init(name:"Japan Color 2011",aliases:["japancolor2011"],publisher:"Japan Color",url:URL(string:"https://japancolor.jp/icc.html")!),
        .init(name:"Newspaper",aliases:["newspaper","newsprint"],publisher:"WAN-IFRA",url:URL(string:"https://wan-ifra.org/articles/2011/01/07/downloads/")!)
    ]
}

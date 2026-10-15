import AppKit
import ColorSync

/// ICC files remain at their user-selected locations. This catalogue contains metadata and links only.
final class ICCProfileLibrary {
    static let shared=ICCProfileLibrary()
    static let changed=Notification.Name("ICCProfileLibraryChanged")
    static let prefix="Linked ICC "
    static let maximumBytes=32*1024*1024
    struct Profile:Codable,Equatable {
        var id:String,name:String,path:String,model:String,profileClass:String,version:String,copyright:String
        var folder:String?=nil
        var transformable:Bool?=nil
        var key:String {ICCProfileLibrary.prefix+id}
        var canTarget:Bool {transformable != false && ["RGB","CMYK","Grey"].contains(model) && ["mntr","prtr","scnr","spac"].contains(profileClass)}
        var channel:ProfileChannel {ProfileChannel(space:model == "CMYK" ? ProfileChannel.print:(model == "Grey" ? ProfileChannel.printGrey:ProfileChannel.iccRGB),press:key,intent:.relative)}
    }
    enum Failure:LocalizedError {
        case invalid,tooLarge,tooManyFiles,mismatch
        var errorDescription:String? {switch self {
        case .invalid:return "This file is not a valid ICC profile. Choose an .icc or .icm profile."
        case .tooLarge:return "This ICC profile exceeds the 32 MB limit."
        case .tooManyFiles:return "This folder contains more than 100,000 items. Choose a smaller profile folder."
        case .mismatch:return "This is a different ICC profile. Locate the original file; add this one separately if you want another target."
        }}
    }
    private let lock=NSRecursiveLock()
    private var linked:[Profile]=[]
    private var cache:[String:(Date,Int,CGColorSpace)]=[:]
    private var systemProfiles:[Profile]=[]
    var system:[Profile] {lock.lock();defer{lock.unlock()};return systemProfiles}
    private var refreshing=false
    private var timer:Timer?
    private var observer:NSObjectProtocol?
    private let storage="Workspace.ICC.LinkedProfiles"
    var profiles:[Profile] {lock.lock();defer{lock.unlock()};return linked}
    init(load:Bool=true){
        if load,let data=AppPreferences.shared.data(forKey:storage),let saved=try? JSONDecoder().decode([Profile].self,from:data){linked=saved}
    }
    func start(){
        guard timer == nil else{return}
        refresh()
        timer=Timer.scheduledTimer(withTimeInterval:15,repeats:true){[weak self] _ in self?.checkLinks()}
        observer=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification,object:nil,queue:.main){[weak self] _ in self?.refresh()}
    }
    deinit{timer?.invalidate();if let observer{NotificationCenter.default.removeObserver(observer)}}
    static func read(_ url:URL,folder:String?=nil)throws->Profile {
        let size=(try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
        guard size <= maximumBytes else{throw Failure.tooLarge}
        let data=try Data(contentsOf:url,options:.mappedIfSafe)
        return try inspect(data,path:url.path,folder:folder)
    }
    static func inspect(_ data:Data,path:String,folder:String?=nil)throws->Profile {
        guard data.count >= 132,data.count <= maximumBytes else{throw Failure.invalid}
        func u32(_ at:Int)->Int {Int(data[at])<<24 | Int(data[at+1])<<16 | Int(data[at+2])<<8 | Int(data[at+3])}
        func ascii(_ at:Int,_ n:Int)->String {String(data:data.subdata(in:at..<at+n),encoding:.ascii) ?? ""}
        guard ascii(36,4) == "acsp",u32(0) >= 132,u32(0) <= data.count,u32(128) <= 4096,132+u32(128)*12 <= data.count else{throw Failure.invalid}
        let className=ascii(12,4),sig=ascii(16,4)
        let model=["RGB ":"RGB","CMYK":"CMYK","GRAY":"Grey","Lab ":"Lab","XYZ ":"XYZ"][sig] ?? sig.trimmingCharacters(in:.whitespaces)
        var tags:[String:Data]=[:]
        for i in 0..<u32(128){let at=132+i*12,offset=u32(at+4),length=u32(at+8)
            guard offset >= 128,length >= 8,offset <= data.count,length <= data.count-offset else{throw Failure.invalid}
            tags[ascii(at,4)]=data.subdata(in:offset..<offset+length)
        }
        let space=CGColorSpace(iccData:data as CFData)
        let description=tags["desc"].flatMap(tagText)
        let rawName=description.flatMap{$0.isEmpty ? nil:$0} ?? space.flatMap{NSColorSpace(cgColorSpace:$0)?.localizedName} ?? URL(fileURLWithPath:path).deletingPathExtension().lastPathComponent
        let name=String(rawName.prefix(512))
        var profile=Profile(id:Sharing.sha256(data),name:name,path:path,model:model,profileClass:className,version:"\(data[8]).\(data[9]>>4).\(data[9]&15)",copyright:String((tags["cprt"].flatMap(tagText) ?? "Not Stated").prefix(4096)),folder:folder)
        profile.transformable=space != nil && data[8] <= 4
        return profile
    }
    private static func tagText(_ data:Data)->String? {
        guard data.count >= 8 else{return nil}
        func word(_ at:Int)->Int? {guard at >= 0,at+4 <= data.count else{return nil};return data[at..<at+4].reduce(0){$0<<8|Int($1)}}
        let type=String(data:data.prefix(4),encoding:.ascii)
        if type == "text" {return String(data:data.dropFirst(8),encoding:.utf8)?.trimmingCharacters(in:.controlCharacters)}
        if type == "desc",let count=word(8),count > 0,count <= data.count-12 {return String(data:data.subdata(in:12..<12+count-1),encoding:.isoLatin1)}
        if type == "mluc",let count=word(8),let stride=word(12),count > 0,count <= 512,stride >= 12,16+count*stride <= data.count {
            let records=(0..<count).map{16+$0*stride}
            let selected=records.first{String(data:data[$0..<$0+2],encoding:.ascii) == "en"} ?? records[0]
            if let length=word(selected+4),let offset=word(selected+8),offset >= 0,length <= data.count-offset,offset <= data.count {return String(data:data.subdata(in:offset..<offset+length),encoding:.utf16BigEndian)}
        }
        return nil
    }
    static func installed()->[Profile] {
        final class URLs {var urls:[URL]=[]}
        let found=URLs();var seed:UInt32=0
        ColorSyncIterateInstalledProfiles({info,user in
            if let info=info as? [String:Any],let user,let url=info[kColorSyncProfileURL.takeUnretainedValue() as String] as? URL {Unmanaged<URLs>.fromOpaque(user).takeUnretainedValue().urls.append(url)}
            return true
        },&seed,Unmanaged.passUnretained(found).toOpaque(),nil)
        var paths=Set<String>()
        return found.urls.filter{paths.insert($0.path).inserted}.compactMap{try? read($0)}.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    static func files(in folder:URL)throws->[URL] {
        var traversalError:Error?
        guard let iterator=FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants],errorHandler:{_,error in traversalError=error;return false}) else{throw CocoaError(.fileReadNoPermission)}
        var urls:[URL]=[],visited=0
        for case let url as URL in iterator {
            visited+=1;guard visited <= 100000 else{throw Failure.tooManyFiles}
            let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            if values.isSymbolicLink == true{iterator.skipDescendants();continue}
            if values.isRegularFile == true,["icc","icm"].contains(url.pathExtension.lowercased()){urls.append(url)}
        }
        if let traversalError{throw traversalError}
        return urls.sorted{$0.path < $1.path}
    }
    func add(_ profiles:[Profile]){
        lock.lock()
        for profile in profiles {if let i=linked.firstIndex(where:{$0.id == profile.id}){linked[i]=profile}else{linked.append(profile)}}
        cache=[:];lock.unlock();save()
    }
    func relocate(_ id:String,to url:URL)throws {
        let profile=try Self.read(url)
        guard profile.id == id else{throw Failure.mismatch}
        try FolderAccess.authorize(url)
        lock.lock();if let i=linked.firstIndex(where:{$0.id == id}){var replacement=profile;replacement.folder=nil;linked[i]=replacement};cache[id]=nil;lock.unlock();save()
    }
    func remove(_ id:String){lock.lock();linked.removeAll{$0.id == id};cache[id]=nil;lock.unlock();save()}
    func profile(for key:String)->Profile? {let id=key.replacingOccurrences(of:Self.prefix,with:"");return profiles.first{$0.id == id} ?? system.first{$0.id == id}}
    static func resolvedURL(_ profile:Profile)->URL {
        for (old,url) in FolderAccess.held.sorted(by:{$0.key.count > $1.key.count}) {
            if profile.path == old{return url}
            if profile.path.hasPrefix(old+"/"){return url.appendingPathComponent(String(profile.path.dropFirst(old.count+1)))}
        }
        return URL(fileURLWithPath:profile.path)
    }
    func space(for key:String)->CGColorSpace? {
        guard key.hasPrefix(Self.prefix),let profile=profile(for:key) else{return nil}
        let url=Self.resolvedURL(profile)
        lock.lock();defer{lock.unlock()}
        guard let values=try? url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]),let modified=values.contentModificationDate,let size=values.fileSize,size <= Self.maximumBytes else{cache[profile.id]=nil;return nil}
        // URL metadata can be cached, and replacement files can retain size/date.
        // Validate the linked identity before reusing its expensive colour transform.
        guard let data=try? Data(contentsOf:url),data.count <= Self.maximumBytes,Sharing.sha256(data) == profile.id else{cache[profile.id]=nil;return nil}
        if let cached=cache[profile.id]{return cached.2}
        guard let space=CGColorSpace(iccData:data as CFData) else{cache[profile.id]=nil;return nil}
        cache[profile.id]=(modified,size,space);return space
    }
    func needsLocate(_ profile:Profile)->Bool {
        profile.canTarget ? space(for:profile.key) == nil:!FileManager.default.isReadableFile(atPath:Self.resolvedURL(profile).path)
    }
    func grouped(_ profiles:[Profile])->(missing:[Profile],available:[Profile]) {
        let ordered=profiles.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
        return (ordered.filter{needsLocate($0)},ordered.filter{!needsLocate($0)})
    }
    func status(_ profile:Profile)->String {
        if !FileManager.default.isReadableFile(atPath:Self.resolvedURL(profile).path){return "Missing · Locate…"}
        guard profile.canTarget else{return "Inspect Only"}
        return space(for:profile.key) == nil ? (FileManager.default.fileExists(atPath:Self.resolvedURL(profile).path) ? "Changed Or Unavailable":"Missing · Locate…"):"Available"
    }
    private var lastStates:[String:Bool]=[:]
    private func checkLinks(){let states=Dictionary(profiles.map{($0.id,!needsLocate($0))},uniquingKeysWith:{$0 || $1});if states != lastStates{lastStates=states;NotificationCenter.default.post(name:Self.changed,object:self)}}
    func refresh(){
        guard !refreshing else{return};refreshing=true
        DispatchQueue.global(qos:.utility).async {[weak self] in
            let system=Self.installed()
            DispatchQueue.main.async {guard let self else{return};self.lock.lock();self.systemProfiles=system;self.lock.unlock();self.refreshing=false;self.checkLinks();NotificationCenter.default.post(name:Self.changed,object:self)}
        }
    }
    private func save(){if let data=try? JSONEncoder().encode(profiles){AppPreferences.shared.set(data,forKey:storage)};NotificationCenter.default.post(name:Self.changed,object:self)}
}

/// External RGB ICC targets use the actual file's transform, not a guessed built-in RGB space.
enum ICCRGBRendering {
    static func render(_ definition:ColourDefinition,in channel:ProfileChannel)->Rendering {
        let key=channel.press ?? "",store=ICCProfileLibrary.shared
        guard let space=store.space(for:key),space.model == .rgb,
              let source=CGColor(colorSpace:CGColorSpace(name:CGColorSpace.genericXYZ)!,components:[CGFloat(definition.master.x),CGFloat(definition.master.y),CGFloat(definition.master.z),1]),
              let encoded=source.converted(to:space,intent:(channel.intent ?? .relative).system,options:nil),let values=encoded.components,values.count >= 3,
              let back=encoded.converted(to:CGColorSpace(name:CGColorSpace.genericXYZ)!,intent:.relativeColorimetric,options:nil)?.components,back.count >= 3 else {
            return Rendering(channel:channel,value:nil,shown:nil,difference:nil,inRange:false,detail:"ICC Profile Missing Or Unavailable · Locate It In ICC Profiles")
        }
        let shown=XYZ(x:Double(back[0]),y:Double(back[1]),z:Double(back[2])),delta=deltaE2000(definition.master.lab,shown.lab)
        return Rendering(channel:channel,value:zip(["R","G","B"],values.prefix(3)).map{String(format:"%@ %.4f",$0.0,Double($0.1))}.joined(separator:"  "),shown:shown,difference:delta,inRange:delta <= Rendering.visible,detail:(store.profile(for:key)?.name ?? "ICC")+" · "+(channel.intent ?? .relative).name)
    }
}

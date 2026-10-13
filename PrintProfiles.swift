import AppKit

extension Notification.Name { static let printProfilesChanged = Notification.Name("Colorgain.PrintProfilesChanged") }

/// A print settings preset references an installed ICC condition; it does not manufacture a new ICC profile.
struct PrintProfileSettings: Codable, Equatable {
    var press = PressProfiles.generic
    var intent = RenderingIntent.relative
    var blackPoint = false
    var tolerance = 2.0
    var channel: ProfileChannel { .init(space:ProfileChannel.print,press:press,intent:intent,blackPoint:blackPoint) }
    func validate() throws {
        guard !press.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,press.utf8.count<=512,
              tolerance.isFinite,tolerance>0,tolerance<=100 else {throw failure("Invalid printing condition or ΔE tolerance.")}
    }
}
struct SavedPrintProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var description: String
    var settings: PrintProfileSettings
    var createdAt = Date()
    var changedAt = Date()
    func validate() throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.utf8.count<=512,description.utf8.count<=4000,
              createdAt.timeIntervalSince1970.isFinite,changedAt.timeIntervalSince1970.isFinite else {throw failure("Give this profile a name and a description under 4,000 bytes.")}
        try settings.validate()
    }
}
enum SavedPrintProfiles {
    static let key="prepress.printProfiles"
    struct Document:Codable {
        var version=1
        var profiles:[SavedPrintProfile]=[]
        var current=PrintProfileSettings()
        var selected:UUID? = nil
    }
    private struct Exchange:Codable {
        var format="colorgain.print-profile"
        var version=1
        var profile:SavedPrintProfile
    }
    static func load(from store:AppDataStore = .current) throws -> Document {
        let manifest=try store.read(), settings=manifest["settings"] as? [String:Any] ?? [:]
        guard let value=settings[key],!(value is NSNull) else{return Document()}
        let data=try JSONSerialization.data(withJSONObject:value)
        guard data.count<=4*1024*1024 else{throw failure("The saved print profile list exceeds its limit.")}
        let d=try JSONDecoder().decode(Document.self,from:data)
        guard d.version==1,d.profiles.count<=512,Set(d.profiles.map{$0.id}).count==d.profiles.count else{throw failure("Unsupported or invalid print profiles. The saved data has been retained.")}
        try d.current.validate();try d.profiles.forEach{try $0.validate()}
        guard d.selected==nil || d.profiles.contains(where:{$0.id==d.selected}) else{throw failure("The selected print profile is unavailable.")}
        return d
    }
    private static func persist(_ document:Document,to store:AppDataStore) throws {
        let data=try JSONEncoder().encode(document), object=try JSONSerialization.jsonObject(with:data)
        try store.update { manifest in var settings=manifest["settings"] as? [String:Any] ?? [:];settings[key]=object;manifest["settings"]=settings }
        if store.url == AppDataStore.current.url { PrintCondition.current=document.current.channel; NotificationCenter.default.post(name:.printProfilesChanged,object:nil) }
    }
    static func setCurrent(_ settings:PrintProfileSettings,selected:UUID? = nil,in store:AppDataStore = .current) throws {
        try settings.validate();var d=try load(from:store)
        guard selected==nil || d.profiles.contains(where:{$0.id==selected}) else{throw failure("The selected profile no longer exists.")}
        d.current=settings;d.selected=selected;try persist(d,to:store)
    }
    @discardableResult static func save(_ profile:SavedPrintProfile,in store:AppDataStore = .current) throws -> SavedPrintProfile {
        try profile.validate();var d=try load(from:store), profile=profile
        guard d.profiles.count<512 || d.profiles.contains(where:{$0.id==profile.id}) else{throw failure("The saved profile limit has been reached.")}
        profile.name=uniqueName(profile.name.trimmingCharacters(in:.whitespacesAndNewlines),among:d.profiles.filter{$0.id != profile.id}.map{$0.name})
        profile.changedAt=Date()
        if let i=d.profiles.firstIndex(where:{$0.id==profile.id}){profile.createdAt=d.profiles[i].createdAt;d.profiles[i]=profile}else{d.profiles.append(profile)}
        d.selected=profile.id;d.current=profile.settings;try persist(d,to:store);return profile
    }
    static func remove(_ id:UUID,in store:AppDataStore = .current) throws {
        var d=try load(from:store);guard d.profiles.contains(where:{$0.id==id}) else{return}
        d.profiles.removeAll{$0.id==id};if d.selected==id{d.selected=nil};try persist(d,to:store)
    }
    static func select(_ id:UUID,in store:AppDataStore = .current) throws {
        let d=try load(from:store);guard let p=d.profiles.first(where:{$0.id==id}) else{throw failure("The selected profile no longer exists.")}
        try setCurrent(p.settings,selected:id,in:store)
    }
    @discardableResult static func duplicate(_ id:UUID,in store:AppDataStore = .current) throws -> SavedPrintProfile {
        let d=try load(from:store);guard var p=d.profiles.first(where:{$0.id==id}) else{throw failure("Select a saved profile first.")}
        p.id=UUID();p.name += " Copy";p.createdAt=Date();return try save(p,in:store)
    }
    static func export(_ p:SavedPrintProfile) throws -> Data {try p.validate();let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(Exchange(profile:p))}
    @discardableResult static func importProfile(_ data:Data,in store:AppDataStore = .current) throws -> SavedPrintProfile {
        guard data.count<=65536 else{throw failure("Choose a .colpro profile under 64 KB.")}
        let exchange=try JSONDecoder().decode(Exchange.self,from:data)
        guard exchange.version==1,exchange.format=="colorgain.print-profile" else{throw failure("Unsupported print profile file.")}
        var p=exchange.profile;try p.validate();p.id=UUID();p.createdAt=Date();p.changedAt=p.createdAt;return try save(p,in:store)
    }
}

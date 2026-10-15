import Foundation

func runPrintProfileTests(check:(Bool,String)->Void){
    print("Saved print profiles and .colpro exchange")
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root)}
    let store=AppDataStore(root:root)
    do{
        try store.write(AppDataStore.initialManifest())
        try store.update{$0["settings"]=["existingSetting":"Retained"]; $0["catalogues"]=[["name":"Existing","path":"/fixture"]]}
        let settings=PrintProfileSettings(press:"Uninstalled Customer ICC",intent:.absolute,blackPoint:true,tolerance:1.5)
        let saved=try SavedPrintProfiles.save(.init(name:"Packaging",description:"Customer carton",settings:settings),in:store)
        var doc=try SavedPrintProfiles.load(from:store)
        check(doc.profiles==[saved] && doc.current==settings && doc.selected==saved.id,"print profiles and current settings persist in .coldata")
        let manifest=try store.read()
        check((manifest["settings"] as? [String:Any])?["existingSetting"] as? String == "Retained" && (manifest["catalogues"] as? [[String:String]])?.first?["name"]=="Existing","saving print settings preserves unrelated setup and catalogue entries")
        let bytes=try SavedPrintProfiles.export(saved),imported=try SavedPrintProfiles.importProfile(bytes,in:store)
        check(imported.settings==settings && imported.description==saved.description && imported.id != saved.id,".colpro import preserves condition, intent, BPC, tolerance and description with an independent identity")
        check(imported.name != saved.name,"duplicate profile import keeps both named profiles")
        var edit=saved;edit.name="Packaging Revised";edit.description="Updated carton";edit.settings.tolerance=3
        let edited=try SavedPrintProfiles.save(edit,in:store);doc=try SavedPrintProfiles.load(from:store)
        check(doc.profiles.count==2 && edited.id==saved.id && edited.createdAt==saved.createdAt && doc.current.tolerance==3,"editing a saved profile updates its settings while retaining identity and creation date")
        let copy=try SavedPrintProfiles.duplicate(saved.id,in:store)
        check(copy.id != saved.id && copy.settings==edited.settings,"duplicating a profile creates an independent complete settings copy")
        try SavedPrintProfiles.remove(copy.id,in:store);doc=try SavedPrintProfiles.load(from:store)
        check(doc.selected==nil && doc.current==copy.settings && !doc.profiles.contains{$0.id==copy.id},"removing the active profile preserves its current settings and removes only that saved entry")
        try SavedPrintProfiles.select(imported.id,in:store)
        check(try SavedPrintProfiles.load(from:store).current==settings,"selecting an imported profile restores all shared print settings")
        let before=try Data(contentsOf:store.url)
        var invalid=imported;invalid.settings.tolerance = .nan
        do{try SavedPrintProfiles.save(invalid,in:store);check(false,"invalid print settings do not overwrite .coldata")}catch{check(try Data(contentsOf:store.url)==before,"invalid print settings do not overwrite .coldata")}
        var object=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];object["version"]=99
        do{try SavedPrintProfiles.importProfile(JSONSerialization.data(withJSONObject:object),in:store);check(false,"future .colpro files are rejected without changing saved settings")}catch{check(try Data(contentsOf:store.url)==before,"future .colpro files are rejected without changing saved settings")}
    }catch{check(false,"print profile regression: "+error.localizedDescription)}
}

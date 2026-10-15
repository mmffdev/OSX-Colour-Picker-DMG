import AppKit

func runICCProfileTests(check:(Bool,String)->Void){
    let root=FileManager.default.temporaryDirectory.appendingPathComponent("ICC-Library-Test-"+UUID().uuidString,isDirectory:true)
    let storage="Workspace.ICC.LinkedProfiles",previous=AppPreferences.shared.object(forKey:storage)
    defer{try? FileManager.default.removeItem(at:root);AppPreferences.shared.set(previous,forKey:storage)}
    do {
        try FileManager.default.createDirectory(at:root.appendingPathComponent("Nested/Press"),withIntermediateDirectories:true)
        guard let data=CGColorSpace(name:CGColorSpace.sRGB)?.copyICCData() as Data? else{check(false,"ICC test fixture is available");return}
        let original=root.appendingPathComponent("Nested/Press/Test.icc"),moved=root.appendingPathComponent("Moved.icc")
        try data.write(to:original)
        try Data("not a profile".utf8).write(to:root.appendingPathComponent("Readme.txt"))
        let profile=try ICCProfileLibrary.read(original,folder:root.path)
        check(profile.id == Sharing.sha256(data) && profile.model == "RGB" && profile.canTarget && !profile.name.isEmpty,"ICC metadata reads the real model, description and content hash")
        let files=try ICCProfileLibrary.files(in:root)
        check(files.map{$0.resolvingSymlinksInPath()} == [original.resolvingSymlinksInPath()],"ICC folder linking discovers nested profiles and ignores unrelated files")
        let registry=ICCProfileLibrary(load:false);registry.add([profile,profile])
        check(registry.profiles.count == 1 && registry.space(for:profile.key)?.model == .rgb,"duplicate ICC bytes produce one usable linked target")
        let persisted=AppPreferences.shared.data(forKey:storage) ?? Data()
        check((try? JSONDecoder().decode([ICCProfileLibrary.Profile].self,from:persisted))?.first?.path == profile.path && persisted.range(of:data) == nil,"ICC registry stores metadata and references without embedding profile bytes")
        check(ICCProfileLibrary().profiles == [profile],"ICC file references survive a library reload")
        try FileManager.default.moveItem(at:original,to:moved)
        check(registry.space(for:profile.key) == nil && registry.status(profile).contains("Missing"),"a moved ICC invalidates its cached transform instead of silently using old bytes")
        let groups=registry.grouped(registry.profiles)
        check(groups.missing.map(\.id) == [profile.id] && groups.available.isEmpty,"missing ICCs are partitioned into the shared warning section")
        try registry.relocate(profile.id,to:moved)
        check(registry.space(for:profile.key) != nil && registry.profiles.first?.path == moved.path,"relocating the same ICC restores its linked target")
        let other=root.appendingPathComponent("Different.icc")
        let otherData=CGColorSpace(name:CGColorSpace.displayP3)!.copyICCData()! as Data
        try otherData.write(to:other)
        var rejected=false;do{try registry.relocate(profile.id,to:other)}catch{rejected=true}
        check(rejected && registry.profiles.first?.path == moved.path,"relocation refuses a different ICC even when it is a valid profile")
        var corrupt=data;corrupt[36]=0
        check((try? ICCProfileLibrary.inspect(corrupt,path:"Corrupt.icc")) == nil && (try? ICCProfileLibrary.inspect(Data(data.prefix(100)),path:"Truncated.icc")) == nil,"ICC parsing rejects corrupt signatures and truncated headers")
        var badTags=data;badTags[128]=255
        check((try? ICCProfileLibrary.inspect(badTags,path:"BadTags.icc")) == nil,"ICC tag counts are bounded before reading tag records")
        try otherData.write(to:moved)
        check(registry.space(for:profile.key) == nil,"changed bytes at the saved path cannot impersonate the original target")
        try data.write(to:moved)
        let shared=ICCProfileLibrary.shared,prior=shared.profiles
        let relocated=try ICCProfileLibrary.read(moved)
        shared.add([relocated])
        let result=Rendering.of(ColourDefinition.of(hex:"#336699")!,in:relocated.channel)
        let values=(result.value ?? "").components(separatedBy:"  ").compactMap{Double($0.split(separator:" ").last ?? "")}
        check(values.count == 3 && zip(values,[0.2,0.4,0.6]).allSatisfy{abs($0-$1) < 0.002} && (result.difference ?? 99) < 0.1,"linked RGB rendering uses its ICC transform and round-trips a known sRGB colour (\(result.value ?? result.detail), Delta \(result.difference ?? -1))")
        if !prior.contains(where:{$0.id == relocated.id}){shared.remove(relocated.id)}else{shared.add(prior.filter{$0.id == relocated.id})}
        registry.remove(profile.id)
        check(FileManager.default.fileExists(atPath:moved.path) && registry.profiles.isEmpty,"Remove Link preserves the user's original ICC file")
        let download=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("ICC",isDirectory:true)
        if FileManager.default.fileExists(atPath:download.path),let downloaded=try? ICCProfileLibrary.files(in:download),!downloaded.isEmpty {
            let profiles=try downloaded.map{try ICCProfileLibrary.read($0)}
            check(profiles.allSatisfy{!$0.id.isEmpty && !$0.name.isEmpty && !$0.model.isEmpty},"available user-supplied nested ICC downloads expose their real metadata")
            if let press=profiles.first(where:{$0.model == "CMYK" && $0.canTarget}) {
                let prior=shared.profiles;shared.add([press])
                let rendering=Rendering.of(ColourDefinition.of(hex:"#336699")!,in:press.channel)
                check(rendering.value?.contains("C ") == true && rendering.shown != nil && rendering.difference?.isFinite == true,"a user-downloaded CMYK ICC supplies real separation values and a predicted proof")
                if !prior.contains(where:{$0.id == press.id}){shared.remove(press.id)}else{shared.add(prior.filter{$0.id == press.id})}
            }
        }
    }catch{check(false,"ICC library integration: "+error.localizedDescription)}
}

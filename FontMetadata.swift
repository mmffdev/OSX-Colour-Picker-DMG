import AppKit
import CoreText

/// Read-only facts about the selected face. These come from Core Text and the
/// font's own tables; annotations in FontAssetInfo remain separately editable.
struct FontFaceFacts {
    struct Section {
        let title:String
        let rows:[(String,String)]
    }
    let sections:[Section]
    let preview:String
    let previewFont:NSFont

    static func read(postScriptName:String,family:String,sourceURL:URL?)->FontFaceFacts? {
        let descriptor:CTFontDescriptor
        if let sourceURL,
           let found=(CTFontManagerCreateFontDescriptorsFromURL(sourceURL as CFURL) as? [CTFontDescriptor]),
           let match=found.first(where:{(CTFontDescriptorCopyAttribute($0,kCTFontNameAttribute) as? String) == postScriptName}) ?? found.first {
            descriptor=match
        } else {
            descriptor=CTFontDescriptorCreateWithNameAndSize(postScriptName as CFString,24)
        }
        let font=CTFontCreateWithFontDescriptor(descriptor,24,nil)
        let previewFont=font as NSFont
        func name(_ key:CFString)->String? {
            (CTFontCopyName(font,key) as String?)?.trimmingCharacters(in:.whitespacesAndNewlines).nilIfEmpty
        }
        func add(_ label:String,_ value:String?,to rows:inout [(String,String)]) {
            if let value=value?.trimmingCharacters(in:.whitespacesAndNewlines),!value.isEmpty {rows.append((label,value))}
        }

        let covered=CTFontCopyCharacterSet(font) as CharacterSet
        let scripts:[(String,String)]=[
            ("Latin","ABC abc"),("Cyrillic","Привет мир"),("Greek","Ελληνικά"),
            ("Simplified Han","汉字排版设计"),("Traditional Han","漢字排版設計"),
            ("Japanese","かなカナ日本語"),("Korean","한글 글꼴"),
            ("Arabic","العربية"),("Hebrew","עברית"),("Devanagari","नमस्ते"),
            ("Thai","ภาษาไทย")]
        func supports(_ text:String)->Bool {
            let scalars=text.unicodeScalars.filter{!CharacterSet.whitespacesAndNewlines.contains($0)}
            return !scalars.isEmpty && scalars.allSatisfy{covered.contains($0)}
        }
        let supportedScripts=scripts.filter{supports($0.1)}.map(\.0)
        let sample=scripts.first(where:{$0.0 == "Simplified Han" && supports($0.1)})?.1
            ?? scripts.first(where:{$0.0 == "Traditional Han" && supports($0.1)})?.1
            ?? scripts.first(where:{$0.0 != "Latin" && supports($0.1)})?.1
            ?? "Colorgain ABC abc 0123456789"
        var previewLines=[sample]
        if sample.hasPrefix("汉") || sample.hasPrefix("漢"),supports("色彩管理 字体示例") {
            previewLines.append("色彩管理 字体示例")
        }
        if !sample.contains("ABC abc 0123456789"),supports("ABC abc 0123456789") {
            previewLines.append("ABC abc 0123456789")
        }
        let preview=previewLines.joined(separator:"\n")

        var languageRows:[(String,String)]=[]
        let languageCodes=CTFontCopySupportedLanguages(font) as? [String] ?? []
        let languages=Set(languageCodes.compactMap { tag -> String? in
            let code=tag.split(separator:"-").first.map(String.init) ?? tag
            return Locale.current.localizedString(forLanguageCode:code)?.capitalized
        }).sorted{$0.localizedStandardCompare($1) == .orderedAscending}
        add("Supported Languages",languages.isEmpty ? nil:languages.joined(separator:" · "),to:&languageRows)
        add("Scripts",supportedScripts.isEmpty ? nil:supportedScripts.joined(separator:" · "),to:&languageRows)

        var identifiers:[(String,String)]=[]
        add("Family Name",name(kCTFontFamilyNameKey) ?? family,to:&identifiers)
        add("Style Name",name(kCTFontStyleNameKey),to:&identifiers)
        add("PostScript Name",name(kCTFontPostScriptNameKey) ?? postScriptName,to:&identifiers)
        add("Unique Name",name(kCTFontUniqueNameKey),to:&identifiers)

        var usage:[(String,String)]=[]
        add("Copyright",name(kCTFontCopyrightNameKey),to:&usage)
        add("Trademark",name(kCTFontTrademarkNameKey),to:&usage)
        if let table=CTFontCopyTable(font,CTFontTableTag(0x4F532F32),[]) as Data?,table.count >= 10 {
            let flags=(UInt16(table[8]) << 8) | UInt16(table[9])
            let embedding:String
            if flags & 0x0002 != 0 {embedding="Restricted"}
            else if flags & 0x0008 != 0 {embedding="Editable"}
            else if flags & 0x0004 != 0 {embedding="Preview & Print"}
            else {embedding="Installable"}
            var qualifiers:[String]=[]
            if flags & 0x0100 != 0 {qualifiers.append("No subsetting")}
            if flags & 0x0200 != 0 {qualifiers.append("Bitmap only")}
            add("Embedding",([embedding]+qualifiers).joined(separator:" · "),to:&usage)
            add("Copy Protected",flags & 0x0002 != 0 ? "Yes":"No",to:&usage)
        }

        var details:[(String,String)]=[]
        let actualURL=sourceURL ?? (CTFontCopyAttribute(font,kCTFontURLAttribute) as? URL)
            ?? (CTFontDescriptorCopyAttribute(descriptor,kCTFontURLAttribute) as? URL)
        let ext=actualURL?.pathExtension.lowercased()
        let format:[String:String]=["otf":"OpenType","ttf":"TrueType","ttc":"TrueType Collection","otc":"OpenType Collection"]
        add("Format",ext.flatMap{format[$0]},to:&details)
        if let path=actualURL?.standardizedFileURL.path {
            add("System Font",path.hasPrefix("/System/Library/Fonts/") ? "Yes":"No",to:&details)
        }
        add("Active",NSFont(name:postScriptName,size:24) == nil ? "No":"Yes",to:&details)
        add("Glyph Count",String(CTFontGetGlyphCount(font)),to:&details)
        add("Version",name(kCTFontVersionNameKey),to:&details)

        return FontFaceFacts(sections:[Section(title:"Language Support",rows:languageRows),Section(title:"Identifiers",rows:identifiers),Section(title:"Usage",rows:usage),Section(title:"Details",rows:details)],preview:preview,previewFont:previewFont)
    }
}

private extension String {
    var nilIfEmpty:String? {isEmpty ? nil:self}
}

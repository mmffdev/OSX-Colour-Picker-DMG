import AppKit
import WebKit

struct WorkFormField:Codable,Equatable {
    var id:String
    var label:String
    var type:String
}
struct WorkFormPreset:Codable,Equatable {
    var id:String
    var name:String
    var fields:[WorkFormField]
}

/// Shared catalogue onboarding, directory and modal editor. All writes use the catalogue store.
final class CatalogueJourneyView:WKWebView,WKScriptMessageHandler,WKNavigationDelegate {
    private weak var library:LibraryController?
    private let mode:String
    private let clientID:UUID?
    private let projectID:UUID?
    override var intrinsicContentSize:NSSize {NSSize(width:720,height:580)}
    var finished:(()->Void)?
    var onBrowse:(()->Void)?
    private var loaded=false
    private var committed=false
    private var watch:NSObjectProtocol?
    init(library:LibraryController,mode:String="welcome",client:UUID?=nil,project:UUID?=nil){
        self.library=library;self.mode=mode;clientID=client;projectID=project
        let configuration=WKWebViewConfiguration()
        super.init(frame:.zero,configuration:configuration)
        configuration.userContentController.add(JourneyMessageBridge(self),name:"journey")
        navigationDelegate=self
        loadHTMLString(Self.document,baseURL:nil)
        watch=NotificationCenter.default.addObserver(forName:.libraryDidChange,object:library,queue:.main){[weak self] _ in self?.refresh()}
    }
    required init?(coder:NSCoder){fatalError()}
    deinit{if let watch{NotificationCenter.default.removeObserver(watch)}}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){loaded=true;refresh()}
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(action.request.url?.absoluteString == "about:blank" ? .allow:.cancel)}
    func refresh(){
        guard loaded,let library else{return}
        let file=SchemaTrial.read(in:library.store.root),config=SimpleAssetType.includingWorkspace(file.structure ?? SimpleCatalogueStructure(),home:Catalogues.standard.root)
        let availableTypes=SimpleAssetType.types(in:config)
        let clients=file.collections.map{c -> [String:Any] in
            ["id":c.id.uuidString,"name":c.name,"word":c.stack.name,"profile":c.profile ?? [:],"assets":availableTypes.filter{type in c.stack.children.flatMap(\.children).contains{node in (type.role != nil && SchemaTrial.role(of:node) == type.role) || SchemaTrial.type(of:node) == (type.id == "photography" ? "Photography":type.title)}}.map(\.id),"projects":library.library.orderedProjects.filter{file.places[$0.id.uuidString]?.collection == c.id}.map{["id":$0.id.uuidString,"name":$0.name,"details":$0.details ?? [:]] as [String:Any]}]
        }
        let presets=(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(config.formPresets ?? []))) ?? []
        let data:[String:Any]=["personal":config.personalMode == true,"personalID":config.personalCollectionID?.uuidString ?? "","mode":mode,"clientID":clientID?.uuidString ?? "","projectID":projectID?.uuidString ?? "","clientWord":config.clientName,"workWord":config.singular,"clients":clients,"presets":presets,"assets":config.assetTypes,"libraryAssets":GlobalAssets(home:Catalogues.standard.root).assetTypes,"types":availableTypes.map{["id":$0.id,"name":$0.selectable ? $0.setupTitle:$0.title,"family":$0.setupFamily,"selectable":$0.selectable] as [String:Any]},"customAssetFamilies":config.customAssetFamilies ?? [],"profileFields":ProjectField.fields(in:.client).map{["id":$0.rawValue,"name":$0.title.capitalized]},"dark":mode == "directory" || Theme.isDark]
        guard let bytes=try? JSONSerialization.data(withJSONObject:data),let json=String(data:bytes,encoding:.utf8) else{return}
        evaluateJavaScript("load(\(json))",completionHandler:nil)
    }
    static func present(library:LibraryController,over host:NSView,client:UUID?=nil,project:UUID?=nil,kind:String="client"){
        guard kind != "client" || !SchemaTrial.personalMode else{return}
        let owner=kind == "work" && project == nil && SchemaTrial.personalMode ? SchemaTrial.personalCollection?.id:client
        let editor=CatalogueJourneyView(library:library,mode:kind,client:owner,project:project)
        let modal=SwissFocusModal(content:editor,size:NSSize(width:760,height:720))
        // Settings owns its toolbar layout. Hiding it during WebKit presentation can
        // recursively resize the settings window on macOS.
        modal.preservesHostToolbar = true
        editor.finished={ [weak modal] in modal?.dismissOverlay() }
        modal.present(over:host)
    }

    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){
        guard !committed,message.frameInfo.isMainFrame,let library,let d=message.body as? [String:Any],let action=d["action"] as? String else{return}
        do {
            switch action {
            case "importLibrary":MyLibraryFile.chooseImport(library:library,over:self)
            case "exportLibrary":MyLibraryFile.chooseExport(over:self)
            case "setPersonal":
                let schema=try SimpleCatalogue.settingPersonal(d["enabled"] as? Bool == true,in:SchemaTrial.read(in:library.store.root))
                try library.store.save(library.library,schema:schema);library.reload();refresh()
            case "openClient":
                guard !SchemaTrial.personalMode else{throw failure("Enable clients in Catalogue Structure to add a client.")}
                Self.present(library:library,over:self,client:(d["id"] as? String).flatMap(UUID.init(uuidString:)),kind:"client")
            case "openWork":Self.present(library:library,over:self,client:(d["client"] as? String).flatMap(UUID.init(uuidString:)),project:(d["id"] as? String).flatMap(UUID.init(uuidString:)),kind:"work")
            case "cancel":finished?()
            case "browse":onBrowse?()
            case "saveDefaults":
                var file=SchemaTrial.read(in:library.store.root);guard let original=file.structure else{return};var config=SimpleAssetType.includingWorkspace(original,home:Catalogues.standard.root)
                config.clientLabel=d["clientWord"] as? String ?? config.clientName
                config.singular=d["workWord"] as? String ?? config.singular
                config.plural=["Project":"Projects","Product":"Products","Campaign":"Campaigns","Work Order":"Work Orders"][config.singular] ?? config.singular
                config.assetTypes=d["assets"] as? [String] ?? config.assetTypes;try config.validate()
                let libraryAssets=d["libraryAssets"] as? [String] ?? config.assetTypes
                guard libraryAssets.allSatisfy({SimpleAssetType.find($0,in:config) != nil}) else{throw failure("Unsupported asset category.")}
                file.structure=config;try library.store.save(library.library,schema:file)
                try GlobalAssets(home:Catalogues.standard.root).setAssetTypes(libraryAssets)
                library.reload();refresh()
            case "saveClient":
                guard !SchemaTrial.personalMode else{throw failure("Enable clients before adding or editing a client.")}
                var file=SchemaTrial.read(in:library.store.root)
                guard let original=file.structure else{throw failure("This catalogue needs conversion before using this editor.")};var config=SimpleAssetType.includingWorkspace(original,home:Catalogues.standard.root)
                let name=(d["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines);try SimpleCatalogue.validateLabel(name)
                guard !file.collections.contains(where:{$0.id != clientID && $0.name.caseInsensitiveCompare(name) == .orderedSame}) else{throw failure("That name is already in this catalogue.")}
                let word=d["word"] as? String ?? config.singular;try SimpleCatalogue.validateLabel(word)
                config.singular=word;config.plural=["Project":"Projects","Product":"Products","Campaign":"Campaigns","Work Order":"Work Orders"][word] ?? word
                config.assetTypes=d["assets"] as? [String] ?? config.assetTypes;try config.validate()
                var client=clientID.flatMap{id in file.collections.first{$0.id == id}} ?? SimpleCatalogue.client(name,config:config)
                client.name=name;client.profile=d["profile"] as? [String:String];client.stack=SimpleCatalogue.stack(config,existing:client.stack);client.workItemPlural=config.plural
                if let problem=ProjectField.problem(name:name,values:client.profile ?? [:],naming:config.clientName){throw failure(problem)}
                if let index=file.collections.firstIndex(where:{$0.id == client.id}){file.collections[index]=client}else{file.collections.append(client)}
                file.structure=config;try SimpleCatalogue.validate(file);try library.store.save(library.library,schema:file);library.reload();committed=true;finished?()
            case "saveWork":
                var file=SchemaTrial.read(in:library.store.root)
                let owner=projectID == nil && SchemaTrial.personalMode ? file.structure?.personalCollectionID:(d["client"] as? String).flatMap(UUID.init(uuidString:))
                guard let id=owner,file.collections.contains(where:{$0.id == id}) else{throw failure("Create or choose a client first.")}
                let name=(d["name"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines);try SimpleCatalogue.validateLabel(name)
                var values=d["values"] as? [String:String] ?? [:]
                let fields=try fields(d)
                values["customForm"]=String(data:try JSONEncoder().encode(fields),encoding:.utf8)
                guard (values["dueDate"] ?? "").isEmpty || (values["startDate"] ?? "").isEmpty || values["dueDate"]! >= values["startDate"]! else{throw failure("The deadline must be on or after the start date.")}
                var next=library.library
                let pid:UUID
                if let projectID {guard let p=next.project(projectID),!p.isLocked else{throw failure("This work item is locked or no longer available.")};pid=projectID;_ = next.renameProject(pid,to:name)}else{pid=next.createProject(named:name)}
                next.setProjectDetails(pid,values);file.places[pid.uuidString]=SchemaPlace(collection:id)
                try library.store.save(next,schema:file);library.reload();committed=true;finished?()
            case "savePreset":
                var file=SchemaTrial.read(in:library.store.root);guard var config=file.structure else{return}
                let name=d["name"] as? String ?? "";try SimpleCatalogue.validateLabel(name)
                var list=config.formPresets ?? [];let fields=try fields(d)
                if let index=list.firstIndex(where:{$0.name.caseInsensitiveCompare(name) == .orderedSame}){list[index].fields=fields}else{list.append(WorkFormPreset(id:UUID().uuidString,name:name,fields:fields))}
                config.formPresets=list;file.structure=config;try library.store.save(library.library,schema:file)
                refresh();evaluateJavaScript("status('Form preset saved. No answers were included.')",completionHandler:nil)
            default:break
            }
        }catch{let text=(try? JSONSerialization.data(withJSONObject:[error.localizedDescription])).flatMap{String(data:$0,encoding:.utf8)} ?? "[]";evaluateJavaScript("status((\(text))[0])",completionHandler:nil)}
    }
    private func fields(_ d:[String:Any])throws->[WorkFormField]{
        let data=try JSONSerialization.data(withJSONObject:d["fields"] ?? [])
        let fields=try JSONDecoder().decode([WorkFormField].self,from:data)
        guard fields.count<=100,Set(fields.map(\.id)).count==fields.count,fields.allSatisfy({!$0.label.trimmingCharacters(in:.whitespaces).isEmpty && ["Text","Long Text","Number","Date","Checkbox","URL","Email"].contains($0.type)}) else{throw failure("Give each field a name and a supported type.")}
        return fields
    }
    private static let document = #"""
<!doctype html><html><head><meta charset="utf-8"><style>[hidden]{display:none!important}
:root{color-scheme:light;--bg:#f8f7f4;--ink:#171717;--quiet:#666;--rule:#ccc;--blue:#53a1e9}*{box-sizing:border-box}body{margin:0;padding:0;background:var(--bg);color:var(--ink);font:13px 'Helvetica Neue',sans-serif}body.dark{color-scheme:dark;--bg:#242424;--ink:#f5f5f5;--quiet:#bdbdbd;--rule:#666}body.page{padding:28px}body.directory{padding:22px 28px;--bg:#242424}body.directory #app{max-width:760px;margin:0 auto}body.directory header{justify-content:flex-start;gap:32px}body.directory h1{font-size:13px;font-weight:600;margin:0}body.directory h2{font-size:13px;font-weight:600;margin:24px 0 12px}body.directory .row{grid-template-columns:minmax(160px,320px) max-content max-content;gap:24px;padding:8px 0}body.directory p{max-width:580px}body.directory .actions{margin-top:12px}body.directory summary{margin-top:24px}select{appearance:none;border-radius:4px;padding-right:44px;background-image:linear-gradient(45deg,transparent 50%,var(--ink) 50%),linear-gradient(135deg,var(--ink) 50%,transparent 50%),linear-gradient(var(--rule),var(--rule));background-position:calc(100% - 18px) 50%,calc(100% - 14px) 50%,calc(100% - 36px) 0;background-size:4px 4px,4px 4px,1px 100%;background-repeat:no-repeat}::-webkit-scrollbar{width:8px}::-webkit-scrollbar-thumb{background:#f4be00;border-radius:4px}h1{font-size:20px;font-weight:500;margin:0 0 24px}h2{font-size:17px;margin:28px 0 14px}p{line-height:1.5;color:var(--quiet)}button{font:inherit;color:inherit;cursor:pointer;background:none;border:0;padding:8px 0;text-align:left}button:hover{text-decoration:underline;text-underline-offset:5px}button:focus-visible{outline:2px solid var(--blue);outline-offset:3px}button:disabled{opacity:.45;cursor:default}label{display:block;margin:16px 0 7px;color:var(--quiet)}input,textarea,select{font:inherit;color:var(--ink);background:var(--bg);border:1px solid var(--rule);padding:9px;width:100%;border-radius:0}input:not([type=checkbox]),textarea{border:0;border-bottom:1px solid var(--rule);padding:9px 0}input[type=checkbox]{width:auto;accent-color:#f4be00}textarea{min-height:80px;resize:vertical}input[type=date]{min-height:34px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:20px}.actions{display:flex;gap:36px;margin-top:24px}.primary{font-weight:500}.row{display:grid;grid-template-columns:minmax(120px,1fr) 130px 110px;gap:20px;align-items:baseline;padding:12px 0}.child{padding-left:26px}.fields{margin:20px 0}.field{padding:12px 0;border-bottom:1px solid var(--rule)}.fieldtools{display:grid;grid-template-columns:1fr 150px 30px 30px 50px;gap:10px;align-items:end}.hint{color:var(--quiet)}#status{color:var(--ink);white-space:pre-wrap;margin-top:16px}.check{margin:28px 0;padding:0;list-style:none}.check li{margin:20px 0;font-size:17px}.check p{font-size:13px;margin:4px 0}.types{display:grid;grid-template-columns:1fr 1fr;gap:8px}.types label{margin:0}.types input{margin-right:8px}.type-groups{max-height:244px;overflow-y:auto;overscroll-behavior:contain;border-top:1px solid var(--rule);border-bottom:1px solid var(--rule);scrollbar-color:#f4be00 transparent;scrollbar-width:thin}.type-family{border-bottom:1px solid var(--rule)}.type-family:last-child{border:0}.type-family-title{margin:0;padding:10px 6px;display:flex;justify-content:space-between;font-weight:600}.type-family-title span{font-weight:400;color:var(--quiet)}.type-family .types{padding:0 10px 14px;column-gap:12px}.type-family label{color:var(--ink);line-height:21px;cursor:pointer}summary{cursor:pointer;margin:18px 0}a{color:inherit}header{display:flex;gap:20px;justify-content:space-between;align-items:baseline}.empty{margin:20px 0}
</style></head><body><main id="app"></main><div id="status" role="status"></div><script>
let data, draft, fields=[],values={},stage=0;
const $=id=>document.getElementById(id), esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function newID(){return crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)}
function send(action,rest={}){window.webkit.messageHandlers.journey.postMessage({action,...rest})}function status(t){$('status').textContent=t}
function load(d){data=d;document.body.classList.toggle('dark',d.dark);document.body.classList.toggle('directory',d.mode==='directory');document.body.classList.toggle('page',d.mode==='welcome'||d.mode==='directory');if(['welcome','directory'].includes(d.mode)){render();return}if(draft){if($('preset'))$('preset').innerHTML='<option value="">Choose a Preset</option>'+(d.presets||[]).map(p=>`<option value="${p.id}">${esc(p.name)}</option>`).join('');return;}let c=d.clients.find(x=>x.id===d.clientID);let p=c?.projects.find(x=>x.id===d.projectID);draft={name:(d.mode==='client'?c?.name:p?.name)||'',word:c?.word||d.workWord,profile:c?.profile||{},assets:c?.assets||d.assets,client:c?.id||(d.personal?d.personalID:d.clients[0]?.id)||''};values={...(p?.details||{})};try{fields=JSON.parse(values.customForm||'[]')}catch{fields=[]}render()}
function groupedTypes(attribute,chosen){const visible=data.types.filter(t=>t.selectable||chosen.includes(t.id));const families=[...new Set([...visible.map(t=>t.family),...(data.customAssetFamilies||[])])];return `<div class="type-groups" role="group" aria-label="Asset categories">${families.map(family=>{const options=visible.filter(t=>t.family===family);const count=options.filter(t=>chosen.includes(t.id)).length;return `<section class="type-family"><div class="type-family-title">${esc(family)}<span>${count?count+' selected':''}</span></div><div class="types">${options.map(t=>`<label><input type="checkbox" data-${attribute}="${t.id}" ${chosen.includes(t.id)?'checked':''}>${esc(t.name)}</label>`).join('')}</div></section>`}).join('')}</div>`}
function btn(text,action){return `<button type="button" onclick="${action}">${esc(text)}</button>`}function field(label,id,value='',type='text'){return `<div class="input-field"><label for="${id}">${esc(label)}</label><input id="${id}" type="${type}" value="${esc(value)}"></div>`}
function render(){status('');const d=data,c=d.clients.find(x=>x.id===draft?.client);let html='';
if(d.personal&&d.mode==='welcome'){let total=d.clients.reduce((n,c)=>n+c.projects.length,0);html=`<h1>Welcome to Colorgain</h1><p>Organise your own work and assets here. You can enable ${esc(d.clientWord)} organisation later in Settings → Catalogue Structure.</p><ol class="check"><li>${btn('Add your '+d.workWord,"send('openWork',{client:data.personalID})")}<p>Add a name, description, dates and your own metadata fields.</p></li><li>Add your assets<p>My Library is available alongside your work.</p></li></ol>${total?btn('Open Catalogue',"send('browse')"):''}`}
else if(d.personal&&d.mode==='directory'){html=`<header><h1>Catalogue Structure</h1>${btn('＋ Add '+d.workWord,"send('openWork',{client:data.personalID})")}</header><p>Organise your own work here.</p>`;for(const c of d.clients)for(const p of c.projects)html+=`<div class="row"><span>${esc(p.name)}</span>${btn('Edit '+c.word,`send('openWork',{client:'${c.id}',id:'${p.id}'})`)}<span></span></div>`}
else if(d.mode==='welcome'){let total=d.clients.reduce((n,c)=>n+c.projects.length,0);html=`<h1>Welcome to Colorgain</h1><p>Build your catalogue around the people you work for and the work you do.</p><ol class="check"><li>${d.clients.length?'✓':'1.'} ${btn(d.clients.length?'Add another '+d.clientWord:'Add your first '+d.clientWord,"send('openClient')")}<p>Save their name, then add contact and organisation details when you need them.</p></li><li>${total?'✓':'2.'} <button ${!d.clients.length?'disabled':''} onclick="send('openWork',{client:data.clients[0]?.id})">${total?'Add another':'Add your first'} ${esc(d.workWord)}</button><p>${!d.clients.length?'Create a '+esc(d.clientWord)+' first.':'Add a description, dates and any additional fields your work needs.'}</p></li><li>${total?'3.':'3.'} Add your assets<p>Your selected asset categories are ready under each work item and in My Library.</p></li></ol>${total?btn('Open Catalogue',"send('browse')"):""}`}
else if(d.mode==='directory'){html=`<header><h1>Catalogue Structure</h1>${btn('＋ Add '+d.clientWord,"send('openClient')")}</header>`;if(!d.clients.length)html+=`<p class="empty">You can’t add a ${esc(d.workWord)} until you add a ${esc(d.clientWord)}.</p>${btn('＋ Create '+d.clientWord,"send('openClient')")}`;for(const c of d.clients){html+=`<div class="row"><strong>${esc(c.name)}</strong>${btn('Edit '+d.clientWord,`send('openClient',{id:'${c.id}'})`)}${btn('＋ '+c.word,`send('openWork',{client:'${c.id}'})`)}</div>`;if(!c.projects.length)html+=`<p class="child">No ${esc(c.word)} yet. ${btn('Create '+c.word,`send('openWork',{client:'${c.id}'})`)}</p>`;for(const p of c.projects)html+=`<div class="row child"><span>└ ${esc(p.name)}</span>${btn('Edit '+c.word,`send('openWork',{client:'${c.id}',id:'${p.id}'})`)}<span></span></div>`}html+=`<p>Each ${esc(d.clientWord)} can use its own work terminology and asset categories.</p>`}
if(d.mode==='directory'){html+=`<details><summary>Catalogue Defaults & My Library</summary><p>Defaults apply to new work structures. Existing clients keep their own choices.</p>${field('Client / Customer Name','defaultClient',d.clientWord)}${field('Work Name — Project, Product, Campaign or your own','defaultWork',d.workWord)}<h2>Catalogue Asset Categories</h2>${groupedTypes('default-asset',d.assets)}<h2>My Library Categories</h2>${groupedTypes('library-asset',d.libraryAssets)}${btn('Save Defaults',"send('saveDefaults',{clientWord:$('defaultClient').value,workWord:$('defaultWork').value,assets:[...document.querySelectorAll('[data-default-asset]:checked')].map(x=>x.dataset.defaultAsset),libraryAssets:[...document.querySelectorAll('[data-library-asset]:checked')].map(x=>x.dataset.libraryAsset)})")}</details><h2>My Library</h2><p>Import or export your library together with its assets.</p><div class="actions">${btn('Import Library…',"send('importLibrary')")}${btn('Export Library…',"send('exportLibrary')")}</div>`}
else if(d.mode==='client'){html=`<h1>${data.clientID?'Edit':'New'} ${esc(d.clientWord)}</h1>`;if(stage===0){html+=field(d.clientWord+' Name','name',draft.name)+`<details ${Object.values(draft.profile).some(Boolean)?'open':''}><summary>Add additional information</summary><div class="columns">`+d.profileFields.map(f=>field(f.name,'profile-'+f.id,draft.profile[f.id]||'')).join('')+`</div></details><div class="actions">${btn('Continue to Work Structure',"capture();stage=1;render()")}${btn('Cancel',"send('cancel')")}</div>`}else{html+=`<p>Choose how ${esc(draft.name||'this '+d.clientWord)} organises work.</p><label>Work Type</label><select id="word" onchange="$('customWord').hidden=this.value!=='Custom'">`+['Project','Product','Campaign','Work Order','Custom'].map(v=>`<option ${v===(['Project','Product','Campaign','Work Order'].includes(draft.word)?draft.word:'Custom')?'selected':''}>${v}</option>`).join('')+`</select><input id="customWord" aria-label="Custom Work Type" value="${esc(draft.word)}" ${['Project','Product','Campaign','Work Order'].includes(draft.word)?'hidden':''}><h2>Asset Categories</h2>${groupedTypes('asset',draft.assets)}<div class="actions">${btn('↗ Save '+d.clientWord,"saveClient()")}${btn('Back',"capture();stage=0;render()")}${btn('Cancel',"send('cancel')")}</div>`}}
else if(d.mode==='work'){let word=c?.word||d.workWord;html=`<h1>${d.projectID?'Edit':'New'} ${esc(word)}</h1>`;if(!d.clients.length){html+=`<p>Create a ${esc(d.clientWord)} first.</p>${btn('Cancel',"send('cancel')")}`}else{html+=`<label>${esc(d.clientWord)}</label><select id="client" onchange="capture();render()">`+d.clients.map(c=>`<option value="${c.id}" ${c.id===draft.client?'selected':''}>${esc(c.name)}</option>`).join('')+'</select>'+field(word+' Name','name',draft.name)+`<label for="description">Description</label><textarea id="description">${esc(values.description||'')}</textarea><div class="columns">${field('Start Date','startDate',values.startDate||'','date')}${field('Deadline','dueDate',values.dueDate||'','date')}</div><details ${fields.length?'open':''}><summary>Add additional details</summary><p>Build a form for this ${esc(word)}. Saved presets contain labels, field types and their order, with no answers.</p><label>Form Preset</label><select id="preset"><option value="">Choose a Preset</option>`+(d.presets||[]).map(p=>`<option value="${p.id}">${esc(p.name)}</option>`).join('')+`</select>${btn('Apply Preset',"applyPreset()")}${field('Preset Name','presetName')} ${btn('Save Form as Preset',"capture();send('savePreset',{name:$('presetName').value,fields})")}<div class="fields">`+fields.map((f,i)=>`<div class="field"><div class="fieldtools">${field('Field Name','label-'+i,f.label)}<div><label>Field Type</label><select id="type-${i}" onchange="capture();render()">`+['Text','Long Text','Number','Date','Checkbox','URL','Email'].map(t=>`<option ${t===f.type?'selected':''}>${t}</option>`).join('')+`</select></div>${btn('↑',`move(${i},-1)`)}${btn('↓',`move(${i},1)`)}${btn('Remove',`capture();fields.splice(${i},1);render()`)}</div><label>Value</label>`+valueInput(f,i)+`</div>`).join('')+`</div>${btn('＋ Add Field',"capture();fields.push({id:newID(),label:'New Field',type:'Text'});render()")}</details><div class="actions">${btn('↗ Save '+word,"saveWork()")}${btn('Cancel',"send('cancel')")}</div>`}}
if(['welcome','directory'].includes(d.mode)){let control=`<label><input type="checkbox" ${d.personal?'checked':''} onchange="send('setPersonal',{enabled:this.checked})"> I don’t have clients — this is for me</label><p>${d.mode==='directory'?'You can change this at any time. Existing work is retained.':'You can enable '+esc(d.clientWord)+' organisation later in Settings → Catalogue Structure.'}</p>`;html=d.mode==='directory'?html.replace('</header>','</header>'+control):html.replace('</p>','</p>'+control)}
$('app').innerHTML=html;if(d.personal&&d.mode==='work'){let selector=$('client');if(selector){selector.previousElementSibling.hidden=true;selector.hidden=true}}}
function valueInput(f,i){let v=values['custom.'+f.id]||'';if(f.type==='Long Text')return `<textarea id="value-${i}">${esc(v)}</textarea>`;if(f.type==='Checkbox')return `<input id="value-${i}" type="checkbox" ${v==='true'?'checked':''} aria-label="${esc(f.label)}">`;return `<input id="value-${i}" type="${({Number:'number',Date:'date',URL:'url',Email:'email'})[f.type]||'text'}" value="${esc(v)}" aria-label="${esc(f.label)}">`}
function capture(){if($('name'))draft.name=$('name').value;if(data.mode==='client'){for(const f of data.profileFields)if($('profile-'+f.id))draft.profile[f.id]=$('profile-'+f.id).value;if($('word')){draft.word=$('word').value==='Custom'?$('customWord').value:$('word').value;draft.assets=[...document.querySelectorAll('[data-asset]:checked')].map(x=>x.dataset.asset)}}else{if($('client'))draft.client=$('client').value;for(const id of ['description','startDate','dueDate'])if($(id))values[id]=$(id).value;fields.forEach((f,i)=>{const v=$('value-'+i);if(v)values['custom.'+f.id]=v.type==='checkbox'?String(v.checked):v.value;if($('label-'+i))f.label=$('label-'+i).value;if($('type-'+i))f.type=$('type-'+i).value})}}
function saveClient(){capture();send('saveClient',draft)}function saveWork(){capture();send('saveWork',{...draft,values,fields})}function move(i,n){capture();if(i+n<0||i+n>=fields.length)return;[fields[i],fields[i+n]]=[fields[i+n],fields[i]];render()}function applyPreset(){capture();let p=data.presets.find(x=>x.id===$('preset').value);if(!p)return;fields=p.fields.map(f=>({...f,id:newID()}));render()}
document.addEventListener('change',event=>{if(!event.target.matches('.type-family input[type="checkbox"]'))return;const family=event.target.closest('.type-family');const count=family.querySelectorAll('input:checked').length;family.querySelector('.type-family-title span').textContent=count?count+' selected':''});
</script></body></html>
"""#
}
private final class JourneyMessageBridge:NSObject,WKScriptMessageHandler {
    weak var owner:CatalogueJourneyView?
    init(_ owner:CatalogueJourneyView){self.owner=owner}
    func userContentController(_ controller:WKUserContentController,didReceive message:WKScriptMessage){owner?.userContentController(controller,didReceive:message)}
}

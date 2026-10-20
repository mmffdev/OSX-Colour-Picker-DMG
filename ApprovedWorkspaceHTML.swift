import Foundation

/// Workspace recovery uses the approved setup shell, logo, grid and action anchors.
enum ApprovedWorkspaceHTML {
    static var document:String {
        let shell=String(ApprovedSetupHTML.document.components(separatedBy:"<script>")[0])
        return shell + #"""
<style>
.recovery-options{display:flex;flex-direction:column;gap:20px;margin-top:24px}.recovery-options button{font-size:17px;text-align:left;padding:0}.recovery-picker{position:relative;border:1px solid var(--rule);border-radius:4px;font-size:17px}.recovery-picker summary{padding:12px;cursor:pointer}.recovery-picker .menu{position:absolute;left:0;right:0;z-index:10;background:var(--paper);border:1px solid var(--rule);max-height:190px;overflow:auto}.recovery-picker .menu button{display:block;width:100%;padding:10px;text-align:left}.recovery-picker .menu button:hover{background:var(--rule)}.recovery-path{overflow-wrap:anywhere;font-size:16px;line-height:24px;margin:0 0 24px}.right .demo-title{font-size:34px;line-height:40px;font-weight:600;letter-spacing:-.8px;color:var(--muted);margin:0}.right .recovery-body{position:absolute;top:102px;left:0;right:0}.recovery-error{color:var(--ink);font-size:14px;line-height:20px;margin-top:20px}.recovery-options button:hover{text-decoration:underline;text-underline-offset:5px}
</style><script>
const $=s=>document.querySelector(s),esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function send(action,extra={}){window.webkit.messageHandlers.setup.postMessage({action,name:$('#recoveryName')?.value,...extra})}
function action(label,key){return `<button class="action" onclick="send('${key}')"><svg class="arrow" viewBox="0 0 24 20" aria-hidden="true"><path d="M0 7h13L7 1h7l10 9-10 9H7l6-6H0z"/></svg><span class="label">${esc(label)}</span></button>`}
window.restoreRecovery=function(d){
if(d.stage==='create'&&$('#recoveryName'))d.name=$('#recoveryName').value;
const title=d.stage==='workspace'?'Open your workspace':d.stage==='catalogues'?'Choose a catalogue':'Name your catalogue';
const description=d.stage==='workspace'?'Open an existing workspace to continue where you left off, or start a new workspace.':d.stage==='catalogues'?'Choose the catalogue you want to open. You can also locate another catalogue or create a new one.':'Give your catalogue a name. Next, you’ll choose how to organise your work and which assets to use.';
let form='',primary='';
if(d.stage==='workspace'){primary=action('Open a Workspace','openData')+action('Start a New Workspace','newData')}
else if(d.stage==='catalogues'){form=`<details class="recovery-picker"><summary>${esc(d.options[d.selected]||'Choose Catalogue')}</summary><div class="menu">${d.options.map((v,i)=>`<button onclick="send('select',{index:${i}})">${esc(v)}</button>`).join('')}</div></details><div class="recovery-options">${action('Locate Catalogue…','locate')}${action('Create Catalogue…','create')}${action('Choose Another Workspace…','switchData')}</div>`;primary=action(d.openTitle,'openCat')}
else{form=`<label class="field"><span>Catalogue Name</span><input id="recoveryName" value="${esc(d.name)}"></label><div class="recovery-options">${action('Locate Catalogue…','locate')}${action('Choose Another Workspace…','switchData')}</div>`;primary=action('Continue to Catalogue Setup','build')}
$('#screen').innerHTML=`<h1 class="heading">${title}</h1><div class="description"><p>${description}</p></div><div class="form">${form}<p class="recovery-error" role="status">${esc(d.error)}</p></div><div class="actions">${primary}${action('Cancel','cancel')}</div><aside class="right"><h2 class="demo-title">Your Workspace</h2><div class="recovery-body"><p class="caption">Workspace</p><p class="recovery-path">${esc(d.root)}</p>${d.folder?`<p class="caption">Catalogue</p><p class="recovery-path">${esc(d.folder)}</p>`:''}<p class="caption">${esc(d.issue||'')}</p></div></aside>`;
if(!d.canOpen&&d.stage==='catalogues')document.querySelector('[onclick="send(\'openCat\')"]').disabled=true;
fit();};
function fit(){const scale=Math.min(innerWidth/1440,innerHeight/875);$('#stage').style.transform=`scale(${scale})`;$('.viewport').style.width=1440*scale+'px';$('.viewport').style.height=875*scale+'px'}
addEventListener('resize',fit);fit();
</script>
"""# + SetupAppearanceHTML.script + "</body></html>"
    }
}

enum SetupAppearanceHTML {
    static let script = #"""
<style>body.setup-dark .brand{filter:invert(1)}body.setup-dark button:hover{color:var(--yellow)}.heading,.choice[aria-pressed=true]{color:var(--ink)}.field input:focus{border-color:var(--ink)}.tree .labelbar{background:var(--rule)}</style>
<script>
window.setSetupAppearance=function(p){let dark=['grey','charcoal','black'].includes(p.id);document.body.classList.toggle('setup-dark',dark);let s=document.documentElement.style;s.setProperty('--paper',p.hex);s.setProperty('--ink',dark?'#ffffff':'#111111');s.setProperty('--muted',dark?'#d1d1d1':'#66645f');s.setProperty('--rule',dark?'#555555':'#c9c6bf')};
document.addEventListener('keydown',e=>{if(e.key.toLowerCase()==='l'&&!e.metaKey&&!e.ctrlKey&&!e.altKey&&!e.repeat&&!e.target.closest('input,textarea,select,[contenteditable=true]')){e.preventDefault();e.stopImmediatePropagation();window.webkit.messageHandlers.setup.postMessage({action:'cycleAppearance'})}},true);
</script>
"""#
    static var document:String {ApprovedSetupHTML.document.replacingOccurrences(of:"</body></html>",with:script+"</body></html>")}
    static func payload(index:Int?=nil)->String {let p=index.map{AppearancePresets.all[$0]} ?? AppearancePresets.selected;let data=try! JSONSerialization.data(withJSONObject:["id":p.id,"hex":p.hex]);return String(data:data,encoding:.utf8)!}
}

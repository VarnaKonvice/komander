(()=>{'use strict';
const openButton=document.getElementById('spaDirectoryOpen');
const overlay=document.getElementById('spaDirectoryOverlay');
if(!openButton||!overlay)return;
const closeButton=document.getElementById('spaDirectoryClose');
const search=document.getElementById('spaDirectorySearch');
const place=document.getElementById('spaDirectoryPlace');
const results=document.getElementById('spaDirectoryResults');
const count=document.getElementById('spaDirectoryCount');
const loadMore=document.getElementById('spaDirectoryMore');
const summary=document.getElementById('spaDirectorySummary');
const tabs=[...overlay.querySelectorAll('[data-spa-dir-tab]')];
let catalog=null,mode='facilities',shown=0,lastFocus=null,visible=[];
const PER_PAGE=28;
const normalize=s=>String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('cs').replace(/\s+/g,' ').trim();
const safeUrl=address=>{try{const u=new URL(address);return u.protocol==='https:'?u.href:null}catch(_){return null}};
const E=(tag,className,txt)=>{const node=document.createElement(tag);if(className)node.className=className;if(txt!==undefined)node.textContent=txt;return node};
const addLink=(parent,text,url)=>{
 const safe=safeUrl(url);
 if(!safe)return;
 const a=E('a','spa-dir-link',text+' ↗');a.href=safe;a.target='_blank';a.rel='noopener noreferrer';parent.append(a);
};
function setError(msg){
 results.replaceChildren(E('div','spa-dir-state',msg));
 summary.textContent='Katalog se nepodařilo načíst.';
 count.textContent='';
 loadMore.hidden=true;
}
async function loadCatalog(){
 if(catalog)return true;
 summary.textContent='Načítám ověřené veřejné podklady…';
 try {
  const r=await fetch('/spa-directory.json',{cache:'no-cache'});
  if(!r.ok)throw Error('HTTP '+r.status);
  const x=await r.json();
  if(!x||x.releaseStatus!=='research_not_release_ready'||x.facilities?.length!==241||x.providers?.length!==97||x.candidates?.length!==21)throw Error('Neočekávaná verze dat');
  catalog=x;
  const names=[...new Set([...x.facilities,...x.candidates].map(f=>f.location))].sort((a,b)=>a.localeCompare(b,'cs'));
  place.replaceChildren(new Option('Všechny lázeňské lokality',''));
  names.forEach(t=>place.add(new Option(t,t)));
  return true;
 }catch(e){setError('Data nelze načíst. Zkontrolujte připojení. '+e.message);return false}
}
function setMode(next){
 mode=next;shown=0;
 tabs.forEach(b=>{const active=b.dataset.spaDirTab===mode;b.setAttribute('aria-selected',String(active));b.classList.toggle('is-active',active)});
 filter();
}
function filter(){
 if(!catalog)return;
 const q=normalize(search.value);const town=place.value;
 let list=mode==='facilities'?catalog.facilities:mode==='candidates'?catalog.candidates:catalog.providers.filter(p=>mode==='mz'?p.mzListed:!p.mzListed);
 visible=list.filter(f=>{
  if(town){
   if(mode==='facilities'||mode==='candidates'){if(f.location!==town)return false}
   else if(!f.locations.includes(town))return false;
  }
  if(!q)return true;
  return normalize(mode==='facilities'?[f.name,...(f.aliases||[]),f.location,f.providerName,f.providerIco,f.address].join(' '):mode==='candidates'?[f.name,f.location,f.reason].join(' '):[f.name,f.ico,f.locations.join(' '),f.nameMZ].join(' ')).includes(q);
 }).sort((a,b)=>(mode==='facilities'||mode==='candidates')?(a.location.localeCompare(b.location,'cs')||a.name.localeCompare(b.name,'cs')):a.name.localeCompare(b.name,'cs'));
 results.replaceChildren();
 shown=0;
 appendMore();
}
function addDetail(target,title,value){
 const field=E('div','spa-dir-meta');
 field.append(E('span','spa-dir-meta-label',title),E('span','spa-dir-meta-value',value));
 target.append(field);
}
function facilityCard(f){
 const a=E('article','spa-dir-card');const title=E('h3',null,f.name);a.append(title);
 a.append(E('p','spa-dir-card-location',f.location));
 addDetail(a,'Poskytovatel',f.providerName+(f.providerIco?' · IČO '+f.providerIco:''));
 if(f.providerMatchStatus==='inferred')a.append(E('p','spa-dir-warning','Vazbu na provozovatele je ještě potřeba potvrdit.'));
 addDetail(a,'Adresa',f.addressStatus==='verified_official'&&f.address?f.address:', přesná adresa zatím neověřena'.slice(2));
 const actions=E('div','spa-dir-actions');
 addLink(actions,'Oficiální web',f.website);
 if(f.source&&f.source!==f.website)addLink(actions,'Zdroj údajů',f.source);
 if(f.crmParent){
  const btn=E('button','spa-dir-parent','Otevřít lázeňské místo v CRM');
  btn.type='button';btn.addEventListener('click',()=>{
   const x=typeof data!=='undefined'?data.find(v=>v.name===f.crmParent):null;
   if(!x||typeof openDrawer!=='function')return;
   close();
   openDrawer(x.id);
  });
  actions.append(btn);
 }
 a.append(actions);
 return a;
}
function providerCard(f){
 const a=E('article','spa-dir-card');
 a.append(E('h3',null,f.name));
 if(f.nameMZ&&f.nameMZ!==f.name)a.append(E('p','spa-dir-card-location','Název v registru MZ: '+f.nameMZ));
 addDetail(a,'IČO',f.ico||'neuvedeno');
 addDetail(a,'Lázeňská místa',f.locations.length?f.locations.join(', '):'nelze jednoznačně přiřadit');
 const status=f.mzListed?'Uveden v seznamu MZ (aktualizace 11. 12. 2025)':'Doplňkový výzkumný záznam; ne v seznamu MZ';
 a.append(E('p','spa-dir-status-note',status));
 const actions=E('div','spa-dir-actions');
 addLink(actions,'Web poskytovatele',f.website);
 if(f.source&&f.source!==f.website)addLink(actions,'Zdroj',f.source);
 a.append(actions);
 return a;
}
function candidateCard(f){
 const a=E('article','spa-dir-card spa-dir-candidate');
 a.append(E('h3',null,f.name));
 a.append(E('p','spa-dir-card-location',f.location));
 a.append(E('p','spa-dir-warning','Rozpis pro samostatné používání pacientem zatím není doložen.'));
 a.append(E('p','spa-dir-status-note',f.reason));
 const actions=E('div','spa-dir-actions');
 addLink(actions,'Informace zařízení',f.source);
 a.append(actions);
 return a;
}
function appendMore(){
 const end=Math.min(visible.length,shown+PER_PAGE);
 const fragment=document.createDocumentFragment();
 for(let i=shown;i<end;i++)fragment.append(mode==='facilities'?facilityCard(visible[i]):mode==='candidates'?candidateCard(visible[i]):providerCard(visible[i]));
 results.append(fragment);shown=end;
 const mx=mode==='facilities'?catalog.stats.identifiedFacilities:mode==='candidates'?catalog.stats.schedulePendingRehab:mode==='mz'?catalog.stats.mzRegisteredProviders:catalog.stats.otherResearchProviders;
 count.textContent='Zobrazeno '+shown+' z '+visible.length+' vyfiltrovaných · katalog celkem '+mx;
 loadMore.hidden=shown>=visible.length;
 if(!visible.length)results.append(E('p','spa-dir-state','Tomuto hledání neodpovídá žádný záznam.'));
 const x=catalog.stats;
 summary.textContent=mode==='candidates'?'Těchto 11 zařízení není přidáno na mapu. Podmínkou je potvrzení, že pacient dostává a samostatně používá vlastní časový rozpis procedur.':'Zdroj: veřejný výzkum 14. 11. 2026 a seznam MZ aktualizovaný 11. 12. 2025. '+x.facilitiesWithoutVerifiedAddress+' zařízení nemá doloženou přesnou adresu; '+x.inferredProviderLinks+' vazeb na poskytovatele vyžaduje potvrzení.';
}
async function open(){
 if(typeof closePop==='function')closePop();
 lastFocus=document.activeElement;
 overlay.hidden=false;document.body.classList.add('spa-dir-dialog-open');
 search.value='';place.value='';mode='facilities';shown=0;
 tabs.forEach(b=>{const active=b.dataset.spaDirTab===mode;b.setAttribute('aria-selected',String(active));b.classList.toggle('is-active',active)});
 results.replaceChildren(E('div','spa-dir-state','Načítám údaje…'));
 openButton.setAttribute('aria-expanded','true');
 closeButton.focus();
 if(await loadCatalog())filter();
}
function close(){
 overlay.hidden=true;
 document.body.classList.remove('spa-dir-dialog-open');
 openButton.setAttribute('aria-expanded','false');
 if(lastFocus&&typeof lastFocus.focus==='function')lastFocus.focus();
}
openButton.addEventListener('click',open);
closeButton.addEventListener('click',close);
overlay.addEventListener('click',e=>{if(e.target===overlay)close()});
overlay.addEventListener('keydown',e=>{
 if(e.key==='Escape'){e.stopPropagation();close()}
 if(e.key==='Tab'){
  const all=[...overlay.querySelectorAll('button:not(:disabled):not([hidden]),input:not(:disabled),select:not(:disabled),a[href]')].filter(x=>x.getClientRects().length);
  if(!all.length)return;
  const first=all[0],last=all[all.length-1];
  if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}
  else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}
 }
});
tabs.forEach(b=>b.addEventListener('click',()=>setMode(b.dataset.spaDirTab)));
search.addEventListener('input',filter);
place.addEventListener('change',filter);
loadMore.addEventListener('click',appendMore);
})();
const fs=require('node:fs'),assert=require('node:assert/strict'),path=require('node:path');
const root=__dirname,site=path.join(root,'site'),app=path.join(root,'app');
const j=JSON.parse(fs.readFileSync(path.join(site,'spa-directory.json'),'utf8'));
assert.equal(j.releaseStatus,'research_not_release_ready');
assert.equal(j.stats.existingCrmLocations,41);
assert.equal(j.facilities.length,241);
assert.equal(j.providers.length,97);
assert.equal(j.providers.filter(x=>x.mzListed).length,89);
assert.equal(j.providers.filter(x=>!x.mzListed).length,8);
assert.equal(j.stats.facilitiesWithoutVerifiedAddress,j.facilities.filter(x=>x.addressStatus!=='verified_official').length);
assert.equal(j.stats.inferredProviderLinks,j.facilities.filter(x=>x.providerMatchStatus==='inferred').length);
assert.equal(j.stats.facilitiesWithoutVerifiedAddress,194);
assert.equal(j.stats.inferredProviderLinks,40);
const source=JSON.parse(fs.readFileSync(path.join(site,'crm-data.json'),'utf8'));
assert.equal(source.length,36);
const locations=new Set([...source.map(x=>x.name),'Čeladná – rehabilitační centrum','Hamzova léčebna Luže-Košumberk','Rehabilitační ústav Brandýs nad Orlicí','Dětská léčebna Křetín','Dětská léčebna pohybových poruch Boskovice']);
const providerIds=new Set(j.providers.map(x=>x.id));
assert.equal(new Set(j.facilities.map(x=>x.id)).size,241);
assert.equal(providerIds.size,97);
assert.equal(new Set(j.providers.filter(x=>x.mzListed).map(x=>x.ico)).size,89);
for(const f of j.facilities){
 assert.ok(f.name&&f.location&&f.providerName&&f.providerIco&&f.id);
 assert.ok(f.source||f.website);
 assert.ok(locations.has(f.crmParent),'missing location: '+f.crmParent);
 assert.ok(providerIds.has(f.providerId));
 if(f.addressStatus!=='verified_official')assert.equal(f.address,null);
 assert.ok(['verified_official','inferred'].includes(f.providerMatchStatus));
}
assert.equal(j.candidates.length,21);
assert.equal(j.stats.schedulePendingRehab,21);
assert.ok(j.candidates.every(x=>x.scheduleStatus==='to_verify'&&x.source.startsWith('https://')));
for(const ico of ['00183024','00853879']){
 const p=j.providers.find(x=>x.ico===ico);
 const f=j.facilities.find(x=>x.providerIco===ico);
 assert.ok(p&&f);
 assert.ok(!p.mzListed,'rehabilitation provider must not inflate MZ spa registry');
 assert.equal(f.scheduleStatus,'confirmed_patient_copy');
}
const pediatricProvider=j.providers.filter(x=>x.ico==='00386766');
assert.equal(pediatricProvider.length,1,'two pediatric facilities must not duplicate provider');
assert.equal(pediatricProvider[0].locations.length,2);
const pediatric=j.facilities.filter(x=>x.providerIco==='00386766');
assert.equal(pediatric.length,2);
assert.ok(pediatric.every(x=>x.scheduleStatus==='confirmed_patient_copy'&&x.facilitySubtype==='pediatric_with_caregiver'));
assert.equal(j.candidates.length,21);
assert.equal(new Set(j.candidates.map(x=>x.id)).size,21);
for(const town of ['Třebíč','Nové Město na Moravě','Jihlava','Mostiště u Velkého Meziříčí','Pasohlávky','Plzeň – Lochotín']){
 assert.ok(j.candidates.some(x=>x.location===town&&x.scheduleStatus==='to_verify'),town);
}
const celadna=j.facilities.filter(x=>x.location==='Čeladná');
assert.equal(celadna.length,7);
assert.ok(celadna.every(x=>x.providerIco==='25868951'&&x.crmParent==='Čeladná – rehabilitační centrum'));
assert.ok(j.providers.find(x=>x.ico==='25868951'&&!x.mzListed));
const berta=j.facilities.find(x=>x.name==='Lázeňský dům Berta');
assert.ok(berta.aliases.includes('Bertiny lázně'));
const tousen=j.facilities.find(x=>x.name==='Slatinné lázně Toušeň');
assert.equal(tousen.location,'Lázně Toušeň');
const old=fs.readFileSync(path.join(site,'index.html'),'utf8');
assert.ok(old.includes('id="spaDirectoryOpen"'));
assert.ok(old.includes('id="spaDirectoryOverlay"'));
assert.ok(old.includes('href="/apple-touch-icon.png?v=2"'));
assert.ok(!fs.readFileSync(path.join(site,'spa-directory.js'),'utf8').includes('localStorage.setItem'));
for(const f of ['index.html','spa-directory.js','spa-directory.json','spa-directory.css']){
 assert.equal(fs.readFileSync(path.join(site,f),'utf8'),fs.readFileSync(path.join(app,f),'utf8'),f+' mirrors');
}
console.log('PASS: 241 named facilities + 89 MZ providers + 8 research providers; source/status links, original 36 plus Čeladná, alias Berta, Toušeň, no duplicate IDs or changes to existing CRM storage.');

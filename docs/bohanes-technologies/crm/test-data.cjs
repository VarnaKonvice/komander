const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
const root=__dirname,read=p=>fs.readFileSync(path.join(root,p),'utf8');
const html=read('site/index.html'),inline=html.split('<script>\nconst seed=')[1].split('</script>')[0];
function setup(saved){
 const memory=new Map(saved?[['bohanesCRM',JSON.stringify(saved)]]:[]);
 const elements={crmImportFile:{value:'x'}},alerts=[];let downloaded;
 const ctx={window:{},L:{featureGroup:()=>({})},localStorage:{getItem:k=>memory.get(k)||null,setItem:(k,v)=>memory.set(k,v)},document:{getElementById:id=>elements[id]||(elements[id]={}),createElement:()=>({click(){downloaded=this.download}})},location:{reload(){}},confirm:()=>true,alert:x=>alerts.push(x),Blob,URL:{createObjectURL:()=> 'blob:backup',revokeObjectURL(){}},setTimeout:f=>f(),console};
 vm.createContext(ctx);vm.runInContext(read('site/crm-data.js'),ctx);vm.runInContext(read('site/crm-data-tools.js'),ctx);
 vm.runInContext('const seed='+inline.split('const map=')[0],ctx);
 return {ctx,memory,alerts,run:s=>vm.runInContext(s,ctx),download:()=>downloaded};
}
(async()=>{
 for(const file of ['index.html','crm-data-tools.js','crm-data.js','crm-data.json'])assert.equal(read('app/'+file),read('site/'+file),file+' mirrors');
 const a=setup(),fresh=JSON.parse(a.memory.get('bohanesCRM'));
 assert.equal(fresh.length,36);
 assert.equal(fresh.reduce((n,r)=>n+r.contacts.length,0)>=123,true);
 assert.equal(fresh.find(r=>r.name==='Karviná – Darkov').historicalLand,'Slezsko');
 assert.equal(fresh.find(r=>r.name==='Třeboň').photo.includes('katalog_titul_foto'),false,'bad default photograph replaced');
 const ml=fresh[0];assert.notEqual(ml.facilityAddress,ml.registeredAddress);
 const b=setup(fresh);assert.equal(b.memory.get('bohanesCRM'),JSON.stringify(fresh),'reload is idempotent');
 const edited=JSON.parse(JSON.stringify(fresh));edited[0].company='Moje přesnější firma';edited[0].note='Soukromá poznámka';edited[0].status='Jednání';edited[0].contacts[0].phone='+420 123 456 789';delete edited[0].verifiedDataVersion;
 const c=setup(edited);const kept=JSON.parse(c.memory.get('bohanesCRM'))[0];
 assert.equal(kept.company,'Moje přesnější firma');assert.ok(kept.note.startsWith('Soukromá poznámka'));assert.equal(kept.status,'Jednání');assert.equal(kept.contacts[0].phone,'+420 123 456 789');
 a.run('exportCRM()');assert.match(a.download(),/^bohanes-crm-zaloha-/);
 const payload={format:'bohanes-crm',schemaVersion:1,records:fresh};
 a.ctx.payload=JSON.parse(JSON.stringify(payload));
 assert.equal(a.run('validateCRMBackup(payload,data).length'),36);
 const before=a.memory.get('bohanesCRM');
 a.ctx.bad={size:1,text:async()=>JSON.stringify({format:'bohanes-crm',schemaVersion:1,records:[{id:999,name:'Neexistuje'}]})};
 await a.run('importCRM(bad)');assert.equal(a.memory.get('bohanesCRM'),before,'invalid imports atomic');assert.equal(a.alerts.length,1);
 a.ctx.payload.records[0].note='Přeneseno z druhého počítače';a.ctx.payload.records[0].status='Pilot';
 a.ctx.file={size:100,text:async()=>JSON.stringify(a.ctx.payload)};
 await a.run('importCRM(file)');
 assert.equal(JSON.parse(a.memory.get('bohanesCRM'))[0].note,'Přeneseno z druhého počítače');
 assert.equal(JSON.parse(a.memory.get('bohanesCRM'))[0].status,'Pilot');
 a.run('undoCRMImport()');assert.deepEqual(JSON.parse(a.memory.get('bohanesCRM')),JSON.parse(before),'undo restores original state');
 a.ctx.duplicate=[fresh[0],fresh[0]];assert.throws(()=>a.run('validateCRMBackup(duplicate,data)'),/duplicitní/);
 a.ctx.nofunction=[{...fresh[0],contacts:[{name:''}]}];assert.throws(()=>a.run('validateCRMBackup(nofunction,data)'),/jméno/);
// Review every public record and protect a real version-3 upgrade, including manual edits.
const canonical=JSON.parse(read('data/verified-records.json'));
assert.equal(canonical.filter(r=>r.photo&&r.photoSource&&r.photoDescription).length,36);
for(const r of canonical){
 const keys=r.contacts.map(c=>a.run('crmNameKey('+JSON.stringify(c.name)+')'));
 assert.equal(new Set(keys).size,keys.length,'duplicate contact within '+r.name);
 assert.ok(r.facilityAddress&&r.registeredAddress&&r.website&&r.historicalLand);
 assert.ok(r.contacts.every(c=>c.role&&c.note.includes('https://')));
}
const prior=JSON.parse(JSON.stringify(canonical));
// Fixed examples of the deployed version-3 data, independent of the current Git HEAD.
for(const r of prior)delete r.photo;
prior.find(r=>r.name==='Teplice nad Bečvou').facilityAddress='Pilotní cíl Moravan: přesné číslo dosud neověřeno (verze 3).';
prior.find(r=>r.name==='Karviná – Darkov').contacts=prior.find(r=>r.name==='Karviná – Darkov').contacts.filter(c=>c.name!=='Lenka Krótká');
prior.find(r=>r.name==='Karviná – Darkov').contacts[0].role='Člen statutárního orgánu — Lázně Darkov, a.s.';

const upgrading=JSON.parse(JSON.stringify(fresh));
for(const r of upgrading){
 const old=prior.find(x=>x.name===r.name);
 for(const k of ['company','ico','website','phone','email','facilityAddress','registeredAddress','photo','historicalLand','note']){
  if(old[k]===undefined)delete r[k];else r[k]=old[k];
 }
 r.contacts=JSON.parse(JSON.stringify(old.contacts));
 r._verifiedBaseline={...old};r.verifiedDataVersion='2026-11-05.3';
 for(const k of ['photoSource','photoDescription','photoAttribution','photoLicense'])delete r[k];
}
const dr=upgrading.find(r=>r.name==='Karviná – Darkov');
dr.contacts.push({name:'Lenka Krótká',role:'Obchodní ředitelka (stávající údaj, aktuálnost neověřena)',phone:'+420 596 373 301',note:'Stávající kontakt: aktuální funkce a kontaktní údaje nebyly touto veřejnou rešerší potvrzeny.'});
upgrading[0].note='Moje důležitá poznámka';upgrading[0].company='Moje upravená firma';
const migrated=JSON.parse(setup(upgrading).memory.get('bohanesCRM'));
assert.equal(migrated[0].company,'Moje upravená firma');assert.ok(migrated[0].note.startsWith('Moje důležitá poznámka'));
assert.ok(migrated.find(r=>r.name==='Teplice nad Bečvou').facilityAddress.includes('č.p. 63'));
const lenka=migrated.find(r=>r.name==='Karviná – Darkov').contacts.find(c=>c.name==='Lenka Krótká');
assert.equal(lenka.phone,'');assert.equal(lenka.role,'Obchodní ředitelka — Lázně Darkov, a.s.');
for(const row of migrated){const ref=canonical.find(x=>x.name===row.name);assert.equal(row.photo,ref.photo);assert.equal(row.photoSource,ref.photoSource)}
const custom=JSON.parse(JSON.stringify(upgrading));custom[1].photo='https://example.com/my-own-photo.jpg';
const customResult=JSON.parse(setup(custom).memory.get('bohanesCRM'))[1];assert.equal(customResult.photo,custom[1].photo);assert.equal(customResult.photoAttribution,undefined);
new vm.Script('const seed='+inline,'inline application syntax');
console.log('PASS: all 36 photos/sources, 134 sourced contacts, duplicate checks, version-3 upgrade, updated roles, whistleblowing removal, preserved private edits and custom photos.');

 console.log('PASS: 36 records, mirrors, idempotent migration, custom data preservation, photo replacement, export/import, invalid import, undo, duplicates.');
})().catch(e=>{console.error(e);process.exitCode=1});

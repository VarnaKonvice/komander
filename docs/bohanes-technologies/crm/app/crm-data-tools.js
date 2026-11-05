
// Společná veřejná data jsou verzovaná odděleně od místních obchodních úprav.
const VERIFIED_DATA_VERSION='2026-11-05.1';
function crmNameKey(name){return String(name||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\b(prof|paeddr|phdr|judr|mudr|mgr|ing|bc|dr|csc|ph|d|mba|m|b|a|ll|dis)\b/g,'').replace(/[^a-z]/g,'')}
function applyVerifiedRecords(records,verified){
 const fields=['company','ico','website','phone','email','facilityAddress','registeredAddress','photo','historicalLand'];
 for(const row of verified){
  const x=records.find(v=>v.name===row.name);if(!x||x.verifiedDataVersion===VERIFIED_DATA_VERSION)continue;
  const legacy=enrich[x.name]||{},previous=x._verifiedBaseline||{};
  for(const k of fields){
   if(row[k]===undefined)continue;
   if(!x[k]||x[k]===legacy[k]||x[k]===previous[k])x[k]=row[k];
  }
  const marker='\n\n— Ověřené veřejné údaje —\n';
  const base=(x.note||'').split(marker)[0];
  x.note=(!base||base===legacy.note)?row.note:base+marker+row.note;
  x.contacts=Array.isArray(x.contacts)?x.contacts:[];
  for(const c of row.contacts||[]){
   const key=crmNameKey(c.name);let old=x.contacts.find(v=>crmNameKey(v.name)===key);
   if(!old){x.contacts.push({...c});continue}
   const original=(legacy.contacts||[]).find(v=>crmNameKey(v.name)===key);
   if(c.role&&old.role!==c.role){
    if(!old.role||old.role===original?.role)old.role=c.role;
    else if(!old.role.includes(c.role))old.role+='; '+c.role;
   }
   for(const k of ['phone','email'])if(c[k]&&(!old[k]||old[k]===original?.[k]))old[k]=c[k];
   if(c.note&&!(old.note||'').includes(c.note))old.note=[old.note,c.note].filter(Boolean).join('\n');
  }
  for(const c of x.contacts){
   if(!(row.contacts||[]).some(v=>crmNameKey(v.name)===crmNameKey(c.name))&&!(c.note||'').includes('Stávající kontakt')){
    c.note=[c.note,'Stávající kontakt: aktuální funkce a kontaktní údaje nebyly touto veřejnou rešerší potvrzeny.'].filter(Boolean).join('\n');
   }
  }
  // Historický obchodní kontakt nesmí být považován za ověřený jen převzetím ze staré verze.
  if(x.name==='Karviná – Darkov'){
   const c=x.contacts.find(v=>crmNameKey(v.name)===crmNameKey('Lenka Krótká'));
   if(c){if(c.role==='Obchodní ředitelka')c.role+=' (stávající údaj, aktuálnost neověřena)';c.note=[c.note,'Telefon +420 596 373 301 je zveřejněn pro oznamování protiprávního jednání; nejde o ověřený obchodní kontakt. Zdroj: https://www.laznedarkov.cz/kontakt'].filter(Boolean).join('\n')}
  }
  x._verifiedBaseline=Object.fromEntries(fields.filter(k=>row[k]!==undefined).map(k=>[k,row[k]]));
  x.verifiedDataVersion=VERIFIED_DATA_VERSION;
 }
 return records;
}
function validateCRMBackup(value,knownRecords){
 const rows=Array.isArray(value)?value:(value?.format==='bohanes-crm'&&value?.schemaVersion===1?value.records:null);
 if(!Array.isArray(rows)||!rows.length||rows.length>1000)throw new Error('Soubor neobsahuje platnou zálohu CRM.');
 const seen=new Set(),known=new Map(knownRecords.map(x=>[x.id,x.name]));
 const keys=['company','ico','website','phone','email','facilityAddress','registeredAddress','note','status','photo','historicalLand'];
 return rows.map(row=>{
  if(!row||!Number.isInteger(row.id)||seen.has(row.id)||known.get(row.id)!==row.name)throw new Error('Záloha obsahuje neznámý nebo duplicitní záznam.');
  seen.add(row.id);const result={id:row.id,name:row.name};
  for(const k of keys){if(row[k]!==undefined){if(typeof row[k]!=='string'||row[k].length>100000)throw new Error('Neplatný text v záloze.');result[k]=row[k]}}
  if(row.status!==undefined&&!['Nový lead','Nová příležitost','Kontaktováno','Jednání','Nabídka','Pilot','Aktivní zákazník','Odloženo','Ztraceno'].includes(row.status))throw new Error('Neplatný obchodní stav.');
  if(row.contacts!==undefined){
   if(!Array.isArray(row.contacts)||row.contacts.length>500)throw new Error('Neplatný seznam kontaktů.');
   result.contacts=row.contacts.map(c=>{
    if(!c||typeof c.name!=='string'||!c.name.trim())throw new Error('Kontakt nemá jméno.');
    const item={};for(const k of ['name','role','phone','email','note']){if(c[k]!==undefined){if(typeof c[k]!=='string'||c[k].length>100000)throw new Error('Neplatný kontakt.');item[k]=c[k]}}return item;
   });
  }
  return result;
 });
}
function exportCRM(){
 const payload={format:'bohanes-crm',schemaVersion:1,exportedAt:new Date().toISOString(),records:data};
 const url=URL.createObjectURL(new Blob([JSON.stringify(payload,null,2)],{type:'application/json'}));
 const a=document.createElement('a');a.href=url;a.download='bohanes-crm-zaloha-'+new Date().toISOString().slice(0,10)+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
function chooseCRMImport(){document.getElementById('crmImportFile').click()}
async function importCRM(file){
 if(!file)return;
 try{
  if(file.size>5*1024*1024)throw new Error('Záloha je příliš velká (maximum 5 MB).');
  const rows=validateCRMBackup(JSON.parse(await file.text()),data);
  if(!confirm('Načíst zálohu s '+rows.length+' záznamy? U těchto záznamů se nahradí obchodní údaje a kontakty. Poslední import můžeš vrátit v nabídce profilu.'))return;
  localStorage.setItem('bohanesCRM-before-import',JSON.stringify(data));
  for(const row of rows){const x=data.find(v=>v.id===row.id);Object.assign(x,row);if(x.status==='Nový lead')x.status='Nová příležitost'}
  persist();location.reload();
 }catch(e){alert('Zálohu se nepodařilo načíst: '+e.message)}
 finally{document.getElementById('crmImportFile').value=''}
}
function undoCRMImport(){
 const backup=localStorage.getItem('bohanesCRM-before-import');if(!backup){alert('Není k dispozici žádný předchozí import.');return}
 try{
  const rows=validateCRMBackup(JSON.parse(backup),data);
  if(!confirm('Vrátit stav před posledním importem? Současný stav zůstane uložen pro případné vrácení.'))return;
  localStorage.setItem('bohanesCRM-before-import',JSON.stringify(data));
  for(const row of rows){
   const target=data.find(v=>v.id===row.id);
   for(const key of ['company','ico','website','phone','email','facilityAddress','registeredAddress','note','status','photo','historicalLand','contacts'])delete target[key];
   Object.assign(target,row);
  }
  persist();location.reload();
 }catch(e){alert('Předchozí stav se nepodařilo obnovit: '+e.message)}
}

(function(){
  var STORE='lazensky_commander_schedule_v10';
  var stay={appName:'Lázeňský Komandér',spaName:'Slatinné lázně Třeboň',mealShift:'1. směna',leaveBufferMinutes:15,room:'1LDB-A / 133',doctor:'MUDr. Čech',diagnosis:'G112 Mozečková ataxie',doctorOffice:'Ordinace 214 · 2. patro · LDB',stayFrom:'2026-05-22',stayTo:'2026-06-18'};
  var procs=[['Slatinná koupel','LDB-Slatina 1',20],['Klasická masáž částečná','LDB-Slatina 1',20],['Vysokoindukční magnet','LDB-Elektroléčba',20],['Parafínový zábal','LDB-Parafín',20],['IMOOVE','LDB-Fyzioterapie 4',20],['Vířivka dolní končetiny','LDB-Vodoléčba',20],['Ultrazvuk','LDB-Elektroléčba',20],['Fyzioterapie individuální','LDB-Fyzioterapie 3',30],['Skupinové cvičení','Tělocvična',30],['Bazén','LDB-Bazén',30]];
  var patterns=[['08:15','08:45','10:30'],['08:00','09:30','12:00'],['09:00','10:30','12:15'],['08:05','08:40','10:30'],['08:30','10:00','12:10'],['09:15','11:50']];
  function p(n){return String(n).padStart(2,'0')}
  function iso(d){return d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())}
  function D(s){return new Date(s+'T12:00:00')}
  function addD(d,n){var x=new Date(d);x.setHours(12,0,0,0);x.setDate(x.getDate()+n);return x}
  function tAdd(t,m){var q=t.split(':').map(Number),v=q[0]*60+q[1]+m;return p(Math.floor(v/60))+':'+p(v%60)}
  function ev(id,type,date,start,end,title,place){return{id:id,type:type,date:date,start:start,end:end,title:title,place:place}}
  function build(){var start=D(stay.stayFrom),items=[];for(var day=0;day<28;day++){var dd=addD(start,day),date=iso(dd),sun=dd.getDay()===0;if(day===0){items.push(ev('m'+date+'v','meal',date,'17:00','17:45','Večeře','Jídelna'));continue}items.push(ev('m'+date+'s','meal',date,'07:00','07:45','Snídaně','Jídelna'));if(date==='2026-05-24'){items.push(ev('p'+date+'test','procedure',date,'09:30','09:50','Test procedura','Testovací místnost'))}else if(!sun){var pat=day===1?['08:15','08:45','10:30']:patterns[day%patterns.length];pat.forEach(function(t,i){var pr=procs[(day*2+i)%procs.length];items.push(ev('p'+date+i,'procedure',date,t,tAdd(t,pr[2]),pr[0],pr[1]))})}items.push(ev('m'+date+'o','meal',date,'11:00','11:45','Oběd','Jídelna'));items.push(ev('m'+date+'v','meal',date,'17:00','17:45','Večeře','Jídelna'))}return{stay:stay,items:items}}
  localStorage.setItem(STORE,JSON.stringify(build()));
})();
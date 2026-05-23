(function(){
  'use strict';
  var STORE = 'lazensky_commander_schedule_v10';
  function toSchedule(source){
    var items = [];
    if(source && source.days){
      Object.keys(source.days).sort().forEach(function(date){
        (source.days[date] || []).forEach(function(item, index){
          items.push({
            id: item.id || ('lk-' + date + '-' + index),
            type: item.type === 'meal' ? 'meal' : 'procedure',
            date: String(item.date || date),
            start: String(item.start || item.alarmTime || '00:00'),
            end: String(item.end || item.start || item.alarmTime || '00:00'),
            title: String(item.title || item.name || 'Událost'),
            place: String(item.place || item.location || '—'),
            leaveTime: item.leaveTime || null,
            alarmTime: item.alarmTime || null
          });
        });
      });
    }
    var stay = Object.assign({
      appName: 'Lázeňský Komandér',
      spaName: 'Slatinné lázně Třeboň',
      mealShift: '1. směna',
      leaveBufferMinutes: 15,
      room: '1LDB-A / 133',
      doctor: 'MUDr. Čech',
      diagnosis: 'G112 Mozečková ataxie',
      doctorOffice: 'Ordinace 214 · 2. patro · LDB',
      stayFrom: '2026-05-22',
      stayTo: '2026-06-18'
    }, source && source.stay ? {
      stayFrom: source.stay.from || source.stay.stayFrom || '2026-05-22',
      stayTo: source.stay.to || source.stay.stayTo || '2026-06-18',
      leaveBufferMinutes: source.stay.leaveBufferMinutes || 15
    } : {});
    return { source: 'alarms.json', generatedAt: source.generatedAt || null, stay: stay, items: items };
  }
  function loadScript(src, done){
    var script = document.createElement('script');
    script.src = src;
    script.onload = done || function(){};
    script.onerror = function(){
      var app = document.getElementById('app');
      if(app) app.innerHTML = '<div class="fatal"><b>Chyba načtení</b>Nepodařilo se načíst ' + src + '.</div>';
    };
    document.body.appendChild(script);
  }
  function bootApp(){
    loadScript('./app-v29.js', function(){
      loadScript('./app-v33-polish.js', function(){
        loadScript('./app-v35-polish.js');
      });
    });
  }
  fetch('./alarms.json?source=v35-' + Date.now(), { cache: 'no-store' })
    .then(function(response){
      if(!response.ok) throw new Error('alarms.json HTTP ' + response.status);
      return response.json();
    })
    .then(function(source){
      var schedule = toSchedule(source);
      localStorage.setItem(STORE, JSON.stringify(schedule));
      window.LK_SOURCE_OF_TRUTH = 'alarms.json';
      bootApp();
    })
    .catch(function(error){
      var app = document.getElementById('app');
      if(app) app.innerHTML = '<div class="fatal"><b>Chyba zdroje dat</b>Komandér nenačetl alarms.json.<br>' + String(error.message || error) + '</div>';
    });
})();

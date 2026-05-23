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
  function keepNavVisible(){
    document.body.classList.remove('nav-hidden');
    var nav = document.querySelector('nav');
    if(nav){
      nav.style.transform = 'none';
      nav.style.opacity = '1';
      nav.style.pointerEvents = 'auto';
    }
  }
  function dynamicSummary(){
    var summary = document.querySelector('.full');
    var current = document.querySelector('.now2');
    if(!summary || !current) return;
    function text(selector){
      var element = document.querySelector(selector);
      return element ? element.textContent.trim().replace(/\s+/g, ' ') : '';
    }
    var status = text('.now2 .pill');
    var command = text('.now2 .cmd');
    var amount = text('.now2 .big').replace(/([0-9])([a-zA-Zá-žÁ-Ž])/g, '$1 $2');
    var title = text('.now2 .detail b');
    if(status === 'VOLNO'){
      summary.innerHTML = (command === 'Volno do odchodu' ? 'Volno do odchodu: ' : 'Volno: ') + '<b>' + amount + '</b>';
    }else if(status === 'JE ČAS VYRAZIT'){
      summary.innerHTML = 'Teď vyrazit: <b>' + title + '</b>';
    }else if(status === 'PROBÍHÁ'){
      summary.innerHTML = 'Právě probíhá: <b>' + title + '</b>';
    }
  }
  function bootPolish(){
    loadScript('./app-v33-polish.js', function(){
      setTimeout(function(){ keepNavVisible(); dynamicSummary(); }, 50);
      setTimeout(function(){ keepNavVisible(); dynamicSummary(); }, 500);
      setInterval(function(){ keepNavVisible(); dynamicSummary(); }, 1000);
    });
  }
  fetch('./alarms.json?source=final-' + Date.now(), { cache: 'no-store' })
    .then(function(response){
      if(!response.ok) throw new Error('alarms.json HTTP ' + response.status);
      return response.json();
    })
    .then(function(source){
      localStorage.setItem(STORE, JSON.stringify(toSchedule(source)));
      loadScript('./app-v29.js', bootPolish);
    })
    .catch(function(error){
      var app = document.getElementById('app');
      if(app) app.innerHTML = '<div class="fatal"><b>Chyba zdroje dat</b>Komandér nenačetl alarms.json.<br>' + String(error.message || error) + '</div>';
    });
})();

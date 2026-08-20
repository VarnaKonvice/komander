(function(){
  'use strict';

  var STORE = 'lazensky_commander_public_schedule_v1';
  var LEGACY_STORE = 'lazensky_commander_schedule_v10';
  var LOCAL_SETTINGS_STORE = 'lazensky_commander_local_settings_v1';
  var MODULE_URL = typeof document !== 'undefined' && document.currentScript && document.currentScript.src ? document.currentScript.src : '';
  var SCHEDULE_URL = MODULE_URL ? new URL('./data/schedule.json', MODULE_URL).href : './data/schedule.json';
  var syncRunning = false;

  function safeParse(value){ try { return JSON.parse(value); } catch (error) { return null; } }
  function compactText(value){ return String(value == null ? '' : value).trim(); }
  function own(object, key){ return Object.prototype.hasOwnProperty.call(object || {}, key); }
  function overrideKey(value){ var text = compactText(value); return text && text.normalize ? text.normalize('NFC').toLocaleLowerCase('cs-CZ') : text.toLocaleLowerCase('cs-CZ'); }
  function validMinutes(value){ if(value == null || typeof value === 'boolean' || compactText(value) === '') return null; var number = Number(value); return Number.isInteger(number) && number >= 0 && number <= 180 ? number : null; }
  function objectOfMinutes(value){ var result = {}; Object.keys(value || {}).forEach(function(key){ var minutes = validMinutes(value[key]); var normalized = overrideKey(key); if(minutes != null && normalized) result[normalized] = minutes; }); return result; }
  function validDate(value){ var match = compactText(value).match(/^(\d{4})-(\d{2})-(\d{2})$/); if(!match) return false; var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])); return date.getFullYear() === Number(match[1]) && date.getMonth() === Number(match[2]) - 1 && date.getDate() === Number(match[3]); }
  function clockMinutes(value){ var match = compactText(value).match(/^(?:[01]?\d|2[0-3]):[0-5]\d$/); return match ? Number(match[0].split(':')[0]) * 60 + Number(match[0].split(':')[1]) : -1; }
  function inferMealType(value){ var title = compactText(value).toLowerCase(); if(title.indexOf('snídan') >= 0) return 'Snídaně'; if(title.indexOf('oběd') >= 0) return 'Oběd'; if(title.indexOf('večeř') >= 0) return 'Večeře'; return compactText(value) || 'Jídlo'; }
  function normalizeSettings(value, legacyStay){ value = value || {}; var fallback = validMinutes(legacyStay && legacyStay.leaveBufferMinutes); return { defaultLeadTimeMinutes: validMinutes(value.defaultLeadTimeMinutes) != null ? validMinutes(value.defaultLeadTimeMinutes) : (fallback != null ? fallback : 20), procedureTypeOverrides: objectOfMinutes(value.procedureTypeOverrides), mealOverrides: objectOfMinutes(value.mealOverrides) }; }
  function normalizeEvent(value, index){ value = value || {}; var kind = value.kind === 'meal' || value.type === 'meal' ? 'meal' : 'procedure'; return { stableId: compactText(value.stableId || value.id) || 'legacy-' + index, date: compactText(value.date), start: compactText(value.start), end: compactText(value.end || value.start), title: compactText(value.title || value.name || 'Událost'), location: compactText(value.location || value.place), kind: kind, procedureType: kind === 'procedure' ? compactText(value.procedureType || value.title || value.name) : '', mealType: kind === 'meal' ? compactText(value.mealType || inferMealType(value.title || value.name)) : '', leadTimeMinutes: validMinutes(value.leadTimeMinutes) }; }
  function normalizeSchedule(value, options){
    options = options || {}; value = value || {};
    var version = Number(value.scheduleVersion); if(!Number.isSafeInteger(version) || version < 0) version = options.defaultVersion == null ? 0 : options.defaultVersion;
    var schedule = { schemaVersion: 1, scheduleVersion: version, updatedAt: compactText(value.updatedAt || options.updatedAt || new Date().toISOString()), stay: value.stay || {}, events: (Array.isArray(value.events) ? value.events : (Array.isArray(value.items) ? value.items : [])).map(normalizeEvent), settings: normalizeSettings(value.settings, value.stay) };
    schedule.events.sort(function(left, right){ return [left.date, left.start, left.end, left.stableId].join('|').localeCompare([right.date, right.start, right.end, right.stableId].join('|')); });
    validateSchedule(schedule); return schedule;
  }
  function validateSchedule(schedule){
    if(!schedule || !Array.isArray(schedule.events) || !schedule.stay || !schedule.settings) throw new Error('Rozpis nemá platnou strukturu.');
    if(!compactText(schedule.updatedAt) || Number.isNaN(Date.parse(schedule.updatedAt))) throw new Error('Rozpis nemá platné updatedAt.');
    var ids = {};
    schedule.events.forEach(function(event){ var start = clockMinutes(event.start), end = clockMinutes(event.end); if(!validDate(event.date) || start < 0 || end < start) throw new Error('Událost '+event.stableId+' nemá platné datum nebo čas.'); if(ids[event.stableId]) throw new Error('Rozpis obsahuje duplicitní stabilní ID: '+event.stableId+'.'); ids[event.stableId] = true; });
    return true;
  }
  function toLegacySchedule(schedule){ return { stay: Object.assign({}, schedule.stay, { spaName: schedule.stay.spa || schedule.stay.spaName, stayFrom: schedule.stay.dateFrom || schedule.stay.stayFrom, stayTo: schedule.stay.dateTo || schedule.stay.stayTo, leaveBufferMinutes: schedule.settings.defaultLeadTimeMinutes }), items: schedule.events.map(function(event){ return { id: event.stableId, type: event.kind, date: event.date, start: event.start, end: event.end, title: event.title, place: event.location }; }) }; }
  function persistSchedule(schedule, source){ localStorage.setItem(STORE, JSON.stringify({ source: source || 'public-feed', schedule: schedule })); localStorage.setItem(LEGACY_STORE, JSON.stringify(toLegacySchedule(schedule))); window.dispatchEvent(new Event('lazensky-schedule-change')); return schedule; }
  function currentSchedule(){ var stored = safeParse(localStorage.getItem(STORE) || 'null'); if(stored && stored.schedule){ try { return normalizeSchedule(stored.schedule, { defaultVersion: 0 }); } catch(error) {} } return null; }
  function getLocalSettings(){ var value = safeParse(localStorage.getItem(LOCAL_SETTINGS_STORE) || 'null') || {}; return { defaultLeadTimeMinutes: own(value, 'defaultLeadTimeMinutes') ? validMinutes(value.defaultLeadTimeMinutes) : null, procedureTypeOverrides: objectOfMinutes(value.procedureTypeOverrides), mealOverrides: objectOfMinutes(value.mealOverrides), eventOverrides: objectOfMinutes(value.eventOverrides) }; }
  function saveLocalSettings(value){ localStorage.setItem(LOCAL_SETTINGS_STORE, JSON.stringify(value)); window.dispatchEvent(new Event('lazensky-schedule-settings-change')); }
  function effectiveLeadTime(event, schedule){ schedule = schedule || currentSchedule(); if(!schedule) return 20; var local = getLocalSettings(), type = overrideKey(event.kind === 'meal' ? event.mealType : event.procedureType), automatic = event.kind === 'meal' ? schedule.settings.mealOverrides[type] : schedule.settings.procedureTypeOverrides[type], localType = event.kind === 'meal' ? local.mealOverrides[type] : local.procedureTypeOverrides[type]; if(local.eventOverrides[event.stableId] != null) return local.eventOverrides[event.stableId]; if(localType != null) return localType; if(local.defaultLeadTimeMinutes != null) return local.defaultLeadTimeMinutes; if(event.leadTimeMinutes != null) return event.leadTimeMinutes; return automatic != null ? automatic : schedule.settings.defaultLeadTimeMinutes; }
  function localIso(date){ return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0'); }
  function eventDateTime(event, time){ var value = new Date(event.date+'T'+time+':00'); return Number.isNaN(value.getTime()) ? null : value; }
  function localDateTimeIso(date){ return date.getFullYear()+'-'+String(date.getMonth()+1).padStart(2,'0')+'-'+String(date.getDate()).padStart(2,'0')+'T'+String(date.getHours()).padStart(2,'0')+':'+String(date.getMinutes()).padStart(2,'0')+':00'; }
  function alarmContract(schedule){ schedule = schedule || currentSchedule(); if(!schedule) return []; try { schedule = normalizeSchedule(schedule, { defaultVersion: 0 }); } catch(error) { return []; } return schedule.events.map(function(event){ var startAt = eventDateTime(event,event.start), endAt = eventDateTime(event,event.end), effectiveLeadTimeMinutes = effectiveLeadTime(event,schedule), leaveAt = new Date(startAt.getTime()-effectiveLeadTimeMinutes*60000); return { stableId:event.stableId, scheduleVersion:schedule.scheduleVersion, kind:event.kind, title:event.title, location:event.location, startAt:localDateTimeIso(startAt), endAt:localDateTimeIso(endAt), effectiveLeadTimeMinutes:effectiveLeadTimeMinutes, leaveAt:localDateTimeIso(leaveAt) }; }); }
  function liveEvent(event){ return event ? { stableId:event.stableId, date:event.date, start:event.start, end:event.end, title:event.title, location:event.location, kind:event.kind, procedureType:event.procedureType || '', mealType:event.mealType || '' } : null; }
  function liveResult(state, event, nextEvent, startAt, endAt, leaveAt, now, leadTimeMinutes){ return { state:state, event:liveEvent(event), nextEvent:liveEvent(nextEvent), startAt:startAt ? startAt.getFullYear()+'-'+String(startAt.getMonth()+1).padStart(2,'0')+'-'+String(startAt.getDate()).padStart(2,'0')+'T'+String(startAt.getHours()).padStart(2,'0')+':'+String(startAt.getMinutes()).padStart(2,'0')+':00' : null, endAt:endAt ? endAt.getFullYear()+'-'+String(endAt.getMonth()+1).padStart(2,'0')+'-'+String(endAt.getDate()).padStart(2,'0')+'T'+String(endAt.getHours()).padStart(2,'0')+':'+String(endAt.getMinutes()).padStart(2,'0')+':00' : null, leaveAt:leaveAt ? leaveAt.getFullYear()+'-'+String(leaveAt.getMonth()+1).padStart(2,'0')+'-'+String(leaveAt.getDate()).padStart(2,'0')+'T'+String(leaveAt.getHours()).padStart(2,'0')+':'+String(leaveAt.getMinutes()).padStart(2,'0')+':00' : null, minutesUntilStart:startAt ? Math.ceil((startAt.getTime()-now.getTime())/60000) : null, minutesUntilLeave:leaveAt ? Math.ceil((leaveAt.getTime()-now.getTime())/60000) : null, leadTimeMinutes:leadTimeMinutes == null ? null : leadTimeMinutes }; }
  function computeLiveState(scheduleInput, nowInput){
    var now = nowInput instanceof Date ? new Date(nowInput.getTime()) : new Date(nowInput == null ? Date.now() : nowInput);
    if(Number.isNaN(now.getTime()) || !scheduleInput) return liveResult('NO_SCHEDULE', null, null, null, null, null, Number.isNaN(now.getTime()) ? new Date(0) : now, null);
    var schedule;
    try { schedule = normalizeSchedule(scheduleInput, { defaultVersion: 0 }); } catch(error) { return liveResult('NO_SCHEDULE', null, null, null, null, null, now, null); }
    var today = localIso(now), events = schedule.events.slice().sort(function(left,right){ return [left.date,left.start,left.end,left.stableId].join('|').localeCompare([right.date,right.start,right.end,right.stableId].join('|')); }), todayEvents = events.filter(function(event){ return event.date === today; });
    for(var index=0; index<todayEvents.length; index++){
      var event = todayEvents[index], startAt = eventDateTime(event,event.start), endAt = eventDateTime(event,event.end);
      if(!startAt || !endAt || endAt.getTime() < startAt.getTime()) return liveResult('NO_SCHEDULE', null, null, null, null, null, now, null);
      var leadTimeMinutes = effectiveLeadTime(event,schedule), leaveAt = new Date(startAt.getTime()-leadTimeMinutes*60000);
      if(now.getTime() < leaveAt.getTime()) return liveResult('UPCOMING', event, event, startAt, endAt, leaveAt, now, leadTimeMinutes);
      if(now.getTime() < startAt.getTime()) return liveResult('LEAVE_NOW', event, event, startAt, endAt, leaveAt, now, leadTimeMinutes);
      if(now.getTime() < endAt.getTime()) return liveResult('IN_PROGRESS', event, event, startAt, endAt, leaveAt, now, leadTimeMinutes);
    }
    var nextEvent = events.find(function(event){ var startAt = eventDateTime(event,event.start); return startAt && startAt.getTime() > now.getTime(); }) || null;
    return liveResult('DAY_DONE', null, nextEvent, null, null, null, now, null);
  }
  function calendarContract(schedule){ schedule = schedule || currentSchedule(); return schedule ? schedule.events.map(function(event){ return { stableId: event.stableId, syncKey: 'lc:'+event.stableId, managedBy: 'lazensky-commander', targetCalendar: event.kind === 'meal' ? 'Jídlo' : 'Procedury', title: event.title, start: event.date+'T'+event.start+':00', end: event.date+'T'+event.end+':00', timezone: 'Europe/Prague', location: event.location, kind: event.kind, procedureType: event.procedureType || null, mealType: event.mealType || null, leadTimeMinutes: effectiveLeadTime(event, schedule), descriptionMarker: '[LC:'+event.stableId+']' }; }) : []; }
  async function refreshPublicSchedule(){
    if(syncRunning) return { status: 'busy' }; syncRunning = true;
    try {
      var response = await fetch(SCHEDULE_URL+'?v='+Date.now(), { cache: 'no-store', headers: { 'Cache-Control': 'no-cache' } });
      if(response.status === 404) return { status: 'missing' };
      if(!response.ok) throw new Error('Server vrátil '+response.status+'.');
      var schedule = normalizeSchedule(await response.json());
      if(schedule.scheduleVersion < 1) throw new Error('Automatický rozpis musí mít kladné scheduleVersion.');
      var current = currentSchedule();
      if(current && schedule.scheduleVersion <= current.scheduleVersion) return { status: 'current', scheduleVersion: current.scheduleVersion };
      persistSchedule(schedule, 'public-feed'); return { status: 'updated', scheduleVersion: schedule.scheduleVersion };
    } finally { syncRunning = false; }
  }
  function escapeHtml(value){ return String(value == null ? '' : value).replace(/[&<>"']/g, function(character){ return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[character]; }); }
  function notificationSettingsHtml(){ var schedule = currentSchedule(); if(!schedule) return ''; var local = getLocalSettings(), procedureTypes = Array.from(new Set(schedule.events.filter(function(event){ return event.kind === 'procedure'; }).map(function(event){ return event.procedureType; }))).sort(), mealTypes = ['Snídaně','Oběd','Večeře']; function valueFor(group, type){ if(group === 'default') return local.defaultLeadTimeMinutes != null ? local.defaultLeadTimeMinutes : schedule.settings.defaultLeadTimeMinutes; var localValues = group === 'procedure' ? local.procedureTypeOverrides : local.mealOverrides, sourceValues = group === 'procedure' ? schedule.settings.procedureTypeOverrides : schedule.settings.mealOverrides, key = overrideKey(type); return own(localValues, key) ? localValues[key] : (own(sourceValues, key) ? sourceValues[key] : schedule.settings.defaultLeadTimeMinutes); } function row(label, group, type){ return '<label class="lkLeadRow"><span>'+escapeHtml(label)+'</span><input type="number" min="0" max="180" inputmode="numeric" value="'+valueFor(group,type)+'" data-lk-lead-group="'+group+'" data-lk-lead-type="'+escapeHtml(type || '')+'"><em>min</em></label>'; } return '<section class="lkStaySection lkSectionCard lkLeadSettings" data-lk-lead-settings="1"><div class="lkSectionHeader"><h2>Nastavení upozornění</h2><i class="lkBadge">Vyrazit</i></div><p class="lkSecondaryText">Časy se použijí pro budoucí upozornění, neukazují se v programu dne.</p>'+row('Výchozí','default','')+procedureTypes.map(function(type){ return row(type,'procedure',type); }).join('')+mealTypes.map(function(type){ return row(type,'meal',type); }).join('')+'</section>'; }
  function bindNotificationSettings(root){ if(!root) return; root.addEventListener('change', function(event){ var input = event.target.closest('[data-lk-lead-group]'); if(!input) return; var minutes = validMinutes(input.value); if(minutes == null){ input.value = ''; return; } var group = input.dataset.lkLeadGroup, type = input.dataset.lkLeadType || '', local = getLocalSettings(); if(group === 'default') local.defaultLeadTimeMinutes = minutes; else if(group === 'procedure') local.procedureTypeOverrides[type] = minutes; else if(group === 'meal') local.mealOverrides[type] = minutes; saveLocalSettings(local); }); }
  function startAutoSync(){ refreshPublicSchedule().catch(function(){}); document.addEventListener('visibilitychange', function(){ if(!document.hidden) refreshPublicSchedule().catch(function(){}); }); window.addEventListener('online', function(){ refreshPublicSchedule().catch(function(){}); }); }

  window.LazenskySchedule = { normalizeSchedule: normalizeSchedule, validateSchedule: validateSchedule, toLegacySchedule: toLegacySchedule, getSchedule: currentSchedule, getEffectiveLeadTime: effectiveLeadTime, computeLiveState: computeLiveState, alarmContract: alarmContract, calendarContract: calendarContract, renderNotificationSettings: notificationSettingsHtml, bindNotificationSettings: bindNotificationSettings, refreshPublicSchedule: refreshPublicSchedule, scheduleUrl: SCHEDULE_URL };
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', startAutoSync, { once: true }); else startAutoSync();
})();

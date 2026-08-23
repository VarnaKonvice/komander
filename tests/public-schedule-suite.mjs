import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function createLocalStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); }
  };
}

function createRuntime(calendarSource, source, shared) {
  const listeners = {};
  const location = { pathname: '/', search: '', hash: '' };
  const window = {
    location,
    addEventListener(type, listener) { listeners[type] = listener; },
    dispatchEvent() {}
  };
  const document = {
    readyState: 'loading',
    currentScript: { src: 'https://unit.test/komander/public-schedule-feed.js' },
    addEventListener(type, listener) { listeners['document:'+type] = listener; }
  };
  const sandbox = {
    window, document, location, localStorage: shared.localStorage, fetch: shared.fetch,
    URL, TextEncoder, Event: class Event { constructor(type) { this.type = type; } },
    console, setTimeout, clearTimeout
  };
  vm.runInNewContext(calendarSource, sandbox, { filename: 'calendar-contract.js' });
  vm.runInNewContext(source, sandbox, { filename: 'public-schedule-feed.js' });
  return { api: window.LazenskySchedule, sandbox, listeners };
}

export async function runPublicScheduleSuite(options) {
  const root = options.repoRoot;
  const calendarSource = await fs.readFile(path.join(root, 'calendar-contract.js'), 'utf8');
  const source = await fs.readFile(path.join(root, 'public-schedule-feed.js'), 'utf8');
  const productionSchedule = JSON.parse(await fs.readFile(path.join(root, 'data/schedule.json'), 'utf8'));
  const nativeAlarmFixtures = JSON.parse(await fs.readFile(path.join(root, 'tests/fixtures/native-alarm-reconciliation-v1.json'), 'utf8'));
  const iconMap = JSON.parse(await fs.readFile(path.join(root, 'assets/icons/lazensky-v1/icon-map.json'), 'utf8'));
  const iconColors = JSON.parse(await fs.readFile(path.join(root, 'assets/icons/lazensky-v1/colors.json'), 'utf8'));
  const cases = [];
  async function test(name, run) {
    try { await run(); cases.push({ name, ok: true }); }
    catch (error) { cases.push({ name, ok: false, error: error.message }); }
  }

  const shared = { localStorage: createLocalStorage(), fetch: null };
  let activeSchedule = clone(productionSchedule);
  shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(activeSchedule); } }; };
  const runtime = createRuntime(calendarSource, source, shared);

  await test('public feed: production schedule validates', async function() {
    runtime.api.validateSchedule(runtime.api.normalizeSchedule(productionSchedule));
    assert(productionSchedule.scheduleVersion === 4, 'Unexpected production scheduleVersion');
    assert(productionSchedule.events.some(function(event) { return event.kind === 'meal'; }), 'Meals are missing');
    assert(productionSchedule.events.some(function(event) { return event.kind === 'procedure'; }), 'Procedures are missing');
  });
  await test('visual contract: all approved categories and specialized precedence classify consistently', async function() {
    const mappings = [
      ['Snídaně', 'meal', 'meal_breakfast'], ['Oběd', 'meal', 'meal_lunch'], ['Večeře', 'meal', 'meal_dinner'],
      ['Plavání v bazénu', 'procedure', 'pool'], ['Jodobromový bazén', 'procedure', 'iodobrom'],
      ['Vířivá vana', 'procedure', 'whirlpool'], ['Whirlpool', 'procedure', 'whirlpool'],
      ['Rašelinový zábal', 'procedure', 'peat_wrap'], ['Slatina', 'procedure', 'peat_wrap'], ['Parafín', 'procedure', 'peat_wrap'],
      ['iMoove', 'procedure', 'imoove'], ['Hydrojet masáž', 'procedure', 'hydrojet'],
      ['Magnetoterapie', 'procedure', 'electro_therapy'], ['Elektroterapie', 'procedure', 'electro_therapy'],
      ['Ultrazvuková masáž', 'procedure', 'electro_therapy'], ['Galvanická lázeň', 'procedure', 'electro_therapy'], ['Čtyřkomorová lázeň', 'procedure', 'electro_therapy'],
      ['Individuální LTV', 'procedure', 'individual_rehab'], ['Ergoterapie', 'procedure', 'individual_rehab'],
      ['Rehabilitace', 'procedure', 'individual_rehab'], ['Chodicí pás', 'procedure', 'individual_rehab'],
      ['Klasická masáž', 'procedure', 'massage']
    ];
    mappings.forEach(function(item) {
      const event = { title: item[0], kind: item[1], procedureType: item[1] === 'procedure' ? item[0] : '', mealType: item[1] === 'meal' ? item[0] : '' };
      const icon = runtime.api.classifyEventIcon(event, iconMap);
      assert(icon && icon.key === item[2], item[0]+' was classified as '+(icon && icon.key));
    });
    iconMap.icons.forEach(function(icon) {
      const colorKey = icon.key.startsWith('meal_') ? 'meal' : icon.key;
      assert(icon.accent === iconColors.procedures[colorKey], icon.key+' accent differs from colors.json');
    });
  });
  await test('visual contract: unknown procedures preserve a neutral no-category fallback', async function() {
    const unknown = runtime.api.classifyEventIcon({ title: 'Neznámá péče XYZ', kind: 'procedure', procedureType: 'Neznámá péče XYZ' }, iconMap);
    assert(unknown === null, 'Unknown procedure received a concrete category');
    assert(iconMap.fallback.key === null, 'Fallback still points to a concrete icon');
    assert(iconMap.fallback.accent === iconColors.brand.commanderPurple, 'Fallback is not neutral Commander purple');
  });
  await test('visual contract: PWA loads icon-map and colors through the shared schedule API', async function() {
    const requests = [];
    const visualShared = { localStorage: createLocalStorage(), fetch: async function(url) {
      requests.push(String(url));
      if(String(url).endsWith('/icon-map.json')) return { ok: true, status: 200, json: async function() { return clone(iconMap); } };
      if(String(url).endsWith('/colors.json')) return { ok: true, status: 200, json: async function() { return clone(iconColors); } };
      throw new Error('Unexpected visual contract URL: '+url);
    } };
    const visualRuntime = createRuntime(calendarSource, source, visualShared);
    const contract = await visualRuntime.api.loadVisualContract();
    const electro = visualRuntime.api.getEventVisual({ title: 'Ultrazvuková masáž', kind: 'procedure', procedureType: 'Ultrazvuková masáž' });
    const unknown = visualRuntime.api.getEventVisual({ title: 'Neznámá péče XYZ', kind: 'procedure' });
    assert(contract.iconMap.version === 1 && contract.colors.brand.commanderPurple === '#6E56CF', 'Loaded visual contract is incomplete');
    assert(requests.length === 2 && requests.some(function(url) { return url.endsWith('/icon-map.json'); }) && requests.some(function(url) { return url.endsWith('/colors.json'); }), 'Shared API did not load both canonical visual files');
    assert(electro.key === 'electro_therapy' && electro.iconUrl.endsWith('/icons/256/electro_therapy.png'), 'Known PWA visual is incorrect');
    assert(electro.accent === iconColors.procedures.electro_therapy, 'PWA accent is not sourced from colors.json');
    assert(unknown.known === false && unknown.key === null && unknown.iconUrl === null, 'Unknown PWA visual uses a fake icon');
    assert(visualRuntime.api.visualAssetUrls(256).length === iconMap.icons.length + 2, 'Visual asset list is incomplete');
  });
  await test('visual contract: current cards render approved PNGs and offline cache contains every dependency', async function() {
    const overview = await fs.readFile(path.join(root, 'day-overview-v1.js'), 'utf8');
    const css = await fs.readFile(path.join(root, 'day-overview-v1.css'), 'utf8');
    const worker = await fs.readFile(path.join(root, 'sw.js'), 'utf8');
    assert(overview.includes('window.LazenskySchedule.getEventVisual') && overview.includes('lkEventIcon'), 'PWA cards do not use the shared visual API');
    assert(overview.includes("window.addEventListener('lazensky-visual-contract-ready'"), 'PWA does not refresh after the visual contract loads');
    assert(!overview.includes("return item.type === 'meal' ? '♨︎' : '⌖'"), 'Legacy generic symbols remain as the visual category source');
    assert(css.includes('border-left-color:var(--lk-category-accent)') && css.includes('.lkEventIcon'), 'Category accent or icon styling is missing');
    assert(worker.includes("const CACHE_NAME = 'komander-pwa-v8'"), 'PWA cache version was not advanced');
    assert(worker.includes("'./calendar-contract.js?v=1'"), 'Shared calendar contract is missing from the offline cache');
    ['icon-map.json','colors.json'].forEach(function(file) { assert(worker.includes('assets/icons/lazensky-v1/'+file), file+' is missing from offline cache'); });
    iconMap.icons.forEach(function(icon) {
      assert(worker.includes('assets/icons/lazensky-v1/icons/256/'+icon.key+'.png'), icon.key+' is missing from offline cache');
    });
  });
  await test('public feed: first launch downloads and persists the schedule', async function() {
    const result = await runtime.api.refreshPublicSchedule();
    assert(result.status === 'updated' && result.scheduleVersion === 4, 'First public refresh failed');
    assert(runtime.api.getSchedule().scheduleVersion === 4, 'Schedule was not stored locally');
  });
  await test('public feed: unchanged version does not overwrite local data', async function() {
    const result = await runtime.api.refreshPublicSchedule();
    assert(result.status === 'current' && result.scheduleVersion === 4, 'Unchanged version did not remain current');
  });
  await test('public feed: newer version automatically replaces the local schedule', async function() {
    activeSchedule = clone(productionSchedule);
    activeSchedule.scheduleVersion = 5;
    activeSchedule.updatedAt = '2026-08-16T13:00:00.000Z';
    const result = await runtime.api.refreshPublicSchedule();
    assert(result.status === 'updated' && runtime.api.getSchedule().scheduleVersion === 5, 'Newer public schedule was not applied');
  });
  await test('public feed: invalid newer version leaves the last valid schedule intact', async function() {
    activeSchedule = clone(productionSchedule);
    activeSchedule.scheduleVersion = 6;
    activeSchedule.updatedAt = '2026-08-16T14:00:00.000Z';
    activeSchedule.events[0].end = '06:00';
    try { await runtime.api.refreshPublicSchedule(); throw new Error('Invalid schedule was accepted'); }
    catch (error) { assert(runtime.api.getSchedule().scheduleVersion === 5, 'Invalid public schedule replaced last valid data'); }
  });
  await test('public feed: offline preserves the last valid schedule', async function() {
    shared.fetch = async function() { throw new Error('offline'); };
    runtime.sandbox.fetch = shared.fetch;
    try { await runtime.api.refreshPublicSchedule(); } catch (error) {}
    assert(runtime.api.getSchedule().scheduleVersion === 5, 'Offline refresh removed local schedule');
  });
  await test('public feed: reload uses the locally persisted schedule', async function() {
    const reloaded = createRuntime(calendarSource, source, shared);
    assert(reloaded.api.getSchedule().scheduleVersion === 5, 'Public schedule did not survive reload');
  });
  await test('public feed: legacy storage is a derived compatibility projection', async function() {
    const legacy = JSON.parse(shared.localStorage.getItem('lazensky_commander_schedule_v10'));
    assert(typeof runtime.api.toLegacySchedule === 'function', 'Legacy compatibility adapter is not exported');
    assert(legacy.stay.spaName === productionSchedule.stay.spa, 'Legacy stay projection is incorrect');
    assert(legacy.items.some(function(event) { return event.id === 'synthetic-0815-bath' && event.type === 'procedure'; }), 'Legacy event projection is incorrect');
    assert(!source.includes('LEGACY_MIRROR_STORE'), 'Redundant legacy mirror remains');
  });
  await test('public feed: legacy storage is never accepted as the canonical schedule', async function() {
    const legacyOnly = { localStorage: createLocalStorage(), fetch: async function() { throw new Error('offline'); } };
    legacyOnly.localStorage.setItem('lazensky_commander_schedule_v10', JSON.stringify(runtime.api.toLegacySchedule(productionSchedule)));
    const legacyRuntime = createRuntime(calendarSource, source, legacyOnly);
    assert(legacyRuntime.api.getSchedule() === null, 'Legacy storage became a canonical schedule source');
  });
  await test('legacy inline Commander starts and refreshes from the canonical API', async function() {
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    assert(index.indexOf('calendar-contract.js?v=1') < index.indexOf('public-schedule-feed.js?v=4'), 'Shared calendar contract is not loaded before the public schedule feed');
    assert(index.indexOf('public-schedule-feed.js') < index.indexOf("var VERSION='"), 'Public schedule API is not available before inline Commander startup');
    assert(index.includes('api&&api.getSchedule&&api.toLegacySchedule'), 'Inline Commander does not read the canonical schedule API');
    assert(index.includes("window.addEventListener('lazensky-schedule-change'"), 'Inline Commander does not refresh after a canonical schedule update');
    assert(!index.includes('localStorage.getItem(STORE)'), 'Inline Commander still reads v10 as its schedule source');
    assert(!index.includes('lazensky_commander_schedule_v10'), 'Inline Commander still owns the legacy schedule store');
    assert(!index.includes('localStorage.setItem(STORE,JSON.stringify(data))'), 'Inline Commander can still create a local schedule source');
    assert(index.includes("alert('Rozpis se načítá z data/schedule.json.')"), 'Legacy schedule import is not disabled');
  });
  await test('alarm contract: meals and procedures expose the canonical leave time', async function() {
    const alarms = runtime.api.alarmContract(productionSchedule);
    const bath = alarms.find(function(alarm) { return alarm.stableId === 'synthetic-0815-bath'; });
    const breakfast = alarms.find(function(alarm) { return alarm.stableId === 'synthetic-0815-breakfast'; });
    assert(typeof runtime.api.alarmContract === 'function', 'Alarm contract is not exported');
    assert(bath.scheduleVersion === 4 && bath.kind === 'procedure', 'Procedure alarm metadata is incorrect');
    assert(bath.title === 'Jodobromová koupel' && bath.location === 'Balneo', 'Procedure alarm text is incorrect');
    assert(bath.startAt === '2026-08-15T10:00:00' && bath.endAt === '2026-08-15T10:30:00', 'Procedure alarm times are incorrect');
    assert(bath.effectiveLeadTimeMinutes === 30 && bath.leaveAt === '2026-08-15T09:30:00', 'Procedure alarm leave time is incorrect');
    assert(breakfast.kind === 'meal' && breakfast.effectiveLeadTimeMinutes === 15 && breakfast.leaveAt === '2026-08-15T07:15:00', 'Meal alarm leave time is incorrect');
    assert(runtime.api.computeLiveState(productionSchedule, '2026-08-15T09:20:00').leaveAt === bath.leaveAt, 'Alarm and live state have different leaveAt values');
    assert(source.includes('var alarm = alarmForEvent(event,schedule,effectiveOverrides)'), 'Live state does not consume the shared alarm event contract');
    assert(!/function computeLiveState[\s\S]*?startAt\.getTime\(\)-leadTimeMinutes\*60000/.test(source), 'Live state still contains a second leaveAt calculation');
  });
  await test('alarm contract: lead-time priority and zero remain intact', async function() {
    const schedule = clone(productionSchedule);
    const bath = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-bath'; });
    bath.leadTimeMinutes = 25;
    const before = JSON.stringify(schedule);
    assert(runtime.api.alarmContract(schedule).find(function(alarm) { return alarm.stableId === bath.stableId; }).effectiveLeadTimeMinutes === 25, 'Event lead time did not override the source type default');
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ defaultLeadTimeMinutes: 12 }));
    const defaultOverride = runtime.api.alarmContract(schedule).find(function(alarm) { return alarm.stableId === bath.stableId; });
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ defaultLeadTimeMinutes: 12, procedureTypeOverrides: { 'Jodobromová koupel': 40 } }));
    const typeOverride = runtime.api.alarmContract(schedule).find(function(alarm) { return alarm.stableId === bath.stableId; });
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ defaultLeadTimeMinutes: 12, procedureTypeOverrides: { 'Jodobromová koupel': 40 }, eventOverrides: { 'synthetic-0815-bath': 0 } }));
    const eventOverride = runtime.api.alarmContract(schedule).find(function(alarm) { return alarm.stableId === bath.stableId; });
    shared.localStorage.removeItem('lazensky_commander_local_settings_v1');
    assert(defaultOverride.effectiveLeadTimeMinutes === 12, 'Local default override was ignored');
    assert(typeOverride.effectiveLeadTimeMinutes === 40, 'Local type override did not override the local default');
    assert(eventOverride.effectiveLeadTimeMinutes === 0 && eventOverride.leaveAt === eventOverride.startAt, 'Local event override with zero was not preserved');
    assert(JSON.stringify(schedule) === before, 'Alarm contract mutated the source schedule');
  });
  await test('alarm contract: a time correction keeps stableId and recalculates leaveAt', async function() {
    const corrected = clone(productionSchedule);
    const original = runtime.api.alarmContract(productionSchedule).find(function(alarm) { return alarm.stableId === 'synthetic-0815-magnet'; });
    corrected.events.find(function(event) { return event.stableId === original.stableId; }).start = '08:25';
    const updated = runtime.api.alarmContract(corrected).find(function(alarm) { return alarm.stableId === original.stableId; });
    assert(updated.stableId === original.stableId, 'Time correction changed stableId');
    assert(updated.startAt === '2026-08-15T08:25:00' && updated.leaveAt === '2026-08-15T08:05:00', 'Time correction did not recalculate leaveAt');
  });
  await test('native alarm payload: versioned output is deterministic and derived from the alarm contract', async function() {
    const payload = runtime.api.nativeAlarmPayload(productionSchedule);
    const repeated = runtime.api.nativeAlarmPayload(productionSchedule);
    const contract = runtime.api.alarmContract(productionSchedule);
    const bath = payload.alarms.find(function(alarm) { return alarm.stableId === 'synthetic-0815-bath'; });
    const contractBath = contract.find(function(alarm) { return alarm.stableId === bath.stableId; });
    assert(typeof runtime.api.nativeAlarmPayload === 'function', 'Native alarm payload is not exported');
    assert(payload.contractVersion === 1 && payload.scheduleVersion === 4, 'Native payload version metadata is incorrect');
    assert(JSON.stringify(payload) === JSON.stringify(repeated), 'Native payload is not deterministic');
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ eventOverrides: { 'synthetic-0815-bath': 0 } }));
    const withBrowserStoredOverride = runtime.api.nativeAlarmPayload(productionSchedule);
    shared.localStorage.removeItem('lazensky_commander_local_settings_v1');
    assert(JSON.stringify(payload) === JSON.stringify(withBrowserStoredOverride), 'Native payload read a browser-stored override');
    assert(!JSON.stringify(payload).includes('generatedAt'), 'Native payload includes a volatile generated timestamp');
    assert(JSON.stringify(Object.keys(bath).sort()) === JSON.stringify(['effectiveLeadTimeMinutes', 'endAt', 'kind', 'leaveAt', 'location', 'stableId', 'startAt', 'title']), 'Native alarm payload entry shape is incorrect');
    assert(JSON.stringify(bath) === JSON.stringify({ stableId: contractBath.stableId, kind: contractBath.kind, title: contractBath.title, location: contractBath.location, startAt: contractBath.startAt, endAt: contractBath.endAt, effectiveLeadTimeMinutes: contractBath.effectiveLeadTimeMinutes, leaveAt: contractBath.leaveAt }), 'Native payload does not reuse the alarm contract values');
  });
  await test('native alarm reconciliation: cross-platform fixtures cover all contract outcomes', async function() {
    assert(typeof runtime.api.reconcileNativeAlarms === 'function', 'Native alarm reconciliation is not exported');
    assert(nativeAlarmFixtures.contractVersion === 1, 'Native alarm fixture contract version is incorrect');
    nativeAlarmFixtures.cases.forEach(function(fixture) {
      const plan = runtime.api.reconcileNativeAlarms(fixture.currentAlarms, fixture.nextPayload);
      const repeated = runtime.api.reconcileNativeAlarms(fixture.currentAlarms, fixture.nextPayload);
      ['create', 'update', 'cancel', 'unchanged'].forEach(function(action) {
        assert(JSON.stringify(plan[action].map(function(item) { return item.stableId; })) === JSON.stringify(fixture.expected[action]), fixture.name+' produced wrong '+action+' actions');
      });
      assert(JSON.stringify(plan) === JSON.stringify(repeated), fixture.name+' reconciliation is not deterministic');
    });
  });
  await test('native alarm reconciliation: scheduleVersion alone leaves an alarm unchanged', async function() {
    const fixture = nativeAlarmFixtures.cases.find(function(item) { return item.name === 'unchanged-after-schedule-version-increase'; });
    const plan = runtime.api.reconcileNativeAlarms({ contractVersion: 1, scheduleVersion: 4, alarms: fixture.currentAlarms }, fixture.nextPayload);
    assert(plan.unchanged.length === 1 && plan.unchanged[0].stableId === 'procedure-bath', 'ScheduleVersion alone updated an unchanged alarm');
    assert(plan.create.length === 0 && plan.update.length === 0 && plan.cancel.length === 0, 'ScheduleVersion-only reconciliation produced a change action');
  });
  await test('native alarm payload: explicit overrides match the shared alarm and live-state contracts', async function() {
    const fixture = nativeAlarmFixtures.explicitOverrideCase;
    const currentPayload = runtime.api.nativeAlarmPayload(fixture.schedule, fixture.currentOverrides);
    const nextPayload = runtime.api.nativeAlarmPayload(fixture.schedule, fixture.nextOverrides);
    const currentAlarm = currentPayload.alarms[0];
    const nextAlarm = nextPayload.alarms[0];
    const sharedAlarm = runtime.api.alarmContract(fixture.schedule, fixture.nextOverrides)[0];
    const liveState = runtime.api.computeLiveState(fixture.schedule, '2026-08-20T09:00:00', fixture.nextOverrides);
    const plan = runtime.api.reconcileNativeAlarms(currentPayload, nextPayload);
    assert(currentAlarm.stableId === nextAlarm.stableId, 'Explicit override changed stableId');
    assert(currentAlarm.leaveAt === fixture.expected.currentLeaveAt && currentAlarm.effectiveLeadTimeMinutes === 30, 'Current explicit override did not set the expected leave time');
    assert(nextAlarm.leaveAt === fixture.expected.nextLeaveAt && nextAlarm.effectiveLeadTimeMinutes === 0, 'Next explicit override did not preserve lead time zero');
    assert(nextAlarm.leaveAt === sharedAlarm.leaveAt && nextAlarm.leaveAt === liveState.leaveAt, 'Native, alarm, and live-state contracts have different leaveAt values');
    ['create', 'update', 'cancel', 'unchanged'].forEach(function(action) {
      assert(JSON.stringify(plan[action].map(function(item) { return item.stableId; })) === JSON.stringify(fixture.expected[action]), 'Explicit override reconciliation produced wrong '+action+' actions');
    });
  });
  await test('legacy inline Commander uses the alarm contract instead of its stay buffer', async function() {
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    const checkSignals = index.match(/function checkSignals\(\)\{.*?\}function showNav/);
    assert(checkSignals && checkSignals[0].includes('window.LazenskySchedule.alarmContract()'), 'Web alarm does not use the alarm contract');
    assert(!checkSignals[0].includes('data.stay.leaveBufferMinutes'), 'Web alarm still calculates leave time from the legacy stay buffer');
  });
  await test('legacy inline Commander displays the same overridden leaveAt as the web alarm', async function() {
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ procedureTypeOverrides: { 'Jodobromová koupel': 44 }, mealOverrides: { 'Snídaně': 8 } }));
    const alarms = runtime.api.alarmContract(productionSchedule);
    shared.localStorage.removeItem('lazensky_commander_local_settings_v1');
    const bath = alarms.find(function(alarm) { return alarm.stableId === 'synthetic-0815-bath'; });
    const breakfast = alarms.find(function(alarm) { return alarm.stableId === 'synthetic-0815-breakfast'; });
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    const freeCard = index.match(/function freeCard\(next,now\)\{.*?\}function nextCard/);
    const nextCard = index.match(/function nextCard\(i,now,rank\)\{.*?\}function item/);
    const item = index.match(/function item\(i,now\)\{.*?\}function emptySchedule/);
    const exportWeek = index.match(/function exportWeek\(kind\)\{.*?\}function importView/);
    assert(bath.leaveAt === '2026-08-15T09:16:00' && breakfast.leaveAt === '2026-08-15T07:22:00', 'Procedure and meal overrides did not produce the expected leaveAt values');
    [freeCard, nextCard, item, exportWeek].forEach(function(fragment) {
      assert(fragment && fragment[0].includes('leaveAtFor') || fragment && fragment[0].includes('leaveTimeFor'), 'A displayed leave time does not use the alarm contract helper');
      assert(!fragment[0].includes('leaveBufferMinutes'), 'A displayed leave time still uses the legacy stay buffer');
    });
  });
  await test('live state: no usable schedule returns NO_SCHEDULE', async function() {
    const state = runtime.api.computeLiveState(null, '2026-08-15T09:00:00');
    assert(state.state === 'NO_SCHEDULE', 'Missing schedule did not return NO_SCHEDULE');
  });
  await test('live state: UPCOMING uses the procedure lead time', async function() {
    const state = runtime.api.computeLiveState(productionSchedule, '2026-08-15T09:20:00');
    assert(state.state === 'UPCOMING', 'Expected UPCOMING before the bath leave time');
    assert(state.event.stableId === 'synthetic-0815-bath', 'UPCOMING selected the wrong event');
    assert(state.leadTimeMinutes === 30 && state.leaveAt === '2026-08-15T09:30:00', 'Procedure lead time was not applied');
    assert(state.minutesUntilLeave === 10, 'UPCOMING countdown is incorrect');
  });
  await test('live state: leave and progress boundaries are exact', async function() {
    const leave = runtime.api.computeLiveState(productionSchedule, '2026-08-15T09:30:00');
    const between = runtime.api.computeLiveState(productionSchedule, '2026-08-15T09:45:00');
    const start = runtime.api.computeLiveState(productionSchedule, '2026-08-15T10:00:00');
    const during = runtime.api.computeLiveState(productionSchedule, '2026-08-15T10:10:00');
    assert(leave.state === 'LEAVE_NOW' && leave.minutesUntilLeave === 0, 'leaveAt boundary is incorrect');
    assert(between.state === 'LEAVE_NOW', 'Time between leaveAt and startAt is incorrect');
    assert(start.state === 'IN_PROGRESS', 'startAt boundary is incorrect');
    assert(during.state === 'IN_PROGRESS', 'Time during an event is incorrect');
  });
  await test('live state: end boundary searches the next event and completes the day', async function() {
    const end = runtime.api.computeLiveState(productionSchedule, '2026-08-15T10:30:00');
    const gap = runtime.api.computeLiveState(productionSchedule, '2026-08-15T10:40:00');
    const done = runtime.api.computeLiveState(productionSchedule, '2026-08-15T18:00:00');
    assert(end.state === 'UPCOMING' && end.event.stableId === 'synthetic-0815-lunch', 'endAt did not select the next event');
    assert(gap.state === 'UPCOMING' && gap.event.stableId === 'synthetic-0815-lunch', 'Gap between events is incorrect');
    assert(done.state === 'DAY_DONE', 'Time after the final event is not DAY_DONE');
    assert(done.nextEvent.stableId === 'synthetic-0816-breakfast', 'DAY_DONE has the wrong next event');
  });
  await test('live state: a new day uses that day’s first event', async function() {
    const state = runtime.api.computeLiveState(productionSchedule, '2026-08-16T07:00:00');
    assert(state.state === 'UPCOMING' && state.event.stableId === 'synthetic-0816-breakfast', 'New day did not start from its first event');
  });
  await test('live state: meal lead time is preserved', async function() {
    const before = runtime.api.computeLiveState(productionSchedule, '2026-08-15T07:10:00');
    const leave = runtime.api.computeLiveState(productionSchedule, '2026-08-15T07:15:00');
    assert(before.state === 'UPCOMING' && before.leadTimeMinutes === 15, 'Meal lead time was not applied');
    assert(leave.state === 'LEAVE_NOW' && leave.event.stableId === 'synthetic-0815-breakfast', 'Meal leave boundary is incorrect');
  });
  await test('live state: local type override has the same priority as production lead time', async function() {
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ procedureTypeOverrides: { 'Jodobromová koupel': 40 } }));
    const state = runtime.api.computeLiveState(productionSchedule, '2026-08-15T09:19:00');
    shared.localStorage.removeItem('lazensky_commander_local_settings_v1');
    assert(state.state === 'UPCOMING' && state.leadTimeMinutes === 40, 'Local procedure override was ignored');
    assert(state.leaveAt === '2026-08-15T09:20:00', 'Local procedure override calculated the wrong leave time');
  });
  await test('live state: schedule version is accepted without mutating its input', async function() {
    const schedule = clone(productionSchedule);
    schedule.scheduleVersion = 6;
    const before = JSON.stringify(schedule);
    const state = runtime.api.computeLiveState(schedule, '2026-08-15T09:20:00');
    assert(state.state === 'UPCOMING', 'Newer scheduleVersion is not usable by the live engine');
    assert(JSON.stringify(schedule) === before, 'Live engine mutated the input schedule');
  });
  await test('live UI: Today uses the production engine and refreshes without a page reload', async function() {
    const overview = await fs.readFile(path.join(root, 'day-overview-v1.js'), 'utf8');
    assert(overview.includes('window.LazenskySchedule.computeLiveState'), 'Today does not call the production live engine');
    assert(overview.includes('window.LazenskySchedule.toLegacySchedule(schedule)'), 'Today does not use the canonical compatibility adapter');
    assert(!overview.includes('localStorage.getItem(STORE)'), 'Today still reads the legacy schedule store directly');
    assert(overview.includes('renderLiveCard(data, day)'), 'Today does not render from the live engine data');
    assert(overview.includes('window.setInterval(sync, 30000)'), 'Live state is not checked every 30 seconds');
    assert(overview.includes("document.addEventListener('visibilitychange'"), 'Live state is not refreshed on foreground return');
    assert(!overview.includes('liveFreeInfo('), 'An obsolete parallel live-state implementation remains');
  });
  await test('live UI: long names and locations have portrait-safe wrapping', async function() {
    const overview = await fs.readFile(path.join(root, 'day-overview-v1.js'), 'utf8');
    const css = await fs.readFile(path.join(root, 'day-overview-v1.css'), 'utf8');
    const longEvent = { title: 'Komplexní fyzioterapeutická procedura s dlouhým názvem', location: 'Léčebný dům B, rehabilitační oddělení, místnost 214' };
    assert(longEvent.title.length > 40 && longEvent.location.length > 40, 'Long-text fixture is not representative');
    assert(overview.includes('lkLiveLocation') && overview.includes('lkLiveNextEvent'), 'Live markup has no wrapping targets for long data');
    assert(css.includes('.lkLiveBlock .lkLiveLocation') && css.includes('overflow-wrap:anywhere!important'), 'Live location does not have a wrapping rule');
    assert(css.includes('.lkLiveBlock .lkNextTop') && css.includes('grid-template-columns:minmax(0,1fr)!important'), 'Portrait live badge has no reserved row');
  });
  await test('live UI: portrait layout covers 320, 375, 390 and 430 px without changing landscape', async function() {
    const css = await fs.readFile(path.join(root, 'day-overview-v1.css'), 'utf8');
    const portraitStart = css.indexOf('@media (max-width:430px) and (orientation:portrait)');
    const portraitEnd = css.indexOf('@media (max-width:349px) and (orientation:portrait)', portraitStart);
    const portrait = css.slice(portraitStart, portraitEnd);
    const landscapeStart = css.indexOf('@media (orientation:landscape)');
    const landscape = css.slice(landscapeStart, portraitStart);
    [320, 375, 390, 430].forEach(function(width) {
      assert(width <= 430 && portrait.includes('.lkLiveBlock .lkNextTop'), 'Portrait live layout does not cover '+width+' px');
    });
    assert(!landscape.includes('.lkLiveBlock .lkNextTop'), 'Portrait live layout leaked into landscape');
  });
  await test('calendar contract: procedures target Procedury and meals target Jídlo', async function() {
    const schedule = runtime.api.normalizeSchedule(productionSchedule);
    const events = runtime.api.calendarContract(schedule);
    const procedure = events.find(function(event) { return event.kind === 'procedure'; });
    const meal = events.find(function(event) { return event.kind === 'meal'; });
    assert(procedure.targetCalendar === 'Procedury', 'Procedure target calendar is incorrect');
    assert(meal.targetCalendar === 'Jídlo', 'Meal target calendar is incorrect');
  });
  await test('calendar contract: stable identifiers produce deterministic duplicate-safe metadata', async function() {
    const schedule = runtime.api.normalizeSchedule(productionSchedule);
    const original = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-magnet'; });
    const contract = runtime.api.calendarContract(schedule);
    const originalContract = contract.find(function(event) { return event.stableId === original.stableId; });
    const corrected = clone(schedule);
    corrected.events.find(function(event) { return event.stableId === original.stableId; }).start = '08:25';
    const correctedContract = runtime.api.calendarContract(corrected).find(function(event) { return event.stableId === original.stableId; });
    const otherContract = contract.find(function(event) { return event.stableId !== original.stableId; });
    assert(originalContract.syncKey === 'lc:'+original.stableId, 'syncKey is not deterministic');
    assert(originalContract.descriptionMarker === '[LC:'+original.stableId+']', 'Description marker does not contain stableId');
    assert(correctedContract.syncKey === originalContract.syncKey, 'Time correction changed syncKey');
    assert(otherContract.syncKey !== originalContract.syncKey, 'Different stable IDs share syncKey');
    assert(originalContract.managedBy === 'lazensky-commander', 'Managed-by marker is missing');
  });
  await test('calendar contract: timezone, lead time and source schedule are preserved', async function() {
    const schedule = runtime.api.normalizeSchedule(productionSchedule);
    const before = JSON.stringify(schedule);
    const contract = runtime.api.calendarContract(schedule);
    const bath = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-bath'; });
    const bathContract = contract.find(function(event) { return event.stableId === bath.stableId; });
    assert(contract.every(function(event) { return event.timezone === 'Europe/Prague'; }), 'Timezone is not Europe/Prague');
    assert(bathContract.leadTimeMinutes === runtime.api.getEffectiveLeadTime(bath, schedule), 'Effective lead time changed');
    assert(JSON.stringify(schedule) === before, 'calendarContract mutated the source schedule');
  });
  await test('public feed: no private pairing system remains', async function() {
    const names = (await fs.readdir(root, { recursive: true })).filter(function(name) { return !name.split(path.sep).includes('.git'); });
    assert(!names.some(function(name) { return /private-schedule|schedule\.enc|schedule-public-key|device-pairing|\.pk8$|\.pem$|\.key$/i.test(name); }), 'Private pairing artifact remains in repository');
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    const worker = await fs.readFile(path.join(root, 'sw.js'), 'utf8');
    assert(index.includes('public-schedule-feed.js') && !index.includes('private-schedule-feed.js'), 'Application does not load the public feed module');
    assert(/pathname\.endsWith\('\/data\/schedule\.json'\)/.test(worker), 'Service worker may cache the public schedule');
  });

  const failed = cases.filter(function(item) { return !item.ok; });
  return { passed: cases.length - failed.length, failed: failed.length, cases };
}

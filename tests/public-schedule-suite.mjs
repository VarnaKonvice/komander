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

function createRuntime(source, shared) {
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
  vm.runInNewContext(source, sandbox, { filename: 'public-schedule-feed.js' });
  return { api: window.LazenskySchedule, sandbox, listeners };
}

export async function runPublicScheduleSuite(options) {
  const root = options.repoRoot;
  const source = await fs.readFile(path.join(root, 'public-schedule-feed.js'), 'utf8');
  const productionSchedule = JSON.parse(await fs.readFile(path.join(root, 'data/schedule.json'), 'utf8'));
  const cases = [];
  async function test(name, run) {
    try { await run(); cases.push({ name, ok: true }); }
    catch (error) { cases.push({ name, ok: false, error: error.message }); }
  }

  const shared = { localStorage: createLocalStorage(), fetch: null };
  let activeSchedule = clone(productionSchedule);
  shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(activeSchedule); } }; };
  const runtime = createRuntime(source, shared);

  await test('public feed: production schedule validates', async function() {
    runtime.api.validateSchedule(runtime.api.normalizeSchedule(productionSchedule));
    assert(productionSchedule.scheduleVersion === 4, 'Unexpected production scheduleVersion');
    assert(productionSchedule.events.some(function(event) { return event.kind === 'meal'; }), 'Meals are missing');
    assert(productionSchedule.events.some(function(event) { return event.kind === 'procedure'; }), 'Procedures are missing');
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
    const reloaded = createRuntime(source, shared);
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
    const legacyRuntime = createRuntime(source, legacyOnly);
    assert(legacyRuntime.api.getSchedule() === null, 'Legacy storage became a canonical schedule source');
  });
  await test('legacy inline Commander starts and refreshes from the canonical API', async function() {
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    assert(index.indexOf('public-schedule-feed.js') < index.indexOf("var VERSION='"), 'Public schedule API is not available before inline Commander startup');
    assert(index.includes('api&&api.getSchedule&&api.toLegacySchedule'), 'Inline Commander does not read the canonical schedule API');
    assert(index.includes("window.addEventListener('lazensky-schedule-change'"), 'Inline Commander does not refresh after a canonical schedule update');
    assert(!index.includes('localStorage.getItem(STORE)'), 'Inline Commander still reads v10 as its schedule source');
    assert(!index.includes('lazensky_commander_schedule_v10'), 'Inline Commander still owns the legacy schedule store');
    assert(!index.includes('localStorage.setItem(STORE,JSON.stringify(data))'), 'Inline Commander can still create a local schedule source');
    assert(index.includes("alert('Rozpis se načítá z data/schedule.json.')"), 'Legacy schedule import is not disabled');
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

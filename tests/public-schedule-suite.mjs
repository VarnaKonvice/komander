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

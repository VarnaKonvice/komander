import { Buffer } from 'node:buffer';
import { webcrypto } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function createLocalStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); }
  };
}

function createIndexedDb() {
  const stores = new Map();
  let initialized = false;
  const db = {
    objectStoreNames: { contains(name) { return stores.has(name); } },
    createObjectStore(name) { if (!stores.has(name)) stores.set(name, new Map()); },
    transaction(name) {
      const store = stores.get(name);
      if (!store) throw new Error('Missing IndexedDB store ' + name);
      return { objectStore() { return {
        get(key) {
          const request = {};
          queueMicrotask(function() { request.result = store.has(key) ? store.get(key) : undefined; if (request.onsuccess) request.onsuccess(); });
          return request;
        },
        put(value, key) {
          const request = {};
          queueMicrotask(function() { store.set(key, value); if (request.onsuccess) request.onsuccess(); });
          return request;
        },
        delete(key) {
          const request = {};
          queueMicrotask(function() { store.delete(key); if (request.onsuccess) request.onsuccess(); });
          return request;
        }
      }; } };
    }
  };
  return {
    open() {
      const request = {};
      queueMicrotask(function() {
        request.result = db;
        if (!initialized) { initialized = true; if (request.onupgradeneeded) request.onupgradeneeded(); }
        if (request.onsuccess) request.onsuccess();
      });
      return request;
    }
  };
}

function createRuntime(source, shared, hash) {
  const location = { hash: hash || '', pathname: '/tests/private-schedule-suite.html', search: '' };
  const history = { replaceState(_state, _title, value) { location.hash = ''; location.pathname = String(value).split('?')[0] || '/'; location.search = String(value).indexOf('?') >= 0 ? '?' + String(value).split('?')[1] : ''; } };
  const document = { readyState: 'loading', currentScript: { src: 'https://unit.test/komander/private-schedule-feed.js' }, addEventListener() {} };
  const window = {
    __lkDisableAutoSync: true,
    crypto: webcrypto,
    indexedDB: shared.indexedDb,
    isSecureContext: true,
    location,
    addEventListener() {},
    dispatchEvent() {}
  };
  const sandbox = {
    window, document, location, history, crypto: webcrypto, indexedDB: shared.indexedDb,
    localStorage: shared.localStorage, fetch: shared.fetch, URL, URLSearchParams, TextEncoder,
    TextDecoder, ArrayBuffer, Uint8Array, Event: class Event { constructor(type) { this.type = type; } },
    btoa(value) { return Buffer.from(value, 'binary').toString('base64'); },
    atob(value) { return Buffer.from(value, 'base64').toString('binary'); },
    console, queueMicrotask, setTimeout, clearTimeout
  };
  vm.runInNewContext(source, sandbox, { filename: 'private-schedule-feed.js' });
  return { api: window.LazenskySchedule, location, sandbox };
}

function rejectWith(api, feed, expected) {
  try { api.validateFeed(feed); } catch (error) { assert(error.message === expected, 'Expected ' + expected + ', got ' + error.message); return; }
  throw new Error('Malformed feed was accepted: ' + expected);
}

export async function runPrivateScheduleSuite(options) {
  const root = options.repoRoot;
  const privateKeyPath = options.privateKeyPath;
  const source = await fs.readFile(path.join(root, 'private-schedule-feed.js'), 'utf8');
  const fixture = JSON.parse(await fs.readFile(path.join(root, 'fixtures/confirmed-schedule.synthetic.json'), 'utf8'));
  const publicKey = JSON.parse(await fs.readFile(path.join(root, 'data/schedule-public-key.json'), 'utf8'));
  const actualFeed = JSON.parse(await fs.readFile(path.join(root, 'data/schedule.enc.json'), 'utf8'));
  const actualPairingPackage = JSON.parse(await fs.readFile(path.join(root, 'data/device-pairing.enc.json'), 'utf8'));
  const privateKey = await fs.readFile(privateKeyPath);
  const cases = [];
  async function test(name, run) {
    try { await run(); cases.push({ name, ok: true }); }
    catch (error) { cases.push({ name, ok: false, error: error.message }); }
  }

  const shared = { indexedDb: createIndexedDb(), localStorage: createLocalStorage(), fetch: null };
  const deviceShared = { indexedDb: createIndexedDb(), localStorage: createLocalStorage(), fetch: null };
  const pairingToken = base64Url(privateKey);
  const pairingSecret = options.pairingSecretPath ? (await fs.readFile(options.pairingSecretPath, 'utf8')).trim() : Buffer.from(webcrypto.getRandomValues(new Uint8Array(16))).toString('hex');
  const primary = createRuntime(source, shared, '#pair=' + pairingToken);
  const api = primary.api;

  await test('crypto: Base64URL accepts ArrayBuffer and Uint8Array', async function() {
    const bytes = new Uint8Array([0, 1, 2, 253, 254, 255]);
    const encoded = api.bytesToBase64Url(bytes.buffer);
    assert(encoded === api.bytesToBase64Url(bytes), 'ArrayBuffer and Uint8Array differ');
    assert(Buffer.compare(Buffer.from(api.base64UrlToBytes(encoded)), Buffer.from(bytes)) === 0, 'Base64URL round-trip failed');
  });
  await test('pairing: PKCS8 import, fragment removal and non-extractable key', async function() {
    assert(await api.consumePairingFragment(), 'Pairing fragment was not consumed');
    assert(primary.location.hash === '', 'Pairing fragment remained in the URL');
    assert(await api.privateKeyAvailable(), 'Private key was not persisted');
    assert(await api.privateKeyIsNonExtractable(), 'Private key is extractable');
  });
  const restored = createRuntime(source, shared, '');
  await test('pairing: IndexedDB restores the private key after reload', async function() {
    assert(await restored.api.privateKeyAvailable(), 'Private key did not survive reload');
    assert(await restored.api.privateKeyIsNonExtractable(), 'Restored key is extractable');
  });
  const device = createRuntime(source, deviceShared, '');
  let devicePairingPackage;
  await test('device pairing: unpaired device cannot sync', async function() {
    assert(!(await device.api.privateKeyAvailable()), 'Fresh device already has a private key');
    const result = await device.api.refreshPrivateSchedule();
    assert(result.status === 'unpaired', 'Fresh device did not remain unpaired');
  });
  await test('device pairing: package encrypts the private key without storing pairing material', async function() {
    devicePairingPackage = options.pairingSecretPath ? actualPairingPackage : await device.api.createDevicePairingPackage(pairingToken, pairingSecret);
    device.api.validatePairingPackage(devicePairingPackage);
    const serialized = JSON.stringify(devicePairingPackage);
    assert(!serialized.includes('privateKeyPkcs8') && !serialized.includes(pairingSecret), 'Pairing package exposes plaintext pairing material');
  });
  deviceShared.fetch = async function(url) {
    if (String(url).includes('device-pairing.enc.json')) return { ok: true, status: 200, json: async function() { return clone(devicePairingPackage); } };
    return { ok: true, status: 200, json: async function() { return clone(actualFeed); } };
  };
  device.sandbox.fetch = deviceShared.fetch;
  await test('device pairing: wrong secret leaves the device unpaired', async function() {
    try { await device.api.pairDeviceWithSecret('00000000000000000000000000000000'); throw new Error('Wrong pairing secret was accepted'); }
    catch (error) { assert(error.message === 'Párovací kód neodpovídá tomuto zařízení.', error.message); }
    assert(!(await device.api.privateKeyAvailable()), 'Wrong pairing secret stored a key');
  });
  await test('device pairing: correct secret stores a non-extractable key and decrypts the feed', async function() {
    const result = await device.api.pairDeviceWithSecret(pairingSecret);
    assert(result.paired && result.sync && result.sync.status === 'updated', 'Correct pairing did not update the encrypted schedule');
    assert(await device.api.privateKeyAvailable(), 'Correct pairing did not persist the key');
    assert(await device.api.privateKeyIsNonExtractable(), 'Paired key is extractable');
    assert(device.api.getSchedule().scheduleVersion === 4, 'Paired device did not load the schedule');
  });
  const pairedReload = createRuntime(source, deviceShared, '');
  await test('device pairing: key survives reload and removal affects only pairing', async function() {
    assert(await pairedReload.api.privateKeyAvailable(), 'Paired key did not survive reload');
    assert(await pairedReload.api.privateKeyIsNonExtractable(), 'Reloaded paired key is extractable');
    await pairedReload.api.removeDevicePairing();
    assert(!(await pairedReload.api.privateKeyAvailable()), 'Pairing removal did not remove the key');
    assert(pairedReload.api.getSchedule().scheduleVersion === 4, 'Pairing removal removed the valid local schedule');
  });
  await test('device pairing: removed device can pair again', async function() {
    const result = await pairedReload.api.pairDeviceWithSecret(pairingSecret);
    assert(result.paired && result.sync && result.sync.status === 'current', 'Re-pairing did not restore the device');
    assert(await pairedReload.api.privateKeyAvailable(), 'Re-pairing did not restore the private key');
  });
  await test('data: confirmed schedule accepts meals, procedures and a day without procedures', async function() {
    const schedule = api.normalizeSchedule(fixture);
    api.validateSchedule(schedule);
    assert(schedule.events.filter(function(event) { return event.kind === 'meal'; }).length === 9, 'Meals missing');
    assert(schedule.events.filter(function(event) { return event.date === '2026-08-16' && event.kind === 'procedure'; }).length === 0, 'Day without procedures missing');
    assert(new Set(schedule.events.map(function(event) { return event.stableId; })).size === schedule.events.length, 'Stable IDs are not unique');
  });
  await test('data: malformed dates, reversed times and duplicate IDs are rejected', async function() {
    const badDate = clone(fixture); badDate.events[0].date = '2026-02-30';
    try { api.normalizeSchedule(badDate); throw new Error('Invalid date was accepted'); } catch (error) { assert(/platné datum/.test(error.message), error.message); }
    const reversed = clone(fixture); reversed.events[0].start = '10:00'; reversed.events[0].end = '8:00';
    try { api.normalizeSchedule(reversed); throw new Error('Reversed time was accepted'); } catch (error) { assert(/platné datum/.test(error.message), error.message); }
    const duplicate = clone(fixture); duplicate.events[1].stableId = duplicate.events[0].stableId;
    try { api.normalizeSchedule(duplicate); throw new Error('Duplicate ID was accepted'); } catch (error) { assert(/duplicitní/.test(error.message), error.message); }
  });
  let generatedFeed;
  await test('crypto: public key wraps AES key and AES-GCM decrypts the generated schedule', async function() {
    generatedFeed = (await restored.api.createEncryptedFeed(fixture, publicKey)).feed;
    restored.api.validateFeed(generatedFeed);
    assert(generatedFeed.crypto.wrappedKey.length === 512, 'RSA-OAEP wrapped key is empty or unexpected');
    const decrypted = await restored.api.decryptFeed(generatedFeed);
    assert(decrypted.scheduleVersion === fixture.scheduleVersion, 'Generated schedule version changed');
  });
  await test('crypto: malformed envelopes are rejected precisely', async function() {
    ['wrappedKey', 'payloadIv', 'ciphertext'].forEach(function(field) { const feed = clone(generatedFeed); delete feed.crypto[field]; rejectWith(restored.api, feed, 'MISSING: ' + field); });
    const badAlgorithm = clone(generatedFeed); badAlgorithm.crypto.algorithm = 'AES-CBC'; rejectWith(restored.api, badAlgorithm, 'INVALID: algorithm');
    const badBase64 = clone(generatedFeed); badBase64.crypto.wrappedKey = 'A'; rejectWith(restored.api, badBase64, 'INVALID: base64 wrappedKey');
    const extraField = clone(generatedFeed); extraField.crypto.keyIv = 'unused'; rejectWith(restored.api, extraField, 'INVALID: crypto fields');
  });
  await test('crypto: production encrypted feed decrypts and validates', async function() {
    restored.api.validateFeed(actualFeed);
    const decrypted = await restored.api.decryptFeed(actualFeed);
    assert(decrypted.scheduleVersion === 4, 'Expected scheduleVersion 4');
    restored.api.validateSchedule(decrypted);
  });
  await test('lead time: Safari type override regression uses the decrypted production feed', async function() {
    shared.localStorage.removeItem('lazensky_commander_local_settings_v1');
    const decrypted = await restored.api.decryptFeed(actualFeed);
    const bath = decrypted.events.find(function(event) { return event.stableId === 'synthetic-0815-bath'; });
    const decision = restored.api.explainLeadTime(bath, decrypted);
    assert(decision.procedureType === 'Jodobromová koupel', 'Unexpected procedure type');
    assert(decision.normalizedType === 'jodobromová koupel', 'Procedure type was not normalized');
    assert(decision.automaticDefault === 20, 'Unexpected automatic default');
    assert(decision.automaticTypeOverride === 30, 'Production type override was not found');
    assert(decision.automaticEventOverride === null, 'Event override masks the type regression');
    assert(decision.localDefault === null && decision.localTypeOverride === null && decision.localEventOverride === null, 'Local override leaked into the regression case');
    assert(decision.effectiveLeadTimeMinutes === 30 && decision.source === 'type', 'Production type override did not win');
    const calendarEvent = restored.api.calendarContract(decrypted).find(function(event) { return event.stableId === 'synthetic-0815-bath'; });
    assert(calendarEvent.leadTimeMinutes === 30, 'Calendar contract does not use the production lead-time function');
  });
  await test('lead time: automatic, local and event override precedence is complete', async function() {
    const sourceSchedule = clone(fixture);
    sourceSchedule.settings = { defaultLeadTimeMinutes: 20, procedureTypeOverrides: { ' JODOBROMOVÁ KOUPEL ': 30 }, mealOverrides: { 'SNÍDANĚ': 15, 'OBĚD': 16, 'VEČEŘE': 17 } };
    sourceSchedule.events[2].procedureType = '  jodobromová koupel  '; sourceSchedule.events[2].leadTimeMinutes = 25;
    const schedule = restored.api.normalizeSchedule(sourceSchedule);
    const bath = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-bath'; });
    const breakfast = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-breakfast'; });
    const lunch = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-lunch'; });
    const dinner = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-dinner'; });
    const massage = schedule.events.find(function(event) { return event.stableId === 'synthetic-0815-massage'; });
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({}));
    assert(restored.api.getEffectiveLeadTime(bath, schedule) === 25, 'Automatic event override lost');
    assert(restored.api.getEffectiveLeadTime(massage, schedule) === 20, 'Automatic default lost');
    assert(restored.api.getEffectiveLeadTime(breakfast, schedule) === 15, 'Breakfast override lost');
    assert(restored.api.getEffectiveLeadTime(lunch, schedule) === 16, 'Lunch override lost');
    assert(restored.api.getEffectiveLeadTime(dinner, schedule) === 17, 'Dinner override lost');
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ defaultLeadTimeMinutes: 0, procedureTypeOverrides: { '  JODOBROMOVÁ KOUPEL ': 11 }, mealOverrides: { ' snídaně ': 12 }, eventOverrides: {} }));
    assert(restored.api.getEffectiveLeadTime(bath, schedule) === 11, 'Local type override lost');
    assert(restored.api.getEffectiveLeadTime(breakfast, schedule) === 12, 'Local meal type override lost');
    assert(restored.api.getEffectiveLeadTime(massage, schedule) === 0, 'Local default value 0 lost');
    shared.localStorage.setItem('lazensky_commander_local_settings_v1', JSON.stringify({ defaultLeadTimeMinutes: 0, procedureTypeOverrides: { 'jodobromová koupel': 11 }, mealOverrides: {}, eventOverrides: { 'synthetic-0815-bath': 7 } }));
    assert(restored.api.getEffectiveLeadTime(bath, schedule) === 7, 'Local event override lost');
  });
  await test('sync: first load, same version, newer version, invalid newer feed, offline and recovery', async function() {
    shared.localStorage.removeItem('lazensky_commander_confirmed_schedule_v1');
    shared.localStorage.removeItem('lazensky_commander_schedule_v10');
    shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(actualFeed); } }; };
    restored.sandbox.fetch = shared.fetch;
    let result = await restored.api.refreshPrivateSchedule(); assert(result.status === 'updated' && result.scheduleVersion === 4, 'First sync failed');
    result = await restored.api.refreshPrivateSchedule(); assert(result.status === 'current', 'Same version did not remain current');
    const newerSchedule = clone(fixture); newerSchedule.scheduleVersion = 5; newerSchedule.updatedAt = '2026-08-16T10:00:00.000Z';
    const newerFeed = (await restored.api.createEncryptedFeed(newerSchedule, publicKey)).feed;
    shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(newerFeed); } }; }; restored.sandbox.fetch = shared.fetch;
    result = await restored.api.refreshPrivateSchedule(); assert(result.status === 'updated' && result.scheduleVersion === 5, 'Newer version was not applied');
    const tampered = clone(newerFeed); tampered.scheduleVersion = 6; tampered.crypto.ciphertext = tampered.crypto.ciphertext.slice(0, -1) + (tampered.crypto.ciphertext.endsWith('A') ? 'B' : 'A');
    shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(tampered); } }; }; restored.sandbox.fetch = shared.fetch;
    try { await restored.api.refreshPrivateSchedule(); throw new Error('Tampered newer feed was accepted'); } catch (error) { assert(restored.api.getSchedule().scheduleVersion === 5, 'Invalid feed replaced last-good schedule'); }
    shared.fetch = async function() { throw new Error('offline'); }; restored.sandbox.fetch = shared.fetch;
    try { await restored.api.refreshPrivateSchedule(); } catch (error) {}
    assert(restored.api.getSchedule().scheduleVersion === 5, 'Offline state replaced last-good schedule');
    const recoveredSchedule = clone(fixture); recoveredSchedule.scheduleVersion = 6; recoveredSchedule.updatedAt = '2026-08-16T11:00:00.000Z';
    const recoveredFeed = (await restored.api.createEncryptedFeed(recoveredSchedule, publicKey)).feed;
    shared.fetch = async function() { return { ok: true, status: 200, json: async function() { return clone(recoveredFeed); } }; }; restored.sandbox.fetch = shared.fetch;
    result = await restored.api.refreshPrivateSchedule(); assert(result.status === 'updated' && result.scheduleVersion === 6, 'Online recovery failed');
  });
  await test('security: feed has no plaintext or private material and service worker bypasses it', async function() {
    const feedText = await fs.readFile(path.join(root, 'data/schedule.enc.json'), 'utf8');
    const pairingPackageText = await fs.readFile(path.join(root, 'data/device-pairing.enc.json'), 'utf8');
    assert(!/keyIv|PRIVATE KEY|BEGIN [A-Z ]*PRIVATE|Magnetoterapie|Testovací lázně/.test(feedText), 'Encrypted feed contains forbidden material');
    assert(!/privateKeyPkcs8|PRIVATE KEY|BEGIN [A-Z ]*PRIVATE/.test(pairingPackageText), 'Pairing package contains plaintext private material');
    assert(!pairingPackageText.includes(pairingSecret), 'Pairing package contains the pairing secret');
    const names = await fs.readdir(root, { recursive: true });
    assert(!names.some(function(name) { return /\.(pem|pk8|p8|key)$/i.test(name); }), 'Private key file found in repository');
    const worker = await fs.readFile(path.join(root, 'sw.js'), 'utf8');
    assert(/pathname\.endsWith\('\/data\/schedule\.enc\.json'\)/.test(worker), 'Service worker may cache encrypted feed');
    assert(/pathname\.endsWith\('\/data\/device-pairing\.enc\.json'\)/.test(worker), 'Service worker may cache pairing material');
  });
  await test('ui regression: locked views remain present and the shared module is loaded before the enhancer', async function() {
    const index = await fs.readFile(path.join(root, 'index.html'), 'utf8');
    const overview = await fs.readFile(path.join(root, 'day-overview-v1.js'), 'utf8');
    assert(index.indexOf('private-schedule-feed.js') < index.indexOf('day-overview-v1.js'), 'Private module loads after the UI enhancer');
    ['renderOverview', 'renderStayOverview', 'enhanceStayView', 'enhanceImportView'].forEach(function(name) { assert(overview.includes(name), 'Missing locked UI function ' + name); });
  });

  const failed = cases.filter(function(item) { return !item.ok; });
  return { passed: cases.length - failed.length, failed: failed.length, cases };
}

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import {
  googleEventResource,
  isOwnedGoogleEvent,
  synchronizeCalendarProjection
} from '../calendar-sync/calendar-reconciliation.mjs';
import {
  projectCanonicalSchedule,
  validateCanonicalSchedule
} from '../calendar-sync/schedule-projection.mjs';
import {
  GoogleCalendarAdapter,
  readWriteConfiguration
} from '../calendar-sync/google-calendar-adapter.mjs';
import { runCalendarSync } from '../calendar-sync/sync-google-calendar.mjs';

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

class FakeCalendarAdapter {
  constructor(seed = {}) {
    this.events = {
      Procedury: clone(seed.Procedury || []),
      'Jídlo': clone(seed['Jídlo'] || [])
    };
    this.writes = [];
    this.nextId = 1;
  }

  async listEvents(calendarName) {
    return clone(this.events[calendarName]);
  }

  async createEvent(calendarName, resource) {
    const id = `fake-${this.nextId++}`;
    this.events[calendarName].push({ id, ...clone(resource) });
    this.writes.push({ action: 'create', calendarName, id });
  }

  async updateEvent(calendarName, eventId, resource) {
    const index = this.events[calendarName].findIndex(event => event.id === eventId);
    if (index < 0) throw new Error(`Fake event ${eventId} does not exist.`);
    this.events[calendarName][index] = { id: eventId, ...clone(resource) };
    this.writes.push({ action: 'update', calendarName, id: eventId });
  }

  async deleteEvent(calendarName, eventId) {
    const before = this.events[calendarName].length;
    this.events[calendarName] = this.events[calendarName].filter(event => event.id !== eventId);
    if (before === this.events[calendarName].length) throw new Error(`Fake event ${eventId} does not exist.`);
    this.writes.push({ action: 'delete', calendarName, id: eventId });
  }
}

function oneEventSchedule(schedule, event) {
  const result = clone(schedule);
  result.scheduleVersion += 1;
  result.updatedAt = '2026-08-22T12:00:00.000Z';
  result.events = [clone(event)];
  return result;
}

function storedEvent(event, id = `google-${event.stableId}`) {
  return { id, ...googleEventResource(event) };
}

export async function runCalendarSyncSuite({ repoRoot }) {
  const productionSchedule = JSON.parse(await fs.readFile(path.join(repoRoot, 'data/schedule.json'), 'utf8'));
  const iconMap = JSON.parse(await fs.readFile(path.join(repoRoot, 'assets/icons/lazensky-v1/icon-map.json'), 'utf8'));
  const productionProjection = await projectCanonicalSchedule({ repoRoot, schedule: productionSchedule });
  const procedureSource = productionSchedule.events.find(event => event.kind === 'procedure');
  const mealSource = productionSchedule.events.find(event => event.kind === 'meal');
  const cases = [];

  async function test(name, run) {
    try {
      await run();
      cases.push({ name, ok: true });
    } catch (error) {
      cases.push({ name, ok: false, error: error instanceof Error ? error.message : String(error) });
    }
  }

  await test('A: a procedure targets Procedury', async () => {
    const projected = await projectCanonicalSchedule({ repoRoot, schedule: oneEventSchedule(productionSchedule, procedureSource) });
    assert(projected.events.length === 1 && projected.events[0].targetCalendar === 'Procedury', 'Procedure target is incorrect.');
  });

  await test('B: a meal targets Jidlo', async () => {
    const projected = await projectCanonicalSchedule({ repoRoot, schedule: oneEventSchedule(productionSchedule, mealSource) });
    assert(projected.events.length === 1 && projected.events[0].targetCalendar === 'Jídlo', 'Meal target is incorrect.');
  });

  await test('C: a new canonical event is created', async () => {
    const adapter = new FakeCalendarAdapter();
    const result = await synchronizeCalendarProjection({ desiredEvents: [productionProjection.events[0]], adapter, dryRun: false });
    assert(result.created === 1 && result.updated === 0 && result.deleted === 0, 'New event did not produce one create.');
    assert(adapter.writes.length === 1 && adapter.writes[0].action === 'create', 'Create was not the only write.');
  });

  await test('D: changing time for the same stableId produces update', async () => {
    const original = clone(productionProjection.events.find(event => event.kind === 'procedure'));
    const changed = { ...original, start: `${original.start.slice(0, 11)}11:05:00`, end: `${original.end.slice(0, 11)}11:25:00` };
    const adapter = new FakeCalendarAdapter({ Procedury: [storedEvent(original)] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [changed], adapter, dryRun: false });
    assert(result.updated === 1 && adapter.writes[0].action === 'update', 'Time change did not produce update.');
  });

  await test('E: changing title or location produces update', async () => {
    const original = clone(productionProjection.events.find(event => event.kind === 'procedure'));
    const changed = { ...original, title: `${original.title} - upraveno`, location: 'Nova mistnost' };
    const adapter = new FakeCalendarAdapter({ Procedury: [storedEvent(original)] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [changed], adapter, dryRun: false });
    assert(result.updated === 1 && adapter.writes[0].action === 'update', 'Title/location change did not produce update.');
  });

  await test('F: removing a managed event produces delete', async () => {
    const original = productionProjection.events.find(event => event.kind === 'procedure');
    const adapter = new FakeCalendarAdapter({ Procedury: [storedEvent(original)] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [], adapter, dryRun: false });
    assert(result.deleted === 1 && adapter.writes[0].action === 'delete', 'Removed event did not produce delete.');
  });

  await test('G: a second identical sync performs zero writes', async () => {
    const desired = [productionProjection.events[0]];
    const adapter = new FakeCalendarAdapter();
    await synchronizeCalendarProjection({ desiredEvents: desired, adapter, dryRun: false });
    adapter.writes = [];
    const result = await synchronizeCalendarProjection({ desiredEvents: desired, adapter, dryRun: false });
    assert(result.created === 0 && result.updated === 0 && result.deleted === 0 && result.unchanged === 1, 'Second sync is not idempotent.');
    assert(adapter.writes.length === 0, 'Second sync performed a write.');
  });

  await test('H: a foreign Google event is untouched', async () => {
    const foreign = { id: 'foreign', summary: 'Soukroma udalost' };
    const adapter = new FakeCalendarAdapter({ Procedury: [foreign] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [], adapter, dryRun: false });
    assert(result.deleted === 0 && adapter.writes.length === 0 && adapter.events.Procedury.length === 1, 'Foreign event was modified.');
  });

  await test('I: an event managed by another system is untouched', async () => {
    const foreign = {
      id: 'other-managed',
      extendedProperties: { private: { managedBy: 'other-system', stableId: 'x', syncKey: 'lc:x' } }
    };
    const adapter = new FakeCalendarAdapter({ Procedury: [foreign] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [], adapter, dryRun: false });
    assert(!isOwnedGoogleEvent(foreign) && result.deleted === 0 && adapter.writes.length === 0, 'Other managed event was modified.');
  });

  await test('J: changing meal to procedure moves the event between calendars', async () => {
    const original = clone(productionProjection.events.find(event => event.kind === 'meal'));
    const moved = { ...original, kind: 'procedure', mealType: null, procedureType: 'Rehabilitace', targetCalendar: 'Procedury' };
    const adapter = new FakeCalendarAdapter({ 'Jídlo': [storedEvent(original)] });
    const result = await synchronizeCalendarProjection({ desiredEvents: [moved], adapter, dryRun: false });
    assert(result.created === 1 && result.deleted === 1 && result.updated === 0, 'Kind change did not produce create and delete.');
    assert(adapter.writes.some(write => write.action === 'create' && write.calendarName === 'Procedury'), 'Moved event was not created in Procedury.');
    assert(adapter.writes.some(write => write.action === 'delete' && write.calendarName === 'Jídlo'), 'Old meal event was not deleted from Jidlo.');
  });

  await test('K: past canonical events remain in the desired calendar set', async () => {
    const adapter = new FakeCalendarAdapter();
    const result = await synchronizeCalendarProjection({ desiredEvents: productionProjection.events, adapter, dryRun: false });
    assert(result.desired === productionSchedule.events.length && result.created === productionSchedule.events.length, 'Past events were filtered from calendar sync.');
  });

  await test('L: every Google event uses Europe/Prague', async () => {
    for (const event of productionProjection.events) {
      const resource = googleEventResource(event);
      assert(resource.start.timeZone === 'Europe/Prague' && resource.end.timeZone === 'Europe/Prague', `Timezone differs for ${event.stableId}.`);
    }
  });

  await test('M: Google reminders are disabled', async () => {
    const resource = googleEventResource(productionProjection.events[0]);
    assert(resource.reminders.useDefault === false && resource.reminders.overrides.length === 0, 'Google reminders are enabled.');
  });

  await test('N: Google events contain no attendees or Meet data', async () => {
    const resource = googleEventResource(productionProjection.events[0]);
    assert(!Object.hasOwn(resource, 'attendees') && !Object.hasOwn(resource, 'conferenceData') && !Object.hasOwn(resource, 'hangoutLink'), 'Attendee or Meet data is present.');
  });

  await test('O: private extended properties contain strict ownership identity', async () => {
    const event = productionProjection.events[0];
    const properties = googleEventResource(event).extendedProperties.private;
    assert(properties.managedBy === 'lazensky-commander', 'managedBy is missing.');
    assert(properties.stableId === event.stableId && properties.syncKey === `lc:${event.stableId}`, 'Stable ownership identity is incorrect.');
  });

  await test('P: an unknown procedure keeps default Google color', async () => {
    const unknown = clone(procedureSource);
    unknown.stableId = 'unknown-procedure';
    unknown.title = 'Neznama pece XYZ';
    unknown.procedureType = 'Neznama pece XYZ';
    const projection = await projectCanonicalSchedule({ repoRoot, schedule: oneEventSchedule(productionSchedule, unknown) });
    const resource = googleEventResource(projection.events[0]);
    assert(projection.events[0].iconKey === null && projection.events[0].colorId === null, 'Unknown procedure was classified.');
    assert(!Object.hasOwn(resource, 'colorId'), 'Unknown procedure received a Google colorId.');
  });

  await test('Q: all 12 approved icon keys have deterministic Google colors', async () => {
    const schedule = clone(productionSchedule);
    schedule.events = iconMap.icons.map((icon, index) => {
      const meal = icon.key.startsWith('meal_');
      const title = icon.keywords[0];
      return {
        stableId: `icon-${icon.key}`,
        date: `2026-09-${String(index + 1).padStart(2, '0')}`,
        start: '10:00',
        end: '10:30',
        title,
        location: 'Test',
        kind: meal ? 'meal' : 'procedure',
        ...(meal ? { mealType: title } : { procedureType: title })
      };
    });
    const first = await projectCanonicalSchedule({ repoRoot, schedule });
    const second = await projectCanonicalSchedule({ repoRoot, schedule });
    assert(first.events.length === 12, 'Projection does not contain all approved icons.');
    for (const configured of iconMap.icons) {
      const projected = first.events.find(event => event.stableId === `icon-${configured.key}`);
      assert(projected && projected.iconKey === configured.key, `Icon ${configured.key} was not classified by the existing visual contract.`);
      assert(projected.colorId === configured.googleCalendarColorId, `Icon ${configured.key} has an incorrect colorId.`);
    }
    assert(JSON.stringify(first.events) === JSON.stringify(second.events), 'Google color projection is not deterministic.');
  });

  await test('R: malformed schedule fails before any write', async () => {
    const malformed = clone(productionSchedule);
    malformed.events[0].end = 'invalid';
    const adapter = new FakeCalendarAdapter();
    let failed = false;
    try {
      validateCanonicalSchedule(malformed);
      const projection = await projectCanonicalSchedule({ repoRoot, schedule: malformed });
      await synchronizeCalendarProjection({ desiredEvents: projection.events, adapter, dryRun: false });
    } catch {
      failed = true;
    }
    assert(failed && adapter.writes.length === 0, 'Malformed schedule reached a write.');
  });

  await test('S: missing write configuration fails before adapter creation or write', async () => {
    let factoryCalls = 0;
    let failed = false;
    try {
      await runCalendarSync({
        repoRoot,
        argv: ['--write'],
        env: {},
        adapterFactory: async () => {
          factoryCalls += 1;
          return new FakeCalendarAdapter();
        }
      });
    } catch (error) {
      failed = /LC_GOOGLE_SERVICE_ACCOUNT_JSON/.test(error.message);
    }
    assert(failed && factoryCalls === 0, 'Missing configuration did not fail before adapter creation.');
  });

  await test('dry-run validates and reconciles without writes', async () => {
    const adapter = new FakeCalendarAdapter();
    const result = await synchronizeCalendarProjection({ desiredEvents: productionProjection.events, adapter, dryRun: true });
    assert(result.created === productionProjection.events.length, 'Dry-run did not create the expected plan.');
    assert(adapter.writes.length === 0, 'Dry-run performed a write.');
  });

  await test('write configuration and Google adapter requests stay environment-driven', async () => {
    const configuration = readWriteConfiguration({
      LC_GOOGLE_SERVICE_ACCOUNT_JSON: JSON.stringify({ type: 'service_account', client_email: 'calendar@example.invalid', private_key: 'private-key' }),
      LC_GOOGLE_CALENDAR_PROCEDURES_ID: 'procedures-id',
      LC_GOOGLE_CALENDAR_MEALS_ID: 'meals-id'
    });
    assert(configuration.calendarIds.Procedury === 'procedures-id' && configuration.calendarIds['Jídlo'] === 'meals-id', 'Calendar IDs were not read from the environment.');
    const requests = [];
    const authClient = { async request(options) { requests.push(options); return { data: { items: [] } }; } };
    const adapter = new GoogleCalendarAdapter(authClient, configuration.calendarIds);
    await adapter.listEvents('Procedury');
    await adapter.createEvent('Jídlo', googleEventResource(productionProjection.events.find(event => event.kind === 'meal')));
    assert(requests[0].url.includes('privateExtendedProperty=managedBy%3Dlazensky-commander'), 'Managed-event list filter is missing.');
    assert(requests[1].url.includes('sendUpdates=none'), 'Google write may send attendee updates.');
  });

  const failed = cases.filter(item => !item.ok);
  return { passed: cases.length - failed.length, failed: failed.length, cases };
}

async function main() {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const result = await runCalendarSyncSuite({ repoRoot });
  console.log(JSON.stringify(result, null, 2));
  if (result.failed) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();

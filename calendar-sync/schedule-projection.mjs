import fs from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';

function requiredText(value, field) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`Canonical schedule is missing ${field}.`);
  return value.trim();
}

function validDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
  if (!match) return false;
  const date = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return date.getUTCFullYear() === Number(match[1]) && date.getUTCMonth() === Number(match[2]) - 1 && date.getUTCDate() === Number(match[3]);
}

function clockMinutes(value) {
  const match = /^(\d{2}):(\d{2})$/.exec(value || '');
  if (!match) return -1;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour <= 23 && minute <= 59 ? hour * 60 + minute : -1;
}

function validateMinutes(value, field) {
  if (!Number.isInteger(value) || value < 0 || value > 180) throw new Error(`Canonical schedule has invalid ${field}.`);
}

function validateMinuteMap(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`Canonical schedule is missing ${field}.`);
  for (const [key, minutes] of Object.entries(value)) {
    requiredText(key, `${field} key`);
    validateMinutes(minutes, `${field}.${key}`);
  }
}

export function validateCanonicalSchedule(schedule) {
  if (!schedule || typeof schedule !== 'object' || Array.isArray(schedule)) throw new Error('Canonical schedule must be an object.');
  if (schedule.schemaVersion !== 1) throw new Error('Canonical schedule must use schemaVersion 1.');
  if (!Number.isSafeInteger(schedule.scheduleVersion) || schedule.scheduleVersion < 1) throw new Error('Canonical schedule must have a positive scheduleVersion.');
  if (typeof schedule.updatedAt !== 'string' || Number.isNaN(Date.parse(schedule.updatedAt))) throw new Error('Canonical schedule has invalid updatedAt.');
  if (!schedule.stay || typeof schedule.stay !== 'object' || Array.isArray(schedule.stay)) throw new Error('Canonical schedule is missing stay.');
  if (!schedule.settings || typeof schedule.settings !== 'object' || Array.isArray(schedule.settings)) throw new Error('Canonical schedule is missing settings.');
  validateMinutes(schedule.settings.defaultLeadTimeMinutes, 'settings.defaultLeadTimeMinutes');
  validateMinuteMap(schedule.settings.procedureTypeOverrides, 'settings.procedureTypeOverrides');
  validateMinuteMap(schedule.settings.mealOverrides, 'settings.mealOverrides');
  if (!Array.isArray(schedule.events)) throw new Error('Canonical schedule events must be an array.');

  const stableIds = new Set();
  for (const event of schedule.events) {
    if (!event || typeof event !== 'object' || Array.isArray(event)) throw new Error('Canonical schedule contains an invalid event.');
    const stableId = requiredText(event.stableId, 'events[].stableId');
    if (stableIds.has(stableId)) throw new Error(`Canonical schedule contains duplicate stableId ${stableId}.`);
    stableIds.add(stableId);
    requiredText(event.title, `event ${stableId} title`);
    requiredText(event.location, `event ${stableId} location`);
    if (event.kind !== 'procedure' && event.kind !== 'meal') throw new Error(`Canonical event ${stableId} has invalid kind.`);
    if (!validDate(event.date)) throw new Error(`Canonical event ${stableId} has invalid date.`);
    const start = clockMinutes(event.start);
    const end = clockMinutes(event.end);
    if (start < 0 || end < start) throw new Error(`Canonical event ${stableId} has invalid time range.`);
    if (event.leadTimeMinutes != null) validateMinutes(event.leadTimeMinutes, `event ${stableId} leadTimeMinutes`);
  }
  return schedule;
}

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); }
  };
}

export async function loadPublicScheduleRuntime(repoRoot) {
  const [calendarSource, scheduleSource] = await Promise.all([
    fs.readFile(path.join(repoRoot, 'calendar-contract.js'), 'utf8'),
    fs.readFile(path.join(repoRoot, 'public-schedule-feed.js'), 'utf8')
  ]);
  const listeners = {};
  const window = {
    location: { pathname: '/', search: '', hash: '' },
    addEventListener(type, listener) { listeners[type] = listener; },
    dispatchEvent() {}
  };
  const document = {
    readyState: 'loading',
    currentScript: { src: 'https://calendar-sync.invalid/public-schedule-feed.js' },
    addEventListener(type, listener) { listeners[`document:${type}`] = listener; }
  };
  const sandbox = {
    window,
    document,
    location: window.location,
    localStorage: memoryStorage(),
    fetch: async function() { throw new Error('Calendar projection must not fetch.'); },
    URL,
    TextEncoder,
    Event: class Event { constructor(type) { this.type = type; } },
    console,
    setTimeout,
    clearTimeout
  };
  vm.runInNewContext(calendarSource, sandbox, { filename: 'calendar-contract.js' });
  vm.runInNewContext(scheduleSource, sandbox, { filename: 'public-schedule-feed.js' });
  if (!window.LazenskySchedule || !window.LazenskyCalendarContract) throw new Error('Shared public schedule runtime did not initialize.');
  return window.LazenskySchedule;
}

export function validateVisualContract(iconMap, colors) {
  if (!iconMap || iconMap.version !== 1 || !Array.isArray(iconMap.icons) || iconMap.icons.length !== 12) throw new Error('Icon Set v1 must contain exactly 12 approved keys.');
  if (!colors || !colors.brand || !colors.procedures) throw new Error('Visual color contract is invalid.');
  const keys = new Set();
  for (const icon of iconMap.icons) {
    if (!icon.key || keys.has(icon.key)) throw new Error('Icon map contains a missing or duplicate key.');
    keys.add(icon.key);
    if (!/^(?:[1-9]|10|11)$/.test(icon.googleCalendarColorId || '')) throw new Error(`Icon ${icon.key} is missing a valid Google Calendar colorId.`);
    const colorKey = icon.key.startsWith('meal_') ? 'meal' : icon.key;
    if (colors.procedures[colorKey] !== icon.accent) throw new Error(`Icon ${icon.key} differs from colors.json.`);
  }
  if (!iconMap.fallback || iconMap.fallback.key !== null) throw new Error('Unknown procedures must keep the neutral fallback.');
  return true;
}

export async function projectCanonicalSchedule({ repoRoot, schedule }) {
  validateCanonicalSchedule(schedule);
  const [scheduleApi, iconMap, colors] = await Promise.all([
    loadPublicScheduleRuntime(repoRoot),
    fs.readFile(path.join(repoRoot, 'assets/icons/lazensky-v1/icon-map.json'), 'utf8').then(JSON.parse),
    fs.readFile(path.join(repoRoot, 'assets/icons/lazensky-v1/colors.json'), 'utf8').then(JSON.parse)
  ]);
  validateVisualContract(iconMap, colors);
  const normalized = scheduleApi.normalizeSchedule(schedule, { defaultVersion: schedule.scheduleVersion });
  const calendarEvents = scheduleApi.calendarContract(normalized);
  return {
    schedule: normalized,
    events: calendarEvents.map(event => {
      const icon = scheduleApi.classifyEventIcon(event, iconMap);
      return {
        ...event,
        iconKey: icon ? icon.key : null,
        colorId: icon ? icon.googleCalendarColorId : null
      };
    }),
    iconMap,
    colors
  };
}

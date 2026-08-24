import { createHash } from 'node:crypto';

export const MANAGED_BY = 'lazensky-commander';
export const CALENDAR_NAMES = Object.freeze(['Procedury', 'Jídlo']);

function contractFingerprint(event) {
  const content = {
    stableId: event.stableId,
    syncKey: event.syncKey,
    managedBy: event.managedBy,
    targetCalendar: event.targetCalendar,
    title: event.title,
    start: event.start,
    end: event.end,
    timezone: event.timezone,
    location: event.location,
    kind: event.kind,
    procedureType: event.procedureType,
    mealType: event.mealType,
    leadTimeMinutes: event.leadTimeMinutes,
    leaveAt: event.leaveAt,
    descriptionMarker: event.descriptionMarker,
    iconKey: event.iconKey,
    colorId: event.colorId
  };
  return createHash('sha256').update(JSON.stringify(content)).digest('hex');
}

export function googleEventResource(event) {
  if (!Number.isInteger(event.leadTimeMinutes) || event.leadTimeMinutes < 0) {
    throw new Error(`Calendar event ${event.stableId} has an invalid canonical lead time.`);
  }
  const resource = {
    summary: event.title,
    location: event.location,
    description: `Lázeňský Commander\n${event.descriptionMarker}`,
    start: { dateTime: event.start, timeZone: event.timezone },
    end: { dateTime: event.end, timeZone: event.timezone },
    reminders: {
      useDefault: false,
      overrides: [{ method: 'popup', minutes: event.leadTimeMinutes }]
    },
    extendedProperties: {
      private: {
        managedBy: event.managedBy,
        stableId: event.stableId,
        syncKey: event.syncKey,
        contractHash: contractFingerprint(event)
      }
    }
  };
  if (event.colorId) resource.colorId = event.colorId;
  return resource;
}

export function isOwnedGoogleEvent(event) {
  const properties = event && event.extendedProperties && event.extendedProperties.private;
  const stableId = properties && typeof properties.stableId === 'string' ? properties.stableId.trim() : '';
  return Boolean(
    event && event.id &&
    properties && properties.managedBy === MANAGED_BY &&
    stableId && properties.syncKey === `lc:${stableId}`
  );
}

function localDateTime(value, timezone) {
  if (typeof value !== 'string') return null;
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(value)) return value;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    hourCycle: 'h23'
  }).formatToParts(date).reduce((result, part) => {
    if (part.type !== 'literal') result[part.type] = part.value;
    return result;
  }, {});
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}`;
}

export function sameGoogleEventContent(current, desiredEvent) {
  const desired = googleEventResource(desiredEvent);
  const properties = current.extendedProperties && current.extendedProperties.private || {};
  const currentOverrides = current.reminders && Array.isArray(current.reminders.overrides) ? current.reminders.overrides : [];
  const desiredReminder = desired.reminders.overrides[0];
  const hasConference = Boolean(current.hangoutLink || (current.conferenceData && Object.keys(current.conferenceData).length));
  return current.summary === desired.summary &&
    (current.location || '') === desired.location &&
    current.description === desired.description &&
    current.start && current.start.timeZone === desired.start.timeZone &&
    localDateTime(current.start.dateTime, desired.start.timeZone) === desired.start.dateTime &&
    current.end && current.end.timeZone === desired.end.timeZone &&
    localDateTime(current.end.dateTime, desired.end.timeZone) === desired.end.dateTime &&
    current.reminders && current.reminders.useDefault === false &&
    currentOverrides.length === 1 && currentOverrides[0].method === desiredReminder.method &&
    currentOverrides[0].minutes === desiredReminder.minutes &&
    (!Array.isArray(current.attendees) || current.attendees.length === 0) && !hasConference &&
    (current.colorId || null) === (desired.colorId || null) &&
    properties.managedBy === desired.extendedProperties.private.managedBy &&
    properties.stableId === desired.extendedProperties.private.stableId &&
    properties.syncKey === desired.extendedProperties.private.syncKey &&
    properties.contractHash === desired.extendedProperties.private.contractHash;
}

function operationOrder(left, right) {
  return `${left.calendarName}|${left.stableId}|${left.eventId || ''}`.localeCompare(`${right.calendarName}|${right.stableId}|${right.eventId || ''}`);
}

export function reconcileCalendarEvents(desiredEvents, currentByCalendar) {
  const desiredByStableId = new Map();
  for (const event of desiredEvents) {
    if (desiredByStableId.has(event.stableId)) throw new Error(`Calendar desired set contains duplicate stableId ${event.stableId}.`);
    if (!CALENDAR_NAMES.includes(event.targetCalendar)) throw new Error(`Calendar desired event ${event.stableId} has an unknown target.`);
    desiredByStableId.set(event.stableId, event);
  }

  const currentByStableId = new Map();
  for (const calendarName of CALENDAR_NAMES) {
    for (const event of currentByCalendar[calendarName] || []) {
      if (!isOwnedGoogleEvent(event)) continue;
      const stableId = event.extendedProperties.private.stableId;
      const entries = currentByStableId.get(stableId) || [];
      entries.push({ calendarName, event });
      currentByStableId.set(stableId, entries);
    }
  }

  const plan = { create: [], update: [], delete: [], unchanged: [] };
  const deletedKeys = new Set();
  const addDelete = (calendarName, event, stableId) => {
    const key = `${calendarName}|${event.id}`;
    if (deletedKeys.has(key)) return;
    deletedKeys.add(key);
    plan.delete.push({ calendarName, eventId: event.id, stableId });
  };

  for (const desiredEvent of [...desiredEvents].sort((a, b) => a.stableId.localeCompare(b.stableId))) {
    const candidates = (currentByStableId.get(desiredEvent.stableId) || []).sort((a, b) => `${a.calendarName}|${a.event.id}`.localeCompare(`${b.calendarName}|${b.event.id}`));
    const inTarget = candidates.filter(item => item.calendarName === desiredEvent.targetCalendar);
    const primary = inTarget[0];
    const resource = googleEventResource(desiredEvent);
    if (!primary) {
      plan.create.push({ calendarName: desiredEvent.targetCalendar, stableId: desiredEvent.stableId, resource });
    } else if (sameGoogleEventContent(primary.event, desiredEvent)) {
      plan.unchanged.push({ calendarName: primary.calendarName, eventId: primary.event.id, stableId: desiredEvent.stableId });
    } else {
      plan.update.push({ calendarName: primary.calendarName, eventId: primary.event.id, stableId: desiredEvent.stableId, resource });
    }
    for (const candidate of candidates) {
      if (!primary || candidate.calendarName !== primary.calendarName || candidate.event.id !== primary.event.id) addDelete(candidate.calendarName, candidate.event, desiredEvent.stableId);
    }
    currentByStableId.delete(desiredEvent.stableId);
  }

  for (const [stableId, candidates] of currentByStableId) {
    for (const candidate of candidates) addDelete(candidate.calendarName, candidate.event, stableId);
  }

  plan.create.sort(operationOrder);
  plan.update.sort(operationOrder);
  plan.delete.sort(operationOrder);
  plan.unchanged.sort(operationOrder);
  return plan;
}

export async function synchronizeCalendarProjection({ desiredEvents, adapter, dryRun = true }) {
  const pairs = await Promise.all(CALENDAR_NAMES.map(async calendarName => [calendarName, await adapter.listEvents(calendarName)]));
  const currentByCalendar = Object.fromEntries(pairs);
  const plan = reconcileCalendarEvents(desiredEvents, currentByCalendar);

  if (!dryRun) {
    for (const operation of plan.create) await adapter.createEvent(operation.calendarName, operation.resource);
    for (const operation of plan.update) await adapter.updateEvent(operation.calendarName, operation.eventId, operation.resource);
    for (const operation of plan.delete) await adapter.deleteEvent(operation.calendarName, operation.eventId);
  }

  return {
    desired: desiredEvents.length,
    created: plan.create.length,
    updated: plan.update.length,
    deleted: plan.delete.length,
    unchanged: plan.unchanged.length,
    plan
  };
}

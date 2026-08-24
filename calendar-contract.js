(function(root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  var target = root && root.window ? root.window : root;
  if (target) target.LazenskyCalendarContract = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  'use strict';

  var MANAGED_BY = 'lazensky-commander';
  var TIMEZONE = 'Europe/Prague';
  var PROCEDURES_CALENDAR = 'Procedury';
  var MEALS_CALENDAR = 'Jídlo';

  function createCalendarContract(schedule, resolveAlarm) {
    if (!schedule) return [];
    if (!Array.isArray(schedule.events)) throw new Error('Schedule events must be an array.');
    if (typeof resolveAlarm !== 'function') throw new Error('Calendar contract requires the shared alarm resolver.');

    return schedule.events.map(function(event) {
      var stableId = String(event.stableId || '').trim();
      if (!stableId) throw new Error('Calendar event is missing stableId.');
      var alarm = resolveAlarm(event, schedule);
      if (!alarm || alarm.stableId !== stableId) throw new Error('Calendar event is missing its canonical alarm contract.');
      return {
        stableId: stableId,
        syncKey: 'lc:' + stableId,
        managedBy: MANAGED_BY,
        targetCalendar: event.kind === 'meal' ? MEALS_CALENDAR : PROCEDURES_CALENDAR,
        title: event.title,
        start: alarm.startAt,
        end: alarm.endAt,
        leaveAt: alarm.leaveAt,
        timezone: TIMEZONE,
        location: event.location,
        kind: event.kind,
        procedureType: event.procedureType || null,
        mealType: event.mealType || null,
        leadTimeMinutes: alarm.effectiveLeadTimeMinutes,
        descriptionMarker: '[LC:' + stableId + ']'
      };
    });
  }

  return Object.freeze({
    managedBy: MANAGED_BY,
    timezone: TIMEZONE,
    proceduresCalendar: PROCEDURES_CALENDAR,
    mealsCalendar: MEALS_CALENDAR,
    createCalendarContract: createCalendarContract
  });
});

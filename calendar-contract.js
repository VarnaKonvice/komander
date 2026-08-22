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

  function createCalendarContract(schedule, resolveLeadTime) {
    if (!schedule) return [];
    if (!Array.isArray(schedule.events)) throw new Error('Schedule events must be an array.');
    if (typeof resolveLeadTime !== 'function') throw new Error('Calendar contract requires the shared lead-time resolver.');

    return schedule.events.map(function(event) {
      var stableId = String(event.stableId || '').trim();
      if (!stableId) throw new Error('Calendar event is missing stableId.');
      return {
        stableId: stableId,
        syncKey: 'lc:' + stableId,
        managedBy: MANAGED_BY,
        targetCalendar: event.kind === 'meal' ? MEALS_CALENDAR : PROCEDURES_CALENDAR,
        title: event.title,
        start: event.date + 'T' + event.start + ':00',
        end: event.date + 'T' + event.end + ':00',
        timezone: TIMEZONE,
        location: event.location,
        kind: event.kind,
        procedureType: event.procedureType || null,
        mealType: event.mealType || null,
        leadTimeMinutes: resolveLeadTime(event, schedule),
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

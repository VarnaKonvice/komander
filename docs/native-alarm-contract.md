# Native alarm contract v1

`LazenskySchedule.nativeAlarmPayload(schedule, overrides)` is the versioned, platform-neutral alarm input derived from the canonical schedule. It is used by the native iOS AlarmKit app and does not create another schedule source.

## Payload schema

```json
{
  "contractVersion": 1,
  "scheduleVersion": 42,
  "alarms": [
    {
      "stableId": "procedure-massage-2026-08-20",
      "kind": "procedure",
      "title": "Massage",
      "location": "Pavilion A",
      "startAt": "2026-08-20T10:00:00",
      "endAt": "2026-08-20T10:30:00",
      "effectiveLeadTimeMinutes": 30,
      "leaveAt": "2026-08-20T09:30:00"
    }
  ]
}
```

`contractVersion` changes only when this native contract changes incompatibly. `scheduleVersion` is the version of the canonical schedule from which the payload was derived. It is useful for freshness and observability, but it is not itself an alarm update trigger.

Every alarm entry is derived through `LazenskySchedule.alarmContract(schedule, overrides)`. `effectiveLeadTimeMinutes` and `leaveAt` therefore use the single existing effective-lead-time calculation. Without `overrides`, the payload uses only canonical values from `data/schedule.json`. It never reads browser storage or another platform store.

`overrides` is an optional plain JSON object with `defaultLeadTimeMinutes`, `procedureTypeOverrides`, `mealOverrides`, and `eventOverrides`. It has the same priority as the existing local effective-lead-time settings. Device-local preferences do not belong in `data/schedule.json`; the platform that owns them passes them explicitly to `nativeAlarmPayload`, `alarmContract`, or `computeLiveState`. Equal schedule and equal overrides produce equal payload output. Datetimes use the same local ISO representation as the schedule contract, and the payload has no generated timestamp or other volatile value.

`stableId` is the canonical identity of one scheduled event. It must remain stable when the event is corrected, such as when its time, title, location, or lead time changes. It is not an iOS, AlarmKit, or platform UUID.

## Reconciliation

`LazenskySchedule.reconcileNativeAlarms(currentAlarms, nextPayload)` produces:

```json
{
  "create": [{ "stableId": "...", "nextAlarm": {} }],
  "update": [{ "stableId": "...", "currentAlarm": {}, "nextAlarm": {} }],
  "cancel": [{ "stableId": "...", "currentAlarm": {} }],
  "unchanged": [{ "stableId": "...", "currentAlarm": {}, "nextAlarm": {} }]
}
```

`currentAlarms` may be an alarm array or a previous payload with an `alarms` array. Identity is always `stableId`.

- A `stableId` present only in `nextPayload.alarms` is `create`.
- A `stableId` present only in `currentAlarms` is `cancel`.
- A shared `stableId` is `unchanged` when `kind`, `title`, `location`, `startAt`, `endAt`, `effectiveLeadTimeMinutes`, and `leaveAt` are all equal.
- A shared `stableId` is `update` when any of those alarm-relevant fields differs.
- A higher `scheduleVersion` alone never produces `update`.

The native client owns its local mapping from `stableId` to `AlarmKit.Alarm.ID` (or another platform identifier). Neither `data/schedule.json` nor this payload contains a platform UUID. The mapping is local implementation state and can be recreated from the canonical payload and reconciliation plan.

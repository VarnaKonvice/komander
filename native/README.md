# Native companion foundation

This directory intentionally contains no Xcode project or native implementation yet. The future iOS companion consumes the stable platform-neutral contract exposed by `LazenskySchedule`:

- `nativeAlarmPayload(schedule, overrides)` provides versioned alarms from `data/schedule.json` and optional explicit device-local preferences.
- `reconcileNativeAlarms(currentAlarms, nextPayload)` provides create, update, cancel, and unchanged actions keyed by canonical `stableId`.

The companion must keep its own local `stableId -> AlarmKit.Alarm.ID` mapping. It passes local lead-time preferences as the explicit JSON `overrides` input; `nativeAlarmPayload` never reads browser storage. Platform identifiers and device-local preferences must not be written back into `data/schedule.json` or the canonical payload.

The first native implementation should fetch the canonical schedule, derive or consume the native payload, reconcile against locally known alarm content, persist its mapping, and apply the reconciliation plan through AlarmKit. AlarmKit, ActivityKit, Apple Watch support, and an Xcode project are deliberately outside this foundation step.

See `../docs/native-alarm-contract.md` for the versioned schema and reconciliation rules.

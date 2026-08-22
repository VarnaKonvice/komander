# Lazensky Commander native apps

Open `LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj` in Xcode 26.6 or newer. The project contains the iPhone app, its AlarmKit Live Activity extension, the paired Watch app, and the Watch widget extension. Shared platform-neutral behavior lives in the local Swift package `LazenskyCommander`.

## Targets and requirements

| Target | Bundle identifier | Minimum OS |
| --- | --- | --- |
| `LazenskyCommanderApp` | `com.varnakonvice.lazenskycommander` | iOS 26.1 |
| `LazenskyCommanderLiveActivity` | `com.varnakonvice.lazenskycommander.liveactivity` | iOS 26.1 |
| `LazenskyCommanderWatchApp` | `com.varnakonvice.lazenskycommander.watchkitapp` | watchOS 26.0 |
| `LazenskyCommanderWatchWidget` | `com.varnakonvice.lazenskycommander.watchkitapp.widget` | watchOS 26.0 |

`LazenskyCommanderCore` supports iOS 26 and watchOS 26. The app requires iOS 26.1 because `AlarmPresentation.Alert` is available from that version. The Xcode project contains development team `2CCL69T42P`; physical-device builds still require valid local signing and provisioning for all targets and the Watch App Group.

The Watch app and widget share `group.com.varnakonvice.lazenskycommander.watch`. The iPhone app embeds the Live Activity extension and Watch app; the Watch app embeds its widget extension.

## Canonical schedule and one-fetch sync

`data/schedule.json` is the only schedule source of truth. `AppConfiguration.scheduleURL` points to its production raw GitHub URL. One manual iPhone sync downloads and validates the complete `Schedule` once through `CommanderScheduleSyncCoordinator`. The same validated value is then used by:

- `AlarmSyncService` and AlarmKit reconciliation;
- the persisted iPhone snapshot and Commander Live Card;
- the complete `WatchScheduleSnapshot` sent with `WCSession.updateApplicationContext`.

The iPhone and Watch stores are validated local caches, not alternative schedule sources. Device-local lead-time preferences are explicit contract inputs and are never written to `schedule.json`.

## iPhone AlarmKit and Live Activity

`NativeAlarmContract` is the single source of effective lead time and `leaveAt` for native alarm, live-state, and Watch projections. AlarmKit reconciliation identifies events by `stableId`; it stores the local `stableId -> AlarmKit Alarm.ID` mapping outside the canonical schedule.

For each sync, `AlarmSyncService` derives the AlarmKit desired set by retaining only canonical alarms with `leaveAt > now`. An alarm exactly at `now` is not newly scheduled. Past managed alarms still present in AlarmKit are cancelled, and stale mappings absent from the platform are pruned. This filter does not modify the complete `Schedule` used by the Live Card or Watch snapshot.

Each AlarmKit alarm fires at canonical `leaveAt`. Its pre-alert starts at the previous event's `endAt` when that time is before `leaveAt`, otherwise no more than 30 minutes before `leaveAt`. `CommanderAlarmMetadata` is carried by `AlarmAttributes<CommanderAlarmMetadata>` into the Live Activity extension. The Lock Screen and Dynamic Island render AlarmKit countdown, paused, and alert states with system date/timer rendering and no polling timer.

The Commander Live Card reads the last validated iPhone snapshot and evaluates presentation transitions through `CommanderLiveStateCalculator`; countdown changes do not trigger another network fetch.

## Watch transport, cache, and offline behavior

The iPhone sends the entire multi-day schedule, not only today's events. The Watch receiver validates the envelope and schedule, applies the shared version decision, and atomically replaces the App Group cache. Equal snapshots are idempotent; stale or conflicting versions are rejected.

The Watch app, WidgetKit timeline, Smart Stack relevance, and local leave notifications all use this cache. Timeline entries include day-boundary and event-state transitions, so the next day works without a new sync. Cached data expires after the final event plus 24 hours.

The Watch has no direct schedule network fetch and no GPS or cellular dependency. `WCSession.isReachable` is not required when an alarm fires; `updateApplicationContext` provides the latest snapshot whenever the paired devices can exchange it.

## Standalone Watch alarms

The persistent **Samostatné alarmy Watch** setting authorizes and reconciles standard active `UNUserNotificationCenter` requests on watchOS. Requests use the system sound and respect the Watch system notification and Focus settings. They use deterministic identifiers in the `lazensky.commander.watch.leave.<stableId>` namespace and canonical `leaveAt` values. Reconciliation creates, updates, preserves, or cancels only requests owned by this namespace.

At most the nearest 60 future requests are pending because of the platform limit. This rolling limit does not truncate the full schedule cache. Disabling the setting removes only Commander Watch leave notifications and leaves unrelated notifications untouched.

## Visual assets

`../assets/icons/lazensky-v1/icon-map.json` and `colors.json` are the shared visual contract. The PWA uses approved 256px PNGs, the iPhone app uses 512px assets, and Live Activity/Watch surfaces use 128px assets. Unknown procedures retain their source text, receive no fabricated category icon, and use neutral Commander purple.

## Verification

Run the platform-neutral checks from the repository root:

```sh
swift test --package-path native/LazenskyCommander
swift run --package-path native/LazenskyCommander LazenskyCommanderCoreCheck
```

Run unsigned generic builds with full Xcode:

```sh
xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj \
  -scheme LazenskyCommanderApp -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

xcodebuild -project native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj \
  -scheme LazenskyCommanderWatchApp -destination 'generic/platform=watchOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Generic unsigned builds verify compilation, target dependencies, embedding, and resources. AlarmKit authorization and presentation, Dynamic Island behavior, WatchConnectivity delivery, Smart Stack relevance, and Watch haptics/local notifications require physical-device testing.

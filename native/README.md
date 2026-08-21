# Lazensky Commander iOS AlarmKit app

Open `native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj` in Xcode. It is a standard signable iOS app target linked to the local Swift Package `native/LazenskyCommander`, which provides `LazenskyCommanderCore` and `LazenskyCommanderCoreCheck`.

## Requirements and signing

`LazenskyCommanderCore` supports iOS 26+. The actual `LazenskyCommanderApp` target requires iOS 26.1+ because it uses `AlarmPresentation.Alert`; its bundle ID is `com.varnakonvice.lazenskycommander`. In Xcode, select the `LazenskyCommanderApp` target, choose your Development Team under **Signing & Capabilities**, and allow Xcode to create the provisioning profile. No Apple Development Team is stored in this project.

The app needs full Xcode with an iOS 26.1-or-newer SDK and a physical iPhone on a supported iOS version. The current repository environment only has Command Line Tools, so it cannot compile or install the `import AlarmKit` app target.

## Schedule and native contract

`AppConfiguration.scheduleURL` is the only production URL. It currently points to:

`https://raw.githubusercontent.com/VarnaKonvice/komander/main/data/schedule.json`

`URLSessionScheduleService` validates the downloaded schedule before it can change local alarms. `NativeAlarmContract.payload(schedule:overrides:)` implements the shared canonical contract and decodes the fixture at `tests/fixtures/native-alarm-reconciliation-v1.json` in the Swift tests.

The local ISO `leaveAt` contract is parsed as an `Europe/Prague` wall-clock time before it becomes the absolute `Date` passed to `Alarm.Schedule.fixed`. The device-local lead-time preferences remain explicit `overrides`; they are never written into `schedule.json`.

## AlarmKit permission and sync

`Info.plist` contains the nonempty `NSAlarmKitUsageDescription` string required by AlarmKit. It explains that the app schedules a departure alarm for procedures and meals. If this key is missing or empty, the app reports AlarmKit as unavailable and does not schedule an alarm.

`AlarmKitAdapter` maps `AlarmManager.shared.authorizationState` and calls `AlarmManager.shared.requestAuthorization()`. The app displays authorization status and offers **Povolit alarmy** when permission has not been requested. A denied state is shown as inactive and the sync does not persist a false success.

The sync path is:

`schedule.json -> native payload -> reconciliation -> AlarmKitAdapter -> UserDefaults state`

Each native alarm is a one-shot `Alarm.Schedule.fixed(leaveAt)` alarm with a system stop control and default system sound. It has no countdown, secondary action, snooze, Live Activity, widget extension, App Intent, or Apple Watch UI. The displayed title is `Čas vyrazit: <název>`.

The app stores only `stableId -> platformAlarmID`, last applied alarm content, and the successful payload/sync timestamp. It never writes an AlarmKit UUID into the canonical schedule. On each authorized sync it compares the persisted map with `AlarmManager.shared.alarms`; mappings for system alarms that no longer exist are pruned before reconciliation. Updates cancel the prior alarm and schedule a new one, saving each successful step so a partial failure cannot claim a fully successful sync.

## First alarm on an iPhone

1. Open the `.xcodeproj`, select the `LazenskyCommanderApp` scheme and a signed physical iPhone, then build and run.
2. Confirm that the AlarmKit status is available. Tap **Povolit alarmy** and accept the system permission prompt.
3. Use a future `leaveAt` in the configured schedule URL, then tap **Synchronizovat**.
4. Verify the app reports a created alarm. In a subsequent foreground sync, the adapter also checks `AlarmManager.shared.alarms`; an existing UUID remains in the local mapping only while the system still has that alarm.
5. Wait for the configured departure time and confirm the system alarm presents `Čas vyrazit: ...` with its standard stop control. Then change an event time or override and sync again to verify update; remove an event and verify cancel.

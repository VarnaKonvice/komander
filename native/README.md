# Lazensky Commander native companion

The Xcode-openable Swift Package is in `native/LazenskyCommander/Package.swift`. Open that file in Xcode and select the `LazenskyCommander` executable scheme. The package has no external dependencies and contains a SwiftUI iOS shell plus a separately testable core.

## Requirements

The package declares iOS 26 as its deployment target because AlarmKit belongs to that platform generation. A full Xcode installation with the matching iOS 26 SDK is required to build for an iPhone. The current local environment has Command Line Tools only, without Xcode or the iOS SDK; it cannot verify AlarmKit calls or device entitlements.

## Schedule source and contract

`AppConfiguration.scheduleURL` is the only production schedule URL and defaults to the public raw GitHub schedule:

`https://raw.githubusercontent.com/VarnaKonvice/komander/main/data/schedule.json`

Change this one configuration value when the final GitHub Pages URL is confirmed. `URLSessionScheduleService` validates schema version, schedule version, required event fields, event kinds, dates, times, ranges, lead times, and unique `stableId` values before a sync can change local state.

`NativeAlarmContract.payload(schedule:overrides:)` implements the documented `schedule + explicit overrides -> native alarm payload` contract. The shared JSON fixture remains at `tests/fixtures/native-alarm-reconciliation-v1.json`; Swift tests decode that exact file rather than a Swift-only equivalent.

## Alarm sync and local state

`AlarmSyncService` performs fetch, validation, payload creation, reconciliation, cancellation, update, creation, and persistence in that order. A fetch or validation error runs no alarm mutation. On a partial adapter error, each successfully applied change is persisted immediately so the next sync reconciles against the actual managed state rather than a falsely successful snapshot.

`UserDefaultsAlarmStateStore` stores only managed alarm records: `stableId`, the platform alarm identifier, the last applied alarm content, last successful payload, and last successful sync time. Canonical schedule data never receives a platform UUID.

## AlarmKit status

`AlarmAdapting` is the isolated adapter boundary. `UnavailableAlarmKitAdapter` is active in this repository because the available SDK cannot expose or compile the real AlarmKit API. `AlarmKitSDKBoundary.swift` is the single place where a concrete adapter must be added after checking the actual Xcode SDK. No AlarmKit method signature, entitlement, Info.plist key, or authorization API has been guessed.

The adapter contract already requires availability, authorization status, authorization request, schedule, and cancel. The sync service uses cancel plus schedule for update, preserving the local `stableId -> platformAlarmID` map with the identifier returned by the real adapter.

## First iPhone alarm

1. Install full Xcode with the iOS 26 SDK and open `native/LazenskyCommander/Package.swift`.
2. Verify the exact AlarmKit API, entitlement/capability, authorization request, and any required Info.plist entries from that SDK.
3. Implement `AlarmAdapting` in `AlarmKitSDKBoundary.swift` using those verified APIs, then inject it into `CompanionViewModel` in place of `UnavailableAlarmKitAdapter`.
4. Select a signed physical iPhone running the supported iOS version, build, tap **Synchronize**, approve the system alarm permission, and verify one event at its `leaveAt` time.
5. Change an event time and then a lead-time override; confirm the next sync updates the same `stableId`. Remove an event and confirm the next sync cancels it.

ActivityKit, widgets, Apple Watch, countdown UI, snooze, and a PWA replacement are intentionally outside iOS Companion v1.

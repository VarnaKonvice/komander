#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func coordinatorKeepsCanonicalScheduleAndWatchCurrentWhenAlarmKitStillNeedsRepair() async throws {
  let schedule = stabilitySchedule(version: 41)
  let source = StabilityScheduleService(schedule: schedule)
  let scheduleStore = InMemoryScheduleSnapshotStore()
  let watch = StabilityWatchDelivery()
  let alarmSync = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: AlwaysUnavailableAlarmAdapter()
  )
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmSync,
    scheduleStore: scheduleStore,
    watchDelivery: watch,
    alarmRecoveryAttempts: 3
  )

  let result = try await coordinator.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  )

  #expect(!result.succeeded)
  #expect(result.alarmRecoveryAttempts == 3)
  #expect(await scheduleStore.load() == schedule)
  #expect(await watch.snapshot() == WatchScheduleSnapshot(schedule: schedule))
  #expect(result.watchDeliveryStatus == .sent)
}

@Test func coordinatorAutomaticallyRepairsTransientAlarmKitFailureBeforeReturning() async throws {
  let schedule = stabilitySchedule(version: 42)
  let source = StabilityScheduleService(schedule: schedule)
  let scheduleStore = InMemoryScheduleSnapshotStore()
  let adapter = RecoveringAlarmAdapter()
  let alarmSync = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: adapter
  )
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmSync,
    scheduleStore: scheduleStore,
    alarmRecoveryAttempts: 3
  )

  let result = try await coordinator.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  )

  #expect(result.succeeded)
  #expect(result.alarmRecoveryAttempts == 2)
  #expect(result.alarmSummary.desiredAlarmCount == 1)
  #expect(result.alarmSummary.appliedCreate == 1)
  #expect(await adapter.scheduledCount() == 1)
  #expect(await scheduleStore.load() == schedule)
}

@Test func publishedCanonicalValidationRejectsNonPositiveVersionAndInvalidUpdatedAt() throws {
  let valid = stabilitySchedule(version: 1)
  #expect(throws: Never.self) {
    try NativeAlarmContract.validateCanonical(valid)
  }

  let zeroVersion = Schedule(
    schemaVersion: valid.schemaVersion,
    scheduleVersion: 0,
    updatedAt: valid.updatedAt,
    stay: valid.stay,
    events: valid.events,
    settings: valid.settings
  )
  #expect(throws: ScheduleValidationError.invalidScheduleVersion) {
    try NativeAlarmContract.validateCanonical(zeroVersion)
  }

  let invalidTimestamp = Schedule(
    schemaVersion: valid.schemaVersion,
    scheduleVersion: valid.scheduleVersion,
    updatedAt: "not-a-timestamp",
    stay: valid.stay,
    events: valid.events,
    settings: valid.settings
  )
  #expect(throws: ScheduleValidationError.invalidUpdatedAt) {
    try NativeAlarmContract.validateCanonical(invalidTimestamp)
  }
}

private func stabilitySchedule(version: Int) -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: version,
    updatedAt: "2026-08-20T07:00:00Z",
    stay: ["spa": "Stability test"],
    events: [
      ScheduleEvent(
        stableId: "stability-procedure",
        date: "2026-08-20",
        start: "10:00",
        end: "10:20",
        title: "Masáž",
        location: "Rehabilitace",
        kind: .procedure,
        procedureType: "Masáž",
        mealType: nil,
        leadTimeMinutes: 15
      )
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 15,
      procedureTypeOverrides: [:],
      mealOverrides: [:]
    )
  )
}

private struct StabilityScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor StabilityWatchDelivery: WatchScheduleSnapshotDelivering {
  private var received: WatchScheduleSnapshot?

  func deliver(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleDeliveryDisposition {
    received = snapshot
    return .sent
  }

  func snapshot() -> WatchScheduleSnapshot? { received }
}

private struct AlwaysUnavailableAlarmAdapter: AlarmAdapting {
  func availability() async -> AlarmKitAvailability { .unavailable("temporary test outage") }
  func authorizationStatus() async -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() async throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String {
    throw AlarmAdapterError.unavailable("temporary test outage")
  }
  func cancel(platformAlarmID: String) async throws {}
}

private actor RecoveringAlarmAdapter: AlarmAdapting {
  private var availabilityChecks = 0
  private var scheduled = 0

  func availability() async -> AlarmKitAvailability {
    availabilityChecks += 1
    return availabilityChecks == 1 ? .unavailable("transient") : .available
  }

  func authorizationStatus() async -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() async throws {}

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String {
    scheduled += 1
    return PlatformAlarmIdentifier.newPersistedValue()
  }

  func cancel(platformAlarmID: String) async throws {}
  func scheduledCount() -> Int { scheduled }
}
#endif

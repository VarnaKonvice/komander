#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func canonicalValidationRejectsNonPositiveVersionAndInvalidUpdatedAt() throws {
  let valid = stabilitySchedule(version: 1)
  try NativeAlarmContract.validateCanonical(valid)

  let zero = Schedule(
    schemaVersion: valid.schemaVersion,
    scheduleVersion: 0,
    updatedAt: valid.updatedAt,
    stay: valid.stay,
    events: valid.events,
    settings: valid.settings
  )
  #expect(throws: ScheduleValidationError.invalidScheduleVersion) {
    try NativeAlarmContract.validateCanonical(zero)
  }

  let badTimestamp = Schedule(
    schemaVersion: valid.schemaVersion,
    scheduleVersion: 2,
    updatedAt: "not-an-iso-date",
    stay: valid.stay,
    events: valid.events,
    settings: valid.settings
  )
  #expect(throws: ScheduleValidationError.invalidUpdatedAt("not-an-iso-date")) {
    try NativeAlarmContract.validateCanonical(badTimestamp)
  }
}

@Test func countdownWindowNeverOccupiesMoreThanThirtyMinutes() throws {
  let schedule = Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-25T08:00:00Z",
    stay: [:],
    events: [
      stabilityEvent("first", start: "08:00", end: "08:20"),
      stabilityEvent("second", start: "11:00", end: "11:20")
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 15, procedureTypeOverrides: [:], mealOverrides: [:])
  )
  let alarm = try #require(NativeAlarmContract.payload(schedule: schedule).alarms.first { $0.stableId == "second" })
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
  let plan = try AlarmCountdown.plan(
    for: alarm,
    in: schedule,
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T09:00:00")
  )

  #expect(plan.duration == 30 * 60)
  #expect(plan.scheduledStartAt == leaveAt.addingTimeInterval(-30 * 60))
}

@Test func recoverableAlarmFailureDoesNotRollBackAcceptedCanonicalSchedule() async throws {
  let previous = stabilitySchedule(version: 1, title: "Starý rozpis")
  let incoming = stabilitySchedule(version: 2, title: "Nový rozpis")
  let scheduleStore = InMemoryScheduleSnapshotStore(previous)
  let source = StabilityStaticScheduleService(schedule: incoming)
  let alarmService = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: StabilityUnavailableAlarmAdapter()
  )
  let watch = StabilityWatchDelivery()
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmService,
    scheduleStore: scheduleStore,
    watchDelivery: watch
  )

  let result = try await coordinator.synchronize(
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00")
  )

  #expect(result.schedule == incoming)
  #expect(await scheduleStore.load() == incoming)
  #expect(!result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .sent)
  #expect(await watch.lastSnapshot()?.schedule == incoming)
}

@Test func staleNetworkResponseCannotDowngradeAcceptedCanonicalSchedule() async throws {
  let current = stabilitySchedule(version: 3, title: "Aktuální")
  let stale = stabilitySchedule(version: 2, title: "Starší")
  let scheduleStore = InMemoryScheduleSnapshotStore(current)
  let source = StabilityStaticScheduleService(schedule: stale)
  let alarmService = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: StabilityRecordingAlarmAdapter()
  )
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmService,
    scheduleStore: scheduleStore
  )

  let result = try await coordinator.synchronize(
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00")
  )

  #expect(result.schedule == current)
  #expect(result.scheduleDecision == .rejectedVersion(current: 3, incoming: 2))
  #expect(await scheduleStore.load() == current)
  #expect(result.alarmSummary.scheduleVersion == 3)
}

@Test func alarmVerificationRepairsMissingPlatformAlarmBeforeReportingSuccess() async throws {
  let schedule = stabilitySchedule(version: 4)
  let source = StabilityStaticScheduleService(schedule: schedule)
  let adapter = StabilityRepairingAlarmAdapter(dropFirstScheduledAlarm: true)
  let service = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: adapter
  )

  let summary = try await service.synchronize(
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00")
  )

  #expect(summary.succeeded)
  #expect(summary.verified)
  #expect(summary.repairAttempts == 1)
  #expect(await adapter.scheduleCalls() == 2)
  #expect(await adapter.platformAlarmCount() == 1)
}

private func stabilitySchedule(version: Int, title: String = "Masáž") -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: version,
    updatedAt: "2026-08-25T08:00:00Z",
    stay: ["spa": "Test"],
    events: [stabilityEvent("event-1", title: title, start: "10:00", end: "10:20")],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 15, procedureTypeOverrides: [:], mealOverrides: [:])
  )
}

private func stabilityEvent(
  _ id: String,
  title: String = "Masáž",
  start: String,
  end: String
) -> ScheduleEvent {
  ScheduleEvent(
    stableId: id,
    date: "2026-08-25",
    start: start,
    end: end,
    title: title,
    location: "Rehabilitace",
    kind: .procedure,
    procedureType: title,
    mealType: nil,
    leadTimeMinutes: nil
  )
}

private struct StabilityStaticScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private struct StabilityUnavailableAlarmAdapter: AlarmAdapting {
  func availability() async -> AlarmKitAvailability { .unavailable("temporary") }
  func authorizationStatus() async -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() async throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String { throw AlarmAdapterError.unavailable("temporary") }
  func cancel(platformAlarmID: String) async throws {}
}

private actor StabilityRecordingAlarmAdapter: AlarmAdapting {
  private var ids = Set<String>()

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = PlatformAlarmIdentifier.newPersistedValue()
    ids.insert(id)
    return id
  }
  func cancel(platformAlarmID: String) { ids.remove(platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { ids }
}

private actor StabilityRepairingAlarmAdapter: AlarmAdapting {
  private var ids = Set<String>()
  private var calls = 0
  private var shouldDropFirst: Bool

  init(dropFirstScheduledAlarm: Bool) {
    shouldDropFirst = dropFirstScheduledAlarm
  }

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    calls += 1
    let id = PlatformAlarmIdentifier.newPersistedValue()
    if shouldDropFirst {
      shouldDropFirst = false
    } else {
      ids.insert(id)
    }
    return id
  }
  func cancel(platformAlarmID: String) { ids.remove(platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { ids }
  func scheduleCalls() -> Int { calls }
  func platformAlarmCount() -> Int { ids.count }
}

private actor StabilityWatchDelivery: WatchScheduleSnapshotDelivering {
  private var snapshot: WatchScheduleSnapshot?

  func deliver(_ snapshot: WatchScheduleSnapshot) -> WatchScheduleDeliveryDisposition {
    self.snapshot = snapshot
    return .sent
  }

  func lastSnapshot() -> WatchScheduleSnapshot? { snapshot }
}
#endif

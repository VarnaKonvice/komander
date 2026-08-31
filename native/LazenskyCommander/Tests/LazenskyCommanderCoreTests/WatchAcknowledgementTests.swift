#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func watchAcknowledgementRoundTripsProjectionIdentity() throws {
  let context = try WatchScheduleAcknowledgementCodec.applicationContext(
    scheduleVersion: 42,
    projectionRevision: 7
  )
  let acknowledgement = try WatchScheduleAcknowledgementCodec.decode(applicationContext: context)

  #expect(acknowledgement.contractVersion == WatchScheduleAcknowledgement.currentContractVersion)
  #expect(acknowledgement.scheduleVersion == 42)
  #expect(acknowledgement.projectionRevision == 7)
  #expect(acknowledgement.projectionIdentity == WatchScheduleProjectionIdentity(scheduleVersion: 42, projectionRevision: 7))
}

@Test func watchDeliveryIsNotVerifiedWithoutMatchingAcknowledgement() async throws {
  let schedule = acknowledgementSchedule(version: 7)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(acknowledgedIdentity: nil)
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .sent)
  #expect(result.succeeded)
}

@Test func watchDeliveryBecomesVerifiedOnlyForMatchingScheduleVersion() async throws {
  let schedule = acknowledgementSchedule(version: 8)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(
      acknowledgedIdentity: WatchScheduleProjectionIdentity(scheduleVersion: 8, projectionRevision: 0)
    )
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .verified)
  #expect(result.succeeded)
}

@Test func watchDeliveryRejectsAcknowledgementForDifferentVersion() async throws {
  let schedule = acknowledgementSchedule(version: 9)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(
      acknowledgedIdentity: WatchScheduleProjectionIdentity(scheduleVersion: 8, projectionRevision: 0)
    )
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.watchDeliveryStatus == .sent)
  #expect(result.succeeded)
}

@Test func watchDeliveryRejectsOldLeadTimeRevisionForSameSchedule() async throws {
  let schedule = acknowledgementSchedule(version: 10)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(
      acknowledgedIdentity: WatchScheduleProjectionIdentity(scheduleVersion: 10, projectionRevision: 2)
    )
  ).synchronize(
    overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 15),
    projectionRevision: 3,
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00")
  )

  #expect(result.watchSnapshot.projectionRevision == 3)
  #expect(result.watchDeliveryStatus == .sent)
  #expect(result.succeeded)
}

@Test func watchDeliveryVerifiesMatchingLeadTimeRevisionForSameSchedule() async throws {
  let schedule = acknowledgementSchedule(version: 11)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(
      acknowledgedIdentity: WatchScheduleProjectionIdentity(scheduleVersion: 11, projectionRevision: 4)
    )
  ).synchronize(
    overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 30),
    projectionRevision: 4,
    now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00")
  )

  #expect(result.watchSnapshot.leadTimeOverrides.defaultLeadTimeMinutes == 30)
  #expect(result.watchDeliveryStatus == .verified)
  #expect(result.succeeded)
}

@Test func watchCacheAcceptsNewerLeadTimeRevisionWithoutNewCanonicalVersion() {
  let schedule = acknowledgementSchedule(version: 12)
  let existing = WatchScheduleSnapshot(
    schedule: schedule,
    leadTimeOverrides: LeadTimeOverrides(defaultLeadTimeMinutes: 20),
    projectionRevision: 1
  )
  let incoming = WatchScheduleSnapshot(
    schedule: schedule,
    leadTimeOverrides: LeadTimeOverrides(defaultLeadTimeMinutes: 15),
    projectionRevision: 2
  )

  #expect(WatchScheduleCachePolicy.decision(incoming: incoming, existing: existing) == .stored)
}

private func acknowledgementCoordinator(
  schedule: Schedule,
  watch: AcknowledgementWatchDelivery
) -> CommanderScheduleSyncCoordinator {
  let source = AcknowledgementScheduleService(schedule: schedule)
  let alarmService = AlarmSyncService(
    scheduleService: source,
    store: InMemoryAlarmStateStore(),
    adapter: AcknowledgementAlarmAdapter()
  )
  return CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmService,
    scheduleStore: InMemoryScheduleSnapshotStore(),
    watchDelivery: watch
  )
}

private func acknowledgementSchedule(version: Int) -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: version,
    updatedAt: "2026-08-25T08:00:00Z",
    stay: ["spa": "Test"],
    events: [
      ScheduleEvent(
        stableId: "ack-event",
        date: "2026-08-25",
        start: "10:00",
        end: "10:20",
        title: "Masáž",
        location: "Rehabilitace",
        kind: .procedure,
        procedureType: "Masáž",
        mealType: nil,
        leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 15, procedureTypeOverrides: [:], mealOverrides: [:])
  )
}

private struct AcknowledgementScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor AcknowledgementAlarmAdapter: AlarmAdapting {
  private var ids = Set<String>()

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = PlatformAlarmIdentifier.newPersistedValue()
    ids.insert(id)
    return id
  }

  func cancel(platformAlarmID: String) {
    ids.remove(platformAlarmID)
  }

  func existingPlatformAlarmIDs() -> Set<String>? { ids }
}

private actor AcknowledgementWatchDelivery: WatchScheduleSnapshotDelivering {
  private let acknowledgedIdentity: WatchScheduleProjectionIdentity?

  init(acknowledgedIdentity: WatchScheduleProjectionIdentity?) {
    self.acknowledgedIdentity = acknowledgedIdentity
  }

  func deliver(_ snapshot: WatchScheduleSnapshot) -> WatchScheduleDeliveryDisposition { .sent }
  func verifiedScheduleVersion() -> Int? { acknowledgedIdentity?.scheduleVersion }
  func verifiedProjectionIdentity() -> WatchScheduleProjectionIdentity? { acknowledgedIdentity }
}
#endif

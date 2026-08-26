#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func watchAcknowledgementRoundTripsScheduleVersion() throws {
  let context = try WatchScheduleAcknowledgementCodec.applicationContext(scheduleVersion: 42)
  let acknowledgement = try WatchScheduleAcknowledgementCodec.decode(applicationContext: context)

  #expect(acknowledgement.contractVersion == WatchScheduleAcknowledgement.currentContractVersion)
  #expect(acknowledgement.scheduleVersion == 42)
}

@Test func watchDeliveryIsNotVerifiedWithoutMatchingAcknowledgement() async throws {
  let schedule = acknowledgementSchedule(version: 7)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(acknowledgedVersion: nil)
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .sent)
  #expect(!result.succeeded)
}

@Test func watchDeliveryBecomesVerifiedOnlyForMatchingScheduleVersion() async throws {
  let schedule = acknowledgementSchedule(version: 8)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(acknowledgedVersion: 8)
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .verified)
  #expect(result.succeeded)
}

@Test func watchDeliveryRejectsAcknowledgementForDifferentVersion() async throws {
  let schedule = acknowledgementSchedule(version: 9)
  let result = try await acknowledgementCoordinator(
    schedule: schedule,
    watch: AcknowledgementWatchDelivery(acknowledgedVersion: 8)
  ).synchronize(now: try NativeAlarmContract.date(fromLocalISO: "2026-08-25T07:00:00"))

  #expect(result.watchDeliveryStatus == .sent)
  #expect(!result.succeeded)
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
  private let acknowledgedVersion: Int?

  init(acknowledgedVersion: Int?) {
    self.acknowledgedVersion = acknowledgedVersion
  }

  func deliver(_ snapshot: WatchScheduleSnapshot) -> WatchScheduleDeliveryDisposition { .sent }
  func verifiedScheduleVersion() -> Int? { acknowledgedVersion }
}
#endif

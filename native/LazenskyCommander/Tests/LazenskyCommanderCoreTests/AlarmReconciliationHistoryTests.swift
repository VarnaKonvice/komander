#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func reconciliationHistorySurvivesLegacyStateAndKeepsOnlyRecentEntries() throws {
  let legacyJSON = """
  {"records":{},"lastSuccessfulPayload":null,"lastSuccessfulSync":null}
  """
  var state = try JSONDecoder().decode(ManagedAlarmState.self, from: Data(legacyJSON.utf8))
  #expect(state.reconciliationHistory.isEmpty)

  let base = try ledgerDate("2026-09-07T10:00:00")
  for index in 0..<(ManagedAlarmState.reconciliationHistoryLimit + 4) {
    state.appendReconciliationHistory(
      AlarmReconciliationHistoryEntry(
        scheduleVersion: index + 1,
        startedAt: base.addingTimeInterval(TimeInterval(index)),
        desiredAlarmCount: 1,
        verified: true
      )
    )
  }

  #expect(state.reconciliationHistory.count == ManagedAlarmState.reconciliationHistoryLimit)
  #expect(state.reconciliationHistory.first?.scheduleVersion == 5)
  #expect(state.reconciliationHistory.last?.scheduleVersion == ManagedAlarmState.reconciliationHistoryLimit + 4)
}

@Test func laterPostDepartureRepairCannotEraseEarlierUncertainMasazEvidence() throws {
  let masaz = AlarmReconciliationObservation(
    stableId: "masaz-1400",
    title: "Masáž",
    expectedLeaveAt: "2026-09-07T13:50:00",
    platformAlarmID: "old-masaz-id",
    platformExists: nil,
    actualLeaveAt: nil,
    readbackError: "Stav alarmu před odchodem nebyl doložen."
  )
  var state = ManagedAlarmState()
  state.appendReconciliationHistory(
    AlarmReconciliationHistoryEntry(
      scheduleVersion: 5,
      startedAt: try ledgerDate("2026-09-07T13:25:00"),
      desiredAlarmCount: 8,
      before: [masaz],
      after: [],
      repairAttempts: 0,
      verified: false,
      errorMessage: "Stav alarmu před odchodem nebyl doložen."
    )
  )
  state.appendReconciliationHistory(
    AlarmReconciliationHistoryEntry(
      scheduleVersion: 5,
      startedAt: try ledgerDate("2026-09-07T14:15:00"),
      completedAt: try ledgerDate("2026-09-07T14:16:00"),
      desiredAlarmCount: 7,
      before: [],
      after: [],
      repairAttempts: 1,
      verified: true
    )
  )

  #expect(state.reconciliationHistory.count == 2)
  #expect(state.reconciliationHistory.last?.desiredAlarmCount == 7)
  #expect(state.reconciliationHistory.last?.repairAttempts == 1)
  #expect(state.reconciliationHistory.first?.before.first?.stableId == "masaz-1400")
  #expect(state.reconciliationHistory.first?.before.first?.hasMismatch == true)
  #expect(state.reconciliationHistory.first?.verified == false)
}

@Test func synchronizationStoresActualAlarmStateBeforeAndAfterAutomaticRepair() async throws {
  let schedule = ledgerSchedule()
  let alarm = try #require(NativeAlarmContract.payload(schedule: schedule).alarms.first)
  let stale = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: "missing-platform-id", alarm: alarm)
  let store = InMemoryAlarmStateStore(ManagedAlarmState(records: [alarm.stableId: stale]))
  let runtime = LedgerRuntime()
  let service = AlarmSyncService(
    scheduleService: LedgerSource(schedule: schedule),
    store: store,
    adapter: runtime
  )

  let result = try await service.synchronize(now: ledgerDate("2026-09-07T09:00:00"))
  #expect(result.succeeded)
  #expect(result.repairAttempts == 1)

  let entry = try #require(result.reconciliationHistory.last)
  let before = try #require(entry.before.first)
  let after = try #require(entry.after.first)
  #expect(before.platformAlarmID == "missing-platform-id")
  #expect(before.platformExists == false)
  #expect(before.hasMismatch)
  #expect(after.platformAlarmID != "missing-platform-id")
  #expect(after.platformExists == true)
  #expect(!after.hasMismatch)
  #expect(entry.verified)
  #expect(entry.hadProblemBeforeChanges)
}

@Test func deniedAlarmAccessIsPersistedBeforeLaterSuccessfulRecovery() async throws {
  let store = InMemoryAlarmStateStore()
  let runtime = LedgerRuntime()
  let service = AlarmSyncService(scheduleService: LedgerSource(schedule: ledgerSchedule()), store: store, adapter: runtime)
  await runtime.setAuthorization(.denied)
  let failed = try await service.synchronize(schedule: ledgerSchedule(), now: ledgerDate("2026-09-07T09:00:00"))
  #expect(!failed.succeeded)
  #expect(await store.load().reconciliationHistory.count == 1)
  await runtime.setAuthorization(.authorized)
  let recovered = try await service.synchronize(schedule: ledgerSchedule(), now: ledgerDate("2026-09-07T09:01:00"))
  #expect(recovered.succeeded)
  #expect(recovered.reconciliationHistory.count == 2)
  #expect(recovered.reconciliationHistory.first?.errorMessage == AlarmAdapterError.authorizationDenied.localizedDescription)
}

@Test func postDepartureCleanupRecordsMissingPastAlarmBeforeRemovingItsMapping() async throws {
  let schedule = ledgerSchedule()
  let alarm = try #require(NativeAlarmContract.payload(schedule: schedule).alarms.first)
  let record = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: "missing-past", alarm: alarm)
  let store = InMemoryAlarmStateStore(ManagedAlarmState(records: [alarm.stableId: record]))
  let service = AlarmSyncService(scheduleService: LedgerSource(schedule: schedule), store: store, adapter: LedgerRuntime())
  let result = try await service.synchronize(now: ledgerDate("2026-09-07T14:15:00"))
  #expect(result.succeeded && result.desiredAlarmCount == 0)
  let before = result.reconciliationHistory.last?.before.first
  #expect(before?.stableId == alarm.stableId)
  #expect(before?.platformAlarmID == "missing-past")
  #expect(before?.platformExists == false)
  #expect(before?.hasMismatch == true)
}

@Test func repeatedGreenChecksDoNotEvictLastUncertainAlarmEvidence() throws {
  var state = ManagedAlarmState()
  let failure = AlarmReconciliationHistoryEntry(scheduleVersion: 5, startedAt: Date(),
    desiredAlarmCount: 8, errorMessage: "Nedoložený alarm před odchodem")
  state.appendReconciliationHistory(failure)
  for _ in 0..<(ManagedAlarmState.reconciliationHistoryLimit * 2) {
    state.appendReconciliationHistory(AlarmReconciliationHistoryEntry(scheduleVersion: 5,
      startedAt: Date(), desiredAlarmCount: 7, verified: true))
  }
  let reopened = try JSONDecoder().decode(ManagedAlarmState.self, from: JSONEncoder().encode(state))
  #expect(reopened.reconciliationHistory.count == ManagedAlarmState.reconciliationHistoryLimit)
  #expect(reopened.reconciliationHistory.contains { $0.id == failure.id })
  #expect(reopened.reconciliationHistory.last?.verified == true)
}

@Test func missingLiveActivityRepairsExistingAlertOnlyAlarmWithoutChangingDeadline() async throws {
  let schedule = ledgerSchedule()
  let store = InMemoryAlarmStateStore()
  let runtime = LedgerRuntime()
  let service = AlarmSyncService(scheduleService: LedgerSource(schedule: schedule), store: store, adapter: runtime)
  let now = try ledgerDate("2026-09-07T09:00:00")
  #expect(try await service.synchronize(now: now).succeeded)
  let original = await store.load().records
  #expect(try await service.synchronize(now: now).appliedCreate == 0)
  #expect(await store.load().records == original)
  await runtime.loseHandoff()
  let repaired = try await service.synchronize(now: now)
  #expect(repaired.succeeded && repaired.repairAttempts == 1 && repaired.appliedCreate == 1)
  let replacement = try #require(await store.load().records.values.first)
  #expect(replacement.platformAlarmID != original.values.first?.platformAlarmID)
  #expect(replacement.alarm == original.values.first?.alarm)
  #expect(await runtime.ownsCountdown(replacement.platformAlarmID))
  #expect(try await service.synchronize(now: now).appliedCreate == 0)
}

private struct LedgerSource: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor LedgerRuntime: AlarmAdapting {
  private var dates: [String: Date] = [:]
  private var hasHandoff = true
  private var countdownIDs = Set<String>()
  func loseHandoff() { hasHandoff = false }
  func ownsCountdown(_ id: String) -> Bool { countdownIDs.contains(id) }
  func invalidPlatformPresentationAlarmIDs(for alarms: [String: NativeAlarm]) -> Set<String> {
    hasHandoff ? [] : Set(alarms.keys).subtracting(countdownIDs)
  }
  private var authorization: AlarmAuthorizationStatus = .authorized
  func setAuthorization(_ value: AlarmAuthorizationStatus) { authorization = value }

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { authorization }
  func requestAuthorization() {}

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = UUID().uuidString
    dates[id] = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    if !hasHandoff { countdownIDs.insert(id) }
    return id
  }

  func cancel(platformAlarmID: String) {
    dates.removeValue(forKey: platformAlarmID)
  }

  func existingPlatformAlarmIDs() -> Set<String>? {
    Set(dates.keys)
  }

  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) -> [String: Date]? {
    dates.filter { platformAlarmIDs.contains($0.key) }
  }
}

private func ledgerSchedule() -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 5,
    updatedAt: "2026-09-07T06:52:00.000Z",
    stay: ["title": "Test"],
    events: [
      ScheduleEvent(
        stableId: "masaz-1400",
        date: "2026-09-07",
        start: "14:00",
        end: "14:20",
        title: "Masáž",
        location: "Rehabilitace",
        kind: .procedure,
        procedureType: "Masáž",
        mealType: nil,
        leadTimeMinutes: 10
      )
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 10,
      procedureTypeOverrides: [:],
      mealOverrides: [:]
    )
  )
}

private func ledgerDate(_ value: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: value)
}
#endif

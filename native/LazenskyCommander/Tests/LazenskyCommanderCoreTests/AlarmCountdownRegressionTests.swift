#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func physicalRegressionFiveMinuteCountdownEndsAt1020Not1025() throws {
  let schedule = countdownRegressionSchedule()
  let alarm = try #require(NativeAlarmContract.payload(schedule: schedule).alarms.last)
  let leaveAt = try regressionDate("10:20:00")
  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: regressionDate("09:34:00"))
  #expect(plan.scheduledStartAt == (try regressionDate("10:15:00")))
  #expect(plan.countdownWindow == 300)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: plan.scheduledStartAt, preAlert: plan.countdownWindow, countdownFireDate: nil) == leaveAt)
  // The old adapter passes leaveAt as the START of a five-minute countdown.
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: leaveAt, preAlert: 300, countdownFireDate: nil) == (try regressionDate("10:25:00")))
  let late = try AlarmCountdown.plan(for: alarm, in: schedule, now: regressionDate("10:17:00"))
  #expect(late.scheduledStartAt == nil)
  #expect(late.countdownWindow == 180)
}

@Test func mealAndProcedureCountdownsVerifyWithoutRepairIncludingImmediateTimer() async throws {
  let schedule = countdownRegressionSchedule()
  let now = try regressionDate("09:34:00")
  let adapter = CountdownRuntimeAdapter(now: now)
  let service = AlarmSyncService(scheduleService: CountdownScheduleSource(value: schedule), store: InMemoryAlarmStateStore(), adapter: adapter)
  let first = try await service.synchronize(now: now)
  #expect(first.succeeded && first.verified)
  #expect(first.appliedCreate == 2)
  #expect(first.repairAttempts == 0)
  #expect(await adapter.immediateTimerCount() == 1)
  let second = try await service.synchronize(now: now.addingTimeInterval(60))
  #expect(second.succeeded && second.plan.unchanged.count == 2)
  #expect(second.appliedCreate == 0 && second.appliedUpdate == 0 && second.appliedCancel == 0)
  #expect(await adapter.calls() == 2)
  #expect(await adapter.cancels() == 0)
}

@Test func existingWrongFixedLeaveAtPlusPreAlertIsRepairedWithoutScheduleVersionChange() async throws {
  let schedule = countdownRegressionSchedule()
  let now = try regressionDate("09:34:00")
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let adapter = CountdownRuntimeAdapter(now: now)
  let state = try await adapter.seedLegacy(payload: payload, schedule: schedule)
  let store = InMemoryAlarmStateStore(state)
  let service = AlarmSyncService(scheduleService: CountdownScheduleSource(value: schedule), store: store, adapter: adapter)
  let summary = try await service.synchronize(now: now)
  #expect(summary.succeeded && summary.verified)
  #expect(summary.scheduleVersion == payload.scheduleVersion)
  #expect(summary.repairAttempts == 1)
  #expect(await adapter.cancels() == 2)
  #expect(await adapter.calls() == 2)
  #expect(await store.load().records.values.allSatisfy { !$0.platformAlarmID.hasPrefix("legacy-") })
  let again = try await service.synchronize(now: now)
  #expect(again.succeeded && again.repairAttempts == 0 && again.plan.unchanged.count == 2)
  #expect(await adapter.calls() == 2)
}

@Test func delayedTimerReadbackDoesNotCancelOrRecreateAndRetryVerifiesSameIDs() async throws {
  let schedule = countdownRegressionSchedule()
  let now = try regressionDate("09:34:00")
  let adapter = CountdownRuntimeAdapter(now: now)
  await adapter.setTimerReadbackAvailable(false)
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: CountdownScheduleSource(value: schedule), store: store, adapter: adapter)
  let first = try await service.synchronize(now: now)
  #expect(!first.succeeded && !first.verified)
  #expect(first.errorMessage == AlarmAdapterError.timingReadbackUnavailable.localizedDescription)
  let saved = await store.load()
  #expect(saved.records.count == 2 && saved.lastSuccessfulPayload == nil)
  let pending = try await service.synchronize(now: now.addingTimeInterval(1))
  #expect(!pending.succeeded && pending.repairAttempts == 0)
  #expect(await adapter.calls() == 2)
  #expect(await adapter.cancels() == 0)
  await adapter.setTimerReadbackAvailable(true)
  let verified = try await service.synchronize(now: now.addingTimeInterval(2))
  #expect(verified.succeeded && verified.plan.unchanged.count == 2)
  #expect(await store.load().records == saved.records)
  #expect(await adapter.calls() == 2)
  #expect(await adapter.cancels() == 0)
}

@Test func expiredTimerWithoutActivityStillCancelsAndDoesNotBlockFutureAlarm() async throws {
  let schedule = countdownRegressionSchedule()
  let adapter = CountdownRuntimeAdapter(now: try regressionDate("09:34:00"))
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: CountdownScheduleSource(value: schedule), store: store, adapter: adapter)
  let first = try await service.synchronize(now: regressionDate("09:34:00"))
  #expect(first.succeeded)
  await adapter.setTimerReadbackAvailable(false)
  let next = try await service.synchronize(now: regressionDate("10:01:00"))
  #expect(next.succeeded && next.desiredAlarmCount == 1)
  #expect(next.appliedCancel == 1 && next.appliedCreate == 0 && next.repairAttempts == 0)
  #expect(await store.load().records.count == 1)
}

@Test func unavailableOldTimerReadbackDoesNotBlockExplicitLeadTimeUpdate() async throws {
  let schedule = countdownRegressionSchedule()
  let adapter = CountdownRuntimeAdapter(now: try regressionDate("09:34:00"))
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: CountdownScheduleSource(value: schedule), store: store, adapter: adapter)
  let first = try await service.synchronize(now: regressionDate("09:34:00"))
  #expect(first.succeeded)
  await adapter.setTimerReadbackAvailable(false)
  let updated = try await service.synchronize(overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 0), now: regressionDate("09:34:00"))
  #expect(updated.succeeded && updated.appliedUpdate == 2 && updated.repairAttempts == 0)
  #expect(await adapter.cancels() == 2)
  #expect(await store.load().records.values.allSatisfy { $0.alarm.leaveAt == $0.alarm.startAt })
}

@Test func SDKAdapterAndBothActivitySurfacesUseSystemCountdownContract() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let adapter = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  let widget = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"), encoding: .utf8)
  #expect(adapter.contains("schedule: countdownPlan.scheduledStartAt.map { .fixed($0) }"))
  #expect(adapter.contains("countdownDuration: Alarm.CountdownDuration("))
  #expect(adapter.contains("preAlert: countdownPlan.countdownWindow"))
  #expect(adapter.contains("postAlert: nil"))
  #expect(adapter.contains("Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities"))
  #expect(adapter.contains("countdownDeadlines[activity.content.state.alarmID.uuidString] = countdown.fireDate"))
  #expect(adapter.contains("if let visibleIDs, !visibleIDs.contains(platformID) { continue }"))
  #expect(!adapter.contains("countdown(id:"))
  #expect(widget.contains("ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self)"))
  #expect(widget.contains("Text(countdown.fireDate, style: .timer)"))
}

private func regressionDate(_ time: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: "2026-08-30T\(time)")
}

private func countdownRegressionSchedule() -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: 9004, updatedAt: "2026-08-30T07:00:00Z", stay: [:], events: [
    ScheduleEvent(stableId: "breakfast", date: "2026-08-30", start: "10:10", end: "10:15", title: "TEST – Snídaně", location: "Jídelna", kind: .meal, procedureType: nil, mealType: "Snídaně", leadTimeMinutes: nil),
    ScheduleEvent(stableId: "magnet", date: "2026-08-30", start: "10:30", end: "10:40", title: "TEST – Magnetoterapie", location: "Elektroléčba", kind: .procedure, procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil)
  ], settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private struct CountdownScheduleSource: ScheduleServing {
  let value: Schedule
  func fetchSchedule() async throws -> Schedule { value }
}

// Models the physically observed SDK runtime, not an echo of the desired leaveAt.
private actor CountdownRuntimeAdapter: AlarmAdapting {
  private struct Reading {
    let fixedStart: Date?
    let preAlert: TimeInterval
    let fireDate: Date?
  }
  private let now: Date
  private var scheduleContext: Schedule?
  private var readings: [String: Reading] = [:]
  private var callCount = 0
  private var cancelCount = 0
  private var timerReadbackAvailable = true

  init(now: Date) { self.now = now }
  func prepare(schedule: Schedule) { scheduleContext = schedule }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let schedule = try #require(scheduleContext)
    let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
    callCount += 1
    let id = "created-\(callCount)"
    let fixed = plan.countdownWindow > 0 ? plan.scheduledStartAt : plan.scheduledAlertAt
    readings[id] = Reading(fixedStart: fixed, preAlert: plan.countdownWindow, fireDate: fixed == nil ? now.addingTimeInterval(plan.countdownWindow) : nil)
    return id
  }
  func seedLegacy(payload: NativeAlarmPayload, schedule: Schedule) throws -> ManagedAlarmState {
    var state = ManagedAlarmState(lastSuccessfulPayload: payload, lastSuccessfulSync: now)
    for alarm in payload.alarms {
      let id = "legacy-\(alarm.stableId)"
      let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
      readings[id] = Reading(fixedStart: plan.scheduledAlertAt, preAlert: plan.countdownWindow, fireDate: nil)
      state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: id, alarm: alarm)
    }
    return state
  }
  func cancel(platformAlarmID: String) { cancelCount += 1; readings.removeValue(forKey: platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(readings.keys) }
  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) throws -> [String: Date]? {
    var dates: [String: Date] = [:]
    for (id, reading) in readings where platformAlarmIDs.contains(id) {
      guard let deadline = AlarmCountdown.effectiveAlertDate(fixedScheduleAt: reading.fixedStart, preAlert: reading.preAlert, countdownFireDate: timerReadbackAvailable ? reading.fireDate : nil) else {
        throw AlarmAdapterError.timingReadbackUnavailable
      }
      dates[id] = deadline
    }
    return dates
  }
  func setTimerReadbackAvailable(_ available: Bool) { timerReadbackAvailable = available }
  func calls() -> Int { callCount }
  func cancels() -> Int { cancelCount }
  func immediateTimerCount() -> Int { readings.values.filter { $0.fixedStart == nil }.count }
}
#endif

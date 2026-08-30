#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func alarmFailureThenVerifiedSuccessWithoutWatchClearsFallbackAndStopsRecovery() async throws {
  let context = try ClosureContext(watchStatus: .sent)
  await context.adapter.setAvailable(false)
  var recovery = CommanderSynchronizationRecovery()
  let failed = try await context.coordinator.synchronize(now: context.now)
  recovery.recordAlarmVerification(succeeded: failed.alarmSummary.succeeded)
  #expect(!failed.succeeded && recovery.needsFallback && recovery.shouldRetry)
  #expect(await context.snapshots.load() == context.schedule)

  await context.adapter.setAvailable(true)
  let verified = try await context.coordinator.synchronize(now: context.now)
  recovery.recordAlarmVerification(succeeded: verified.alarmSummary.succeeded)
  #expect(verified.succeeded && verified.alarmSummary.verified)
  #expect(verified.watchDeliveryStatus == .sent)
  #expect(!recovery.needsFallback && !recovery.shouldRetry)

  let saved = await context.alarms.load()
  for _ in 0..<3 {
    let again = try await context.coordinator.synchronize(now: context.now)
    recovery.recordAlarmVerification(succeeded: again.alarmSummary.succeeded)
    #expect(again.succeeded && again.alarmSummary.plan.unchanged.count == 2)
    #expect(again.alarmSummary.appliedCreate == 0 && again.alarmSummary.appliedCancel == 0)
    #expect(again.alarmSummary.appliedUpdate == 0)
    #expect(!recovery.needsFallback && !recovery.shouldRetry)
  }
  #expect(await context.alarms.load().records == saved.records)
  #expect(await context.adapter.scheduleCalls == 2)
  #expect(await context.adapter.cancelCalls == 0)
}

@Test func verifiedIPhoneSyncDoesNotDependOnOptionalWatchStatus() async throws {
  for status: WatchScheduleDeliveryStatus in [.notConfigured, .queued, .sent, .failed(URLError(.notConnectedToInternet).localizedDescription), .verified] {
    let context = try ClosureContext(watchStatus: status)
    let result = try await context.coordinator.synchronize(now: context.now)
    var recovery = CommanderSynchronizationRecovery()
    recovery.recordAlarmVerification(succeeded: result.alarmSummary.succeeded)
    #expect(result.succeeded && result.alarmSummary.verified)
    #expect(result.watchDeliveryStatus == status)
    #expect(result.watchSnapshot.schedule == context.schedule)
    #expect(!recovery.needsFallback && !recovery.shouldRetry)
  }
}

@Test func verifiedWatchCannotHideFailedAlarmKitProjection() async throws {
  let context = try ClosureContext(watchStatus: .verified)
  await context.adapter.setAvailable(false)
  let result = try await context.coordinator.synchronize(now: context.now)
  var recovery = CommanderSynchronizationRecovery()
  recovery.recordAlarmVerification(succeeded: result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .verified)
  #expect(!result.succeeded && recovery.needsFallback && recovery.shouldRetry)
}

@Test func fallbackCleanupFailureRetriesCleanupWithoutRearmingAfterAlarmRecovery() {
  var recovery = CommanderSynchronizationRecovery()
  recovery.recordAlarmVerification(succeeded: false)
  recovery.recordAlarmVerification(succeeded: true)
  recovery.requestRetry() // Existing fallback could not yet be verified as removed.
  #expect(!recovery.needsFallback && recovery.shouldRetry)
  recovery.recordAlarmVerification(succeeded: true)
  #expect(!recovery.needsFallback && !recovery.shouldRetry)
}

@Test func offlineLeadEditReprojectsValidatedSnapshotAndReadbackWithoutFetchingOrSaving() async throws {
  let context = try ClosureContext(watchStatus: .queued)
  let initial = try await context.coordinator.synchronize(now: context.now)
  #expect(initial.succeeded)
  let originalRecords = await context.alarms.load().records
  await context.network.setOnline(false)
  let overrides = LeadTimeOverrides(defaultLeadTimeMinutes: 15)
  let result = try await context.coordinator.synchronize(
    source: .cached, overrides: overrides, projectionRevision: 1, now: context.now
  )
  #expect(result.succeeded && result.alarmSummary.verified)
  #expect(result.alarmSummary.appliedUpdate == 2)
  #expect(result.scheduleDecision == .unchanged)
  #expect(await context.network.fetches == 1)
  #expect(await context.snapshots.saves == 1)
  #expect(await context.snapshots.load() == context.schedule)
  #expect(result.watchSnapshot.schedule == context.schedule)
  #expect(result.watchSnapshot.leadTimeOverrides == overrides)
  #expect(result.watchSnapshot.projectionRevision == 1)
  #expect(await context.adapter.preparedSchedule == context.schedule)
  #expect(await context.adapter.preparedRevision == 1)
  #expect(await context.adapter.readbacks > 0)
  try await expectDashboardMatchesReadback(context, result: result, overrides: overrides)
  let currentRecords = await context.alarms.load().records
  for (id, record) in currentRecords {
    #expect(record.platformAlarmID != originalRecords[id]?.platformAlarmID)
    #expect(record.alarm.leaveAt != originalRecords[id]?.alarm.leaveAt)
  }
}

@Test func cachedProjectionRejectsMissingOrInvalidSnapshotBeforeTouchingAnyPlatform() async throws {
  for schedule in [nil, closureSchedule(version: 0)] {
    let context = try ClosureContext(watchStatus: .sent, cached: schedule)
    await context.network.setOnline(false)
    await #expect(throws: (any Error).self) {
      try await context.coordinator.synchronize(source: .cached, now: context.now)
    }
    #expect(await context.adapter.scheduleCalls == 0)
    #expect(await context.adapter.preparedSchedule == nil)
    #expect(await context.network.fetches == 0)
    #expect(await context.snapshots.saves == 0)
    #expect(await context.alarms.load().records.isEmpty)
  }
}

@Test func networkReturnPreservesLocalRevisionAndAcceptsOnlyNewerCanonicalSchedule() async throws {
  let context = try ClosureContext(watchStatus: .verified)
  _ = try await context.coordinator.synchronize(now: context.now)
  await context.network.setOnline(false)
  let overrides = LeadTimeOverrides(defaultLeadTimeMinutes: 15)
  _ = try await context.coordinator.synchronize(
    source: .cached, overrides: overrides, projectionRevision: 2, now: context.now
  )
  let offlineRecords = await context.alarms.load().records
  await #expect(throws: URLError.self) {
    try await context.coordinator.synchronize(overrides: overrides, projectionRevision: 2, now: context.now)
  }
  #expect(await context.alarms.load().records == offlineRecords)
  await context.network.setOnline(true)
  let same = try await context.coordinator.synchronize(overrides: overrides, projectionRevision: 2, now: context.now)
  #expect(same.succeeded && same.scheduleDecision == .unchanged)
  #expect(same.alarmSummary.plan.unchanged.count == 2)
  #expect(await context.alarms.load().records == offlineRecords)

  let next = closureSchedule(version: 2, procedureStart: "11:05")
  await context.network.setSchedule(next)
  let accepted = try await context.coordinator.synchronize(overrides: overrides, projectionRevision: 2, now: context.now)
  #expect(accepted.succeeded && accepted.scheduleDecision == .stored)
  #expect(accepted.schedule == next && accepted.watchSnapshot.schedule == next)
  #expect(accepted.watchSnapshot.projectionRevision == 2)
  #expect(accepted.watchSnapshot.leadTimeOverrides == overrides)
  #expect(accepted.alarmSummary.appliedUpdate == 1)
  try await expectDashboardMatchesReadback(context, result: accepted, overrides: overrides)

  await context.network.setSchedule(context.schedule)
  let stale = try await context.coordinator.synchronize(overrides: overrides, projectionRevision: 2, now: context.now)
  #expect(stale.succeeded && stale.scheduleDecision == .rejectedVersion(current: 2, incoming: 1))
  #expect(stale.schedule == next && stale.alarmSummary.plan.unchanged.count == 2)
  #expect(await context.snapshots.load() == next)
  #expect(await context.snapshots.saves == 2)
}

@Test func localAndRemoteRequestsCoalesceSeparatelyAndLocalProjectionRunsFirst() {
  for current: CommanderScheduleSource in [.remote, .cached] {
    var queue = CommanderSynchronizationRequestQueue()
    #expect(queue.submit(maxAttempts: 3, automatic: true, source: current)?.source == current)
    #expect(queue.submit(maxAttempts: 2, automatic: true) == nil)
    #expect(queue.submit(maxAttempts: 1, automatic: false, source: .cached) == nil)
    #expect(queue.submit(maxAttempts: 3, automatic: false, source: .cached) == nil)
    #expect(queue.hasPendingCachedProjection)
    #expect(queue.completeCurrentAndTakeNext() == CommanderSynchronizationRequest(maxAttempts: 3, automatic: false, source: .cached))
    #expect(!queue.hasPendingCachedProjection)
    #expect(queue.completeCurrentAndTakeNext() == CommanderSynchronizationRequest(maxAttempts: 2, automatic: true))
    #expect(queue.completeCurrentAndTakeNext() == nil)
  }
}

@Test func appBindsLocalEditsAndRetriesToCachedSourceAndSharedRecoveryPolicy() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift"), encoding: .utf8)
  #expect(app.contains("synchronizeWithRecovery(maxAttempts: 3, automatic: false, source: .cached)"))
  #expect(app.contains("source: request.source"))
  #expect(app.contains("synchronizeWithRecovery(maxAttempts: 2, automatic: true, source: source)"))
  #expect(app.contains("recovery.recordAlarmVerification(succeeded: result.alarmSummary.succeeded)"))
  #expect(app.contains("if recovery.needsFallback, let latestSchedule"))
  #expect(app.contains("if recovery.shouldRetry"))
  #expect(!app.contains("alarmProjectionFailed"))
  #expect(!app.contains("if result.succeeded"))
}

private func expectDashboardMatchesReadback(
  _ context: ClosureContext,
  result: CommanderScheduleSyncResult,
  overrides: LeadTimeOverrides
) async throws {
  let dashboard = CommanderDashboardPresentation.make(schedule: result.schedule, now: context.now, overrides: overrides)
  let records = await context.alarms.load().records
  let dates = try #require(await context.adapter.existingPlatformFixedAlertDates(for: Set(records.values.map(\.platformAlarmID))))
  #expect(dashboard.timeline.count == 2)
  for item in dashboard.timeline {
    let record = try #require(records[item.event.stableId])
    #expect(dates[record.platformAlarmID] == item.leaveAt)
    #expect(try NativeAlarmContract.date(fromLocalISO: record.alarm.leaveAt) == item.leaveAt)
  }
}

private struct ClosureContext {
  let schedule: Schedule
  let now: Date
  let network: ClosureNetwork
  let snapshots: ClosureSnapshots
  let alarms = InMemoryAlarmStateStore()
  let adapter: ClosureAlarmRuntime
  let coordinator: CommanderScheduleSyncCoordinator

  init(watchStatus: WatchScheduleDeliveryStatus, cached: Schedule? = nil) throws {
    schedule = closureSchedule()
    now = try NativeAlarmContract.date(fromLocalISO: "2026-08-30T10:00:00")
    network = ClosureNetwork(schedule: schedule)
    snapshots = ClosureSnapshots(schedule: cached)
    adapter = ClosureAlarmRuntime(now: now)
    coordinator = CommanderScheduleSyncCoordinator(
      scheduleService: network,
      alarmSyncService: AlarmSyncService(scheduleService: network, store: alarms, adapter: adapter),
      scheduleStore: snapshots,
      watchDelivery: watchStatus == .notConfigured ? nil : ClosureWatch(status: watchStatus)
    )
  }
}

private func closureSchedule(version: Int = 1, procedureStart: String = "11:00") -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-08-30T07:00:00Z", stay: [:], events: [
    ScheduleEvent(stableId: "closure-meal", date: "2026-08-30", start: "10:30", end: "10:40", title: "Breakfast", location: "Dining room", kind: .meal, procedureType: nil, mealType: "Breakfast", leadTimeMinutes: nil),
    ScheduleEvent(stableId: "closure-procedure", date: "2026-08-30", start: procedureStart, end: "11:20", title: "Magnetoterapie", location: "Balneo", kind: .procedure, procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil)
  ], settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private actor ClosureNetwork: ScheduleServing {
  private var schedule: Schedule
  private var online = true
  private(set) var fetches = 0
  init(schedule: Schedule) { self.schedule = schedule }
  func setOnline(_ value: Bool) { online = value }
  func setSchedule(_ value: Schedule) { schedule = value }
  func fetchSchedule() throws -> Schedule {
    fetches += 1
    guard online else { throw URLError(.notConnectedToInternet) }
    return schedule
  }
}

private actor ClosureSnapshots: ScheduleSnapshotStoring {
  private var schedule: Schedule?
  private(set) var saves = 0
  init(schedule: Schedule?) { self.schedule = schedule }
  func load() -> Schedule? { schedule }
  func save(_ value: Schedule) { saves += 1; schedule = value }
}

// Platform read-back is computed from the stored SDK timing arguments, not desired metadata.
private actor ClosureAlarmRuntime: AlarmAdapting {
  private let now: Date
  private var available = true
  private var deadlines: [String: Date] = [:]
  private(set) var preparedSchedule: Schedule?
  private(set) var preparedRevision = 0
  private(set) var scheduleCalls = 0
  private(set) var cancelCalls = 0
  private(set) var readbacks = 0
  init(now: Date) { self.now = now }
  func setAvailable(_ value: Bool) { available = value }
  func availability() -> AlarmKitAvailability { available ? .available : .unavailable("test failure") }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func prepare(schedule: Schedule, projectionRevision: Int) {
    preparedSchedule = schedule
    preparedRevision = projectionRevision
  }
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let plan = try AlarmCountdown.plan(for: alarm, in: #require(preparedSchedule), now: now)
    let fixed = plan.countdownWindow > 0 ? plan.scheduledStartAt : plan.scheduledAlertAt
    let endpoint = try #require(AlarmCountdown.effectiveAlertDate(
      fixedScheduleAt: fixed, preAlert: plan.countdownWindow,
      countdownFireDate: fixed == nil ? now.addingTimeInterval(plan.countdownWindow) : nil
    ))
    scheduleCalls += 1
    let id = "closure-alarm-\(scheduleCalls)"
    deadlines[id] = endpoint
    return id
  }
  func cancel(platformAlarmID: String) {
    cancelCalls += 1
    deadlines.removeValue(forKey: platformAlarmID)
  }
  func existingPlatformAlarmIDs() async -> Set<String>? { Set(deadlines.keys) }
  func existingPlatformFixedAlertDates(for ids: Set<String>) async -> [String: Date]? {
    readbacks += 1
    return deadlines.filter { ids.contains($0.key) }
  }
}

private actor ClosureWatch: WatchScheduleSnapshotDelivering {
  private let status: WatchScheduleDeliveryStatus
  private var snapshot: WatchScheduleSnapshot?
  init(status: WatchScheduleDeliveryStatus) { self.status = status }
  func deliver(_ snapshot: WatchScheduleSnapshot) throws -> WatchScheduleDeliveryDisposition {
    self.snapshot = snapshot
    switch status {
    case .failed: throw URLError(.notConnectedToInternet)
    case .queued: return .queued
    default: return .sent
    }
  }
  func verifiedProjectionIdentity() -> WatchScheduleProjectionIdentity? {
    status == .verified ? snapshot?.projectionIdentity : nil
  }
}
#endif

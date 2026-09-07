#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func stopDecisionPreservesRedUntilExactStartWithAndWithoutExistingCard() throws {
  let start = try stabilizationDate("10:30")
  for hasHandoff in [false, true] {
    for seconds in [-600.0, -1, -0.001] {
      #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: hasHandoff, startAt: start,
        now: start.addingTimeInterval(seconds)) == (hasHandoff ? .bridgeUntilStart : .retainAlarmUntilStart))
    }
    for seconds in [0.0, 0.001, 60] {
      #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: hasHandoff, startAt: start,
        now: start.addingTimeInterval(seconds)) == .dismiss)
    }
  }
}

@Test func foregroundCleanupRetainsEndedRedCardOnlyForCurrentCanonicalDeparture() throws {
  let schedule = stabilizationSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms[1]
  for time in ["10:20", "10:25", "10:29:59"] {
    #expect(CommanderLiveActivityHandoff.retainsBridge(storedTarget: alarm, currentTarget: alarm,
      now: try stabilizationDate(time)))
  }
  for time in ["10:19:59", "10:30", "10:40"] {
    #expect(!CommanderLiveActivityHandoff.retainsBridge(storedTarget: alarm, currentTarget: alarm,
      now: try stabilizationDate(time)))
  }
  let updated = try NativeAlarmContract.payload(schedule: schedule,
    overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 15)).alarms[1]
  #expect(!CommanderLiveActivityHandoff.retainsBridge(storedTarget: alarm, currentTarget: updated,
    now: try stabilizationDate("10:25")))
  #expect(!CommanderLiveActivityHandoff.retainsBridge(storedTarget: alarm, currentTarget: nil,
    now: try stabilizationDate("10:25")))
}

@Test func freeTimeOwnerCannotSuppressGreenActivityAtNextStart() throws {
  let end = try stabilizationDate("10:15")
  let start = try stabilizationDate("10:30")
  for (time, expected) in [("10:14:59", false), ("10:15", true), ("10:25", true), ("10:29:59", true), ("10:30", false), ("10:31", false)] {
    #expect(CommanderLiveActivityHandoff.retainsFreeTime(previousEnd: end, targetStart: start,
      now: try stabilizationDate(time)) == expected)
  }
}

@Test func sharedHandoffSelectionRejectsSkippedAndCrossDaySources() throws {
  let schedule = stabilizationSchedule()
  let alarms = try NativeAlarmContract.payload(schedule: schedule).alarms
  #expect(!CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarms[0], in: schedule))
  #expect(CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarms[1], in: schedule))
  #expect(CommanderLiveActivityHandoff.nextEvent(after: schedule.events[0], in: schedule)?.stableId == "procedure")
  let reversed = stabilizationSchedule(events: schedule.events.reversed())
  #expect(CommanderLiveActivityHandoff.nextEvent(after: schedule.events[0], in: reversed)?.stableId == "procedure")
  let inserted = ScheduleEvent(stableId: "intervening", date: "2026-09-06", start: "10:16", end: "10:25", title: "Kontrola", location: "A", kind: .procedure, procedureType: nil, mealType: nil, leadTimeMinutes: 0)
  let crowded = stabilizationSchedule(events: schedule.events + [inserted])
  #expect(!CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarms[1], in: crowded))
  let tomorrow = ScheduleEvent(stableId: "tomorrow", date: "2026-09-07", start: "10:30", end: "10:40", title: "Zítra", location: "A", kind: .procedure, procedureType: nil, mealType: nil, leadTimeMinutes: nil)
  let multiDay = stabilizationSchedule(events: [schedule.events[0], tomorrow])
  #expect(CommanderLiveActivityHandoff.nextEvent(after: schedule.events[0], in: multiDay) == nil)
}

@Test func entireAlarmFlowAgreesAcrossDashboardWatchAndCanonicalBoundaries() throws {
  let schedule = stabilizationSchedule()
  for (time, state, id): (String, CommanderLiveState, String?) in [
    ("09:59:59", .upcoming, "meal"), ("10:00", .leaveNow, "meal"),
    ("10:09:59", .leaveNow, "meal"), ("10:10", .inProgress, "meal"),
    ("10:15", .upcoming, "procedure"), ("10:20", .leaveNow, "procedure"),
    ("10:29:59", .leaveNow, "procedure"), ("10:30", .inProgress, "procedure"),
    ("10:40", .dayDone, nil)
  ] {
    let now = try stabilizationDate(time)
    let live = CommanderLiveStateCalculator.compute(schedule: schedule, now: now)
    #expect(live.state == state && live.event?.stableId == id)
    let watch = try #require(WatchTimelinePlanner.points(schedule: schedule, now: now).first)
    #expect(watch.state == state && watch.stableId == id)
    let dashboard = CommanderDashboardPresentation.make(schedule: schedule, now: now)
    #expect(dashboard.liveState == live)
  }
}

@Test func sameVersionWatchRevisionCannotSmuggleCanonicalChanges() throws {
  let old = WatchScheduleSnapshot(schedule: stabilizationSchedule(), projectionRevision: 1)
  let conflict = WatchScheduleSnapshot(schedule: stabilizationSchedule(title: "Jiný rozpis"), projectionRevision: 2)
  #expect(WatchScheduleCachePolicy.decision(incoming: conflict, existing: old) == .rejectedVersion(current: 1, incoming: 1))
  let valid = WatchScheduleSnapshot(schedule: old.schedule, leadTimeOverrides: LeadTimeOverrides(defaultLeadTimeMinutes: 15), projectionRevision: 2)
  #expect(WatchScheduleCachePolicy.decision(incoming: valid, existing: old) == .stored)
}

@Test func watchDiskCacheRejectsInvalidLocalProjectionAndKeepsLastValidBytes() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let valid = WatchScheduleSnapshot(schedule: stabilizationSchedule(), projectionRevision: 1)
  #expect(try await cache.accept(valid) == .stored)
  let file = directory.appendingPathComponent(FileWatchScheduleCache.defaultFileName)
  let original = try Data(contentsOf: file)
  let invalid = WatchScheduleSnapshot(schedule: valid.schedule, leadTimeOverrides: LeadTimeOverrides(defaultLeadTimeMinutes: -1), projectionRevision: 2)
  #expect(try await cache.accept(invalid) == .rejectedInvalid)
  #expect(try Data(contentsOf: file) == original)
  try JSONEncoder().encode(invalid).write(to: file)
  #expect(try await cache.load() == nil)
}

@Test func concurrentCanonicalAcceptanceNeverRollsBackNewestVersion() async throws {
  let store: any ScheduleSnapshotStoring = InMemoryScheduleSnapshotStore()
  try await withThrowingTaskGroup(of: Void.self) { group in
    for version in 1...30 {
      group.addTask { _ = try await store.accept(stabilizationSchedule(version: version)) }
    }
    try await group.waitForAll()
  }
  #expect(try await store.load()?.scheduleVersion == 30)
}

@Test func persistedCanonicalAcceptanceSurvivesRestartAndRejectsConflictingVersion() async throws {
  let key = "stabilization." + UUID().uuidString
  defer { UserDefaults.standard.removeObject(forKey: key) }
  let first: any ScheduleSnapshotStoring = UserDefaultsScheduleSnapshotStore(key: key)
  #expect(try await first.accept(stabilizationSchedule(version: 2)) == .stored)
  let reopened: any ScheduleSnapshotStoring = UserDefaultsScheduleSnapshotStore(key: key)
  #expect(try await reopened.accept(stabilizationSchedule()) == .rejectedVersion(current: 2, incoming: 1))
  #expect(try await reopened.accept(stabilizationSchedule(version: 2, title: "Conflict")) == .rejectedVersion(current: 2, incoming: 2))
  #expect(try await reopened.load() == stabilizationSchedule(version: 2))
}

@Test func failedCancellationBeforeRepairKeepsManagedIDAndNeverCreatesDuplicate() async throws {
  let schedule = stabilizationSchedule(events: [stabilizationSchedule().events[0]])
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms[0]
  let record = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: "original", alarm: alarm)
  let store = InMemoryAlarmStateStore(ManagedAlarmState(records: [alarm.stableId: record]))
  let runtime = CancelFailureRuntime(original: alarm)
  let source = StabilizationSource(schedule: schedule)
  let service = AlarmSyncService(scheduleService: source, store: store, adapter: runtime)
  let failed = try await service.synchronize(now: stabilizationDate("09:00"))
  #expect(!failed.succeeded)
  #expect(await store.load().records[alarm.stableId] == record)
  #expect(await runtime.creates == 0)
  await runtime.allowCancellation()
  let repaired = try await service.synchronize(now: stabilizationDate("09:00"))
  #expect(repaired.succeeded)
  #expect(await runtime.creates == 1)
  #expect(await runtime.ids.count == 1)
}


@Test func neighbourChangeRefreshesStopIntentWithoutChangingOwnAlarmDeadline() async throws {
  let first = stabilizationSchedule()
  let runtime = ContextRuntime()
  let store = InMemoryAlarmStateStore()
  let source = StabilizationSource(schedule: first)
  let service = AlarmSyncService(scheduleService: source, store: store, adapter: runtime)
  #expect(try await service.synchronize(schedule: first, now: stabilizationDate("09:00")).succeeded)
  let old = await store.load().records
  let changedEvent = ScheduleEvent(stableId: "procedure", date: "2026-09-06", start: "10:35", end: "10:45", title: "Nová procedura", location: "Jiné místo", kind: .procedure, procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil)
  let changed = stabilizationSchedule(version: 2, events: [first.events[0], changedEvent])
  let updated = try await service.synchronize(schedule: changed, now: stabilizationDate("09:00"))
  #expect(updated.succeeded && updated.appliedUpdate == 2)
  let records = await store.load().records
  #expect(records["meal"]?.alarm == old["meal"]?.alarm)
  #expect(records["meal"]?.platformAlarmID != old["meal"]?.platformAlarmID)
  #expect(records["meal"]?.presentationContext?.nextAlarm?.title == "Nová procedura")
  let repeated = try await service.synchronize(schedule: changed, now: stabilizationDate("09:00"))
  #expect(repeated.succeeded && repeated.plan.unchanged.count == 2 && repeated.appliedUpdate == 0)
  let versionOnly = stabilizationSchedule(version: 3, events: changed.events)
  let sameContent = try await service.synchronize(schedule: versionOnly, now: stabilizationDate("09:00"))
  #expect(sameContent.succeeded && sameContent.appliedUpdate == 0)
}

@Test func legacyAlarmPersistenceMigratesContextOnceWithoutChangingCanonicalPayload() async throws {
  let schedule = stabilizationSchedule()
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let runtime = ContextRuntime()
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: StabilizationSource(schedule: schedule), store: store, adapter: runtime)
  _ = try await service.synchronize(now: stabilizationDate("09:00"))
  let current = await store.load()
  var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
  var records = try #require(json["records"] as? [String: [String: Any]])
  for id in records.keys { records[id]?.removeValue(forKey: "presentationContext") }
  json["records"] = records
  let legacy = try JSONDecoder().decode(ManagedAlarmState.self, from: JSONSerialization.data(withJSONObject: json))
  await store.save(legacy)
  #expect(try await service.synchronize(now: stabilizationDate("09:00")).appliedUpdate == 2)
  #expect(try await service.synchronize(now: stabilizationDate("09:00")).appliedUpdate == 0)
  #expect(try NativeAlarmContract.payload(schedule: schedule) == payload)
}

private actor ContextRuntime: AlarmAdapting {
  private var context: Schedule?
  private var overrides: LeadTimeOverrides?
  private var dates: [String: Date] = [:]
  private var alerting: Set<String> = []
  func beginAlerting() { alerting = Set(dates.keys) }
  func stopAlerting() { for id in alerting { dates.removeValue(forKey: id) }; alerting = [] }
  func existingPlatformAlertingAlarmIDs() -> Set<String> { alerting }
  func prepare(schedule: Schedule, projectionRevision: Int, overrides: LeadTimeOverrides?) {
    context = schedule; self.overrides = overrides
  }
  func presentationContext(for alarm: NativeAlarm) throws -> AlarmPresentationContext? {
    try context.map { try AlarmPresentationContext(alarm: alarm, schedule: $0, overrides: overrides) }
  }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = UUID().uuidString
    dates[id] = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    return id
  }
  func cancel(platformAlarmID: String) { dates.removeValue(forKey: platformAlarmID); alerting.remove(platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(dates.keys) }
  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) -> [String: Date]? {
    dates.filter { platformAlarmIDs.contains($0.key) && !alerting.contains($0.key) }
  }
}


@Test func asynchronousNotificationOperationsNeverOverlapAndFailureDoesNotBlockNext() async {
  let queue = CommanderSerialOperationQueue()
  let probe = SerialProbe()
  await withTaskGroup(of: Void.self) { group in
    for number in 0..<20 {
      group.addTask {
        _ = try? await queue.run {
          await probe.enter()
          for _ in 0..<5 { await Task.yield() }
          await probe.leave()
          if number == 0 { throw AlarmAdapterError.verificationFailed }
        }
      }
    }
  }
  #expect(await probe.maximumActive == 1)
  #expect(await probe.completed == 20)
}

private actor SerialProbe {
  private var active = 0
  var maximumActive = 0
  var completed = 0
  func enter() { active += 1; maximumActive = max(maximumActive, active) }
  func leave() { active -= 1; completed += 1 }
}


@Test func failedCancellationDuringPostWriteRepairKeepsNewIDForSafeRetry() async throws {
  let schedule = stabilizationSchedule(events: [stabilizationSchedule().events[0]])
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms[0]
  let runtime = CancelFailureRuntime(original: alarm, seedExisting: false, wrongFirstCreation: true)
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: StabilizationSource(schedule: schedule), store: store, adapter: runtime)
  let failed = try await service.synchronize(now: stabilizationDate("09:00"))
  #expect(!failed.succeeded)
  #expect(await runtime.creates == 1)
  #expect(await store.load().records[alarm.stableId]?.platformAlarmID == "replacement-1")
  await runtime.allowCancellation()
  #expect(try await service.synchronize(now: stabilizationDate("09:00")).succeeded)
  #expect(await runtime.ids.count == 1)
  #expect(await runtime.creates == 2)
}


@Test func foregroundReconciliationDoesNotSilenceRingingCanonicalAlarmOrRecreateStoppedAlarm() async throws {
  let schedule = stabilizationSchedule(events: [stabilizationSchedule().events[0]])
  let runtime = ContextRuntime()
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: StabilizationSource(schedule: schedule), store: store, adapter: runtime)
  _ = try await service.synchronize(now: stabilizationDate("09:00"))
  let original = await store.load().records
  await runtime.beginAlerting()
  for time in ["10:00", "10:05", "10:10"] {
    let refreshed = try await service.synchronize(now: stabilizationDate(time))
    #expect(refreshed.succeeded)
    #expect(refreshed.appliedCancel == 0 && refreshed.appliedCreate == 0 && refreshed.appliedUpdate == 0)
    #expect(await store.load().records == original)
  }
  await runtime.stopAlerting()
  let stopped = try await service.synchronize(now: stabilizationDate("10:11"))
  #expect(stopped.succeeded && stopped.appliedCreate == 0)
  #expect(await store.load().records.isEmpty)
}

@Test func ringingProtectionDoesNotKeepRemovedOrFinishedCanonicalEvents() async throws {
  for remove in [false, true] {
    let schedule = stabilizationSchedule(events: [stabilizationSchedule().events[0]])
    let runtime = ContextRuntime()
    let store = InMemoryAlarmStateStore()
    let service = AlarmSyncService(scheduleService: StabilizationSource(schedule: schedule), store: store, adapter: runtime)
    _ = try await service.synchronize(now: stabilizationDate("09:00"))
    await runtime.beginAlerting()
    let next = remove ? stabilizationSchedule(version: 2, events: []) : schedule
    let result = try await service.synchronize(schedule: next, now: stabilizationDate(remove ? "10:05" : "10:15"))
    #expect(result.succeeded && result.appliedCancel == 1 && result.appliedCreate == 0)
    #expect(await store.load().records.isEmpty)
  }
}

@Test func watchReadbackChecksActualTriggerAndContentInsteadOfTrustingMetadata() throws {
  let item = WatchLocalNotification(stableId: "meal", leaveAt: "2026-09-06T10:00:00", title: "Jídlo", location: "Jídelna")
  let date = try stabilizationDate("10:00")
  for delta in [-1.0, 0, 1] {
    #expect(item.matchesObservedRequest(title: item.notificationTitle, body: item.notificationBody,
      fireDate: date.addingTimeInterval(delta), repeats: false, hasSound: true))
  }
  for observed in [date.addingTimeInterval(-60), date.addingTimeInterval(60), nil] {
    #expect(!item.matchesObservedRequest(title: item.notificationTitle, body: item.notificationBody,
      fireDate: observed, repeats: false, hasSound: true))
  }
  #expect(!item.matchesObservedRequest(title: "Starý nadpis", body: item.notificationBody,
    fireDate: date, repeats: false, hasSound: true))
  #expect(!item.matchesObservedRequest(title: item.notificationTitle, body: "Staré místo",
    fireDate: date, repeats: false, hasSound: true))
  #expect(!item.matchesObservedRequest(title: item.notificationTitle, body: item.notificationBody,
    fireDate: date, repeats: true, hasSound: true))
  #expect(!item.matchesObservedRequest(title: item.notificationTitle, body: item.notificationBody,
    fireDate: date, repeats: false, hasSound: false))
}

@Test func sameWatchPayloadRepairsInvalidRequestAndRetryStopsOnlyAfterReadbackMatches() throws {
  let schedule = stabilizationSchedule()
  let desired = try WatchLocalNotificationPlanner.notifications(schedule: schedule, now: stabilizationDate("09:00"))
  let invalid = Set([desired[0].identifier])
  let repair = WatchNotificationReconciler.reconcile(current: desired, next: desired, invalidIdentifiers: invalid)
  #expect(repair.update == [desired[0]] && repair.unchanged == [desired[1]])
  #expect(repair.create.isEmpty && repair.cancel.isEmpty)
  // A write acknowledgement with unchanged bad OS content is still a failure.
  #expect(WatchNotificationReconciler.reconcile(current: desired, next: desired, invalidIdentifiers: invalid).hasChanges)
  #expect(!WatchNotificationReconciler.reconcile(current: desired, next: desired).hasChanges)
}

@Test func watchAppAndWidgetUseSameExpiryBoundaryWithoutDiscardingPersistedSchedule() throws {
  let schedule = stabilizationSchedule()
  let expiry = try #require(try WatchScheduleExpiryPolicy.expirationDate(for: schedule))
  for (date, expected): (Date, CommanderLiveState) in [(expiry.addingTimeInterval(-1), .dayDone), (expiry, .noSchedule)] {
    let app = CommanderLiveStateCalculator.compute(schedule: WatchScheduleExpiryPolicy.activeSchedule(schedule, at: date), now: date)
    let widget = try #require(WatchTimelinePlanner.points(schedule: schedule, now: date).first)
    #expect(app.state == expected && widget.state == expected)
  }
  #expect(schedule.events.count == 2)
}

@Test func slowFetchUsesAcceptanceTimeAndCannotRecreateAnAlarmWhoseDepartureJustPassed() async throws {
  let schedule = stabilizationSchedule()
  let clock = StabilizationClock(try stabilizationDate("09:59:59"))
  let source = AdvancingScheduleSource(schedule: schedule, clock: clock, afterFetch: try stabilizationDate("10:00"))
  let store = InMemoryAlarmStateStore()
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: AlarmSyncService(scheduleService: source, store: store, adapter: ContextRuntime()),
    scheduleStore: InMemoryScheduleSnapshotStore(), clock: { clock.read() }
  )
  let result = try await coordinator.synchronize()
  #expect(result.succeeded && result.alarmSummary.desiredAlarmCount == 1)
  #expect(await store.load().records["meal"] == nil)
  #expect(await store.load().records["procedure"] != nil)
  #expect(result.schedule == schedule)
}

private final class StabilizationClock: @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date
  init(_ date: Date) { self.date = date }
  func read() -> Date { lock.withLock { date } }
  func set(_ value: Date) { lock.withLock { date = value } }
}

private struct AdvancingScheduleSource: ScheduleServing {
  let schedule: Schedule
  let clock: StabilizationClock
  let afterFetch: Date
  func fetchSchedule() async throws -> Schedule {
    clock.set(afterFetch)
    return schedule
  }
}

private func stabilizationDate(_ time: String) throws -> Date {
  let parts = time.split(separator: ":")
  let minute = try NativeAlarmContract.dateTime(date: "2026-09-06", time: parts.prefix(2).joined(separator: ":"))
  return minute.addingTimeInterval(parts.count == 3 ? Double(parts[2])! : 0)
}

private func stabilizationSchedule(version: Int = 1, title: String = "Jídlo", events: [ScheduleEvent]? = nil) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-06T07:00:00Z", stay: [:], events: events ?? [
    ScheduleEvent(stableId: "meal", date: "2026-09-06", start: "10:10", end: "10:15", title: title, location: "Jídelna", kind: .meal, procedureType: nil, mealType: "Oběd", leadTimeMinutes: nil),
    ScheduleEvent(stableId: "procedure", date: "2026-09-06", start: "10:30", end: "10:40", title: "Magnetoterapie", location: "Balneo", kind: .procedure, procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil)
  ], settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private struct StabilizationSource: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor CancelFailureRuntime: AlarmAdapting {
  var ids: Set<String> = ["original"]
  var creates = 0
  private var cancellationAllowed = false
  private let wrongFirstCreation: Bool
  private let original: NativeAlarm
  init(original: NativeAlarm, seedExisting: Bool = true, wrongFirstCreation: Bool = false) {
    self.original = original
    self.wrongFirstCreation = wrongFirstCreation
    if !seedExisting { ids = [] }
  }
  func allowCancellation() { cancellationAllowed = true }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) -> String {
    creates += 1
    let id = "replacement-\(creates)"
    ids.insert(id)
    return id
  }
  func cancel(platformAlarmID: String) throws {
    guard cancellationAllowed else { throw AlarmAdapterError.unavailable("cancel failed") }
    ids.remove(platformAlarmID)
  }
  func existingPlatformAlarmIDs() -> Set<String>? { ids }
  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) throws -> [String: Date]? {
    let expected = try NativeAlarmContract.date(fromLocalISO: original.leaveAt)
    return Dictionary(uniqueKeysWithValues: ids.intersection(platformAlarmIDs).map {
      ($0, ($0 == "original" || (wrongFirstCreation && $0 == "replacement-1")) ? expected.addingTimeInterval(300) : expected)
    })
  }
}
#endif

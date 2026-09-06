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

private func stabilizationDate(_ time: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: "2026-09-06T" + time + (time.count == 5 ? ":00" : ""))
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
  private let original: NativeAlarm
  init(original: NativeAlarm) { self.original = original }
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
      ($0, $0 == "original" ? expected.addingTimeInterval(300) : expected)
    })
  }
}
#endif

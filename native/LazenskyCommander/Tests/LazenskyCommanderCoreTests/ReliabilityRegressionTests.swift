import Foundation
import Testing
@testable import LazenskyCommanderCore

private func reliabilitySchedule(_ version: Int = 1) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-29T00:00:00Z",
    stay: [:], events: [ScheduleEvent(stableId: "reliability-event", date: "2026-09-29",
      start: "10:00", end: "10:30", title: "Masáž", location: "A", kind: .procedure,
      procedureType: "Masáž", mealType: nil, leadTimeMinutes: nil)],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private struct ReliabilitySource: ScheduleServing {
  let schedule: Schedule
  var fails = false
  func fetchSchedule() async throws -> Schedule {
    if fails { throw URLError(.notConnectedToInternet) }
    return schedule
  }
}

@Test func reservedAlarmIdentitySurvivesRestartBeforeManagedStateWasWritten() async throws {
  let suite = "commander.reliability." + UUID().uuidString
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer { try? FileManager.default.removeItem(at: directory) }
  defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
  let ledger = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!,
    directoryURL: directory, key: "ownership", legacyStateKey: "managed")
  let first = try await ledger.reserve(stableID: "event")
  let restarted = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!,
    directoryURL: directory, key: "ownership", legacyStateKey: "managed")
  #expect(try await restarted.reserve(stableID: "event") == first)
  #expect(try await restarted.ids() == [first])
  try await restarted.forget(first)
  try await restarted.forget(first)
  #expect(try await restarted.ids().isEmpty)
}

@Test func ownershipMigrationIncludesOnlyPreviouslyManagedIDsAndNeverForeignIDs() async throws {
  let suite = "commander.reliability." + UUID().uuidString
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer { try? FileManager.default.removeItem(at: directory) }
  defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
  let alarm = try #require(NativeAlarmContract.payload(schedule: reliabilitySchedule()).alarms.first)
  let id = UUID().uuidString
  let foreign = UUID().uuidString
  let state = ManagedAlarmState(records: [alarm.stableId: ManagedAlarmRecord(
    stableId: alarm.stableId, platformAlarmID: id, alarm: alarm)])
  UserDefaults(suiteName: suite)!.set(try JSONEncoder().encode(state), forKey: "managed")
  let ledger = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!,
    directoryURL: directory, key: "ownership", legacyStateKey: "managed")
  #expect(try await ledger.ids() == [id])
  #expect(try await ledger.reserve(stableID: alarm.stableId) == id)
  #expect(try await ledger.ids().intersection([id, foreign]) == [id])
  try await ledger.forget(id)
  // Legacy mappings must not resurrect an already cancelled alarm on relaunch.
  let restarted = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!,
    directoryURL: directory, key: "ownership", legacyStateKey: "managed")
  #expect(try await restarted.ids().isEmpty)
}

@Test func corruptAlarmPersistenceFailsClosedAndPreservesRecoveryEvidence() async throws {
  let suite = "commander.reliability." + UUID().uuidString
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
  defer { try? FileManager.default.removeItem(at: directory) }
  defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
  let bytes = Data("interrupted-state".utf8)
  UserDefaults(suiteName: suite)!.set(bytes, forKey: "managed")
  let store = UserDefaultsAlarmStateStore(defaults: UserDefaults(suiteName: suite)!, key: "managed")
  do { _ = try await store.load(); Issue.record("Corrupt state was accepted") } catch {}
  #expect(UserDefaults(suiteName: suite)!.data(forKey: "managed") == bytes)
  let ledger = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!,
    directoryURL: directory, key: "ownership", legacyStateKey: "managed")
  do { _ = try await ledger.reserve(stableID: "event"); Issue.record("Corrupt migration created an ID") } catch {}
  #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("ownership.json").path))
}

private actor ReliabilityAlarmAdapter: AlarmAdapting {
  private(set) var creates = 0
  private var alarms: [String: Date] = [:]
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing: String?) async throws -> String {
    creates += 1
    await Task.yield()
    let id = UUID().uuidString
    alarms[id] = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    return id
  }
  func cancel(platformAlarmID: String) { alarms.removeValue(forKey: platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(alarms.keys) }
  func existingPlatformFixedAlertDates() -> [String: Date]? { alarms }
}

@Test func concurrentReconciliationOfSameScheduleCreatesOneAlarm() async throws {
  let schedule = reliabilitySchedule()
  let adapter = ReliabilityAlarmAdapter()
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: ReliabilitySource(schedule: schedule), store: store, adapter: adapter)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-29T09:00:00")
  try await withThrowingTaskGroup(of: AlarmSyncSummary.self) { group in
    for _ in 0..<20 {
      group.addTask { try await service.synchronize(schedule: schedule, now: now) }
    }
    for try await summary in group { #expect(summary.succeeded) }
  }
  #expect(await adapter.creates == 1)
  #expect(await store.load().records.count == 1)
}

@Test func widgetKeepsValidatedSnapshotAcrossOfflineRelaunchAndRejectsStaleFeed() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory, dataset: .production)
  let latest = WatchScheduleSnapshot(schedule: reliabilitySchedule(3))
  _ = try await cache.accept(latest)
  let offline = CommanderWidgetSnapshotLoader(service: ReliabilitySource(schedule: reliabilitySchedule(), fails: true),
    cache: FileWatchScheduleCache(directoryURL: directory, dataset: .production))
  #expect(await offline.load() == latest)
  let stale = CommanderWidgetSnapshotLoader(service: ReliabilitySource(schedule: reliabilitySchedule(2)), cache: cache)
  #expect(await stale.load() == latest)
  let fresh = CommanderWidgetSnapshotLoader(service: ReliabilitySource(schedule: reliabilitySchedule(4)), cache: cache)
  #expect(await fresh.load()?.schedule.scheduleVersion == 4)
}

@Test func widgetEmptyOfflineCacheHasSafeFallbackAndExpiryStillApplies() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let loader = CommanderWidgetSnapshotLoader(service: ReliabilitySource(schedule: reliabilitySchedule(), fails: true),
    cache: FileWatchScheduleCache(directoryURL: directory))
  #expect(await loader.load() == nil)
  let schedule = reliabilitySchedule()
  let expiry = try #require(try WatchScheduleExpiryPolicy.expirationDate(for: schedule))
  #expect(WatchScheduleExpiryPolicy.activeSchedule(schedule, at: expiry) == nil)
}

@Test func watchAcknowledgementOrderingNeverRegressesVersionOrRevision() {
  let current = WatchScheduleProjectionIdentity(scheduleVersion: 3, projectionRevision: 4)
  #expect(WatchScheduleProjectionIdentity(scheduleVersion: 2, projectionRevision: 99).isOlder(than: current))
  #expect(WatchScheduleProjectionIdentity(scheduleVersion: 3, projectionRevision: 3).isOlder(than: current))
  #expect(!current.isOlder(than: current))
  #expect(!WatchScheduleProjectionIdentity(scheduleVersion: 4, projectionRevision: 0).isOlder(than: current))
}

@Test func stopCallbackRejectsChangedMissingAndEndedEvents() throws {
  let alarm = try #require(NativeAlarmContract.payload(schedule: reliabilitySchedule()).alarms.first)
  func event(start: String? = nil) -> CommanderAlarmEventSnapshot {
    CommanderAlarmEventSnapshot(stableId: alarm.stableId, iconKey: "", title: alarm.title,
      location: alarm.location, kind: alarm.kind, startAt: start ?? alarm.startAt,
      endAt: alarm.endAt, leaveAt: alarm.leaveAt)
  }
  let stopped = event()
  let before = try NativeAlarmContract.date(fromLocalISO: "2026-09-29T09:55:00")
  #expect(CommanderAlarmStopPolicy.canApply(stopped: stopped, current: stopped, now: before))
  #expect(!CommanderAlarmStopPolicy.canApply(stopped: stopped, current: nil, now: before))
  #expect(!CommanderAlarmStopPolicy.canApply(stopped: stopped, current: event(start: "2026-09-29T10:05:00"), now: before))
  #expect(!CommanderAlarmStopPolicy.canApply(stopped: stopped, current: stopped,
    now: try NativeAlarmContract.date(fromLocalISO: alarm.endAt)))
}

@Test func runtimeUsesOwnershipPhaseAndCacheGuards() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func source(_ file: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/" + file), encoding: .utf8)
  }
  let adapter = try source("LazenskyCommanderApp/AlarmKitAdapter.swift")
  #expect(adapter.contains("return allIDs.intersection(try await ownership.ids())"))
  #expect(adapter.contains("ownership.reserve(stableID: alarm.stableId)"))
  #expect(adapter.contains("guard currentState != updatedState else { continue }"))
  #expect(adapter.contains("CommanderAlarmStopPolicy.canApply("))
  let activities = try source("LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift")
  let request = try #require(activities.range(of: "private func requestPlannedActivity("))
  let requestBody = String(activities[request.lowerBound...])
  #expect(requestBody.contains("Self.presentationState(snapshots: snapshots, now: now"))
  #expect(requestBody.contains("presentationMode: presentation.1"))
  #expect(activities.contains("where activity.activityState == .ended"))
  let watch = try source("LazenskyCommanderWatchApp/WatchCommanderModel.swift")
  #expect(watch.contains("WatchScheduleCachePolicy.decision(incoming: incoming, existing: snapshot)"))
  #expect(!watch.contains("snapshot = nil"))
  let widget = try source("LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift")
  #expect(widget.contains("return await Self.snapshotLoader.load()"))
  #expect(widget.contains("CommanderRectangularLockWidget(state: state)\n          .containerBackground(.clear, for: .widget)"))
}

@Test func failedOwnershipWriteCannotAuthorizeScheduling() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  // A regular file cannot hold the journal. No platform operation can begin without reserve.
  try Data("unavailable-container".utf8).write(to: directory)
  let ledger = FileAlarmOwnershipStore(directoryURL: directory, key: "ownership",
    legacyStateKey: "commander.test.missing." + UUID().uuidString)
  do {
    _ = try await ledger.reserve(stableID: "event")
    Issue.record("Failed ownership write returned a scheduling ID")
  } catch {}
}

private actor ReliabilityOwnedPlatform: AlarmAdapting {
  let ledger: FileAlarmOwnershipStore
  private var dates: [String: Date]
  private var interruptNextSchedule = true
  private(set) var maximumCount = 0
  init(ledger: FileAlarmOwnershipStore, foreign: String) {
    self.ledger = ledger
    dates = [foreign: .distantFuture]
  }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing: String?) async throws -> String {
    let id = try await ledger.reserve(stableID: alarm.stableId)
    dates[id] = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    maximumCount = max(maximumCount, dates.count)
    if interruptNextSchedule {
      interruptNextSchedule = false
      throw URLError(.networkConnectionLost) // Platform committed, caller did not receive its result.
    }
    return id
  }
  func cancel(platformAlarmID: String) async throws {
    #expect(try await ledger.ids().contains(platformAlarmID))
    dates.removeValue(forKey: platformAlarmID)
    try await ledger.forget(platformAlarmID)
  }
  func existingPlatformAlarmIDs() async throws -> Set<String>? {
    Set(dates.keys).intersection(try await ledger.ids())
  }
  func existingPlatformFixedAlertDates() -> [String: Date]? { dates }
  func contains(_ id: String) -> Bool { dates[id] != nil }
}

@Test func retryAfterAmbiguousPlatformSuccessReusesJournalIdentityAndPreservesForeignAlarm() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let ledger = FileAlarmOwnershipStore(directoryURL: directory, key: "ownership",
    legacyStateKey: "commander.test.missing." + UUID().uuidString)
  let foreign = UUID().uuidString
  let adapter = ReliabilityOwnedPlatform(ledger: ledger, foreign: foreign)
  let source = ReliabilitySource(schedule: reliabilitySchedule())
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-29T09:00:00")
  let first = AlarmSyncService(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: adapter)
  #expect(try await !first.synchronize(now: now).succeeded)
  // Simulate relaunch with no managed mapping from the interrupted first call.
  let restarted = AlarmSyncService(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: adapter)
  #expect(try await restarted.synchronize(now: now).succeeded)
  #expect(try await restarted.synchronize(now: now).appliedCreate == 0)
  #expect(await adapter.maximumCount == 2) // One managed + one foreign, never two managed.
  #expect(await adapter.contains(foreign))
}

#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func decodesProductionScheduleAndBuildsPayload() throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  #expect(payload.contractVersion == 1)
  #expect(payload.scheduleVersion == 4)
  #expect(payload.alarms.count == schedule.events.count)
  #expect(payload.alarms.first(where: { $0.stableId == "synthetic-0815-bath" })?.leaveAt == "2026-08-15T09:30:00")
}

@Test func invalidScheduleAndDuplicateStableIDAreRejected() throws {
  let decoded = try decodeSchedule(named: "data/schedule.json")
  let schedule = Schedule(schemaVersion: decoded.schemaVersion, scheduleVersion: decoded.scheduleVersion, updatedAt: decoded.updatedAt, stay: decoded.stay, events: [decoded.events[0], decoded.events[0]], settings: decoded.settings)
  #expect(throws: ScheduleValidationError.duplicateStableId("synthetic-0815-breakfast")) {
    try NativeAlarmContract.validate(schedule)
  }
}

@Test func crossPlatformReconciliationFixtureParity() throws {
  let fixture = try loadFixture()
  #expect(fixture.contractVersion == 1)
  for item in fixture.cases {
    let plan = AlarmReconciler.reconcile(current: item.currentAlarms, next: item.nextPayload)
    #expect(plan.create.map(\.stableId) == item.expected.create, "\(item.name): create")
    #expect(plan.update.map(\.stableId) == item.expected.update, "\(item.name): update")
    #expect(plan.cancel.map(\.stableId) == item.expected.cancel, "\(item.name): cancel")
    #expect(plan.unchanged.map(\.stableId) == item.expected.unchanged, "\(item.name): unchanged")
  }
}

@Test func explicitOverrideFixtureChangesLeaveAtAndRequiresUpdate() throws {
  let fixture = try loadFixture().explicitOverrideCase
  let current = try NativeAlarmContract.payload(schedule: fixture.schedule, overrides: fixture.currentOverrides)
  let next = try NativeAlarmContract.payload(schedule: fixture.schedule, overrides: fixture.nextOverrides)
  #expect(current.alarms[0].leaveAt == fixture.expected.currentLeaveAt)
  #expect(next.alarms[0].leaveAt == fixture.expected.nextLeaveAt)
  #expect(next.alarms[0].effectiveLeadTimeMinutes == 0)
  #expect(AlarmReconciler.reconcile(current: current.alarms, next: next).update.map(\.stableId) == fixture.expected.update)
}

@Test func secondSuccessfulSyncIsIdempotent() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)
  let first = try await service.synchronize(now: Date(timeIntervalSince1970: 1))
  let second = try await service.synchronize(now: Date(timeIntervalSince1970: 2))
  #expect(first.appliedCreate == schedule.events.count)
  #expect(second.appliedCreate == 0)
  #expect(second.appliedUpdate == 0)
  #expect(second.plan.unchanged.count == schedule.events.count)
  #expect(await adapter.scheduledCount() == schedule.events.count)
}

@Test func alarmSyncSucceedsWithNoDesiredAlarmsWhenScheduleIsEntirelyPast() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("past", date: "2026-08-20", start: "09:00", end: "09:30", title: "Minulá procedura")
  ], lead: 0)
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)

  let summary = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  )

  #expect(summary.succeeded)
  #expect(summary.desiredAlarmCount == 0)
  #expect(summary.plan.create.isEmpty)
  #expect(await adapter.scheduledCount() == 0)
  #expect((await store.load()).records.isEmpty)
}

@Test func alarmSyncSchedulesOnlyFutureAlarmFromMixedCanonicalSchedule() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("past", date: "2026-08-20", start: "09:00", end: "09:30", title: "Minulá procedura"),
    watchEvent("future", date: "2026-08-20", start: "11:00", end: "11:30", title: "Budoucí procedura")
  ], lead: 0)
  let adapter = RecordingAlarmAdapter()
  let store = InMemoryAlarmStateStore()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)

  let summary = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  )

  #expect(summary.desiredAlarmCount == 1)
  #expect(summary.plan.create.map(\.stableId) == ["future"])
  #expect(await adapter.scheduledStableIds() == ["future"])
  #expect(Set((await store.load()).records.keys) == ["future"])
  #expect((await store.load()).lastSuccessfulPayload?.alarms.map(\.stableId) == ["future"])
}

@Test func alarmSyncDoesNotScheduleAlarmWhoseLeaveAtEqualsNow() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("boundary", date: "2026-08-20", start: "10:00", end: "10:30", title: "Hraniční procedura")
  ], lead: 0)
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: InMemoryAlarmStateStore(), adapter: adapter)

  let summary = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  )

  #expect(summary.desiredAlarmCount == 0)
  #expect(summary.plan.create.isEmpty)
  #expect(await adapter.scheduledCount() == 0)
}

@Test func alarmSyncSchedulesAlarmWhoseLeaveAtIsOneSecondInTheFuture() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("future-second", date: "2026-08-20", start: "10:00", end: "10:30", title: "Budoucí procedura")
  ], lead: 0)
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: InMemoryAlarmStateStore(), adapter: adapter)
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")

  let summary = try await service.synchronize(
    now: leaveAt.addingTimeInterval(-1)
  )

  #expect(summary.desiredAlarmCount == 1)
  #expect(summary.appliedCreate == 1)
  #expect(await adapter.scheduledStableIds() == ["future-second"])
}

@Test func alarmSyncCancelsManagedAlarmAfterItsLeaveAtPasses() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("managed", date: "2026-08-20", start: "10:00", end: "10:30", title: "Spravovaná procedura")
  ], lead: 0)
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)

  let initial = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00")
  )
  let expired = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  )

  #expect(initial.appliedCreate == 1)
  #expect(expired.desiredAlarmCount == 0)
  #expect(expired.plan.cancel.map(\.stableId) == ["managed"])
  #expect(expired.appliedCancel == 1)
  #expect(await adapter.cancelledCount() == 1)
  #expect((await store.load()).records.isEmpty)
  #expect((await store.load()).lastSuccessfulPayload?.alarms.isEmpty == true)
}

@Test func mixedScheduleRemainsWholeForIPhoneAndWatchSnapshot() async throws {
  let schedule = watchSchedule(events: [
    watchEvent("past", date: "2026-08-20", start: "09:00", end: "09:30", title: "Minulá procedura"),
    watchEvent("future", date: "2026-08-20", start: "11:00", end: "11:30", title: "Budoucí procedura")
  ], lead: 0)
  let source = CountingScheduleService(schedule: schedule)
  let scheduleStore = InMemoryScheduleSnapshotStore()
  let adapter = RecordingAlarmAdapter()
  let watchDelivery = RecordingWatchScheduleDelivery()
  let alarmSync = AlarmSyncService(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(
    scheduleService: source,
    alarmSyncService: alarmSync,
    scheduleStore: scheduleStore,
    watchDelivery: watchDelivery
  )

  let result = try await coordinator.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  )

  #expect(result.alarmSummary.desiredAlarmCount == 1)
  #expect(await adapter.scheduledStableIds() == ["future"])
  #expect(result.schedule == schedule)
  #expect(result.watchSnapshot.schedule == schedule)
  #expect(result.watchSnapshot.schedule.events.map(\.stableId) == ["past", "future"])
  #expect(await scheduleStore.load() == schedule)
  #expect(await watchDelivery.receivedSnapshot()?.schedule == schedule)
}

@Test func productionVersionFourHasNoDesiredAlarmsOnAugustTwentySecond() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let canonicalPayload = try NativeAlarmContract.payload(schedule: schedule)
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: InMemoryAlarmStateStore(), adapter: adapter)

  let summary = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-22T12:00:00")
  )

  #expect(schedule.scheduleVersion == 4)
  #expect(canonicalPayload.alarms.count == 13)
  #expect(summary.succeeded)
  #expect(summary.desiredAlarmCount == 0)
  #expect(summary.plan.create.isEmpty)
  #expect(await adapter.scheduledCount() == 0)
}

@Test func fetchFailureDoesNotCancelExistingAlarm() async throws {
  let existing = NativeAlarm(stableId: "kept", kind: .procedure, title: "Kept", location: "Room", startAt: "2026-08-20T10:00:00", endAt: "2026-08-20T10:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T10:00:00")
  let initial = ManagedAlarmState(records: ["kept": ManagedAlarmRecord(stableId: "kept", platformAlarmID: "alarm-kept", alarm: existing)])
  let store = InMemoryAlarmStateStore(initial)
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: FailingScheduleService(), store: store, adapter: adapter)
  var didThrow = false
  do { _ = try await service.synchronize() } catch { didThrow = true }
  #expect(didThrow)
  #expect(await adapter.cancelledCount() == 0)
  #expect((await store.load()).records["kept"]?.platformAlarmID == "alarm-kept")
}

@Test func platformAlarmIDRoundTripsAsUUIDAndTitlesAreUserFacing() throws {
  let identifier = PlatformAlarmIdentifier.newPersistedValue()
  #expect(PlatformAlarmIdentifier.uuid(from: identifier)?.uuidString == identifier)
  #expect(PlatformAlarmIdentifier.uuid(from: "not-a-uuid") == nil)
  let procedure = NativeAlarm(stableId: "procedure", kind: .procedure, title: "Masáž", location: "Rehabilitace", startAt: "2026-08-20T10:00:00", endAt: "2026-08-20T10:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T10:00:00")
  let meal = NativeAlarm(stableId: "meal", kind: .meal, title: "Oběd", location: "Jídelna", startAt: "2026-08-20T12:00:00", endAt: "2026-08-20T12:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T12:00:00")
  #expect(NativeAlarmPresentation.title(for: procedure) == "Čas vyrazit: Masáž")
  #expect(NativeAlarmPresentation.title(for: meal) == "Čas vyrazit: Oběd")
}

@Test func localISODateUsesPragueWallClockWithoutUTCShift() throws {
  let date = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:30:00")
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
  let components = calendar.dateComponents([.hour, .minute], from: date)
  #expect(components.hour == 9)
  #expect(components.minute == 30)
}

@Test func deniedAuthorizationDoesNotPersistFalseSuccess() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter(authorization: .denied)
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)
  var didThrow = false
  do { _ = try await service.synchronize(now: Date(timeIntervalSince1970: 1)) } catch { didThrow = true }
  #expect(didThrow)
  #expect((await store.load()).records.isEmpty)
  #expect(await adapter.scheduledCount() == 0)
}

@Test func missingPastSystemAlarmIsPrunedWithoutCancelAttempt() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let stale = NativeAlarm(stableId: "stale", kind: .procedure, title: "Stale", location: "Room", startAt: "2026-08-20T10:00:00", endAt: "2026-08-20T10:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T10:00:00")
  let store = InMemoryAlarmStateStore(ManagedAlarmState(records: ["stale": ManagedAlarmRecord(stableId: "stale", platformAlarmID: UUID().uuidString, alarm: stale)]))
  let adapter = RecordingAlarmAdapter(existingIDs: [])
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)
  let summary = try await service.synchronize(
    now: NativeAlarmContract.date(fromLocalISO: "2026-08-22T12:00:00")
  )
  #expect(summary.desiredAlarmCount == 0)
  #expect(summary.plan.cancel.isEmpty)
  #expect((await store.load()).records["stale"] == nil)
  #expect(await adapter.cancelledCount() == 0)
}

@Test func syncPersistsCreateThenAppliesUpdateAndCancel() async throws {
  let original = try decodeSchedule(named: "data/schedule.json")
  let source = MutableScheduleService(schedule: original)
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: source, store: store, adapter: adapter)
  let syncNow = Date(timeIntervalSince1970: 1)
  _ = try await service.synchronize(now: syncNow)
  let initialState = await store.load()
  #expect(initialState.records.count == original.events.count)
  #expect(initialState.records.values.allSatisfy { PlatformAlarmIdentifier.uuid(from: $0.platformAlarmID) != nil })

  var correctedEvents = original.events
  let first = correctedEvents[0]
  correctedEvents[0] = ScheduleEvent(stableId: first.stableId, date: first.date, start: "07:35", end: "08:00", title: first.title, location: first.location, kind: first.kind, procedureType: first.procedureType, mealType: first.mealType, leadTimeMinutes: first.leadTimeMinutes)
  await source.replace(Schedule(schemaVersion: original.schemaVersion, scheduleVersion: original.scheduleVersion + 1, updatedAt: original.updatedAt, stay: original.stay, events: correctedEvents, settings: original.settings))
  let updated = try await service.synchronize(now: syncNow)
  #expect(updated.appliedUpdate == 1)

  await source.replace(Schedule(schemaVersion: original.schemaVersion, scheduleVersion: original.scheduleVersion + 2, updatedAt: original.updatedAt, stay: original.stay, events: Array(correctedEvents.dropLast()), settings: original.settings))
  let cancelled = try await service.synchronize(now: syncNow)
  #expect(cancelled.appliedCancel == 1)
}

@Test func liveStateUsesWebBoundarySemantics() throws {
  let schedule = try liveSchedule(lead: 20)
  #expect(live("2026-08-20T09:39:00", schedule: schedule).state == .upcoming)
  #expect(live("2026-08-20T09:40:00", schedule: schedule).state == .leaveNow)
  #expect(live("2026-08-20T09:59:00", schedule: schedule).state == .leaveNow)
  #expect(live("2026-08-20T10:00:00", schedule: schedule).state == .inProgress)
  #expect(live("2026-08-20T09:35:00", schedule: schedule).state == .upcoming)
  #expect(live("2026-08-20T11:00:00", schedule: schedule).state == .dayDone)
  #expect(live("2026-08-21T09:00:00", schedule: schedule).state == .dayDone)
  #expect(live("2026-08-20T10:00:00", schedule: try liveSchedule(lead: 0)).state == .inProgress)
}

@Test func sharedIconMapClassifiesApprovedCategoriesAndUsesNeutralFallback() throws {
  let map = try JSONDecoder().decode(CommanderIconMap.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent("assets/icons/lazensky-v1/icon-map.json")))
  let colors = try JSONDecoder().decode(CommanderColorMap.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent("assets/icons/lazensky-v1/colors.json")))
  func event(_ title: String, kind: ScheduleKind = .procedure) -> ScheduleEvent {
    ScheduleEvent(stableId: title, date: "2026-08-20", start: "12:00", end: "12:10", title: title, location: "Pavilon", kind: kind, procedureType: kind == .procedure ? title : nil, mealType: kind == .meal ? title : nil, leadTimeMinutes: nil)
  }
  let cases: [(String, ScheduleKind, String)] = [
    ("Snídaně", .meal, "meal_breakfast"), ("Oběd", .meal, "meal_lunch"), ("Večeře", .meal, "meal_dinner"),
    ("Plavání v bazénu", .procedure, "pool"), ("Jodobromový bazén", .procedure, "iodobrom"),
    ("Vířivá vana", .procedure, "whirlpool"), ("Parafín", .procedure, "peat_wrap"),
    ("iMoove", .procedure, "imoove"), ("Hydrojet masáž", .procedure, "hydrojet"),
    ("Ultrazvuková masáž", .procedure, "electro_therapy"), ("Magnetoterapie", .procedure, "electro_therapy"),
    ("Individuální LTV", .procedure, "individual_rehab"), ("Ergoterapie", .procedure, "individual_rehab"),
    ("Chodicí pás", .procedure, "individual_rehab"), ("Klasická masáž", .procedure, "massage")
  ]
  for item in cases {
    #expect(map.classify(event(item.0, kind: item.1))?.key == item.2, "\(item.0) must classify as \(item.2)")
  }
  #expect(colors.brand.commanderPurple == "#6E56CF")
  #expect(colors.state.leaveNow == "#F97316")
  for icon in map.icons {
    #expect(colors.procedures[icon.key.hasPrefix("meal_") ? "meal" : icon.key] == icon.accent)
  }
  #expect(map.classify(event("Neznámá péče XYZ")) == nil)
  #expect(map.fallback.key == nil)
  #expect(map.fallback.accent == colors.brand.commanderPurple)
}

@Test func scheduleCoordinatorFetchesOnceAndPublishesOneValidatedSchedule() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let source = CountingScheduleService(schedule: schedule)
  let alarmStore = InMemoryAlarmStateStore()
  let scheduleStore = InMemoryScheduleSnapshotStore()
  let adapter = RecordingAlarmAdapter()
  let watchDelivery = RecordingWatchScheduleDelivery()
  let alarmSync = AlarmSyncService(scheduleService: source, store: alarmStore, adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: source, alarmSyncService: alarmSync, scheduleStore: scheduleStore, watchDelivery: watchDelivery)

  let result = try await coordinator.synchronize(now: Date(timeIntervalSince1970: 1))

  #expect(await source.fetchCount() == 1)
  #expect(await adapter.preparedSchedule() == schedule)
  #expect(await scheduleStore.load() == schedule)
  #expect(result.schedule == schedule)
  #expect(result.watchSnapshot.schedule == schedule)
  #expect(result.watchDeliveryStatus == .sent)
  #expect(await watchDelivery.receivedSnapshot() == result.watchSnapshot)
  #expect(result.alarmSummary.appliedCreate == schedule.events.count)
}

@Test func failedAlarmProjectionKeepsNewCanonicalScheduleAccepted() async throws {
  let previous = try liveSchedule(lead: 10)
  let incoming = try decodeSchedule(named: "data/schedule.json")
  let source = CountingScheduleService(schedule: incoming)
  let scheduleStore = InMemoryScheduleSnapshotStore(previous)
  let adapter = RecordingAlarmAdapter(authorization: .denied)
  let alarmSync = AlarmSyncService(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: source, alarmSyncService: alarmSync, scheduleStore: scheduleStore)

  let result = try await coordinator.synchronize(now: Date(timeIntervalSince1970: 1))

  #expect(!result.alarmSummary.succeeded)
  #expect(await source.fetchCount() == 1)
  #expect(await scheduleStore.load() == incoming)
  #expect(result.schedule == incoming)
}

@Test func preAlertStartsAtPreviousEventEndOrThirtyMinutesBeforeLeave() throws {
  let alarm = try NativeAlarmContract.payload(schedule: liveSchedule(lead: 20)).alarms[1]
  #expect(try AlarmCountdown.preAlertDuration(for: alarm, in: liveSchedule(lead: 20)) == 10 * 60)
  let noPrevious = try liveSchedule(lead: 20, events: [liveEvent("first", "10:00", "10:30")])
  let firstAlarm = try NativeAlarmContract.payload(schedule: noPrevious).alarms[0]
  #expect(try AlarmCountdown.preAlertDuration(for: firstAlarm, in: noPrevious) == 30 * 60)
}

@Test func watchContractsAreVersionedAndIdempotent() throws {
  let schedule = try liveSchedule(lead: 20)
  #expect(WatchScheduleSnapshot(schedule: schedule).contractVersion == 1)
  #expect(WatchScheduleCachePolicy.shouldAccept(incoming: schedule, existing: nil))
  let older = Schedule(schemaVersion: 1, scheduleVersion: 0, updatedAt: schedule.updatedAt, stay: schedule.stay, events: schedule.events, settings: schedule.settings)
  #expect(!WatchScheduleCachePolicy.shouldAccept(incoming: older, existing: schedule))
  let next = [WatchLocalNotification(stableId: "a", leaveAt: "2026-08-20T09:40:00", title: "Jodobrom", location: "Bazén")]
  let same = WatchNotificationReconciler.reconcile(current: next, next: next)
  #expect(same.unchanged == next && same.create.isEmpty && same.update.isEmpty && same.cancel.isEmpty)
  let changed = WatchNotificationReconciler.reconcile(current: next, next: [WatchLocalNotification(stableId: "a", leaveAt: "2026-08-20T09:45:00", title: "Jodobrom", location: "Bazén")])
  #expect(changed.update.count == 1)
  let points = try WatchTimelinePlanner.points(schedule: schedule, now: try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00"))
  #expect(points.contains { $0.state == .leaveNow } && points.contains { $0.state == .inProgress })
}

@Test func watchCacheStartsEmptyAndReloadsTheSameValidSnapshot() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  #expect(try await cache.load() == nil)

  let snapshot = WatchScheduleSnapshot(schedule: try liveSchedule(lead: 20))
  #expect(try await cache.accept(snapshot) == .stored)
  #expect(try await cache.accept(snapshot) == .unchanged)
  #expect(try await cache.load() == snapshot)

  let reloaded = FileWatchScheduleCache(directoryURL: directory)
  #expect(try await reloaded.load() == snapshot)
}

@Test func watchCacheRejectsInvalidSnapshotWithoutReplacingValidData() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let valid = try liveSchedule(lead: 20)
  let validSnapshot = WatchScheduleSnapshot(schedule: valid)
  #expect(try await cache.accept(validSnapshot) == .stored)

  let invalid = Schedule(schemaVersion: 99, scheduleVersion: valid.scheduleVersion + 1, updatedAt: valid.updatedAt, stay: valid.stay, events: valid.events, settings: valid.settings)
  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: invalid)) == .rejectedInvalid)
  #expect(try await cache.load() == validSnapshot)
  #expect(try await cache.accept(WatchScheduleSnapshot(contractVersion: 99, schedule: valid)) == .rejectedInvalid)
}

@Test func watchCacheRejectsOlderAndConflictingVersionsThenAcceptsNewer() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let current = try liveSchedule(lead: 20)
  let currentSnapshot = WatchScheduleSnapshot(schedule: current)
  #expect(try await cache.accept(currentSnapshot) == .stored)

  let invalidVersion = Schedule(schemaVersion: 1, scheduleVersion: 0, updatedAt: current.updatedAt, stay: current.stay, events: current.events, settings: current.settings)
  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: invalidVersion)) == .rejectedInvalid)
  let conflict = Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: "2026-08-20T01:00:00Z", stay: current.stay, events: current.events, settings: current.settings)
  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: conflict)) == .rejectedVersion(current: 1, incoming: 1))
  #expect(try await cache.load() == currentSnapshot)

  let newer = Schedule(schemaVersion: 1, scheduleVersion: 2, updatedAt: "2026-08-20T02:00:00Z", stay: current.stay, events: current.events, settings: current.settings)
  let newerSnapshot = WatchScheduleSnapshot(schedule: newer)
  #expect(try await cache.accept(newerSnapshot) == .stored)
  #expect(try await cache.load() == newerSnapshot)
}

@Test func watchLiveStateUsesTheValidatedCachedSchedule() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let snapshot = WatchScheduleSnapshot(schedule: try liveSchedule(lead: 20))
  #expect(try await cache.accept(snapshot) == .stored)
  let cachedSchedule = try #require(await cache.load()?.schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:30:00")
  let state = CommanderLiveStateCalculator.compute(schedule: cachedSchedule, now: now)
  let expectedLeaveAt = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:40:00")
  #expect(state.state == .upcoming)
  #expect(state.event?.stableId == "first")
  #expect(state.leaveAt == expectedLeaveAt)
}

@Test func watchTransportEnvelopeRoundTripsTheSameVersionedSnapshot() throws {
  let snapshot = WatchScheduleSnapshot(schedule: try liveSchedule(lead: 20))
  let data = try WatchScheduleTransportCodec.encode(snapshot)
  let envelope = try JSONDecoder().decode(WatchScheduleTransportEnvelope.self, from: data)

  #expect(envelope.contractVersion == 1)
  #expect(envelope.messageType == WatchScheduleTransportEnvelope.scheduleMessageType)
  #expect(envelope.scheduleSnapshot == snapshot)
  #expect(try WatchScheduleTransportCodec.decode(data) == snapshot)

  let applicationContext = try WatchScheduleTransportCodec.applicationContext(for: snapshot)
  #expect(applicationContext.count == 1)
  #expect(applicationContext[WatchScheduleTransportCodec.applicationContextKey] is Data)
  #expect(try WatchScheduleTransportCodec.decode(applicationContext: applicationContext) == snapshot)
}

@Test func watchTransportRejectsInvalidPayloadAndUnsupportedContracts() throws {
  let snapshot = WatchScheduleSnapshot(schedule: try liveSchedule(lead: 20))
  #expect(throws: WatchScheduleTransportError.invalidPayload) {
    try WatchScheduleTransportCodec.decode(Data("not-json".utf8))
  }
  #expect(throws: WatchScheduleTransportError.missingApplicationContextPayload) {
    try WatchScheduleTransportCodec.decode(applicationContext: [:])
  }

  let unsupportedEnvelope = WatchScheduleTransportEnvelope(contractVersion: 99, scheduleSnapshot: snapshot)
  let unsupportedData = try JSONEncoder().encode(unsupportedEnvelope)
  #expect(throws: WatchScheduleTransportError.unsupportedEnvelopeVersion(99)) {
    try WatchScheduleTransportCodec.decode(unsupportedData)
  }

  let wrongTypeEnvelope = WatchScheduleTransportEnvelope(messageType: "unexpected", scheduleSnapshot: snapshot)
  let wrongTypeData = try JSONEncoder().encode(wrongTypeEnvelope)
  #expect(throws: WatchScheduleTransportError.invalidMessageType("unexpected")) {
    try WatchScheduleTransportCodec.decode(wrongTypeData)
  }

  let invalidSnapshot = WatchScheduleSnapshot(contractVersion: 99, schedule: snapshot.schedule)
  let invalidSnapshotData = try JSONEncoder().encode(WatchScheduleTransportEnvelope(scheduleSnapshot: invalidSnapshot))
  #expect(throws: WatchScheduleTransportError.invalidSnapshotContractVersion(99)) {
    try WatchScheduleTransportCodec.decode(invalidSnapshotData)
  }
}

@Test func watchTransportReceiveUsesExistingCacheVersionAndIdempotenceRules() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let base = try liveSchedule(lead: 20)
  let current = Schedule(schemaVersion: 1, scheduleVersion: 2, updatedAt: "2026-08-20T02:00:00Z", stay: base.stay, events: base.events, settings: base.settings)
  let currentSnapshot = try WatchScheduleTransportCodec.decode(WatchScheduleTransportCodec.encode(WatchScheduleSnapshot(schedule: current)))
  #expect(try await cache.accept(currentSnapshot) == .stored)

  let older = Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: base.updatedAt, stay: base.stay, events: base.events, settings: base.settings)
  let olderSnapshot = try WatchScheduleTransportCodec.decode(WatchScheduleTransportCodec.encode(WatchScheduleSnapshot(schedule: older)))
  #expect(try await cache.accept(olderSnapshot) == .rejectedVersion(current: 2, incoming: 1))
  #expect(try await cache.accept(currentSnapshot) == .unchanged)

  let newer = Schedule(schemaVersion: 1, scheduleVersion: 3, updatedAt: "2026-08-20T03:00:00Z", stay: base.stay, events: base.events, settings: base.settings)
  let newerSnapshot = try WatchScheduleTransportCodec.decode(WatchScheduleTransportCodec.encode(WatchScheduleSnapshot(schedule: newer)))
  #expect(try await cache.accept(newerSnapshot) == .stored)
  #expect(try await cache.load() == newerSnapshot)
}

@Test func watchTransportFailureKeepsCanonicalAcceptedButSyncUnverified() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let source = CountingScheduleService(schedule: schedule)
  let alarmStore = InMemoryAlarmStateStore()
  let scheduleStore = InMemoryScheduleSnapshotStore()
  let adapter = RecordingAlarmAdapter()
  let watchDelivery = FailingWatchScheduleDelivery()
  let alarmSync = AlarmSyncService(scheduleService: source, store: alarmStore, adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: source, alarmSyncService: alarmSync, scheduleStore: scheduleStore, watchDelivery: watchDelivery)

  let result = try await coordinator.synchronize(now: Date(timeIntervalSince1970: 1))

  #expect(!result.succeeded)
  #expect(result.alarmSummary.succeeded)
  #expect(await source.fetchCount() == 1)
  #expect(await scheduleStore.load() == schedule)
  #expect(await adapter.scheduledCount() == schedule.events.count)
  #expect(await watchDelivery.receivedSnapshot() == result.watchSnapshot)
  guard case .failed = result.watchDeliveryStatus else {
    Issue.record("Watch transport failure must keep the whole sync unverified without rolling back canonical data")
    return
  }
}

@Test func watchCachePreservesTheWholeMultiDaySchedule() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let schedule = watchSchedule(events: [
    watchEvent("day-one", date: "2026-08-20", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    watchEvent("day-two", date: "2026-08-21", start: "10:00", end: "10:30", title: "Masáž")
  ])
  let cache = FileWatchScheduleCache(directoryURL: directory)

  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: schedule)) == .stored)
  let cached = try #require(await cache.load()?.schedule)
  #expect(cached == schedule)
  #expect(cached.events.map(\.date) == ["2026-08-20", "2026-08-21"])
}

@Test func watchWidgetSelectsTodaysEventFromTheMultiDaySchedule() {
  let schedule = watchSchedule(events: [
    watchEvent("yesterday", date: "2026-08-19", start: "09:00", end: "09:30", title: "Masáž"),
    watchEvent("today", date: "2026-08-20", start: "11:00", end: "11:20", title: "Jodobromová koupel"),
    watchEvent("tomorrow", date: "2026-08-21", start: "08:00", end: "08:30", title: "Hydrojet")
  ])
  let now = try! NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")

  let state = CommanderLiveStateCalculator.compute(schedule: schedule, now: now)

  #expect(state.state == .upcoming)
  #expect(state.event?.stableId == "today")
}

@Test func watchTimelineCoversCountdownAndEveryLiveStateTransition() throws {
  let schedule = try liveSchedule(lead: 20)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  let points = try WatchTimelinePlanner.points(schedule: schedule, now: now)

  let countdown = try #require(points.first { $0.transition == .countdownStart })
  let countdownDate = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:10:00")
  #expect(countdown.date == countdownDate)
  #expect(countdown.state == .upcoming)

  let leave = try #require(points.first { $0.transition == .leaveAt })
  let leaveDate = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:40:00")
  #expect(leave.date == leaveDate)
  #expect(leave.state == .leaveNow)

  let start = try #require(points.first { $0.transition == .startAt })
  let startDate = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00")
  #expect(start.date == startDate)
  #expect(start.state == .inProgress)

  let firstEndDate = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:30:00")
  let firstEnd = try #require(points.first { $0.transition == .endAt && $0.date == firstEndDate })
  #expect(firstEnd.state == .upcoming)
  #expect(firstEnd.stableId == "next")

  let finalEndDate = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:30:00")
  let finalEnd = try #require(points.first { $0.transition == .endAt && $0.date == finalEndDate })
  #expect(finalEnd.state == .dayDone)
}

@Test func watchTimelineUsesTheSameCachedScheduleOnTheNextDay() throws {
  let schedule = watchSchedule(events: [
    watchEvent("day-one", date: "2026-08-20", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    watchEvent("day-two", date: "2026-08-21", start: "10:00", end: "10:30", title: "Masáž")
  ])
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-21T09:00:00")
  let points = try WatchTimelinePlanner.points(schedule: schedule, now: now)

  #expect(points.first?.state == .upcoming)
  #expect(points.first?.stableId == "day-two")
  #expect(points.contains { $0.transition == .endAt && $0.state == .dayDone })
}

@Test func watchTimelinePrecomputesTheNextDayAtMidnightWithoutAnotherSync() throws {
  let schedule = watchSchedule(events: [
    watchEvent("day-one", date: "2026-08-20", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    watchEvent("day-two", date: "2026-08-21", start: "10:00", end: "10:30", title: "Masáž")
  ])
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T20:00:00")
  let midnight = try NativeAlarmContract.date(fromLocalISO: "2026-08-21T00:00:00")
  let points = try WatchTimelinePlanner.points(schedule: schedule, now: now)
  let nextDay = try #require(points.first { $0.transition == .dayStart && $0.date == midnight })

  #expect(nextDay.state == .upcoming)
  #expect(nextDay.stableId == "day-two")
}

@Test func watchScheduleExpiresOnlyAfterFinalEventPlusTwentyFourHours() throws {
  let schedule = watchSchedule(events: [
    watchEvent("final", date: "2026-08-21", start: "10:00", end: "10:30", title: "Masáž")
  ])
  let expirationValue = try WatchScheduleExpiryPolicy.expirationDate(for: schedule)
  let expiration = try #require(expirationValue)
  let expectedExpiration = try NativeAlarmContract.date(fromLocalISO: "2026-08-22T10:30:00")
  #expect(expiration == expectedExpiration)
  #expect(!WatchScheduleExpiryPolicy.isExpired(schedule, at: expiration.addingTimeInterval(-1)))
  #expect(WatchScheduleExpiryPolicy.isExpired(schedule, at: expiration))
  #expect(WatchScheduleExpiryPolicy.activeSchedule(schedule, at: expiration) == nil)

  let expiredPoints = try WatchTimelinePlanner.points(schedule: schedule, now: expiration)
  #expect(expiredPoints == [WatchTimelinePoint(date: expiration, transition: .now, state: .noSchedule, stableId: nil)])
}

@Test func watchRelevanceIsDerivedFromCountdownLeaveAndProcedureTimes() throws {
  let schedule = try liveSchedule(lead: 20)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  let windows = try WatchTimelinePlanner.relevanceWindows(schedule: schedule, now: now)
  let first = try #require(windows.first { $0.stableId == "first" })
  let second = try #require(windows.first { $0.stableId == "next" })

  let firstStart = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:10:00")
  let firstEnd = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:30:00")
  let firstLeave = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:40:00")
  let secondEnd = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:30:00")
  #expect(first.interval.start == firstStart)
  #expect(first.interval.end == firstEnd)
  #expect(first.interval.contains(firstLeave))
  #expect(second.interval.start == firstEnd)
  #expect(second.interval.end == secondEnd)
}

@Test func watchCacheReloadHookRunsOnlyForAStoredSnapshot() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let recorder = WatchReloadRecorder()
  let cache = FileWatchScheduleCache(directoryURL: directory) { snapshot in
    await recorder.record(snapshot)
  }
  let schedule = try liveSchedule(lead: 20)
  let snapshot = WatchScheduleSnapshot(schedule: schedule)

  #expect(try await cache.accept(snapshot) == .stored)
  #expect(try await cache.accept(snapshot) == .unchanged)
  #expect(await recorder.count() == 1)

  let newer = Schedule(
    schemaVersion: schedule.schemaVersion,
    scheduleVersion: schedule.scheduleVersion + 1,
    updatedAt: "2026-08-20T01:00:00Z",
    stay: schedule.stay,
    events: schedule.events,
    settings: schedule.settings
  )
  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: newer)) == .stored)
  #expect(await recorder.count() == 2)
}

@Test func watchUnknownProcedureUsesNeutralCommanderFallback() throws {
  let iconMap = try JSONDecoder().decode(
    CommanderIconMap.self,
    from: Data(contentsOf: repositoryRoot().appendingPathComponent("assets/icons/lazensky-v1/icon-map.json"))
  )
  let unknown = watchEvent("unknown", date: "2026-08-20", start: "09:00", end: "09:30", title: "Speciální terapie")

  #expect(iconMap.classify(unknown) == nil)
  #expect(iconMap.fallback.key == nil)
  #expect(iconMap.fallback.accent == "#6E56CF")
}

@Test func watchStandaloneModeOffCancelsManagedLeaveNotifications() throws {
  let current = WatchLocalNotification(
    stableId: "procedure-a",
    scheduleVersion: 1,
    leaveAt: "2026-08-20T08:40:00",
    title: "Jodobromová koupel",
    location: "Bazén"
  )

  let plan = try WatchNotificationReconciler.reconcile(
    current: [current],
    schedule: nil,
    enabled: false
  )

  #expect(plan.cancel == ["lazensky.commander.watch.leave.procedure-a"])
  #expect(plan.hasChanges)
  #expect(WatchLeaveNotificationContract.manages(identifier: current.identifier))
  #expect(!WatchLeaveNotificationContract.manages(identifier: "another.app.notification"))
}

@Test func watchNotificationPlannerUsesFutureCanonicalLeaveAtAndContent() throws {
  let schedule = try liveSchedule(lead: 20)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:30:00")
  let notifications = try WatchLocalNotificationPlanner.notifications(schedule: schedule, now: now)
  let first = try #require(notifications.first)

  #expect(first.stableId == "first")
  #expect(first.leaveAt == "2026-08-20T08:40:00")
  #expect(first.identifier == "lazensky.commander.watch.leave.first")
  #expect(first.notificationTitle == "Čas vyrazit")
  #expect(first.notificationBody == "Jodobromová koupel · Bazén")

  let missingLocation = WatchLocalNotification(
    stableId: "without-location",
    leaveAt: "2026-08-20T12:00:00",
    title: "Masáž",
    location: "  "
  )
  #expect(missingLocation.notificationBody == "Masáž")
}

@Test func watchNotificationReconcileCancelsPastAndRemovedEvents() throws {
  let schedule = try liveSchedule(lead: 20, events: [liveEvent("first", "09:00", "09:30")])
  let past = WatchLocalNotification(
    stableId: "first",
    scheduleVersion: 1,
    leaveAt: "2026-08-20T08:40:00",
    title: "Jodobromová koupel",
    location: "Bazén"
  )
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:41:00")
  let pastPlan = try WatchNotificationReconciler.reconcile(
    current: [past],
    schedule: schedule,
    enabled: true,
    now: now
  )
  #expect(pastPlan.cancel == [past.identifier])

  let removed = WatchLocalNotification(
    stableId: "removed",
    scheduleVersion: 1,
    leaveAt: "2026-08-20T10:00:00",
    title: "Hydrojet",
    location: "Rehabilitace"
  )
  let before = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  let removedPlan = try WatchNotificationReconciler.reconcile(
    current: [removed],
    schedule: schedule,
    enabled: true,
    now: before
  )
  #expect(removedPlan.cancel == [removed.identifier])
  #expect(removedPlan.create.map(\.stableId) == ["first"])
}

@Test func watchNotificationReconcileReplacesChangedContentAndIsIdempotent() {
  let current = WatchLocalNotification(
    stableId: "same",
    scheduleVersion: 1,
    leaveAt: "2026-08-20T09:40:00",
    title: "Masáž",
    location: "Bazén"
  )
  let changedValues = [
    WatchLocalNotification(stableId: "same", scheduleVersion: 2, leaveAt: "2026-08-20T09:45:00", title: "Masáž", location: "Bazén"),
    WatchLocalNotification(stableId: "same", scheduleVersion: 2, leaveAt: current.leaveAt, title: "Klasická masáž", location: "Bazén"),
    WatchLocalNotification(stableId: "same", scheduleVersion: 2, leaveAt: current.leaveAt, title: "Masáž", location: "Rehabilitace")
  ]

  for changed in changedValues {
    let plan = WatchNotificationReconciler.reconcile(current: [current], next: [changed])
    #expect(plan.update == [changed])
    #expect(plan.create.isEmpty && plan.cancel.isEmpty && plan.unchanged.isEmpty)
  }

  let higherVersionOnly = WatchLocalNotification(
    stableId: current.stableId,
    scheduleVersion: 2,
    leaveAt: current.leaveAt,
    title: current.title,
    location: current.location
  )
  let duplicate = WatchNotificationReconciler.reconcile(current: [current], next: [higherVersionOnly])
  #expect(duplicate.unchanged == [current])
  #expect(!duplicate.hasChanges)
}

@Test func watchNotificationReconcileIgnoresOlderScheduleVersion() throws {
  let current = WatchLocalNotification(
    stableId: "kept",
    scheduleVersion: 2,
    leaveAt: "2026-08-20T09:40:00",
    title: "Masáž",
    location: "Bazén"
  )
  let older = try liveSchedule(lead: 20)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  let plan = try WatchNotificationReconciler.reconcile(
    current: [current],
    schedule: older,
    enabled: true,
    now: now,
    lastReconciledScheduleVersion: 2
  )

  #expect(plan.ignoredStaleSchedule)
  #expect(plan.unchanged == [current])
  #expect(!plan.hasChanges)
}

@Test func watchNotificationRollingBudgetPrioritizesNearestSixty() throws {
  let schedule = watchSchedule(events: watchFutureEvents(count: 65))
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-19T08:00:00")
  let notifications = try WatchLocalNotificationPlanner.notifications(schedule: schedule, now: now)

  #expect(notifications.count == 60)
  #expect(notifications.first?.stableId == "future-000")
  #expect(notifications.last?.stableId == "future-059")
}

@Test func watchNotificationPlannerSchedulesAllEventsBelowBudget() throws {
  let schedule = watchSchedule(events: watchFutureEvents(count: 3))
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-19T08:00:00")
  let notifications = try WatchLocalNotificationPlanner.notifications(schedule: schedule, now: now)

  #expect(notifications.map(\.stableId) == ["future-000", "future-001", "future-002"])
}

@Test func watchCacheNotificationHookRunsOnlyForStoredSnapshotsWhileEnabled() async throws {
  let directory = temporaryWatchCacheDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let recorder = WatchNotificationHookRecorder(enabled: true)
  let cache = FileWatchScheduleCache(directoryURL: directory) { snapshot in
    await recorder.didStore(snapshot)
  }
  let schedule = try liveSchedule(lead: 20)
  let snapshot = WatchScheduleSnapshot(schedule: schedule)

  #expect(try await cache.accept(snapshot) == .stored)
  #expect(try await cache.accept(snapshot) == .unchanged)
  #expect(await recorder.reconcileCount() == 1)

  await recorder.setEnabled(false)
  let newer = Schedule(
    schemaVersion: schedule.schemaVersion,
    scheduleVersion: 2,
    updatedAt: "2026-08-20T02:00:00Z",
    stay: schedule.stay,
    events: schedule.events,
    settings: schedule.settings
  )
  #expect(try await cache.accept(WatchScheduleSnapshot(schedule: newer)) == .stored)
  #expect(await recorder.reconcileCount() == 1)
}

@Test func deniedWatchNotificationAuthorizationIsNotOperational() {
  let denied = WatchStandaloneAlarmState(isEnabled: true, authorization: .denied)
  let allowed = WatchStandaloneAlarmState(isEnabled: true, authorization: .authorized)
  let disabled = WatchStandaloneAlarmState(isEnabled: false, authorization: .authorized)

  #expect(!denied.isOperational)
  #expect(allowed.isOperational)
  #expect(!disabled.isOperational)
}

@Test func watchAppUsesActiveNotificationsWithoutRestrictedEntitlement() throws {
  let entitlementURL = repositoryRoot().appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderWatchApp/LazenskyCommanderWatchApp.entitlements"
  )
  let plist = try #require(
    PropertyListSerialization.propertyList(
      from: Data(contentsOf: entitlementURL),
      format: nil
    ) as? [String: Any]
  )
  #expect(plist["com.apple.developer.usernotifications.time-sensitive"] == nil)

  let serviceURL = repositoryRoot().appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderWatchApp/WatchLocalNotificationService.swift"
  )
  let service = try String(contentsOf: serviceURL, encoding: .utf8)
  #expect(service.contains("requestAuthorization(options: [.alert, .sound])"))
  #expect(service.contains("content.interruptionLevel = .active"))
  #expect(!service.contains(".timeSensitive"))
}

private func live(_ date: String, schedule: Schedule) -> CommanderLiveStateResult {
  CommanderLiveStateCalculator.compute(schedule: schedule, now: try! NativeAlarmContract.date(fromLocalISO: date))
}

private func temporaryWatchCacheDirectory() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("lazensky-watch-cache-tests-\(UUID().uuidString)", isDirectory: true)
}

private func liveSchedule(lead: Int, events: [ScheduleEvent]? = nil) throws -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: "2026-08-20T00:00:00Z", stay: [:], events: events ?? [liveEvent("first", "09:00", "09:30"), liveEvent("next", "10:00", "10:30")], settings: ScheduleSettings(defaultLeadTimeMinutes: lead, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private func liveEvent(_ id: String, _ start: String, _ end: String) -> ScheduleEvent {
  watchEvent(id, date: "2026-08-20", start: start, end: end, title: id == "first" ? "Jodobromová koupel" : "Masáž")
}

private func watchSchedule(events: [ScheduleEvent], lead: Int = 20, scheduleVersion: Int = 1) -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: scheduleVersion,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: events,
    settings: ScheduleSettings(defaultLeadTimeMinutes: lead, procedureTypeOverrides: [:], mealOverrides: [:])
  )
}

private func watchFutureEvents(count: Int) -> [ScheduleEvent] {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
  let firstDate = try! NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = calendar.timeZone
  formatter.dateFormat = "yyyy-MM-dd"

  return (0..<count).map { index in
    let date = calendar.date(byAdding: .day, value: index, to: firstDate)!
    return watchEvent(
      String(format: "future-%03d", index),
      date: formatter.string(from: date),
      start: "10:00",
      end: "10:30",
      title: "Procedura \(index)"
    )
  }
}

private func watchEvent(_ id: String, date: String, start: String, end: String, title: String) -> ScheduleEvent {
  ScheduleEvent(
    stableId: id,
    date: date,
    start: start,
    end: end,
    title: title,
    location: "Bazén",
    kind: .procedure,
    procedureType: title,
    mealType: nil,
    leadTimeMinutes: nil
  )
}

private func decodeSchedule(named path: String) throws -> Schedule {
  try JSONDecoder().decode(Schedule.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent(path)))
}

private func loadFixture() throws -> NativeFixture {
  try JSONDecoder().decode(NativeFixture.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent("tests/fixtures/native-alarm-reconciliation-v1.json")))
}

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private struct NativeFixture: Decodable {
  let contractVersion: Int
  let cases: [FixtureCase]
  let explicitOverrideCase: ExplicitOverrideCase
}

private struct FixtureCase: Decodable {
  let name: String
  let currentAlarms: [NativeAlarm]
  let nextPayload: NativeAlarmPayload
  let expected: ExpectedActions
}

private struct ExplicitOverrideCase: Decodable {
  let schedule: Schedule
  let currentOverrides: LeadTimeOverrides
  let nextOverrides: LeadTimeOverrides
  let expected: ExplicitOverrideExpectation
}

private struct ExpectedActions: Decodable {
  let create: [String]
  let update: [String]
  let cancel: [String]
  let unchanged: [String]
}

private struct ExplicitOverrideExpectation: Decodable {
  let currentLeaveAt: String
  let nextLeaveAt: String
  let create: [String]
  let update: [String]
  let cancel: [String]
  let unchanged: [String]
}

private struct StaticScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private struct FailingScheduleService: ScheduleServing {
  func fetchSchedule() async throws -> Schedule { throw URLError(.notConnectedToInternet) }
}

private actor RecordingAlarmAdapter: AlarmAdapting {
  private var scheduled: [NativeAlarm] = []
  private var cancelled = 0
  private var prepared: Schedule?
  private let authorization: AlarmAuthorizationStatus
  private let existingIDs: Set<String>?

  init(authorization: AlarmAuthorizationStatus = .authorized, existingIDs: Set<String>? = nil) {
    self.authorization = authorization
    self.existingIDs = existingIDs
  }

  func prepare(schedule: Schedule) { prepared = schedule }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { authorization }
  func requestAuthorization() throws { if authorization != .authorized { throw AlarmAdapterError.authorizationDenied } }
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    scheduled.append(alarm)
    return PlatformAlarmIdentifier.newPersistedValue()
  }
  func cancel(platformAlarmID: String) throws { cancelled += 1 }
  func scheduledCount() -> Int { scheduled.count }
  func scheduledStableIds() -> [String] { scheduled.map(\.stableId) }
  func cancelledCount() -> Int { cancelled }
  func preparedSchedule() -> Schedule? { prepared }
  func existingPlatformAlarmIDs() async throws -> Set<String>? { existingIDs }
}

private actor CountingScheduleService: ScheduleServing {
  private let schedule: Schedule
  private var count = 0

  init(schedule: Schedule) { self.schedule = schedule }
  func fetchSchedule() -> Schedule { count += 1; return schedule }
  func fetchCount() -> Int { count }
}

private actor MutableScheduleService: ScheduleServing {
  private var schedule: Schedule
  init(schedule: Schedule) { self.schedule = schedule }
  func fetchSchedule() async throws -> Schedule { schedule }
  func replace(_ value: Schedule) { schedule = value }
}

private actor RecordingWatchScheduleDelivery: WatchScheduleSnapshotDelivering {
  private var received: WatchScheduleSnapshot?

  func deliver(_ snapshot: WatchScheduleSnapshot) -> WatchScheduleDeliveryDisposition {
    received = snapshot
    return .sent
  }

  func receivedSnapshot() -> WatchScheduleSnapshot? { received }
}

private actor WatchReloadRecorder {
  private var snapshots: [WatchScheduleSnapshot] = []

  func record(_ snapshot: WatchScheduleSnapshot) {
    snapshots.append(snapshot)
  }

  func count() -> Int { snapshots.count }
}

private actor WatchNotificationHookRecorder {
  private var enabled: Bool
  private var reconciledSnapshots: [WatchScheduleSnapshot] = []

  init(enabled: Bool) {
    self.enabled = enabled
  }

  func setEnabled(_ value: Bool) {
    enabled = value
  }

  func didStore(_ snapshot: WatchScheduleSnapshot) {
    guard enabled else { return }
    reconciledSnapshots.append(snapshot)
  }

  func reconcileCount() -> Int {
    reconciledSnapshots.count
  }
}

private actor FailingWatchScheduleDelivery: WatchScheduleSnapshotDelivering {
  private var received: WatchScheduleSnapshot?

  func deliver(_ snapshot: WatchScheduleSnapshot) throws -> WatchScheduleDeliveryDisposition {
    received = snapshot
    throw URLError(.cannotConnectToHost)
  }

  func receivedSnapshot() -> WatchScheduleSnapshot? { received }
}
#endif
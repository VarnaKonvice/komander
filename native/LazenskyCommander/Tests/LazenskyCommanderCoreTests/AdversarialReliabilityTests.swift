import Foundation
import Testing
@testable import LazenskyCommanderCore

private func pass2Date(_ value: String) throws -> Date { try NativeAlarmContract.date(fromLocalISO: value) }
private func pass2Schedule(date: String = "2026-09-29", start: String = "10:00", end: String = "10:30",
                           lead: Int = 10, version: Int = 1) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-29T00:00:00Z", stay: [:],
    events: [ScheduleEvent(stableId: "pass2", date: date, start: start, end: end, title: "Masáž",
      location: "A", kind: .procedure, procedureType: "Masáž", mealType: nil, leadTimeMinutes: nil)],
    settings: ScheduleSettings(defaultLeadTimeMinutes: lead, procedureTypeOverrides: [:], mealOverrides: [:]))
}

@Test @MainActor func previewEditsAndResetCannotReadOrWritePersistentPreferences() throws {
  let suite = "commander.pass2." + UUID().uuidString
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let production = LeadTimePreferencesStore(defaults: defaults, key: "preferences")
  production.save(.init(overrides: .init(defaultLeadTimeMinutes: 42), revision: 7))
  let bytes = defaults.data(forKey: "preferences")
  // Even a mistakenly shared key must be harmless in preview mode.
  let preview = LeadTimePreferencesStore(defaults: defaults, key: "preferences", isPersistent: false)
  #expect(preview.load().overrides == LeadTimeOverrides())
  preview.save(.init(overrides: .init(defaultLeadTimeMinutes: 3), revision: 1))
  preview.save(.init(overrides: .init(), revision: 2))
  #expect(defaults.data(forKey: "preferences") == bytes)
  #expect(LeadTimePreferencesStore(defaults: defaults, key: "preferences", isPersistent: false).load().revision == 0)
  #expect(production.load().overrides.defaultLeadTimeMinutes == 42)
  #expect(production.load().revision == 7)
  defaults.set(true, forKey: "commander.visualReview.enabled")
  #expect(!CommanderPreviewPolicy.enabled(arguments: []))
  #expect(CommanderPreviewPolicy.enabled(arguments: ["-CommanderDesignPreview"]))
  #expect(!CommanderPreviewPolicy.enabled(arguments: ["-CommanderDesignPreview", "-CommanderDisableDesignPreview"]))
}

@Test(arguments: ["09:49", "09:50", "09:55", "10:00", "10:15", "10:30", "10:31"])
func everyBoundaryUsesCurrentPhaseEvenWhenActivityIsStale(time: String) throws {
  let schedule = pass2Schedule()
  let now = try pass2Date("2026-09-29T" + time)
  let projection = try CommanderScheduleProjection(schedule: schedule)
  let timeline = try #require(CommanderLiveActivityTimeline.resolve(events: projection.events.map(\.timelineEvent), at: now, isStale: true))
  let expected: CommanderLiveActivityTimelinePhase = time < "10:00" ? .upcoming : time < "10:30" ? .active : .ended
  #expect(timeline.phase == expected)
  #expect(timeline.departureDue == (time >= "09:50" && time < "10:00"))
  if expected != .ended { #expect(timeline.countdownTarget > now) }
  let live = projection.liveState(at: now)
  #expect(live.state == (time < "09:50" ? .upcoming : time < "10:00" ? .leaveNow : time < "10:30" ? .inProgress : .dayDone))
}

@Test(arguments: ["09:00", "09:50", "09:59", "10:00", "10:30"])
func homeWidgetNeverInventsLocalDeparture(time: String) throws {
  let schedule = pass2Schedule(lead: 60)
  let now = try pass2Date("2026-09-29T" + time)
  let live = CommanderHomeWidgetPresentation.compute(schedule: schedule, now: now)
  #expect(live.leaveAt == nil)
  #expect(live.leadTimeMinutes == nil)
  #expect(live.state == (time < "10:00" ? .upcoming : time < "10:30" ? .inProgress : .dayDone))
  #expect(CommanderHomeWidgetPresentation.compute(schedule: nil, now: now).state == .noSchedule)
}

@Test func departureBeforeMidnightSurvivesDayTransitionAndTimelineReload() throws {
  let schedule = pass2Schedule(date: "2026-09-30", start: "00:10", end: "00:30", lead: 20)
  let before = try pass2Date("2026-09-29T23:49")
  let leave = try pass2Date("2026-09-29T23:50")
  let midnight = try pass2Date("2026-09-30T00:00")
  #expect(CommanderLiveStateCalculator.compute(schedule: schedule, now: before).state == .dayDone)
  for now in [leave, midnight] {
    let state = CommanderLiveStateCalculator.compute(schedule: schedule, now: now)
    #expect(state.state == .leaveNow)
    #expect(state.event?.stableId == "pass2")
  }
  let points = try WatchTimelinePlanner.points(schedule: schedule, now: before)
  #expect(points.contains { $0.date == leave && $0.state == .leaveNow })
  #expect(points.contains { $0.date == midnight && $0.state == .leaveNow })
}

@Test func pragueDSTRejectsMissingOrAmbiguousWallTimesAndDerivedDeparture() throws {
  #expect(throws: (any Error).self) { try pass2Date("2026-03-29T02:30") }
  #expect(throws: (any Error).self) { try pass2Date("2026-10-25T02:30") }
  #expect(throws: (any Error).self) {
    try NativeAlarmContract.payload(schedule: pass2Schedule(date: "2026-10-25", start: "03:10", end: "03:30", lead: 20))
  }
  let spring = try NativeAlarmContract.payload(schedule: pass2Schedule(date: "2026-03-29", start: "03:10", end: "03:30", lead: 20))
  #expect(spring.alarms.first?.leaveAt == "2026-03-29T01:50:00")
  let autumn = try NativeAlarmContract.payload(schedule: pass2Schedule(date: "2026-10-25", start: "04:10", end: "04:30", lead: 20))
  #expect(autumn.alarms.first?.leaveAt == "2026-10-25T03:50:00")
}

@Test(arguments: ["2026-09-29T09:bad:30", "2026-09-bad-29T09:30", "2026-09-29T09:30:15", "2026-02-30T09:30"])
func malformedLocalDatesFailClosed(value: String) {
  #expect(throws: (any Error).self) { try pass2Date(value) }
}

@Test func stopCallbackCannotApplyBeforeDepartureOrAtEnd() throws {
  let alarm = try #require(NativeAlarmContract.payload(schedule: pass2Schedule()).alarms.first)
  let snapshot = CommanderAlarmEventSnapshot(stableId: alarm.stableId, iconKey: "", title: alarm.title,
    location: alarm.location, kind: alarm.kind, startAt: alarm.startAt, endAt: alarm.endAt, leaveAt: alarm.leaveAt)
  for time in ["09:49", "09:50", "10:00", "10:29", "10:30"] {
    #expect(CommanderAlarmStopPolicy.canApply(stopped: snapshot, current: snapshot,
      now: try pass2Date("2026-09-29T" + time)) == (time >= "09:50" && time < "10:30"))
  }
}

private actor DeferredPass2Source: ScheduleServing {
  var pending: CheckedContinuation<Schedule, Never>?
  var waiter: CheckedContinuation<Void, Never>?
  func fetchSchedule() async throws -> Schedule {
    await withCheckedContinuation { continuation in
      pending = continuation
      waiter?.resume(); waiter = nil
    }
  }
  func waitForFetch() async {
    if pending != nil { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func finish(_ schedule: Schedule) { pending?.resume(returning: schedule); pending = nil }
}
private struct Pass2Source: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() -> Schedule { schedule }
}

@Test func olderSuspendedWidgetFetchCannotReplaceNewerSnapshot() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let slow = DeferredPass2Source()
  let oldTask = Task { await CommanderWidgetSnapshotLoader(service: slow, cache: cache).load() }
  await slow.waitForFetch()
  let newest = await CommanderWidgetSnapshotLoader(service: Pass2Source(schedule: pass2Schedule(version: 3)), cache: cache).load()
  await slow.finish(pass2Schedule(version: 2))
  #expect(await oldTask.value == newest)
  #expect(try await FileWatchScheduleCache(directoryURL: directory).load() == newest)
}

@Test func watchRelaunchRejectsOldRevisionRepeatedDeliveryAndConflictingSameVersion() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory)
  let latest = WatchScheduleSnapshot(schedule: pass2Schedule(), leadTimeOverrides: .init(defaultLeadTimeMinutes: 30), projectionRevision: 4)
  #expect(try await cache.accept(latest) == .stored)
  let restarted = FileWatchScheduleCache(directoryURL: directory)
  #expect(try await restarted.load() == latest)
  #expect(try await restarted.accept(latest) == .unchanged)
  #expect(try await restarted.accept(.init(schedule: pass2Schedule(), projectionRevision: 3)) == .rejectedVersion(current: 1, incoming: 1))
  #expect(try await restarted.accept(.init(schedule: pass2Schedule(start: "10:05"), projectionRevision: 5)) == .rejectedVersion(current: 1, incoming: 1))
  #expect(try await restarted.load() == latest)
  let expiry = try #require(try WatchScheduleExpiryPolicy.expirationDate(for: latest.schedule))
  #expect(WatchScheduleExpiryPolicy.activeSchedule(latest.schedule, at: expiry.addingTimeInterval(-1)) != nil)
  #expect(WatchScheduleExpiryPolicy.activeSchedule(latest.schedule, at: expiry) == nil)
  try Data("{\"contractVersion\":1}".utf8).write(to: directory.appendingPathComponent(FileWatchScheduleCache.defaultFileName), options: .atomic)
  #expect(try await restarted.load() == nil)
}

private actor OrphanRingingPlatform: AlarmAdapting {
  private(set) var cancels = 0
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing: String?) throws -> String { throw URLError(.unknown) }
  func cancel(platformAlarmID: String) { cancels += 1 }
  func existingPlatformAlarmIDs() -> Set<String>? { ["owned-ambiguous-success"] }
  func existingPlatformAlertingAlarmIDs() -> Set<String> { ["owned-ambiguous-success"] }
  func existingPlatformFixedAlertDates() -> [String: Date]? { [:] }
}

@Test func relaunchAfterAmbiguousScheduleDoesNotCancelRingingOrphan() async throws {
  let schedule = pass2Schedule()
  let adapter = OrphanRingingPlatform()
  let sync = AlarmSyncService(scheduleService: Pass2Source(schedule: schedule), store: InMemoryAlarmStateStore(), adapter: adapter)
  for time in ["09:50", "09:55", "10:00"] {
    let result = try await sync.synchronize(schedule: schedule, now: pass2Date("2026-09-29T" + time))
    #expect(result.succeeded)
    #expect(result.appliedCreate == 0)
    #expect(await adapter.cancels == 0)
  }
}

@Test func repeatedDelayedStopDoesNotRewindFocusToEarlierOverlappingEvent() throws {
  func event(_ id: String, _ start: String, _ leave: String) -> CommanderAlarmEventSnapshot {
    .init(stableId: id, iconKey: "", title: id, location: "A", kind: .procedure,
      startAt: "2026-09-29T" + start, endAt: "2026-09-29T11:00", leaveAt: "2026-09-29T" + leave)
  }
  let earlier = event("breakfast", "10:00", "09:50")
  let later = event("procedure", "10:10", "10:00")
  let now = try pass2Date("2026-09-29T10:05")
  #expect(CommanderAlarmStopPolicy.canApply(stopped: later, current: later, focused: earlier, now: now))
  #expect(!CommanderAlarmStopPolicy.canApply(stopped: earlier, current: earlier, focused: later, now: now))
}

@Test func runtimeWiresEphemeralPreviewAndSharedActivityWriter() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func source(_ file: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/" + file), encoding: .utf8)
  }
  let app = try source("LazenskyCommanderApp/LazenskyCommanderApp.swift")
  #expect(app.contains("isPersistent: !CommanderDesignPreview.enabled"))
  #expect(!app.contains("commander.visualReview.enabled"))
  #expect(app.contains("if !CommanderDesignPreview.enabled { scheduleAuditReviewStore.save"))
  let widget = try source("LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift")
  #expect(!widget.contains("commander.visualReview.enabled"))
  #expect(widget.contains("if state.schedule == nil"))
  #expect(widget.contains("CommanderPhoneWidgetPresentation"))
  #expect(widget.contains("CommanderPhoneWidgetTimeline.points"))
  #expect(!widget.contains("state.live.leaveAt"))
  for file in ["AlarmKitAdapter.swift", "CommanderProcedureLiveActivityCoordinator.swift"] {
    #expect(try source("LazenskyCommanderApp/" + file).contains("CommanderProcedureLiveActivityPolicy.operations.run"))
  }
  let coordinator = try source("LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift")
  #expect(coordinator.contains("projectionRevision: $0.content.state.projectionRevision"))
  let watchWidget = try source("LazenskyCommanderWatchWidget/LazenskyCommanderWatchWidget.swift")
  #expect(watchWidget.contains("entries: [noScheduleEntry(at: now)], policy: .after"))
}

@Test func ambiguousCanonicalDepartureCannotReplaceValidOfflineSchedule() async throws {
  let valid = pass2Schedule()
  let store = InMemoryScheduleSnapshotStore(valid)
  let invalid = pass2Schedule(date: "2026-10-25", start: "03:10", end: "03:30", lead: 20, version: 2)
  do { _ = try await store.accept(invalid); Issue.record("Ambiguous departure was cached") } catch {}
  #expect(await store.load() == valid)
}

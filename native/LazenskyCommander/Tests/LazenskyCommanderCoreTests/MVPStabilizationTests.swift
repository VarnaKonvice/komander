import Foundation
import Testing
@testable import LazenskyCommanderCore

private func mvpDate(_ time: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: "2026-09-29T\(time):00")
}
private func mvpSchedule(version: Int = 1, start: String = "10:00", location: String = "Budova 2",
                         ids: [String] = ["event/č.1"]) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-29T06:00:00Z", stay: [:],
    events: ids.map { ScheduleEvent(stableId: $0, date: "2026-09-29", start: start, end: "11:00",
      title: "Magnetoterapie", location: location, kind: .procedure, procedureType: nil,
      mealType: nil, leadTimeMinutes: nil) },
    settings: .init(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:]))
}
private func notifications(_ schedule: Schedule, departure: Bool = false,
                           overrides: LeadTimeOverrides = .init()) throws -> [CommanderScheduledNotification] {
  try CommanderNotificationContract.desired(snapshot: .init(schedule: schedule, leadTimeOverrides: overrides),
    dataset: .production, channel: "production", includeDeparture: departure, now: mvpDate("08:00"))
}
private func changes(_ current: [CommanderScheduledNotification], _ desired: [CommanderScheduledNotification]) -> CommanderNotificationChanges {
  CommanderNotificationContract.reconcile(current: current, desired: desired, dataset: .production, channel: "production")
}

@Test func notificationIdentifiersAreStableLosslessAndDatasetScoped() throws {
  let first = try notifications(mvpSchedule())
  let changed = try notifications(mvpSchedule(version: 2, start: "10:15", location: "Nová budova"))
  #expect(first[0].identifier == changed[0].identifier)
  let ids = ["a/b", "a.b", "a+b", "á", "a", "a=="]
  #expect(Set(ids.map { CommanderNotificationContract.identifier(stableID: $0, dataset: .production, channel: "production") }).count == ids.count)
  #expect(CommanderNotificationContract.identifier(stableID: "a", dataset: .production, channel: "production") !=
          CommanderNotificationContract.identifier(stableID: "a", dataset: .acceptance, channel: "production"))
  #expect(CommanderNotificationContract.identifier(stableID: "a", dataset: .production, channel: "production") !=
          CommanderNotificationContract.identifier(stableID: "a", dataset: .production, channel: "e2e"))
}

@Test func notificationAddChangeRemoveAndRetryAreIdempotent() throws {
  var platform: [String: CommanderScheduledNotification] = [:]
  func apply(_ desired: [CommanderScheduledNotification]) {
    let plan = changes(Array(platform.values), desired)
    for id in plan.remove { platform.removeValue(forKey: id) }
    for item in plan.upsert { platform[item.identifier] = item }
  }
  let initial = try notifications(mvpSchedule())
  #expect(changes([], initial).upsert.count == 1)
  apply(initial)
  apply(initial)
  #expect(platform.count == 1)
  #expect(changes(Array(platform.values), initial).upsert.isEmpty)
  let updated = try notifications(mvpSchedule(version: 2, start: "10:15", location: "Jiná budova"))
  #expect(changes(Array(platform.values), updated).upsert.count == 1)
  apply(updated)
  #expect(platform.count == 1)
  #expect(platform.values.first?.fireAt == (try mvpDate("10:15")))
  #expect(platform.values.first?.body == "Jiná budova · 10:15")
  let added = try notifications(mvpSchedule(version: 3, ids: ["event/č.1", "event2"]))
  apply(added)
  #expect(platform.count == 2)
  #expect(changes(Array(platform.values), []).remove.count == 2)
  apply([])
  #expect(platform.isEmpty)
}

@Test func alarmRecoveryRemovesOnlyDepartureFallbackAndRetainsStart() throws {
  let both = try notifications(mvpSchedule(), departure: true)
  let starts = try notifications(mvpSchedule())
  #expect(both.count == 2)
  let recovery = changes(both, starts)
  #expect(recovery.upsert.isEmpty)
  #expect(recovery.remove.count == 1)
  #expect(!recovery.remove.contains(starts[0].identifier))
}

@Test func notificationProjectionUsesCanonicalStartAndLeadTime() throws {
  let schedule = mvpSchedule()
  let overrides = LeadTimeOverrides(eventOverrides: ["event/č.1": 30])
  let projection = try CommanderScheduleProjection(schedule: schedule, overrides: overrides)
  let both = try notifications(schedule, departure: true, overrides: overrides)
  #expect(both[0].fireAt == projection.events[0].leaveAt)
  #expect(both[1].fireAt == projection.events[0].startAt)
  #expect(both[1].payload["stableId"] == "event/č.1")
  #expect(both[1].payload["startAt"] == projection.events[0].alarm.startAt)
  #expect(Set(both.map(\.identifier)).count == both.count)
}

@Test func notificationCleanupPreservesOtherDatasetsAndNamespaces() throws {
  let acceptance = try CommanderAcceptanceSchedule(now: mvpDate("08:00")).schedule
  let acceptanceItems = try CommanderNotificationContract.desired(snapshot: .init(schedule: acceptance),
    dataset: .acceptance, channel: "production", includeDeparture: true, now: mvpDate("08:00"))
  let production = try notifications(mvpSchedule())
  let foreign = CommanderScheduledNotification(identifier: "provisioning-reminder", title: "Reminder", body: "",
    fireAt: try mvpDate("12:00"), payload: [:])
  let plan = changes(acceptanceItems + production + [foreign], [])
  #expect(plan.remove == production.map(\.identifier))
  #expect(plan.upsert.isEmpty)
}

@Test func productionRejectsAcceptanceDemoAndMixedInputs() throws {
  for schedule in [try CommanderAcceptanceSchedule(now: mvpDate("08:00")).schedule,
                   CommanderWidgetDemoSchedule.make(), mvpSchedule(ids: ["widgetDemo.magnet"]),
                   mvpSchedule(ids: [PhysicalAcceptanceRun.stableIDPrefix + "test"])] {
    #expect(!CommanderScheduleDataset.production.accepts(schedule))
    #expect(throws: (any Error).self) { try notifications(schedule) }
  }
}

@Test func notificationsAreBoundedAndDoNotReplayPastStarts() throws {
  let snapshot = WatchScheduleSnapshot(schedule: mvpSchedule())
  let atStart = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: .production,
    channel: "production", includeDeparture: true, now: mvpDate("10:00"))
  #expect(atStart.isEmpty)
  let bounded = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: .production,
    channel: "production", includeDeparture: true, now: mvpDate("08:00"), limit: 1)
  #expect(bounded.count == 1)
  #expect(bounded[0].fireAt == (try mvpDate("09:40")))
}

@Test func everyWidgetUsesTodayDeepLinkContract() {
  #expect(CommanderNavigation.opensToday(CommanderNavigation.todayURL))
  #expect(!CommanderNavigation.opensToday(URL(string: "https://today")!))
  #expect(!CommanderNavigation.opensToday(URL(string: "lazenskycommander://settings")!))
}

@Test func watchDefaultActionRoutesOnlyCommanderDatasetToCanonicalCurrentEvent() throws {
  let notification = try notifications(mvpSchedule())[0]
  func routes(_ action: String, _ payload: [String: String], category: String = CommanderNotificationContract.category) -> Bool {
    CommanderNotificationContract.routesToCurrent(actionIdentifier: action, defaultActionIdentifier: "system-default",
      category: category, payload: payload, dataset: .production)
  }
  #expect(routes("system-default", notification.payload))
  #expect(!routes("system-dismiss", notification.payload))
  #expect(!routes("custom-action", notification.payload))
  #expect(!routes("system-default", notification.payload, category: "another-app"))
  var wrong = notification.payload
  wrong["dataset"] = "acceptance"
  #expect(!routes("system-default", wrong))
  let updated = WatchScheduleSnapshot(schedule: mvpSchedule(version: 2, ids: ["replacement-event"]),
    leadTimeOverrides: .init(defaultLeadTimeMinutes: 30), projectionRevision: 3)
  let now = try mvpDate("10:05")
  let current = CommanderNotificationContract.currentState(snapshot: updated, now: now)
  #expect(current.event?.stableId == "replacement-event")
  #expect(current == CommanderLiveStateCalculator.compute(schedule: updated.schedule, now: now, overrides: updated.leadTimeOverrides))
  #expect(CommanderNotificationContract.currentState(snapshot: nil, now: now).event == nil)
}

@Test func productionMVPDoesNotCreateLiveActivities() {
  #expect(CommanderMVPPolicy.createsLiveActivities == false)
  #expect(CommanderMVPPolicy.createsStandaloneWatchAlerts == false)
}

@Test func partialAlarmFailureNeverDuplicatesExistingAlarmWithDepartureNotification() throws {
  let snapshot = WatchScheduleSnapshot(schedule: mvpSchedule(ids: ["armed", "missing"]))
  let desired = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: .production,
    channel: "production", includeDeparture: true, now: mvpDate("08:00"), departureExclusions: ["armed"])
  #expect(desired.count == 3)
  #expect(desired.filter { $0.payload["kind"] == "start" }.count == 2)
  #expect(desired.filter { $0.payload["kind"] == "leave" }.map { $0.payload["stableId"] } == ["missing"])
}

@Test func notificationRuntimeWiringUsesTestedContractsAndSystemWatchDefaultAction() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func source(_ name: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/" + name), encoding: .utf8)
  }
  let app = try source("LazenskyCommanderApp/LazenskyCommanderApp.swift")
  #expect(app.contains("acceptedSnapshot = result.watchSnapshot"))
  #expect(app.contains("eventNotifications.reconcile(snapshot: result.watchSnapshot"))
  #expect(app.contains("CommanderNotificationContract.reconcile(current: current, desired: desired"))
  #expect(app.contains("existingAlarmEvents != nil"))
  #expect(app.contains("content.categoryIdentifier = CommanderNotificationContract.category"))
  #expect(app.contains("content.userInfo = item.payload"))
  #expect(!app.contains("removeAllPendingNotificationRequests"))
  let watch = try source("LazenskyCommanderWatchApp/LazenskyCommanderWatchApp.swift")
  #expect(watch.contains("UNUserNotificationCenter.current().delegate = notificationDelegate"))
  #expect(watch.contains("response.actionIdentifier == UNNotificationDefaultActionIdentifier"))
  #expect(!watch.contains("WKNotificationScene("))
  #expect(!watch.contains("WKUserNotificationHostingController"))
  #expect(!watch.contains("notificationRouteRevision"))
  #expect(!watch.contains("response.notification"))
  #expect(watch.contains("Task { @MainActor [model] in\n      await model.bootstrap()"))
  #expect(watch.contains("WatchCommanderView(model: model)"))
  let standalone = try source("LazenskyCommanderWatchApp/WatchLocalNotificationService.swift")
  #expect(standalone.contains("enabled && preferences.isEnabled && CommanderMVPPolicy.createsStandaloneWatchAlerts"))
  #expect(standalone.contains("WatchCacheLocation.dataset.accepts(stableID: stableId)"))
  let model = try source("LazenskyCommanderWatchApp/WatchCommanderModel.swift")
  #expect(model.contains("func handleForeground() async {"))
  #expect(model.contains("let cached = try await cache.load()"))
  #expect(model.contains("!WatchScheduleExpiryPolicy.isExpired(cached.schedule"))
  #expect(model.contains("CommanderNotificationContract.currentState(snapshot: snapshot, now: now)"))
  let widget = try source("LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift")
  #expect(widget.components(separatedBy: ".widgetURL(CommanderNavigation.todayURL)").count - 1 == 3)
  let project = try source("LazenskyCommanderApp.xcodeproj/project.pbxproj")
  #expect(!project.contains("COMMANDER_WIDGET_DEMO"))
}

private struct MVPSource: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}
private actor MVPBrokenAlarmStore: AlarmStateStoring {
  func load() throws -> ManagedAlarmState { throw CocoaError(.fileReadCorruptFile) }
  func save(_ state: ManagedAlarmState) throws { throw CocoaError(.fileWriteUnknown) }
}

@Test func canonicalSnapshotStillReachesNotificationProjectionWhenAlarmLedgerCannotBeRead() async throws {
  let schedule = mvpSchedule()
  let source = MVPSource(schedule: schedule)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: source,
    alarmSyncService: .init(scheduleService: source, store: MVPBrokenAlarmStore(), adapter: UnavailableAlarmKitAdapter()),
    scheduleStore: InMemoryScheduleSnapshotStore(), dataset: .production)
  let result = try await coordinator.synchronize(now: mvpDate("08:00"))
  #expect(!result.alarmSummary.succeeded)
  #expect(result.alarmSummary.errorMessage != nil)
  #expect(result.watchSnapshot.schedule == schedule)
  #expect(try await coordinator.loadLastSchedule() == schedule)
  let alerts = try CommanderNotificationContract.desired(snapshot: result.watchSnapshot, dataset: .production,
    channel: "production", includeDeparture: false, now: mvpDate("08:00"))
  #expect(alerts.count == 1)
}

@Test func productionInputBoundaryRejectsDemoBeforeMutatingCanonicalStore() async throws {
  let production = mvpSchedule()
  let store = InMemoryScheduleSnapshotStore(production)
  let source = MVPSource(schedule: CommanderWidgetDemoSchedule.make())
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: source,
    alarmSyncService: .init(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: UnavailableAlarmKitAdapter()),
    scheduleStore: store, dataset: .production)
  await #expect(throws: (any Error).self) { try await coordinator.synchronize(now: mvpDate("08:00")) }
  #expect(await store.load() == production)
  let corruptCache = CommanderScheduleSyncCoordinator(scheduleService: source,
    alarmSyncService: .init(scheduleService: source, store: InMemoryAlarmStateStore(), adapter: UnavailableAlarmKitAdapter()),
    scheduleStore: InMemoryScheduleSnapshotStore(source.schedule), dataset: .production)
  await #expect(throws: (any Error).self) { try await corruptCache.loadLastSchedule() }
  await #expect(throws: (any Error).self) { try await corruptCache.synchronize(source: .cached, now: mvpDate("08:00")) }
}

@Test func sharedWidgetSnapshotSelectsCanonicalEventDuringOverlappingDeparture() throws {
  let meal = ScheduleEvent(stableId: "meal", date: "2026-09-29", start: "09:00", end: "10:30",
    title: "Snídaně", location: "Jídelna", kind: .meal, procedureType: nil, mealType: nil, leadTimeMinutes: nil)
  let seed = mvpSchedule()
  let schedule = Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: seed.updatedAt, stay: [:],
    events: [meal] + seed.events, settings: seed.settings)
  let overrides = LeadTimeOverrides(eventOverrides: ["event/č.1": 30])
  let now = try mvpDate("09:35")
  let canonical = CommanderLiveStateCalculator.compute(schedule: schedule, now: now, overrides: overrides)
  let widget = CommanderHomeWidgetPresentation.compute(schedule: schedule, now: now, overrides: overrides)
  #expect(canonical.event?.stableId == "event/č.1")
  #expect(widget.event == canonical.event)
  #expect(widget.nextEvent == canonical.nextEvent)
  #expect(widget.startAt == canonical.startAt)
  #expect(widget.endAt == canonical.endAt)
  #expect(widget.leaveAt == nil) // Approved widget copy stays start/end only.
  #expect(widget.state == .upcoming)
}

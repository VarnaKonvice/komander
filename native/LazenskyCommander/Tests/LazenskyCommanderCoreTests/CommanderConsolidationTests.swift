import Foundation
import Testing
@testable import LazenskyCommanderCore

private func date(_ time: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: "2026-09-28T\(time):00")
}
private func fixture() -> Schedule {
  let data = """
  {"schemaVersion":1,"scheduleVersion":5,"updatedAt":"2026-09-28T06:00:00Z","stay":{},
   "settings":{"defaultLeadTimeMinutes":10,"procedureTypeOverrides":{},"mealOverrides":{}},
   "events":[
    {"stableId":"meal","date":"2026-09-28","start":"09:00","end":"10:30","title":"Snídaně","location":"Jídelna","kind":"meal"},
    {"stableId":"magnet","date":"2026-09-28","start":"10:00","end":"10:20","title":"Magnetoterapie","location":"A","kind":"procedure"},
    {"stableId":"next","date":"2026-09-28","start":"11:00","end":"11:30","title":"Hydrojet","location":"B","kind":"procedure"}]}
  """
  return try! JSONDecoder().decode(Schedule.self, from: Data(data.utf8))
}

@Test func watchCountdownUsesReadableHoursAndMinutes() throws {
  let now = try date("08:00")
  let leaveAt = now.addingTimeInterval(190 * 60 + 16)
  let presentation = CommanderCountdownPresentation(
    presentationMode: .departureCountdown,
    leaveAt: leaveAt,
    startAt: leaveAt.addingTimeInterval(20 * 60),
    endAt: leaveAt.addingTimeInterval(40 * 60),
    at: now
  )
  #expect(presentation.countdownText(at: now) == "3 h 10 m")
  #expect(presentation.countdownText(at: leaveAt.addingTimeInterval(-59 * 60 - 15)) == "59:15")
  #expect(presentation.countdownText(at: leaveAt.addingTimeInterval(-45)) == "0:45")
  #expect(presentation.countdownText(at: leaveAt) == "0:00")
}

@Test func allNativeSurfacesAgreeOnCanonicalTimesAndOverlapFocus() throws {
  let schedule = fixture()
  let overrides = LeadTimeOverrides(eventOverrides: ["magnet": 20])
  let projection = try CommanderScheduleProjection(schedule: schedule, overrides: overrides)
  for time in ["08:49", "08:50", "09:00", "09:39", "09:40", "10:00", "10:20", "10:30", "11:30"] {
    let now = try date(time)
    let state = CommanderLiveStateCalculator.compute(schedule: schedule, now: now, overrides: overrides)
    let dashboard = CommanderDashboardPresentation.make(schedule: schedule, now: now, overrides: overrides)
    let week = try CommanderWeekPresentation.make(schedule: schedule, now: now, overrides: overrides)
    let timeline = try #require(CommanderLiveActivityTimeline.resolve(events: projection.events.map(\.timelineEvent), at: now))
    #expect(dashboard.liveState == state)
    if timeline.phase != .ended {
      #expect(state.event?.stableId == timeline.primaryStableId)
      #expect(CommanderCountdownPresentation(liveState: state).target == timeline.countdownTarget)
      let item = try #require(week.flatMap(\.events).first { $0.event.stableId == state.event?.stableId })
      #expect(item.leaveAt == state.leaveAt)
      #expect(item.startAt == state.startAt)
      #expect(item.endAt == state.endAt)
    }
  }
  #expect(projection.liveState(at: try date("09:40")).event?.stableId == "magnet")
  #expect(projection.liveState(at: try date("10:00")).event?.stableId == "magnet")
  #expect(projection.liveState(at: try date("10:00")).nextEvent?.stableId == "next")
  #expect(projection.payload.alarms.first { $0.stableId == "magnet" }?.leaveAt == "2026-09-28T09:40:00")
}

// Required story: stale transport metadata must never redefine event phase.
@Test(arguments: [false, true])
func requiredStopStoryHasExactStartAndEndBoundaries(isStale: Bool) throws {
  let seed = CommanderAlarmEventSnapshot(stableId: "magnet", iconKey: "electro_therapy",
    title: "Magnetoterapie", location: "A", kind: .procedure,
    startAt: "2026-09-28T10:00:00", endAt: "2026-09-28T10:20:00", leaveAt: "2026-09-28T09:40:00")
  let start = try date("10:00")
  let end = try date("10:20")
  // Keep the SAME post-Stop content throughout; do not feed the expected mode back in.
  for now in [try date("09:40"), start.addingTimeInterval(-0.001), start,
              start.addingTimeInterval(1), end.addingTimeInterval(-0.001), end,
              end.addingTimeInterval(1), end.addingTimeInterval(86_400)] {
    let display = CommanderActivityPresentation.resolve(seed: seed, events: [seed],
      focusStableId: "magnet", presentationMode: .startCountdown,
      isStale: isStale, at: now)
    #expect(!display.isScheduleFallback)
    if now < start {
      #expect(display.status == "Začátek za")
      #expect(display.countdownTarget == start)
      #expect(display.countdownLabel == "Do začátku")
    } else if now < end {
      #expect(display.status == "Právě probíhá")
      #expect(display.countdownTarget == end)
      #expect(display.countdownLabel == "Do konce")
    } else {
      #expect(display.status == "Skončilo")
      #expect(display.isFinished)
      #expect(display.countdownTarget == nil)
      #expect(display.timing.countdownText(at: now) == nil)
      #expect(display.timing.symbol == "checkmark.circle.fill")
    }
  }
}

@Test(arguments: [CommanderLiveActivityPresentationMode.departureCountdown, .startCountdown, .eventContext])
func requiredStoryNeverKeepsDepartureOrProgressAtOrAfterEnd(mode: CommanderLiveActivityPresentationMode) throws {
  let seed = CommanderAlarmEventSnapshot(stableId: "meal", iconKey: "meal", title: "Oběd",
    location: "A", kind: .meal, startAt: "2026-09-28T10:00:00",
    endAt: "2026-09-28T10:20:00", leaveAt: "2026-09-28T09:40:00")
  for stale in [false, true] {
    for policy in [CommanderActivityRenderingPolicy.deterministic, .suspendedActivity] {
      for now in [try date("10:20"), try date("11:00")] {
        let display = CommanderActivityPresentation.resolve(seed: seed, events: [seed],
          focusStableId: nil, presentationMode: mode, isStale: stale, at: now,
          renderingPolicy: policy)
        #expect(display.status == "Skončilo")
        #expect(display.isFinished)
        #expect(display.countdownTarget == nil)
      }
    }
  }
}

@Test func acceptanceUsesFullProductionBootstrapAndTransport() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func source(_ path: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/" + path), encoding: .utf8)
  }
  let app = try source("LazenskyCommanderApp/LazenskyCommanderApp.swift")
  let lifecycle = String(app[try #require(app.range(of: "@main")).lowerBound...])
  #expect(lifecycle.contains("CommanderAppTabs(model: model)"))
  #expect(lifecycle.contains("await model.bootstrap()"))
  #expect(lifecycle.contains("await model.handleForeground()"))
  #expect(!lifecycle.contains("switch acceptanceMode"))
  #expect(!app.contains("isAcceptanceBuild"))
  #expect(!app.contains("bootstrapAcceptancePassive"))
  let bootstrapStart = try #require(app.range(of: "  func bootstrap() async"))
  let bootstrapEnd = try #require(app.range(of: "@MainActor\nprivate final class ScheduleAuditReviewStore"))
  let operations = app[bootstrapStart.lowerBound..<bootstrapEnd.lowerBound]
  #expect(!operations.contains("#if COMMANDER_ACCEPTANCE"))
  #expect(operations.contains("scheduleSync.synchronize("))
  #expect(operations.contains("procedureActivities.reconcile("))
  #expect(app.contains("enabled: CommanderMVPPolicy.createsLiveActivities && configuration.channel == .production && !CommanderDesignPreview.enabled"))
  #expect(app.contains("CommanderAcceptanceSchedule("))
  #expect(app.contains("--acceptance-single"))
  #expect(app.contains("mode == .single ? .singleRenderer : .fullSpaDay"))
  #expect(app.contains("CommanderAcceptanceLaunchMode.current != .cleanup"))
  #expect(app.contains("configuration.channel == .production && acceptanceWatchDeliveryEnabled ? watchConnectivity : nil"))
  #expect(app.contains("summary?.readbackCoverage.isComplete == true"))
  #expect(app.contains("watchConnectivity.verifiedProjectionIdentity() == expected"))
  let coordinator = try source("LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift")
  #expect(!coordinator.contains("#if COMMANDER_ACCEPTANCE"))
  #expect(coordinator.contains("guard enabled && CommanderMVPPolicy.createsLiveActivities else"))
  #expect(!coordinator.contains("prepareAcceptanceProbe"))
  for path in ["LazenskyCommanderApp/IPhoneWatchConnectivityCoordinator.swift",
               "LazenskyCommanderWatchApp/WatchConnectivityReceiver.swift",
               "LazenskyCommanderWatchApp/WatchCommanderModel.swift",
               "LazenskyCommanderWatchApp/WatchCommanderView.swift"] {
    let text = try source(path)
    #expect(!text.contains("#if COMMANDER_ACCEPTANCE"))
    #expect(!text.contains("WatchAcceptanceProbe"))
  }
  let receiver = try source("LazenskyCommanderWatchApp/WatchConnectivityReceiver.swift")
  #expect(receiver.contains("try await model.receive(snapshot)"))
  #expect(receiver.contains("if let identity = model.projectionIdentity"))
  let watch = try source("LazenskyCommanderWatchApp/WatchCommanderModel.swift")
  #expect(watch.contains("try await cache.acceptAndLoad(incoming)"))
  #expect(watch.contains("let cached = try await cache.load()"))
  #expect(watch.contains("!WatchScheduleExpiryPolicy.isExpired(cached.schedule"))
  #expect(watch.contains("WidgetCenter.shared.reloadAllTimelines"))
  let widget = try source("LazenskyCommanderWatchWidget/LazenskyCommanderWatchWidget.swift")
  #expect(widget.contains("let cache = WatchCacheLocation.makeCache()"))
  #expect(widget.contains("try? await cache.load()"))
  #expect(widget.contains("CommanderWatchWidgetContract.timelineHorizon"))
  let settings = try source("LazenskyCommanderApp/CommanderSettingsView.swift")
  #expect(settings.contains("title: \"Diagnostika\""))
  #expect(!settings.contains("#if DEBUG"))
  let service = try String(contentsOf: repo.appendingPathComponent("Otestovat Lázeňský Commander.command"), encoding: .utf8)
  #expect(service.contains("-DCOMMANDER_ACCEPTANCE_FIXTURES"))
  #expect(!service.contains("-DCOMMANDER_ACCEPTANCE_ONLY"))
  #expect(!service.contains("nezvoní"))
}

@Test func failedDebugDylibExperimentIsNotLeftInProject() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let project = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj/project.pbxproj"),
    encoding: .utf8
  )
  #expect(!project.contains("ENABLE_DEBUG_DYLIB = NO;"))
}

@Test func injectedFixtureTraversesAlarmSyncWatchTransportDiskCacheAndProjection() async throws {
  let now = try date("08:00")
  let source = try CommanderAcceptanceSchedule(now: now)
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let watch = CachedAcceptanceDelivery(directory: directory)
  let adapter = ConsolidationAlarmAdapter()
  let alarms = InMemoryAlarmStateStore()
  let snapshots = InMemoryScheduleSnapshotStore()
  func coordinator(_ source: CommanderAcceptanceSchedule) -> CommanderScheduleSyncCoordinator {
    CommanderScheduleSyncCoordinator(
      scheduleService: source,
      alarmSyncService: AlarmSyncService(scheduleService: source, store: alarms, adapter: adapter),
      scheduleStore: snapshots, watchDelivery: watch, clock: { now }
    )
  }
  let result = try await coordinator(source).synchronize()
  #expect(result.alarmSummary.succeeded)
  #expect(result.alarmSummary.desiredAlarmCount == 4)
  #expect(result.watchDeliveryStatus == .verified)
  // A new cache instance is what the widget and a relaunched Watch actually read.
  let persisted = try #require(try await FileWatchScheduleCache(directoryURL: directory).load())
  #expect(persisted == result.watchSnapshot)
  let projected = try CommanderScheduleProjection(schedule: persisted.schedule, overrides: persisted.leadTimeOverrides)
  #expect(await adapter.scheduledAlarms() == projected.payload.alarms.sorted { $0.stableId < $1.stableId })
  let plans = CommanderLiveActivityPlan.makeWindows(schedule: result.schedule, payload: projected.payload, now: now)
  #expect(!plans.isEmpty)
  for minute in [0, 4, 5, 6, 9, 10, 12, 14, 16, 19, 21, 24] {
    let instant = now.addingTimeInterval(Double(minute * 60))
    let phone = CommanderDashboardPresentation.make(schedule: result.schedule, now: instant).liveState
    #expect(phone == projected.liveState(at: instant))
  }
  // Local preference edits also take the same cached projection route.
  let changed = try await coordinator(source).synchronize(source: .cached,
    overrides: LeadTimeOverrides(eventOverrides: [source.schedule.events[0].stableId: 3]), projectionRevision: 1)
  #expect(changed.watchDeliveryStatus == .verified)
  #expect(try await FileWatchScheduleCache(directoryURL: directory).load() == changed.watchSnapshot)
  let cleanup = try CommanderAcceptanceSchedule(now: now, previousVersion: source.schedule.scheduleVersion, cleanup: true)
  let cleared = try await coordinator(cleanup).synchronize()
  #expect(cleared.alarmSummary.succeeded)
  #expect(cleared.alarmSummary.desiredAlarmCount == 0)
  #expect(await adapter.scheduledAlarms().isEmpty)
  #expect(cleared.watchDeliveryStatus == .verified)
  #expect(try await FileWatchScheduleCache(directoryURL: directory).load()?.schedule.events.isEmpty == true)
}

@Test func cleanupFixtureIsMonotonicAndWorksAcrossMidnight() throws {
  let now = try date("23:59")
  #expect(throws: PhysicalAcceptanceError.self) { try CommanderAcceptanceSchedule(now: now) }
  let cleanup = try CommanderAcceptanceSchedule(now: now, previousVersion: 9_000_000_000_000, cleanup: true)
  #expect(cleanup.schedule.events.isEmpty)
  #expect(cleanup.schedule.scheduleVersion == 9_000_000_000_001)
}

private actor CachedAcceptanceDelivery: WatchScheduleSnapshotDelivering {
  let cache: FileWatchScheduleCache
  init(directory: URL) { cache = FileWatchScheduleCache(directoryURL: directory) }
  func deliver(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleDeliveryDisposition {
    let encoded = try WatchScheduleTransportCodec.encode(snapshot)
    _ = try await cache.accept(WatchScheduleTransportCodec.decode(encoded))
    return .sent
  }
  func verifiedScheduleVersion() async -> Int? { try? await cache.load()?.schedule.scheduleVersion }
  func verifiedProjectionIdentity() async -> WatchScheduleProjectionIdentity? { try? await cache.load()?.projectionIdentity }
}

private actor ConsolidationAlarmAdapter: AlarmAdapting {
  private var alarms: [String: NativeAlarm] = [:]
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = platformAlarmID ?? PlatformAlarmIdentifier.newPersistedValue()
    alarms[id] = alarm
    return id
  }
  func cancel(platformAlarmID: String) { alarms.removeValue(forKey: platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(alarms.keys) }
  func scheduledAlarms() -> [NativeAlarm] { alarms.values.sorted { $0.stableId < $1.stableId } }
}

@Test func replayedFixtureCannotPoisonProductionWatchCacheAfterRestoringNormalBuild() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let cache = FileWatchScheduleCache(directoryURL: directory, dataset: .production)
  let acceptance = try CommanderAcceptanceSchedule(now: date("08:00"))
  let replayed = try WatchScheduleTransportCodec.decode(WatchScheduleTransportCodec.encode(
    WatchScheduleSnapshot(schedule: acceptance.schedule)
  ))
  #expect(try await cache.accept(replayed) == .rejectedInvalid)
  #expect(try await cache.load() == nil)
  let normal = WatchScheduleSnapshot(schedule: fixture())
  #expect(try await cache.accept(normal) == .stored)
  #expect(try await cache.load() == normal)
  let acceptanceCache = FileWatchScheduleCache(directoryURL: directory.appendingPathComponent("acceptance"), dataset: .acceptance)
  #expect(try await acceptanceCache.accept(normal) == .rejectedInvalid)
  #expect(try await acceptanceCache.accept(replayed) == .stored)
}


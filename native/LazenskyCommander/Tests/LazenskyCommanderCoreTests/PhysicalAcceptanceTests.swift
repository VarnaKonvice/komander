#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func physicalRunGeneratesAcceleratedSpaDayWithFourCanonicalAlarms() throws {
  let run = try acceptanceRun()
  let payload = try run.payload()
  #expect(payload.alarms.count == 4)
  #expect(payload.alarms.map(\.kind) == [.meal, .procedure, .procedure, .meal])
  #expect(run.schedule.events.map(\.title) == [
    "TEST – Snídaně", "TEST – Magnetoterapie", "TEST – Rehabilitace", "TEST – Večeře"
  ])
  #expect(payload.alarms.map(\.effectiveLeadTimeMinutes) == [1, 3, 2, 2])
  try NativeAlarmContract.validateCanonical(run.schedule)

  let leaveDates = try payload.alarms.map { try NativeAlarmContract.date(fromLocalISO: $0.leaveAt) }
  #expect(zip(leaveDates, leaveDates.dropFirst()).allSatisfy { $0 < $1 })
  #expect((240...330).contains(leaveDates[0].timeIntervalSince(run.now)))
  #expect((360...450).contains(leaveDates[1].timeIntervalSince(run.now)))
  #expect((720...810).contains(leaveDates[2].timeIntervalSince(run.now)))
  #expect((1140...1230).contains(leaveDates[3].timeIntervalSince(run.now)))

  let breakfastStart = try NativeAlarmContract.date(fromLocalISO: payload.alarms[0].startAt)
  let breakfastEnd = try NativeAlarmContract.date(fromLocalISO: payload.alarms[0].endAt)
  let magnetLeave = leaveDates[1]
  #expect(breakfastStart < magnetLeave && magnetLeave < breakfastEnd)

  let rehabEnd = try NativeAlarmContract.date(fromLocalISO: payload.alarms[2].endAt)
  let dinnerStart = try NativeAlarmContract.date(fromLocalISO: payload.alarms[3].startAt)
  #expect(dinnerStart.timeIntervalSince(rehabEnd) == 5 * 60)
}

@Test func acceleratedSpaDayPlannerAndTimelineTellOneConsistentStory() throws {
  let run = try acceptanceRun()
  let payload = try run.payload()
  let ids = run.schedule.events.map(\.stableId)

  let plans = CommanderLiveActivityPlan.makeWindows(
    schedule: run.schedule,
    payload: payload,
    now: run.now,
    contextLeadTime: 3 * 60,
    maximumIdleGap: 3 * 60,
    maximumActiveLifetime: 30 * 60,
    maximumEvents: 6,
    maximumWindows: 3
  )

  #expect(plans.count == 2)
  #expect(plans[0].includedStableIDs == Array(ids.prefix(3)))
  #expect(plans[1].includedStableIDs == [ids[3]])
  #expect(plans[0].windowEnd <= plans[1].activationStart)

  let firstWindowEvents = try payload.alarms.prefix(3).map {
    CommanderLiveActivityTimelineEvent(
      stableId: $0.stableId,
      leaveAt: try NativeAlarmContract.date(fromLocalISO: $0.leaveAt),
      startAt: try NativeAlarmContract.date(fromLocalISO: $0.startAt),
      endAt: try NativeAlarmContract.date(fromLocalISO: $0.endAt)
    )
  }

  let breakfast = payload.alarms[0]
  let magnet = payload.alarms[1]
  let rehab = payload.alarms[2]
  let magnetLeave = try NativeAlarmContract.date(fromLocalISO: magnet.leaveAt)
  let magnetStart = try NativeAlarmContract.date(fromLocalISO: magnet.startAt)
  let rehabStart = try NativeAlarmContract.date(fromLocalISO: rehab.startAt)

  let beforeMagnetLeave = try #require(CommanderLiveActivityTimeline.resolve(
    events: firstWindowEvents,
    at: magnetLeave.addingTimeInterval(-1)
  ))
  #expect(beforeMagnetLeave.primaryStableId == breakfast.stableId)
  #expect(beforeMagnetLeave.phase == .active)

  let magnetDeparture = try #require(CommanderLiveActivityTimeline.resolve(
    events: firstWindowEvents,
    at: magnetLeave
  ))
  #expect(magnetDeparture.primaryStableId == magnet.stableId)
  #expect(magnetDeparture.phase == .upcoming)
  #expect(magnetDeparture.departureDue)
  #expect(magnetDeparture.countdownTarget == magnetStart)

  let magnetRunning = try #require(CommanderLiveActivityTimeline.resolve(
    events: firstWindowEvents,
    at: magnetStart
  ))
  #expect(magnetRunning.primaryStableId == magnet.stableId)
  #expect(magnetRunning.phase == .active)

  let rehabRunning = try #require(CommanderLiveActivityTimeline.resolve(
    events: firstWindowEvents,
    at: rehabStart
  ))
  #expect(rehabRunning.primaryStableId == rehab.stableId)
  #expect(rehabRunning.phase == .active)
}

@Test func singleRendererPhysicalScenarioHasOneAlertOnlyAlarmAndOneCommanderWindow() throws {
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-27T10:00:00")
  let run = try PhysicalAcceptanceRun(now: now, scenario: .singleRenderer)
  let payload = try run.payload()

  #expect(run.scenario == .singleRenderer)
  #expect(run.schedule.events.count == 1)
  #expect(payload.alarms.count == 1)

  let alarm = try #require(payload.alarms.first)
  #expect(alarm.title == "TEST – Magnetoterapie")
  #expect(alarm.effectiveLeadTimeMinutes == 2)

  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
  let startAt = try NativeAlarmContract.date(fromLocalISO: alarm.startAt)
  let endAt = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
  #expect(startAt.timeIntervalSince(leaveAt) == 2 * 60)
  #expect(endAt.timeIntervalSince(startAt) == 3 * 60)

  let plans = CommanderLiveActivityPlan.makeWindows(
    schedule: run.schedule,
    payload: payload,
    now: run.now,
    contextLeadTime: 5 * 60,
    maximumIdleGap: 3 * 60,
    maximumActiveLifetime: 15 * 60,
    maximumEvents: 6,
    maximumWindows: 1
  )
  #expect(plans.count == 1)
  #expect(plans[0].includedStableIDs == [alarm.stableId])
  #expect(plans[0].activationStart < leaveAt)
  #expect(leaveAt.timeIntervalSince(plans[0].activationStart) == 3 * 60)
}

@Test func localPhysicalTestDoesNotCrossCanonicalMidnightBoundary() throws {
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-30T23:58:00")
  #expect(throws: PhysicalAcceptanceError.self) { try PhysicalAcceptanceRun(now: now) }
}

@Test func leadTimeProvenanceDistinguishesEqualValuedOverrides() throws {
  let run = try acceptanceRun()
  let meal = run.schedule.events[0]
  let procedure = run.schedule.events[1]
  #expect(try NativeAlarmContract.resolvedLeadTime(event: meal, schedule: run.schedule).source == .eventOverride)
  #expect(try NativeAlarmContract.resolvedLeadTime(event: procedure, schedule: run.schedule).source == .eventOverride)
  for (overrides, source) in [
    (LeadTimeOverrides(defaultLeadTimeMinutes: 1), LeadTimeSource.localDefault),
    (LeadTimeOverrides(defaultLeadTimeMinutes: 1, mealOverrides: ["Snídaně": 1]), .localTypeOverride),
    (LeadTimeOverrides(defaultLeadTimeMinutes: 1, mealOverrides: ["Snídaně": 1], eventOverrides: [meal.stableId: 1]), .localEventOverride)
  ] {
    let resolution = try NativeAlarmContract.resolvedLeadTime(event: meal, schedule: run.schedule, overrides: overrides)
    #expect(resolution.minutes == 1 && resolution.source == source)
    #expect(try NativeAlarmContract.effectiveLeadTime(event: meal, schedule: run.schedule, overrides: overrides) == resolution.minutes)
  }
}

@Test func physicalSessionIgnoresPersistentPreferencesAndLeavesProductionStateUntouched() async throws {
  let suite = PhysicalAcceptanceRun.storageSuite + ".test." + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  for channel in ["production", "e2e"] {
    for name in ["scheduleSnapshot", "leadTimePreferences", "managedAlarms"] {
      defaults.set(Data("{\"defaultLeadTimeMinutes\":99}".utf8), forKey: "lazensky.commander.\(name).\(channel).v1")
    }
  }
  defaults.set(["production-alarm"], forKey: "lazensky.commander.alarmkitOwned.e2e.v1")
  let before = defaults.persistentDomain(forName: suite)! as NSDictionary
  let run = try acceptanceRun()
  let adapter = AcceptanceTestAdapter(now: run.now)
  let session = PhysicalAcceptanceSession(run: run, adapter: adapter)
  let result = try await session.synchronize(now: run.now)
  #expect(result.succeeded)
  #expect(result.schedule == run.schedule)
  #expect(result.watchDeliveryStatus == .notConfigured)
  #expect(await adapter.revision() == 1)
  #expect(Set(await session.alarmStore.load().records.values.map { $0.alarm.effectiveLeadTimeMinutes }) == [1, 2, 3])
  #expect(run.overrides == LeadTimeOverrides())
  #expect((defaults.persistentDomain(forName: suite)! as NSDictionary) == before)
}

@Test func successivePhysicalRunsHaveIndependentSnapshotManagedStateAndOwnership() async throws {
  let first = try acceptanceRun()
  let next = try PhysicalAcceptanceRun(now: first.now.addingTimeInterval(60))
  #expect(first.namespace != next.namespace)
  #expect(Set(first.schedule.events.map(\.stableId)).isDisjoint(with: next.schedule.events.map(\.stableId)))
  let a = PhysicalAcceptanceSession(run: first, adapter: AcceptanceTestAdapter(now: first.now))
  let b = PhysicalAcceptanceSession(run: next, adapter: AcceptanceTestAdapter(now: next.now))
  let resultA = try await a.synchronize(now: first.now)
  #expect(resultA.succeeded)
  #expect(await b.alarmStore.load().records.isEmpty)
  #expect(await b.scheduleStore.load() == nil)
  let resultB = try await b.synchronize(now: next.now)
  #expect(resultB.succeeded)
  #expect(await a.scheduleStore.load() == first.schedule)
  #expect(await b.scheduleStore.load() == next.schedule)
  let suite = PhysicalAcceptanceRun.storageSuite + ".test." + UUID().uuidString
  defer { UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite) }
  let ledger = PhysicalAcceptanceOwnershipStore(suiteName: suite)
  await ledger.remember("first-ID", runID: first.id)
  await ledger.remember("next-ID", runID: next.id)
  #expect(await ledger.ids(runID: first.id) == ["first-ID"])
  #expect(await ledger.ids(runID: next.id) == ["next-ID"])
  let reopened = PhysicalAcceptanceOwnershipStore(suiteName: suite)
  #expect(await reopened.allIDs() == ["first-ID", "next-ID"])
  await ledger.forget("first-ID")
  #expect(await ledger.ids(runID: next.id) == ["next-ID"])
}

@Test func physicalCleanupOnlyCancelsExplicitlyOwnedIDsAndFlagsUnknownAlarms() {
  let plan = PhysicalAcceptanceCleanupPlan(ownedIDs: ["owned", "reserved-but-not-created"], platformIDs: ["owned", "foreign"])
  #expect(plan.cancelIDs == ["owned"])
  #expect(plan.unknownIDs == ["foreign"])
}

@Test func physicalPreflightRequiresFourMatchingAlertOnlyAlarmRecords() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let state = await session.alarmStore.load()
  let readings = await adapter.readings()
  let check = try acceptanceCheck(run, readings, state)
  #expect(check.ready && check.expectedAlarmCount == 4 && check.verifiedAlarmCount == 4)
  #expect(check.rows[0].leadTime.source == .eventOverride)
  #expect(check.rows[1].leadTime.source == .eventOverride)

  let payload = try run.payload()
  for alarm in payload.alarms {
    let reading = try #require(readings.first { $0.stableID == alarm.stableId })
    let expected = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    #expect(reading.preAlert == nil)
    #expect(reading.postAlert == nil)
    #expect(reading.scheduleKind == "fixed")
    #expect(reading.state == "scheduled")
    #expect(reading.fixedScheduleAt.map { abs($0.timeIntervalSince(expected)) <= 1 } == true)
  }

  #expect(try !acceptanceCheck(run, [readings[0]], state).ready)
  #expect(try !acceptanceCheck(run, [readings[0], readings[0]], state).ready)
  #expect(try !acceptanceCheck(run, readings + [readings[1]], state).ready)
  #expect(try !acceptanceCheck(run, readings, ManagedAlarmState()).ready)
}

@Test func physicalPreflightRejectsLegacyCountdownShapedAlarm() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let first = try #require(readings.first { $0.stableID == run.schedule.events[0].stableId })
  let brokenFirst = PhysicalAlarmObservation(
    platformID: first.platformID,
    stableID: first.stableID,
    configuredAt: first.configuredAt,
    scheduleKind: "fixed",
    fixedScheduleAt: first.fixedScheduleAt,
    preAlert: 60,
    postAlert: nil,
    state: "scheduled",
    fireDate: nil
  )
  let brokenReadings = readings.map { $0.platformID == first.platformID ? brokenFirst : $0 }
  let check = try await acceptanceCheck(run, brokenReadings, session.alarmStore.load())
  #expect(!check.ready && check.verifiedAlarmCount == 3)
  #expect(check.rows[0].issues.contains("Alert-only alarm nemá mít preAlert."))
}

@Test func physicalPreflightAcceptsOnlyAlertOnlyAlarmsWhenCommanderWindowsArePrepared() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let check = try await acceptanceCheck(run, readings, session.alarmStore.load())
  #expect(check.ready)
  #expect(check.rows.allSatisfy {
    $0.actual?.preAlert == nil &&
    $0.actual?.postAlert == nil &&
    $0.actual?.scheduleKind == "fixed" &&
    $0.actual?.state == "scheduled"
  })
}

@Test func physicalPreflightRejectsCountdownStatePreAlertAndWrongFixedEndpoint() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let first = try #require(readings.first { $0.stableID == run.schedule.events[0].stableId })

  let wrongCases: [PhysicalAlarmObservation] = [
    PhysicalAlarmObservation(
      platformID: first.platformID, stableID: first.stableID, configuredAt: first.configuredAt,
      scheduleKind: "fixed", fixedScheduleAt: first.fixedScheduleAt, preAlert: 60,
      postAlert: nil, state: "scheduled", fireDate: nil
    ),
    PhysicalAlarmObservation(
      platformID: first.platformID, stableID: first.stableID, configuredAt: first.configuredAt,
      scheduleKind: "none", fixedScheduleAt: nil, preAlert: nil,
      postAlert: nil, state: "countdown", fireDate: nil
    ),
    PhysicalAlarmObservation(
      platformID: first.platformID, stableID: first.stableID, configuredAt: first.configuredAt,
      scheduleKind: "fixed", fixedScheduleAt: first.fixedScheduleAt?.addingTimeInterval(60), preAlert: nil,
      postAlert: nil, state: "scheduled", fireDate: nil
    )
  ]

  for bad in wrongCases {
    let badReadings = readings.map { $0.platformID == first.platformID ? bad : $0 }
    let check = try await acceptanceCheck(run, badReadings, session.alarmStore.load())
    #expect(!check.ready && check.verifiedAlarmCount == 3)
  }
}

@Test func physicalPreflightRequiresAlarmAndScheduledCommanderReadiness() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings(), state = await session.alarmStore.load()
  let payload = try run.payload()
  let lastMoment = try NativeAlarmContract.date(fromLocalISO: payload.alarms[0].leaveAt).addingTimeInterval(-59)
  let late = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: true, procedureActivityPrepared: true, now: lastMoment)
  let missingActivity = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: true, procedureActivityPrepared: false, now: run.now)
  let unverified = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: false, procedureActivityPrepared: true, now: run.now)
  #expect(!late.ready)
  #expect(!missingActivity.ready)
  #expect(missingActivity.issues.contains("Commander Live Activity zatím není naplánovaná ani aktivní."))
  #expect(!unverified.ready)
}

@Test func physicalAppHasNoProductionModelNetworkPreferencesOrWatchEntryPoint() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"), encoding: .utf8)
  for forbidden in ["CommanderViewModel(", "URLSession", "UserDefaults.standard", "LeadTimePreferencesStore", "IPhoneWatchConnectivityCoordinator", "countdown(id:"] {
    #expect(!source.contains(forbidden))
  }
  #expect(source.contains("CommanderSynchronizationRequestQueue"))
  #expect(source.contains("AlarmManager.shared.alarmUpdates"))
  #expect(source.contains("--single-renderer-probe"))
  #expect(source.contains("startSingleRendererProbe()"))
  #expect(source.contains("case .singleRenderer:"))
  #expect(source.contains("maximumScheduledActivities: 1"))
  #expect(source.contains("Commander odpočet → AlarmKit v odchodu → Zastavit → Commander pokračuje"))

  let adapter = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  let coordinator = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"), encoding: .utf8)
  #expect(adapter.contains("guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID"))
  #expect(adapter.contains("for alarm in alarms where cleanup.cancelIDs.contains(alarm.id.uuidString)"))
  #expect(!adapter.contains("maximumCommanderActivities"))
  #expect(!adapter.contains("hasVerifiedFreeTimeHandoff"))
  #expect(!adapter.contains("phase: .departureStandby"))
  #expect(adapter.contains("presentation: AlarmPresentation(alert: alert)"))
  #expect(!adapter.contains("presentation: AlarmPresentation(alert: alert, countdown: countdown)"))
  #expect(!adapter.contains("countdownDuration: Alarm.CountdownDuration("))
  #expect(!adapter.contains("Activity<AlarmAttributes<CommanderAlarmMetadata>>.request"))
  #expect(!adapter.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(coordinator.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(coordinator.contains("maximumActiveActivities = 1"))
  #expect(coordinator.contains("maximumScheduledActivities = CommanderLiveActivityPlan.defaultMaximumScheduledWindows"))
  #expect(coordinator.contains("CommanderProcedureLiveActivityPolicy.maximumQueuedEvents"))
  #expect(coordinator.contains("CommanderLiveActivityPlan.makeWindows("))
  #expect(coordinator.contains("start: plan.activationStart"))
  #expect(coordinator.contains("var keepers: [String: Activity<CommanderProcedureLiveActivityAttributes>]"))
  #expect(coordinator.contains("if keepers[stableID] == nil"))
  #expect(coordinator.contains("alertConfiguration: alert"))
  #expect(coordinator.contains("CommanderSilentAlert.wav"))
  let stopStart = try #require(adapter.range(of: "struct CommanderAlarmStopIntent"))
  let actorStart = try #require(adapter.range(of: "actor AlarmKitAdapter"))
  let stopIntent = String(adapter[stopStart.lowerBound..<actorStart.lowerBound])
  #expect(stopIntent.contains("activityPayload"))
  #expect(stopIntent.contains("Activity<CommanderProcedureLiveActivityAttributes>.activities"))
  #expect(stopIntent.contains("presentationMode: .eventContext"))
  #expect(stopIntent.contains("ActivityKit.AlertConfiguration("))
  #expect(stopIntent.contains("sound: .named(\"CommanderSilentAlert.wav\")"))
  #expect(stopIntent.contains("alertConfiguration: watchAlert"))
  #expect(stopIntent.contains("bez Activity.request"))
  #expect(!stopIntent.contains(".request("))
  #expect(stopIntent.contains("return .result()"))
  #expect(adapter.range(of: "await physicalOwnership.remember(id.uuidString, runID: physicalRunID)")!.lowerBound < adapter.range(of: "let scheduled = try await AlarmManager.shared.schedule")!.lowerBound)

  let live = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"), encoding: .utf8)
  #expect(live.contains("CommanderCompactBrandEventMark"))
  #expect(live.contains("CommanderProcedureIslandTiming(context: context, size: .minimal)"))
  #expect(!live.contains("ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self)"))
  #expect(!live.contains("LazenskyCommanderAlarmLiveActivity"))
  #expect(!live.contains("isDepartureBridge"))
}

@Test func physicalXcodeTargetsShareRealExtensionSourcesButNoProductionEntryOrWatchDependency() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let url = repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj/project.pbxproj")
  let project = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
  let objects = try #require(project["objects"] as? [String: [String: Any]])
  func target(_ name: String) throws -> [String: Any] {
    try #require(objects.values.first { ($0["isa"] as? String) == "PBXNativeTarget" && ($0["name"] as? String) == name })
  }
  func files(_ target: [String: Any], phase: String) throws -> Set<String> {
    let phases = try #require(target["buildPhases"] as? [String])
    let object = try #require(phases.compactMap { objects[$0] }.first { ($0["isa"] as? String) == phase })
    let buildFiles = try #require(object["files"] as? [String])
    return Set(buildFiles.compactMap { objects[$0]?["fileRef"] as? String })
  }
  let app = try target("LazenskyCommanderPhysicalAcceptance")
  let ext = try target("LazenskyCommanderPhysicalLiveActivity")
  let productionExtension = try target("LazenskyCommanderLiveActivity")
  #expect(try files(ext, phase: "PBXSourcesBuildPhase") == files(productionExtension, phase: "PBXSourcesBuildPhase"))
  #expect(try files(ext, phase: "PBXResourcesBuildPhase") == files(productionExtension, phase: "PBXResourcesBuildPhase"))
  let appPaths = try files(app, phase: "PBXSourcesBuildPhase").compactMap { objects[$0]?["path"] as? String }
  #expect(Set(appPaths) == ["PhysicalAcceptanceApp.swift", "AlarmKitAdapter.swift", "CommanderProcedureLiveActivityCoordinator.swift", "CommanderVisualAssets.swift", "CommanderAlarmMetadata.swift", "CommanderBrandAssets.swift"])
  let deps = try #require(app["dependencies"] as? [String])
  #expect(deps.count == 1)
  let targetID = try #require(objects[deps[0]]?["target"] as? String)
  #expect(objects[targetID]?["name"] as? String == "LazenskyCommanderPhysicalLiveActivity")
  for (target, bundleID) in [(app, PhysicalAcceptanceRun.bundleID), (ext, PhysicalAcceptanceRun.bundleID + ".liveactivity")] {
    let listID = try #require(target["buildConfigurationList"] as? String)
    for configID in try #require(objects[listID]?["buildConfigurations"] as? [String]) {
      let settings = try #require(objects[configID]?["buildSettings"] as? [String: Any])
      #expect(settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String == bundleID)
      #expect(settings["CODE_SIGN_ENTITLEMENTS"] == nil)
    }
  }
}

private func acceptanceRun() throws -> PhysicalAcceptanceRun {
  try PhysicalAcceptanceRun(now: NativeAlarmContract.date(fromLocalISO: "2026-08-30T11:00:00").addingTimeInterval(17))
}

private func acceptanceSetup() async throws -> (PhysicalAcceptanceRun, PhysicalAcceptanceSession, AcceptanceTestAdapter) {
  let run = try acceptanceRun()
  let adapter = AcceptanceTestAdapter(now: run.now)
  let session = PhysicalAcceptanceSession(run: run, adapter: adapter)
  let result = try await session.synchronize(now: run.now)
  #expect(result.succeeded)
  return (run, session, adapter)
}

private func acceptanceCheck(_ run: PhysicalAcceptanceRun, _ readings: [PhysicalAlarmObservation], _ state: ManagedAlarmState) throws -> PhysicalAcceptancePreflight {
  try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: true, procedureActivityPrepared: true, now: run.now)
}

private actor AcceptanceTestAdapter: AlarmAdapting {
  let now: Date
  private var context: Schedule?
  private var projectionRevision = 0
  private var observations: [String: PhysicalAlarmObservation] = [:]
  init(now: Date) { self.now = now }
  func prepare(schedule: Schedule, projectionRevision: Int) { context = schedule; self.projectionRevision = projectionRevision }
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    _ = try #require(context)
    let alertAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let id = UUID().uuidString
    observations[id] = PhysicalAlarmObservation(
      platformID: id,
      stableID: alarm.stableId,
      configuredAt: now,
      scheduleKind: "fixed",
      fixedScheduleAt: alertAt,
      preAlert: nil,
      postAlert: nil,
      state: "scheduled",
      fireDate: nil
    )
    return id
  }
  func cancel(platformAlarmID: String) { observations.removeValue(forKey: platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(observations.keys) }
  func existingPlatformFixedAlertDates() -> [String: Date]? {
    observations.compactMapValues { AlarmCountdown.effectiveAlertDate(fixedScheduleAt: $0.fixedScheduleAt, preAlert: $0.preAlert, countdownFireDate: $0.fireDate) }
  }
  func readings() -> [PhysicalAlarmObservation] { observations.values.sorted { ($0.stableID ?? "") < ($1.stableID ?? "") } }
  func revision() -> Int { projectionRevision }

}
#endif
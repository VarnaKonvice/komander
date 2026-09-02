#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func physicalRunGeneratesValidLocalMealAndProcedureWithinQuarterHour() throws {
  let run = try acceptanceRun()
  let payload = try run.payload()
  #expect(payload.alarms.count == 2)
  #expect(payload.alarms.map(\.kind) == [.meal, .procedure])
  try NativeAlarmContract.validateCanonical(run.schedule)
  let first = try NativeAlarmContract.date(fromLocalISO: payload.alarms[0].leaveAt)
  let second = try NativeAlarmContract.date(fromLocalISO: payload.alarms[1].leaveAt)
  let procedureStart = try NativeAlarmContract.date(fromLocalISO: payload.alarms[1].startAt)
  #expect((240...300).contains(first.timeIntervalSince(run.now)))
  #expect((660...720).contains(second.timeIntervalSince(run.now)))
  #expect(procedureStart.timeIntervalSince(run.now) <= 840)
  let immediate = try AlarmCountdown.plan(for: payload.alarms[0], in: run.schedule, now: run.now)
  let scheduled = try AlarmCountdown.plan(for: payload.alarms[1], in: run.schedule, now: run.now)
  #expect(immediate.scheduledStartAt == nil)
  #expect(run.now.addingTimeInterval(immediate.countdownWindow) == first)
  #expect(scheduled.countdownWindow == 180)
  #expect(scheduled.scheduledStartAt?.addingTimeInterval(180) == second)
  #expect(scheduled.scheduledStartAt == (try NativeAlarmContract.dateTime(date: run.schedule.events[0].date, time: run.schedule.events[0].end)))
}

@Test func localPhysicalTestDoesNotCrossCanonicalMidnightBoundary() throws {
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-30T23:58:00")
  #expect(throws: PhysicalAcceptanceError.self) { try PhysicalAcceptanceRun(now: now) }
}

@Test func leadTimeProvenanceDistinguishesEqualValuedOverrides() throws {
  let run = try acceptanceRun()
  let meal = run.schedule.events[0]
  let procedure = run.schedule.events[1]
  #expect(try NativeAlarmContract.resolvedLeadTime(event: meal, schedule: run.schedule).source == .scheduleTypeOverride)
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
  #expect(await session.alarmStore.load().records.values.allSatisfy { $0.alarm.effectiveLeadTimeMinutes == 2 })
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

@Test func physicalPreflightRequiresTwoMatchingActualAlarmRecords() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let state = await session.alarmStore.load()
  let readings = await adapter.readings()
  let check = try acceptanceCheck(run, readings, state)
  #expect(check.ready && check.expectedAlarmCount == 2 && check.verifiedAlarmCount == 2)
  #expect(check.rows[0].leadTime.source == .scheduleTypeOverride)
  #expect(check.rows[1].leadTime.source == .eventOverride)
  let first = try #require(readings.first { $0.state == "countdown" })
  let second = try #require(readings.first { $0.stableID == run.schedule.events[1].stableId })
  let secondPlan = try AlarmCountdown.plan(for: run.payload().alarms[1], in: run.schedule, now: run.now)
  #expect(first.preAlert != nil)
  #expect(second.preAlert == nil)
  #expect(second.scheduleKind == "fixed")
  #expect(second.fixedScheduleAt.map { abs($0.timeIntervalSince(secondPlan.scheduledAlertAt)) <= 1 } == true)
  #expect(try !acceptanceCheck(run, [readings[0]], state).ready)
  #expect(try !acceptanceCheck(run, [readings[0], readings[0]], state).ready)
  #expect(try !acceptanceCheck(run, readings + [readings[1]], state).ready)
  #expect(try !acceptanceCheck(run, readings, ManagedAlarmState()).ready)
}

@Test func physicalPreflightRejectsHistoricalFixedLeaveAtPlusPreAlertRegression() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let first = try #require(readings.first { $0.state == "countdown" })
  let second = try #require(readings.first { $0.stableID == run.schedule.events[1].stableId })
  let firstAlarm = run.payload().alarms[0]
  let brokenFirst = PhysicalAlarmObservation(
    platformID: first.platformID, stableID: first.stableID, configuredAt: first.configuredAt,
    scheduleKind: "fixed", fixedScheduleAt: try NativeAlarmContract.date(fromLocalISO: firstAlarm.leaveAt),
    preAlert: first.preAlert, postAlert: nil, state: "scheduled", fireDate: nil
  )
  let check = try await acceptanceCheck(run, [brokenFirst, second], session.alarmStore.load())
  #expect(!check.ready && check.verifiedAlarmCount == 1)
  #expect(check.rows[0].issues.contains("Výsledný čas alarmu neodpovídá času odchodu."))
}

@Test func physicalPreflightRejectsDuplicatePreAlertWhenPreparedHandoffOwnsFreeTime() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let first = try #require(readings.first { $0.state == "countdown" })
  let second = try #require(readings.first { $0.stableID == run.schedule.events[1].stableId })
  let alarm = run.payload().alarms[1]
  let plan = try AlarmCountdown.plan(for: alarm, in: run.schedule, now: run.now)
  let duplicated = PhysicalAlarmObservation(
    platformID: second.platformID, stableID: second.stableID, configuredAt: second.configuredAt,
    scheduleKind: "fixed", fixedScheduleAt: plan.scheduledStartAt,
    preAlert: plan.countdownWindow, postAlert: nil, state: "scheduled", fireDate: nil
  )
  let check = try await acceptanceCheck(run, [first, duplicated], session.alarmStore.load())
  #expect(!check.ready && check.verifiedAlarmCount == 1)
  #expect(check.rows[1].issues.contains("Alarm po připraveném volnu nemá mít duplicitní systémový předodpočet."))
}

@Test func physicalPreflightRejectsMissingImmediateSystemFireDateOrWrongStateOrDuration() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings()
  let first = try #require(readings.first { $0.state == "countdown" })
  let future = try #require(readings.first { $0.stableID == run.schedule.events[1].stableId })
  for (preAlert, state, fire) in [
    (first.preAlert, "countdown", nil as Date?),
    (first.preAlert, "scheduled", first.fireDate),
    (nil as TimeInterval?, "countdown", first.fireDate),
    (first.preAlert, "countdown", first.fireDate?.addingTimeInterval(60))
  ] {
    let bad = PhysicalAlarmObservation(platformID: first.platformID, stableID: first.stableID, configuredAt: first.configuredAt, scheduleKind: "none", fixedScheduleAt: nil, preAlert: preAlert, postAlert: nil, state: state, fireDate: fire)
    let check = try await acceptanceCheck(run, [bad, future], session.alarmStore.load())
    #expect(!check.ready && check.verifiedAlarmCount == 1)
  }
}

@Test func physicalPreflightNeverClaimsReadyAfterSlowPreparationOrWithoutProcedureActivity() async throws {
  let (run, session, adapter) = try await acceptanceSetup()
  let readings = await adapter.readings(), state = await session.alarmStore.load()
  let lastMoment = try NativeAlarmContract.date(fromLocalISO: run.payload().alarms[0].leaveAt).addingTimeInterval(-59)
  let late = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: true, procedureActivityPrepared: true, now: lastMoment)
  let missingActivity = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: true, procedureActivityPrepared: false, now: run.now)
  let unverified = try PhysicalAcceptancePreflight(run: run, observations: readings, managed: state, syncVerified: false, procedureActivityPrepared: true, now: run.now)
  #expect(!late.ready && !missingActivity.ready && !unverified.ready)
}

@Test func physicalAppHasNoProductionModelNetworkPreferencesOrWatchEntryPoint() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"), encoding: .utf8)
  for forbidden in ["CommanderViewModel(", "URLSession", "UserDefaults.standard", "LeadTimePreferencesStore", "IPhoneWatchConnectivityCoordinator", "countdown(id:"] {
    #expect(!source.contains(forbidden))
  }
  #expect(source.contains("CommanderSynchronizationRequestQueue"))
  #expect(source.contains("AlarmManager.shared.alarmUpdates"))
  #expect(source.contains("VYRAZIT TEĎ"))
  let adapter = try String(contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  #expect(adapter.contains("guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID"))
  #expect(adapter.contains("guard channel == .production || physicalRunID != nil"))
  #expect(adapter.contains("for alarm in alarms where cleanup.cancelIDs.contains(alarm.id.uuidString)"))
  #expect(adapter.contains("if hasPreparedHandoff(for: alarm)"))
  #expect(adapter.contains("activity.attributes.endAt <= leaveAt"))
  #expect(adapter.contains("phase: .departureBridge"))
  #expect(!adapter.contains("Activity<AlarmAttributes<CommanderAlarmMetadata>>.request"))
  #expect(adapter.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(adapter.range(of: "await physicalOwnership.remember(id.uuidString, runID: physicalRunID)")!.lowerBound < adapter.range(of: "let scheduled = try await AlarmManager.shared.schedule")!.lowerBound)
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
  #expect(Set(appPaths) == ["PhysicalAcceptanceApp.swift", "AlarmKitAdapter.swift", "CommanderVisualAssets.swift", "CommanderAlarmMetadata.swift", "CommanderBrandAssets.swift"])
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
    let schedule = try #require(context)
    let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
    let id = UUID().uuidString
    let usesPreparedHandoff = hasPriorHandoffSource(for: alarm, schedule: schedule)
    observations[id] = PhysicalAlarmObservation(
      platformID: id,
      stableID: alarm.stableId,
      configuredAt: now,
      scheduleKind: usesPreparedHandoff ? "fixed" : (plan.scheduledStartAt == nil ? "none" : "fixed"),
      fixedScheduleAt: usesPreparedHandoff ? plan.scheduledAlertAt : plan.scheduledStartAt,
      preAlert: usesPreparedHandoff ? nil : plan.countdownWindow,
      postAlert: nil,
      state: usesPreparedHandoff ? "scheduled" : (plan.scheduledStartAt == nil ? "countdown" : "scheduled"),
      fireDate: usesPreparedHandoff ? nil : (plan.scheduledStartAt == nil ? now.addingTimeInterval(plan.countdownWindow) : nil)
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

  private func hasPriorHandoffSource(for alarm: NativeAlarm, schedule: Schedule) -> Bool {
    guard let event = schedule.events.first(where: { $0.stableId == alarm.stableId }),
          let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    else { return false }
    return schedule.events.contains { candidate in
      guard candidate.stableId != event.stableId,
            candidate.date == event.date,
            let endAt = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.end)
      else { return false }
      return endAt <= leaveAt
    }
  }
}
#endif

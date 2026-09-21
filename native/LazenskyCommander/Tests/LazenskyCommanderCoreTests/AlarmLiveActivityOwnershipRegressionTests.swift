import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func stopIntentNeverCreatesOrMutatesCommanderProcedureActivity() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let adapter = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"),
    encoding: .utf8
  )
  let stopStart = try #require(adapter.range(of: "struct CommanderAlarmStopIntent"))
  let actorStart = try #require(adapter.range(of: "actor AlarmKitAdapter"))
  let stopIntent = String(adapter[stopStart.lowerBound..<actorStart.lowerBound])

  #expect(!stopIntent.contains("CommanderProcedureLiveActivity"))
  #expect(!stopIntent.contains("Activity<"))
  #expect(!stopIntent.contains(".request"))
  #expect(!stopIntent.contains(".update"))
  #expect(!stopIntent.contains(".end("))
  #expect(stopIntent.contains("return .result()"))
}

@Test func alarmKitOwnsDepartureAndCommanderContextStartsAtLeaveAt() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let adapter = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"),
    encoding: .utf8
  )
  let coordinator = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"),
    encoding: .utf8
  )
  let live = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"),
    encoding: .utf8
  )

  #expect(adapter.contains("countdownDuration: Alarm.CountdownDuration("))
  #expect(adapter.contains("preAlert: countdownPlan.countdownWindow"))
  #expect(!adapter.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(!adapter.contains("maximumCommanderActivities"))
  #expect(!adapter.contains("departureBridge"))

  #expect(coordinator.contains("maximumPreparedActivities = 2"))
  #expect(coordinator.contains("start: candidate.leaveAt"))
  #expect(coordinator.contains("nextEvent: candidate.nextEvent"))
  #expect(coordinator.contains("sound: .named(\"CommanderSilentAlert.wav\")"))
  #expect(coordinator.contains("staleDate: candidate.endAt"))

  #expect(live.contains("CommanderAlarmIslandCountdown(mode: context.state.mode, size: .minimal)"))
  #expect(live.contains("CommanderCompactBrandEventMark"))
  #expect(live.contains(".frame(width: timerWidth, alignment: .trailing)"))
  #expect(live.contains(".frame(width: timingWidth, alignment: .trailing)"))
  #expect(live.contains("case .compact: return 54"))
  #expect(live.contains("Text(\"Skončilo\")"))
  #expect(live.contains("TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes)))"))
  #expect(live.contains("CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)"))
  #expect(live.contains("return \"Začíná za\""))
  #expect(live.contains("return kind == .meal ? \"Právě jídlo\" : \"Právě probíhá\""))
  #expect(!live.contains("isDepartureBridge"))
  #expect(!live.contains("runningGreen"))
}

@Test func foregroundReconcilesCommanderActivitiesBeforeSynchronizationThrottle() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift"),
    encoding: .utf8
  )
  let foregroundStart = try #require(app.range(of: "func handleForeground() async"))
  let refreshStart = try #require(app.range(of: "func refreshAccess() async"))
  let foreground = String(app[foregroundStart.lowerBound..<refreshStart.lowerBound])
  let reconcile = try #require(foreground.range(of: "await reconcileProcedureActivitiesFromLatestSchedule()"))
  let throttle = try #require(foreground.range(of: "lastAutomaticAttempt"))
  #expect(reconcile.lowerBound < throttle.lowerBound)
  #expect(foreground.contains("guard let latestSchedule else { return }"))
  #expect(foreground.contains("await procedureActivities.reconcile("))
}

@Test func rollingCommanderActivitiesGiveLaterEventHigherRelevance() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let coordinator = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"),
    encoding: .utf8
  )
  #expect(coordinator.contains("Double(($0.offset + 1) * 100)"))
  #expect(coordinator.contains("relevanceScore: relevanceScores[match.event.stableId] ?? 0"))
  #expect(coordinator.contains("relevanceScore: relevanceScores[candidate.event.stableId] ?? 0"))
  #expect(!coordinator.contains("staleDate: candidate.endAt,\n      relevanceScore: 0"))
}

@Test func physicalReportSeparatesReadySnapshotFromCurrentActivityStateAndKeepsTimeline() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let physical = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"),
    encoding: .utf8
  )
  let shared = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/Shared/CommanderAlarmMetadata.swift"),
    encoding: .utf8
  )
  #expect(physical.contains("readyCommanderStableIDs = preparedCommanderStableIDs"))
  #expect(physical.contains("Commander Activity při READY:"))
  #expect(physical.contains("aktuálně:"))
  #expect(shared.contains("physicalAcceptance.timeline.v2"))
  #expect(shared.contains("stringArray(forKey: timelineKey)"))
}

@Test func multiActivityVisualHarnessReproducesStaleOldVersusNewPriority() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift"),
    encoding: .utf8
  )
  #expect(app.contains("--multi-liveactivity-visual-test"))
  #expect(app.contains("stableId: prefix + \"older-meal\""))
  #expect(app.contains("stableId: prefix + \"newer-procedure\""))
  #expect(app.contains("relevanceScore: 100"))
  #expect(app.contains("relevanceScore: 200"))
}

@Test func physicalAcceptancePrimesLiveActivitiesBeforeTimedRun() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let physical = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"),
    encoding: .utf8
  )
  let start = try #require(physical.range(of: "func start()"))
  let begin = try #require(physical.range(of: "private func beginTimedRun()"))
  let startBody = String(physical[start.lowerBound..<begin.lowerBound])
  #expect(startBody.contains("if !liveActivitiesPrimed"))
  #expect(startBody.contains("prepareOrConfirmLiveActivities()"))
  #expect(startBody.contains("beginTimedRun()"))
  #expect(physical.contains("private actor PhysicalAcceptanceLiveActivityPrimer"))
  #expect(physical.contains("Commander Test – příprava"))
  #expect(physical.contains("try await liveActivityPrimer.prepare()"))
  #expect(physical.contains("guard await liveActivityPrimer.confirmAndClear()"))
  #expect(physical.contains("Potvrdit povolení a spustit test"))
}

@Test func commanderContextHasNoPostStopGapAndStaleFallsForwardToNextEvent() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let coordinator = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"),
    encoding: .utf8
  )
  let live = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"),
    encoding: .utf8
  )
  #expect(coordinator.contains("start: candidate.leaveAt"))
  #expect(coordinator.contains("leaveAt: candidate.leaveAt"))
  #expect(coordinator.contains("nextEvent: candidate.nextEvent"))
  #expect(coordinator.contains("CommanderAlarmEventSnapshot("))
  #expect(live.contains("TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes)))"))
  #expect(live.contains("CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)"))
  #expect(live.contains("guard date >= attributes.endAt"))
  #expect(live.contains("let next = attributes.nextEvent"))
  #expect(live.contains("var dates = [attributes.startAt, attributes.endAt]"))
  #expect(live.contains("CommanderAlarmTime.startDate(from: next.startAt)"))
  #expect(live.contains("CommanderAlarmTime.startDate(from: next.endAt)"))
  #expect(live.components(separatedBy: "TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes)))").count - 1 >= 6)
  #expect(live.contains("return \"Začíná za\""))
  #expect(live.contains("return kind == .meal ? \"Právě jídlo\" : \"Právě probíhá\""))
  #expect(live.contains("return kind == .meal ? \"Jídlo skončilo\" : \"Procedura skončila\""))
  #expect(!live.contains("CommanderProcedureHero"))
  #expect(!live.contains("CommanderProcedureStaticStart"))
  #expect(!live.contains("CommanderProcedureText"))
}

@Test func commanderUsesOverrideAdjustedLeaveAtLikeAlarmKitAndWatch() throws {
  let event = ScheduleEvent(
    stableId: "override-procedure", date: "2026-09-18", start: "14:00", end: "14:30",
    title: "Magnetoterapie", location: "Budova A", kind: .procedure,
    procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil
  )
  let schedule = Schedule(
    schemaVersion: 1, scheduleVersion: 7, updatedAt: "2026-09-18T00:00:00Z",
    stay: [:], events: [event],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:])
  )
  let overrides = LeadTimeOverrides(eventOverrides: [event.stableId: 20])
  let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
  let alarm = try #require(payload.alarms.first)
  #expect(alarm.effectiveLeadTimeMinutes == 20)
  #expect(alarm.leaveAt == "2026-09-18T13:40:00")

  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let coordinator = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"
  ), encoding: .utf8)
  #expect(coordinator.contains("overrides: LeadTimeOverrides? = nil"))
  #expect(coordinator.contains("overrides: overrides"))
}

@Test func commanderReconciliationIsSerializedAndDeduplicatesStableIDs() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let coordinator = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"
  ), encoding: .utf8)
  let app = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift"
  ), encoding: .utf8)

  #expect(coordinator.contains("private var reconciliationTail: Task<Void, Never>?"))
  #expect(coordinator.contains("if let previous { await previous.value }"))
  #expect(coordinator.contains("private func performReconcile("))
  #expect(coordinator.contains("var retainedStableIDs = Set<String>()"))
  #expect(coordinator.contains("retainedStableIDs.insert(activity.attributes.stableId).inserted"))
  #expect(coordinator.contains("Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState)"))
  #expect(!coordinator.contains("let alreadyPrepared = Activity<CommanderProcedureLiveActivityAttributes>.activities.contains"))

  #expect(app.contains("let projectionOverrides = leadTimeOverrides"))
  #expect(app.contains("let projectionRevision = leadTimeProjectionRevision"))
  #expect(app.contains("overrides: projectionOverrides"))
  #expect(app.contains("projectionRevision: projectionRevision"))
}

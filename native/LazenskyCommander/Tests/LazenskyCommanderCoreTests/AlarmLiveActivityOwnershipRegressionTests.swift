import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func stopIntentNeverCreatesCommanderLiveActivityFromBackground() throws {
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

  #expect(stopIntent.contains("static let supportedModes: IntentModes = [.background]"))
  #expect(stopIntent.contains("activityPayload"))
  #expect(stopIntent.contains("Commander Live Activity se nevytváří z backgroundu"))
  #expect(!stopIntent.contains("Activity<CommanderProcedureLiveActivityAttributes>"))
  #expect(!stopIntent.contains(".request("))
  #expect(!stopIntent.contains(".update("))
  #expect(stopIntent.contains("return .result()"))
}

@Test func alarmKitOwnsOnlyDepartureAlertWhileCommanderOwnsVisibleCountdown() throws {
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

  #expect(adapter.contains("AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>.alarm("))
  #expect(adapter.contains("schedule: .fixed(leaveAt)"))
  #expect(adapter.contains("presentation: AlarmPresentation(alert: alert)"))
  #expect(!adapter.contains("countdownDuration: Alarm.CountdownDuration("))
  #expect(!adapter.contains("LocalizedStringResource(stringLiteral: \"Odchod · \\(alarm.title)\")"))
  #expect(!adapter.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(!adapter.contains("CommanderAlarmStopHandoffGate"))
  #expect(coordinator.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(!adapter.contains("maximumCommanderActivities"))
  #expect(!adapter.contains("departureBridge"))

  #expect(coordinator.contains("maximumActiveActivities = 1"))
  #expect(coordinator.contains("maximumScheduledActivities = CommanderLiveActivityPlan.defaultMaximumScheduledWindows"))
  #expect(coordinator.contains("CommanderLiveActivityPlan.makeWindows("))
  #expect(coordinator.contains("for plan in plans"))
  #expect(coordinator.contains("var keepers: [String: Activity<CommanderProcedureLiveActivityAttributes>]"))
  #expect(coordinator.contains("start: plan.activationStart"))
  #expect(coordinator.contains("activationStart: plan.activationStart"))
  #expect(coordinator.contains("leaveAt: anchor.leaveAt"))
  #expect(coordinator.contains("staleDate: plan.windowEnd"))
  #expect(coordinator.contains("CommanderSilentAlert.wav"))
  #expect(adapter.contains("scheduleOverrides = overrides"))
  #expect(adapter.contains("nextEvent: nextEvent"))
  #expect(adapter.contains("nextEventSnapshot(after: alarm"))

  #expect(!live.contains("ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self)"))
  #expect(!live.contains("LazenskyCommanderAlarmLiveActivity"))
  #expect(live.components(separatedBy: "ActivityConfiguration(for:").count - 1 == 1)
  #expect(live.contains("CommanderProcedureIslandTiming(context: context, size: .minimal)"))
  #expect(live.contains("Image(systemName: display.departureDue ? \"figure.walk\" : \"clock.badge\")"))
  #expect(live.contains("return departureDue ? \"Čas vyrazit\" : \"Vyrazit za\""))
  #expect(live.contains("countdownTarget"))
  #expect(live.contains("countdownLabel"))
  #expect(live.contains("CommanderLiveActivityTimeline.resolve("))
  #expect(live.contains("events: events.map(\\.timeline)"))
  #expect(live.contains("CommanderLiveActivityTimeline.boundaryDates(events: events.map(\\.timeline))"))
  #expect(live.contains("nextEventLabel: resolution.nextRelation == .concurrent ? \"Současně:\" : \"Potom:\""))
  #expect(live.contains("case .upcoming: departureDue ? urgentOrange : eventAccent"))
  #expect(live.contains("case .active: eventAccent"))
  #expect(live.contains("Text(\"Skončilo\")"))
  #expect(!live.contains("min(timeline.date, Date())"))
  #expect(live.contains("private struct CommanderClampedCountdown"))
  #expect(live.contains(".currentDate"))
  #expect(live.contains("countingDownIn: interval"))
  #expect(!live.contains("pauseTime: target"))
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

@Test func commanderUsesNonOverlappingScheduledWindowsInsteadOfRelevanceCompetition() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let coordinator = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"),
    encoding: .utf8
  )
  let planner = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommander/Sources/LazenskyCommanderCore/CommanderLiveActivityPlan.swift"),
    encoding: .utf8
  )

  #expect(coordinator.contains("maximumActiveActivities = 1"))
  #expect(coordinator.contains("maximumScheduledActivities = CommanderLiveActivityPlan.defaultMaximumScheduledWindows"))
  #expect(coordinator.contains("CommanderLiveActivityPlan.makeWindows("))
  #expect(coordinator.contains("for plan in plans"))
  #expect(coordinator.contains("let desiredIDs = Set(plans.map(\\.anchorStableID))"))
  #expect(coordinator.contains("if keepers[stableID] == nil"))
  #expect(coordinator.contains("relevanceScore: 1_000"))
  #expect(coordinator.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(coordinator.contains("alertConfiguration: alert"))
  #expect(coordinator.contains("start: plan.activationStart"))
  #expect(coordinator.contains("if keeper.activityState == .pending"))
  #expect(coordinator.contains("let pendingIsFresh ="))
  #expect(coordinator.contains("activity.attributes.activationStart ?? activity.attributes.leaveAt"))
  #expect(coordinator.contains("keeper.content.state.events == expectedState.events"))
  #expect(planner.contains("defaultMaximumIdleGap: TimeInterval = 2 * 60 * 60"))
  #expect(planner.contains("defaultMaximumScheduledWindows = 3"))
  #expect(planner.contains("idleGap > max(0, maximumIdleGap)"))
  #expect(!coordinator.contains("relevanceScores"))
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
  #expect(physical.contains("Commander Live Activity: okna připravena před prvními odchody"))
  #expect(physical.contains("Commander Live Activity okna připravena"))
  #expect(shared.contains("physicalAcceptance.timeline.v2"))
  #expect(shared.contains("stringArray(forKey: timelineKey)"))
}

@Test func productionAppHasNoAlternateCommanderCreationHarness() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift"),
    encoding: .utf8
  )
  #expect(!app.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(!app.contains("AlarmFreeVisual"))
  #expect(!app.contains("CommanderRuntime"))
  #expect(!app.contains("--single-liveactivity-overlap-visual-test"))
  #expect(!app.contains("--alarm-free-visual-test"))
}

@Test func physicalAcceptancePrimesLiveActivitiesBeforeTimedRun() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let physical = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"),
    encoding: .utf8
  )
  let start = try #require(physical.range(of: "private func startScenario(_ scenario: PhysicalAcceptanceScenario)"))
  let begin = try #require(physical.range(of: "private func beginTimedRun(_ scenario: PhysicalAcceptanceScenario)"))
  let startBody = String(physical[start.lowerBound..<begin.lowerBound])
  #expect(startBody.contains("if !liveActivitiesPrimed"))
  #expect(startBody.contains("prepareOrConfirmLiveActivities()"))
  #expect(startBody.contains("beginTimedRun(scenario)"))
  #expect(physical.contains("func startSingleRendererProbe()"))
  #expect(physical.contains("startScenario(.singleRenderer)"))
  #expect(physical.contains("private actor PhysicalAcceptanceLiveActivityPrimer"))
  #expect(physical.contains("Commander Test – příprava"))
  #expect(physical.contains("try await liveActivityPrimer.prepare()"))
  #expect(physical.contains("guard await liveActivityPrimer.confirmAndClear()"))
  #expect(physical.contains("Potvrdit povolení a spustit test"))
  #expect(physical.contains("clearAllPhysicalAcceptanceActivities()"))
  #expect(physical.contains("await liveActivityPrimer.clearAllPhysicalAcceptanceActivities()"))
  #expect(physical.contains("--cleanup-only"))
  #expect(physical.contains("ÚKLID HOTOV – žádné testovací alarmy ani Live Activities."))
}

@Test func commanderContextCoversDepartureEventAndSuccessorWindows() throws {
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

  #expect(coordinator.contains("start: plan.activationStart"))
  #expect(coordinator.contains("maximumActiveActivities = 1"))
  #expect(coordinator.contains("maximumScheduledActivities"))
  #expect(coordinator.contains("let snapshots = queue.map(Self.snapshot)"))
  #expect(coordinator.contains("CommanderProcedureLiveActivityPolicy.contentState("))
  #expect(coordinator.contains("staleDate: plan.windowEnd"))
  #expect(coordinator.contains("activationStart: plan.activationStart"))
  #expect(coordinator.contains("leaveAt: anchor.leaveAt"))
  #expect(coordinator.contains("CommanderAlarmEventSnapshot("))

  #expect(live.contains("TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes, state: context.state)))"))
  #expect(live.contains("CommanderProcedureDisplay.resolve(attributes: context.attributes, state: context.state, at: timeline.date, isStale: context.isStale)"))
  #expect(live.contains("CommanderLiveActivityTimeline.resolve("))
  #expect(live.contains("CommanderLiveActivityTimeline.boundaryDates("))
  #expect(live.contains("phase: resolution.phase"))
  #expect(live.contains("departureDue: resolution.departureDue"))
  #expect(live.contains("countdownTarget: resolution.countdownTarget"))
  #expect(live.contains("nextEventLabel: resolution.nextRelation == .concurrent ? \"Současně:\" : \"Potom:\""))
  #expect(live.contains("return departureDue ? \"Čas vyrazit\" : \"Vyrazit za\""))
  #expect(live.contains("return \"Právě probíhá\""))
  #expect(live.contains("return \"Skončilo\""))
  #expect(live.contains("return departureDue ? \"Začátek\" : \"Odchod\""))
  #expect(!live.contains("CommanderProcedureHero"))
  #expect(!live.contains("CommanderProcedureStaticStart"))
}

@Test func liveActivityBuildRevisionIsBumpedForFreshExtensionInstall() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let project = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj/project.pbxproj"),
    encoding: .utf8
  )
  let appInfo = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/Info.plist"),
    encoding: .utf8
  )
  let metadata = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/Shared/CommanderAlarmMetadata.swift"),
    encoding: .utf8
  )
  let coordinator = try String(
    contentsOf: repo.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/CommanderProcedureLiveActivityCoordinator.swift"),
    encoding: .utf8
  )

  #expect(!project.contains("CURRENT_PROJECT_VERSION = 4;"))
  #expect(!project.contains("CURRENT_PROJECT_VERSION = \"4\";"))
  #expect(project.components(separatedBy: "CURRENT_PROJECT_VERSION = 6;").count - 1 == 8)
  #expect(project.components(separatedBy: "CURRENT_PROJECT_VERSION = \"6\";").count - 1 == 4)
  #expect(appInfo.contains("<string>$(MARKETING_VERSION)</string>"))
  #expect(appInfo.contains("<string>$(CURRENT_PROJECT_VERSION)</string>"))
  #expect(metadata.contains("static let currentRendererRevision = 6"))
  #expect(metadata.contains("let activationStart: Date?"))
  #expect(metadata.contains("let rendererRevision: Int?"))
  #expect(coordinator.contains("activity.attributes.rendererRevision == CommanderProcedureLiveActivityAttributes.currentRendererRevision"))
  #expect(coordinator.contains("private static func staticIdentityMatches("))
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
  #expect(coordinator.contains("var keepers: [String: Activity<CommanderProcedureLiveActivityAttributes>]"))
  #expect(coordinator.contains("if keepers[stableID] == nil"))
  #expect(coordinator.contains("Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState)"))
  #expect(coordinator.contains("maximumActiveActivities = 1"))
  #expect(coordinator.contains("maximumScheduledActivities"))
  #expect(coordinator.contains("Activity<CommanderProcedureLiveActivityAttributes>.request"))
  #expect(coordinator.contains("alertConfiguration: alert"))
  #expect(!coordinator.contains("retainedStableIDs"))

  #expect(app.contains("let projectionOverrides = leadTimeOverrides"))
  #expect(app.contains("let projectionRevision = leadTimeProjectionRevision"))
  #expect(app.contains("overrides: projectionOverrides"))
  #expect(app.contains("projectionRevision: projectionRevision"))
}

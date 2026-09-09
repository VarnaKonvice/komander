import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func lockedSecondStopUsesActivityPreparedBeforeFirstAlarm() throws {
  let now = try activityDate("14:19:35")
  let run = try PhysicalAcceptanceRun(now: now)
  let events = CommanderLiveActivityHandoff.runningEvents(in: run.schedule, now: now)
  #expect(events.count == 2)
  #expect(events.map(\.kind) == [.meal, .procedure])
  let alarms = try run.payload().alarms
  #expect(alarms.map(\.leaveAt) == ["2026-09-08T14:24:00", "2026-09-08T14:31:00"])

  // Simulated OS holds both foreground-created requests. Stop may end the
  // previous card but cannot request another activity while locked.
  var prepared = Dictionary(uniqueKeysWithValues: events.map { ($0.stableId, $0) })
  let foregroundRequestCount = prepared.count
  #expect(CommanderLiveActivityHandoff.hasCompleteRunningPreparation(
    expectedIDs: events.map(\.stableId), preparedIDs: Array(prepared.keys)))
  #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: false,
    startAt: try activityDate("14:26:00"), now: try activityDate("14:24:10")) == .retainAlarmUntilStart)
  #expect(prepared[events[0].stableId] != nil)
  #expect(CommanderLiveActivityHandoff.retainsFreeTime(previousEnd: try activityDate("14:28:00"),
    targetStart: try activityDate("14:33:00"), now: try activityDate("14:29:00")))
  #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: true,
    startAt: try activityDate("14:33:00"), now: try activityDate("14:31:10")) == .bridgeUntilStart)
  prepared.removeValue(forKey: events[0].stableId)
  let second = try #require(prepared[events[1].stableId])
  #expect(second.start == "14:33" && second.end == "14:35")
  #expect(foregroundRequestCount == 2)
  // Foreground recovery during the free-time handoff still requires the second
  // running activity; the old limit of one/empty selection fails this check.
  #expect(CommanderLiveActivityHandoff.runningEvents(in: run.schedule,
    now: try activityDate("14:29:00")).map(\.stableId) == [second.stableId])
  #expect(CommanderLiveActivityHandoff.runningEvents(in: run.schedule,
    now: try activityDate("14:35:00")).isEmpty)
}

@Test func readinessRejectsMissingSecondActivityAndDuplicateFirstActivity() throws {
  let run = try PhysicalAcceptanceRun(now: activityDate("14:19:35"))
  let ids = CommanderLiveActivityHandoff.runningEvents(in: run.schedule, now: run.now).map(\.stableId)
  #expect(!CommanderLiveActivityHandoff.hasCompleteRunningPreparation(expectedIDs: ids, preparedIDs: [ids[0]]))
  #expect(!CommanderLiveActivityHandoff.hasCompleteRunningPreparation(expectedIDs: ids, preparedIDs: [ids[0], ids[0]]))
  #expect(CommanderLiveActivityHandoff.hasCompleteRunningPreparation(expectedIDs: ids, preparedIDs: ids.reversed()))
}

@Test func backgroundStopCannotReachActivityRequestFactory() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  let start = try #require(source.range(of: "struct CommanderAlarmStopIntent"))
  let end = try #require(source.range(of: "actor AlarmKitAdapter"))
  let stop = String(source[start.lowerBound..<end.lowerBound])
  #expect(!stop.contains(".request("))
  #expect(!stop.contains("scheduleRunning("))
  #expect(stop.contains("CommanderRollingLiveActivity.isPrepared("))
  let factory = String(source[..<start.lowerBound])
  let foregroundGuard = try #require(factory.range(of: "guard UIApplication.shared.applicationState == .active"))
  let request = try #require(factory.range(of: "Activity<CommanderProcedureLiveActivityAttributes>.request("))
  #expect(foregroundGuard.lowerBound < request.lowerBound)
  let readEnd = try #require(factory.range(of: "nonisolated static func date("))
  #expect(!factory[..<readEnd.lowerBound].contains(".request("))
}

private func activityDate(_ time: String) throws -> Date {
  try #require(ISO8601DateFormatter().date(from: "2026-09-08T\(time)+02:00"))
}

@Test func foregroundQueueIsBoundedAndAdvancesOnlyWhenPreparedAgain() throws {
  let run = try PhysicalAcceptanceRun(now: activityDate("14:19:35"))
  let future = (16...20).map { hour in
    ScheduleEvent(stableId: "event-\(hour)", date: "2026-09-08", start: "\(hour):00", end: "\(hour):20",
      title: "Procedura", location: "Balneo", kind: .procedure, procedureType: nil, mealType: nil, leadTimeMinutes: nil)
  }
  let base = run.schedule
  let schedule = Schedule(schemaVersion: base.schemaVersion, scheduleVersion: base.scheduleVersion,
    updatedAt: base.updatedAt, stay: base.stay, events: (base.events + future).reversed(), settings: base.settings)
  let prepared = CommanderLiveActivityHandoff.runningEvents(in: schedule, now: run.now)
  #expect(CommanderLiveActivityHandoff.maximumPreparedActivities == 3)
  #expect(prepared.map(\.stableId) == base.events.map(\.stableId) + ["event-16"])
  #expect(CommanderLiveActivityHandoff.runningEvents(in: schedule, now: try activityDate("14:35:00"))
    .map(\.stableId) == ["event-16", "event-17", "event-18"])
  #expect(prepared.count == 3) // Time passing alone does not refill the foreground queue.
  #expect(try NativeAlarmContract.payload(schedule: schedule).alarms.count == 7)
}

@Test func legacyPresentationProofRequiresRefreshWithoutChangingCanonicalAlarm() throws {
  let run = try PhysicalAcceptanceRun(now: activityDate("14:19:35"))
  let alarm = try run.payload().alarms[1]
  let current = try AlarmPresentationContext(alarm: alarm, schedule: run.schedule, overrides: run.overrides)
  var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
  for key in ["liveActivityContractRevision", "liveActivityScheduleVersion", "handoffIdentity"] {
    json.removeValue(forKey: key)
  }
  let legacy = try JSONDecoder().decode(AlarmPresentationContext.self, from: JSONSerialization.data(withJSONObject: json))
  #expect(legacy != current)
  #expect(current.liveActivityContractRevision == 1)
  #expect(current == (try AlarmPresentationContext(alarm: alarm, schedule: run.schedule, overrides: run.overrides)))
  #expect(try run.payload().alarms[1] == alarm)
}

@Test func planningAndStopUseSameCompleteCanonicalIdentity() throws {
  let run = try PhysicalAcceptanceRun(now: activityDate("14:19:35"))
  let alarm = try run.payload().alarms[1]
  let identity = try #require(CommanderLiveActivityHandoff.identity(for: alarm, in: run.schedule))
  let encoded = try JSONEncoder().encode(identity)
  let stopProof = try JSONDecoder().decode(CommanderLiveActivityHandoff.Identity.self, from: encoded)
  for time in ["14:28:00", "14:31:00", "14:32:59"] {
    #expect(CommanderLiveActivityHandoff.matches(actual: identity, expected: stopProof, now: try activityDate(time)))
  }
  for time in ["14:27:59", "14:33:00", "14:35:00"] {
    #expect(!CommanderLiveActivityHandoff.matches(actual: identity, expected: stopProof, now: try activityDate(time)))
  }
  let now = try activityDate("14:31:00")
  #expect(!CommanderLiveActivityHandoff.matches(actual: nil, expected: stopProof, now: now))
  #expect(!CommanderLiveActivityHandoff.matches(actual: identity, expected: nil, now: now))
  let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  for field in ["scheduleVersion", "sourceStableId", "sourceTitle", "sourceLocation", "sourceKind", "sourceStartAt", "sourceEndAt"] {
    var json = original
    if let number = json[field] as? NSNumber { json[field] = number.doubleValue + 1 }
    else { json[field] = field == "sourceKind" ? "procedure" : "foreign" }
    let foreign = try JSONDecoder().decode(CommanderLiveActivityHandoff.Identity.self,
      from: JSONSerialization.data(withJSONObject: json))
    #expect(!CommanderLiveActivityHandoff.matches(actual: foreign, expected: stopProof, now: now))
  }
  for field in ["stableId", "title", "location", "startAt", "endAt", "leaveAt", "effectiveLeadTimeMinutes", "kind"] {
    var json = original
    var target = try #require(json["target"] as? [String: Any])
    if let number = target[field] as? NSNumber { target[field] = number.intValue + 1 }
    else { target[field] = field == "kind" ? "meal" : "foreign" }
    json["target"] = target
    let foreign = try JSONDecoder().decode(CommanderLiveActivityHandoff.Identity.self,
      from: JSONSerialization.data(withJSONObject: json))
    #expect(!CommanderLiveActivityHandoff.matches(actual: foreign, expected: stopProof, now: now))
  }
}

@Test func reconciliationKeepsOneValidPreparationAndRejectsInvalidAndEndedCopies() {
  var retained = Set<String>()
  #expect(!CommanderLiveActivityHandoff.retainPrepared(stableId: "second", matchesCanonical: false, ongoing: true, retainedIDs: &retained))
  #expect(!CommanderLiveActivityHandoff.retainPrepared(stableId: "second", matchesCanonical: true, ongoing: false, retainedIDs: &retained))
  #expect(CommanderLiveActivityHandoff.retainPrepared(stableId: "second", matchesCanonical: true, ongoing: true, retainedIDs: &retained))
  #expect(!CommanderLiveActivityHandoff.retainPrepared(stableId: "second", matchesCanonical: true, ongoing: true, retainedIDs: &retained))
  #expect(retained == ["second"])
}

@Test func endTimeAllowsStaleCardUntilExecutionThenImmediateCleanupExceptVerifiedHandoff() throws {
  let end = try activityDate("14:28:00")
  #expect(!CommanderLiveActivityHandoff.needsCleanup(endAt: end, hasVerifiedHandoff: false, now: end.addingTimeInterval(-1)))
  #expect(CommanderLiveActivityHandoff.needsCleanup(endAt: end, hasVerifiedHandoff: false, now: end))
  #expect(!CommanderLiveActivityHandoff.needsCleanup(endAt: end, hasVerifiedHandoff: true, now: end))
  let finalEnd = try activityDate("14:35:00")
  // The clock is not an execution callback. Only the actual cleanup invocation removes a card.
  var visible = true
  let nextExecution = finalEnd.addingTimeInterval(300)
  #expect(visible)
  if CommanderLiveActivityHandoff.needsCleanup(endAt: finalEnd, hasVerifiedHandoff: false, now: nextExecution) {
    visible = false
  }
  #expect(!visible)
}

@Test func realAdapterUsesSharedProofAndImmediateCleanupWithoutChangingWidgetDesign() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let adapter = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  let stop = try #require(adapter.range(of: "struct CommanderAlarmStopIntent"))
  let actor = try #require(adapter.range(of: "actor AlarmKitAdapter"))
  #expect(adapter[stop.lowerBound..<actor.lowerBound].contains("CommanderRollingLiveActivity.matchesHandoff("))
  #expect(adapter[actor.lowerBound...].contains("CommanderRollingLiveActivity.matchesHandoff("))
  #expect(!adapter.contains("state.nextStableId == stableId"))
  #expect(adapter.contains("existingRed == nil"))
  let cleanup = try #require(adapter.range(of: "static func cleanupExpired("))
  let next = try #require(adapter.range(of: "nonisolated static func isPrepared("))
  #expect(adapter[cleanup.lowerBound..<next.lowerBound].contains("dismissalPolicy: .immediate"))
  #expect(!adapter.contains("dismissalPolicy: .default"))
  let physical = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/PhysicalAcceptance/PhysicalAcceptanceApp.swift"), encoding: .utf8)
  #expect(physical.contains("await adapter.cleanupFinishedLiveActivities()"))
  #expect(physical.contains("await model.resume()"))
}

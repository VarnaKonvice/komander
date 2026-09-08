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

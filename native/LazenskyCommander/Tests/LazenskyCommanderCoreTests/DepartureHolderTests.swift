import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func firstDepartureHolderIsPlannedOnlyInForegroundWithRunningActivityPrepared() throws {
  let f = try HolderFixture()
  #expect(CommanderLiveActivityHandoff.identity(for: f.first, in: f.run.schedule) == nil)
  #expect(CommanderDepartureHolder.reconcile(expected: f.identity, observed: [], now: f.run.now,
    foreground: true, runningPrepared: true).create)
  for (foreground, running) in [(false, true), (true, false), (false, false)] {
    #expect(!CommanderDepartureHolder.reconcile(expected: f.identity, observed: [], now: f.run.now,
      foreground: foreground, runningPrepared: running).create)
  }
  #expect(!CommanderDepartureHolder.reconcile(expected: f.identity, observed: [], now: f.leave,
    foreground: true, runningPrepared: true).create)
}

@Test func firstHolderOwnsCountdownOnlyAfterUniqueActiveCanonicalReadback() throws {
  let f = try HolderFixture()
  let active = f.observation()
  #expect(CommanderDepartureHolder.verified(expected: f.identity, observed: [active],
    now: f.run.now, runningPrepared: true))
  for state in [CommanderDepartureHolder.State.pending, .ended, .dismissed] {
    #expect(!CommanderDepartureHolder.verified(expected: f.identity, observed: [f.observation(state: state)],
      now: f.run.now, runningPrepared: true))
  }
  // A rejected request, a missing activity, a duplicate, or a missing scheduled
  // event must leave the adapter's AlarmKit countdown branch enabled.
  for observations in [[], [active, f.observation(id: "duplicate")]] {
    #expect(!CommanderDepartureHolder.verified(expected: f.identity, observed: observations,
      now: f.run.now, runningPrepared: true))
  }
  #expect(!CommanderDepartureHolder.verified(expected: f.identity, observed: [active],
    now: f.run.now, runningPrepared: false))
  let lostRunning = CommanderDepartureHolder.reconcile(expected: f.identity, observed: [active],
    now: f.run.now, foreground: true, runningPrepared: false)
  #expect(lostRunning.removeIDs == [active.id] && !lostRunning.create)
}

@Test func lockedFirstStopKeepsSameHolderRedUntilScheduledEventStart() throws {
  let f = try HolderFixture()
  let active = f.observation()
  let foreground = CommanderDepartureHolder.reconcile(expected: f.identity, observed: [], now: f.run.now,
    foreground: true, runningPrepared: true)
  #expect(foreground.create)
  let stopTime = f.leave.addingTimeInterval(1)
  let owner = CommanderDepartureHolder.stopHolderID(expected: f.identity, observed: [active], now: stopTime)
  #expect(owner == active.id)
  #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: owner != nil, startAt: f.start,
    now: stopTime) == .bridgeUntilStart)
  // Activity.end(.after(startAt)) still has a visible red final state. Keep it
  // across repeated Stop/foreground callbacks, without making another request.
  let red = f.observation(state: .ended, isRed: true)
  for now in [stopTime, f.start.addingTimeInterval(-0.001)] {
    let plan = CommanderDepartureHolder.reconcile(expected: f.identity, observed: [red], now: now,
      foreground: false, runningPrepared: true)
    #expect(plan.retainedID == owner && plan.removeIDs.isEmpty && !plan.create)
    #expect(CommanderDepartureHolder.stopHolderID(expected: f.identity, observed: [red], now: now) == owner)
  }
  let atStart = CommanderDepartureHolder.reconcile(expected: f.identity, observed: [red], now: f.start,
    foreground: false, runningPrepared: true)
  #expect(atStart.retainedID == nil && atStart.removeIDs == [active.id] && !atStart.create)
  #expect(CommanderDepartureHolder.stopHolderID(expected: f.identity, observed: [red], now: f.start) == nil)
  #expect(CommanderLiveStateCalculator.compute(schedule: f.run.schedule, now: f.start).state == .inProgress)
  #expect(CommanderLiveActivityHandoff.runningEvents(in: f.run.schedule, now: f.run.now)
    .map(\.stableId) == f.run.schedule.events.map(\.stableId))
}

@Test func firstHolderCannotBorrowAnOldVersionOrDifferentCanonicalIdentity() throws {
  let f = try HolderFixture()
  let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(f.identity)) as? [String: Any])
  for field in ["scheduleVersion", "iconKey", "stableId", "kind", "title", "location", "startAt", "endAt", "leaveAt", "effectiveLeadTimeMinutes"] {
    var changed = json
    if field == "scheduleVersion" { changed[field] = f.identity.scheduleVersion + 1 }
    else if field == "iconKey" { changed[field] = "foreign" }
    else {
      var target = try #require(changed["target"] as? [String: Any])
      if field == "effectiveLeadTimeMinutes" { target[field] = 99 }
      else { target[field] = field == "kind" ? "procedure" : "foreign" }
      changed["target"] = target
    }
    let identity = try JSONDecoder().decode(CommanderDepartureHolder.Identity.self,
      from: JSONSerialization.data(withJSONObject: changed))
    let bad = CommanderDepartureHolder.Observation(id: "bad", identity: identity, state: .active)
    #expect(!CommanderDepartureHolder.verified(expected: f.identity, observed: [bad], now: f.run.now, runningPrepared: true))
    #expect(CommanderDepartureHolder.stopHolderID(expected: f.identity, observed: [bad], now: f.leave) == nil)
    let plan = CommanderDepartureHolder.reconcile(expected: f.identity, observed: [bad], now: f.run.now,
      foreground: true, runningPrepared: true)
    #expect(plan.removeIDs == ["bad"] && plan.create)
  }
}

@Test func holderReconciliationRemovesDuplicatesInvalidAndObsoleteCards() throws {
  let f = try HolderFixture()
  let observed = [f.observation(id: "b"), f.observation(id: "a"),
    CommanderDepartureHolder.Observation(id: "bad", identity: nil, state: .active),
    f.observation(id: "ended", state: .ended)]
  let plan = CommanderDepartureHolder.reconcile(expected: f.identity, observed: observed,
    now: f.run.now, foreground: true, runningPrepared: true)
  #expect(plan.retainedID == "a" && plan.removeIDs == ["b", "bad", "ended"] && !plan.create)
  let removed = CommanderDepartureHolder.reconcile(expected: nil, observed: observed,
    now: f.run.now, foreground: true, runningPrepared: true)
  #expect(removed.retainedID == nil && removed.removeIDs.count == 4 && !removed.create)
  let red = f.observation(id: "red", state: .ended, isRed: true)
  let repeated = CommanderDepartureHolder.reconcile(expected: f.identity, observed: observed + [red],
    now: f.leave, foreground: true, runningPrepared: true)
  #expect(repeated.retainedID == "red" && repeated.removeIDs.count == 4 && !repeated.create)
}

@Test func secondCanonicalFreeTimeHandoffDoesNotAcquireADepartureHolder() throws {
  let f = try HolderFixture()
  let second = try f.run.payload().alarms[1]
  let end = try NativeAlarmContract.date(fromLocalISO: f.first.endAt)
  let leave = try NativeAlarmContract.date(fromLocalISO: second.leaveAt)
  let start = try NativeAlarmContract.date(fromLocalISO: second.startAt)
  let identity = try #require(CommanderLiveActivityHandoff.identity(for: second, in: f.run.schedule))
  for now in [f.run.now, end, leave, start.addingTimeInterval(-1)] {
    #expect(CommanderDepartureHolder.identity(for: second, in: f.run.schedule, iconKey: "magnet", now: now) == nil)
  }
  for now in [end, leave, start.addingTimeInterval(-1)] {
    #expect(CommanderLiveActivityHandoff.matches(actual: identity, expected: identity, now: now))
  }
  #expect(CommanderLiveActivityHandoff.stopDisposition(hasHandoff: true, startAt: start,
    now: leave.addingTimeInterval(1)) == .bridgeUntilStart)
}

@Test func firstHolderContextRefreshesExistingAlarmWithoutChangingSecondAlarmContext() throws {
  let f = try HolderFixture()
  let legacy = try AlarmPresentationContext(alarm: f.first, schedule: f.run.schedule, overrides: f.run.overrides)
  let ready = try AlarmPresentationContext(alarm: f.first, schedule: f.run.schedule, overrides: f.run.overrides, departureHolderVerified: true)
  let lost = try AlarmPresentationContext(alarm: f.first, schedule: f.run.schedule, overrides: f.run.overrides, departureHolderVerified: false)
  #expect(legacy != ready && ready != lost)
  #expect(ready.handoffIdentity == nil && ready.countdownWindow == legacy.countdownWindow)
  let second = try f.run.payload().alarms[1]
  let unchanged = try AlarmPresentationContext(alarm: second, schedule: f.run.schedule, overrides: f.run.overrides)
  #expect(unchanged.departureHolderVerified == nil && unchanged.liveActivityContractRevision == 1)
}

// Wiring guard supplements the behavioral policy tests; it is not a device test.
@Test func holderIsVisibleAndStopUsesExistingActivityWithoutForegroundRequests() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let adapter = try String(contentsOf: root.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"), encoding: .utf8)
  let start = try #require(adapter.range(of: "struct CommanderAlarmStopIntent"))
  let end = try #require(adapter.range(of: "actor AlarmKitAdapter"))
  let stop = String(adapter[start.lowerBound..<end.lowerBound])
  #expect(stop.contains("CommanderDepartureHolder.stopHolderID("))
  #expect(stop.contains("await handoff.end("))
  #expect(!stop.contains(".request(") && !stop.contains("reconcileHolder(") && !stop.contains("scheduleRunning("))
  let live = try String(contentsOf: root.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"), encoding: .utf8)
  #expect(live.contains("CommanderDepartureBridgeHero(startAt: leaveAt, isDepartureCountdown: true)"))
  #expect(live.contains("isDepartureCountdown ? \"Odchod za\" : \"VYRAZIT TEĎ\""))
  #expect(adapter.contains("phase: .departureHolder"))
  #expect(adapter.contains("|| hasVerifiedDepartureHolder(for: alarm, now: now)"))
}

private struct HolderFixture {
  let run: PhysicalAcceptanceRun
  let first: NativeAlarm
  let identity: CommanderDepartureHolder.Identity
  let leave: Date
  let start: Date
  init() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-09-12T10:00:00Z"))
    run = try PhysicalAcceptanceRun(now: now)
    first = try run.payload().alarms[0]
    identity = try #require(CommanderDepartureHolder.identity(for: first, in: run.schedule, iconKey: "meal", now: now))
    leave = try NativeAlarmContract.date(fromLocalISO: first.leaveAt)
    start = try NativeAlarmContract.date(fromLocalISO: first.startAt)
  }
  func observation(id: String = "holder", state: CommanderDepartureHolder.State = .active,
                   isRed: Bool = false) -> CommanderDepartureHolder.Observation {
    .init(id: id, identity: identity, state: state, isRed: isRed)
  }
}

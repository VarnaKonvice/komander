#if canImport(Testing)
import Foundation
import Testing

@Test func stoppedAlarmPreservesVerifiedRedDepartureHandoff() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let adapter = try String(
    contentsOf: repo.appendingPathComponent(
      "native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"
    ),
    encoding: .utf8
  )
  let live = try String(
    contentsOf: repo.appendingPathComponent(
      "native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift"
    ),
    encoding: .utf8
  )

  let stopStart = try #require(adapter.range(of: "struct CommanderAlarmStopIntent"))
  let actorStart = try #require(adapter.range(of: "actor AlarmKitAdapter"))
  let stopIntent = String(adapter[stopStart.lowerBound..<actorStart.lowerBound])

  // The physically verified handoff must remain explicit: ringing is owned by AlarmKit,
  // then an existing free-time/procedure activity becomes the red departure card until start.
  #expect(stopIntent.contains("phase: .departureBridge"))
  #expect(stopIntent.contains("CommanderLiveActivityHandoff.stopDisposition("))
  #expect(stopIntent.contains("await alarmActivity.end(nil, dismissalPolicy: .immediate)"))
  #expect(stopIntent.contains("await handoff.end("))
  #expect(stopIntent.contains("dismissalPolicy: .after(startDate)"))
  #expect(stopIntent.contains("Červená karta předána"))

  // Legacy best effort remains when no Commander holder exists, but is NOT a
  // physical guarantee of red after Stop. The first event now selects its own holder.
  #expect(stopIntent.contains("CommanderDepartureHolder.stopHolderID("))
  #expect(stopIntent.contains("departureHolderJSON"))
  #expect(stopIntent.contains("await alarmActivity.end(alarmActivity.content, dismissalPolicy: .after(startDate))"))
  #expect(stopIntent.contains("Červená AlarmKit karta ponechána"))

  // The widget must still render the bridge as the approved red VYRAZIT TEĎ state.
  #expect(live.contains("isDepartureBridge"))
  #expect(live.contains("VYRAZIT TEĎ"))
  #expect(live.contains("criticalRed"))
}

@Test func alertOnlyAlarmRequiresExistingVerifiedFreeTimeActivity() throws {
  let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  let adapter = try String(
    contentsOf: repo.appendingPathComponent(
      "native/LazenskyCommanderApp/LazenskyCommanderApp/AlarmKitAdapter.swift"
    ),
    encoding: .utf8
  )

  // A logical neighbour in the canonical schedule is not enough. The adapter must
  // prove that the matching free-time Live Activity really exists before removing
  // AlarmKit's own countdown presentation.
  #expect(adapter.contains("let verifiedHandoff = hasVerifiedFreeTimeHandoff(for: alarm, now: now)"))
  #expect(adapter.contains("Activity<CommanderProcedureLiveActivityAttributes>.activities.contains"))
  #expect(adapter.contains("CommanderLiveActivityHandoff.identity(for: alarm, in: schedule)"))
  #expect(adapter.contains("CommanderLiveActivityHandoff.matches(actual: identity(activity), expected: expected, now: now)"))
  #expect(adapter.components(separatedBy: "attributes: alertOnlyAttributes,").count == 2)
  #expect(adapter.contains("if !verifiedHandoff, countdownPlan.countdownWindow == 0"))
  #expect(adapter.contains("CommanderRollingLiveActivity.matchesHandoff(activity, expected: expected, now: now)"))
  #expect(adapter.contains("Handoff chybí, používám vlastní countdown"))

  // The old behaviour used schedule topology alone and could therefore suppress the
  // system countdown even when the expected Live Activity was missing on the phone.
  #expect(!adapter.contains("if hasFreeTimeHandoff(for: alarm)"))
}
#endif

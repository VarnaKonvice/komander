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

@Test func commanderHandoffNeverSuppressesAlarmKitSystemCountdown() throws {
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

  let scheduleMethod = try #require(adapter.range(of: "func schedule(_ alarm: NativeAlarm"))
  let cancelMethod = try #require(adapter.range(of: "func cancel(platformAlarmID:"))
  let scheduling = String(adapter[scheduleMethod.lowerBound..<cancelMethod.lowerBound])

  // Commander Live Activity is presentation only. It must never select an alert-only
  // AlarmKit configuration when a real pre-alert window exists.
  #expect(scheduling.contains("if countdownPlan.countdownWindow > 0"))
  #expect(scheduling.contains("countdownDuration: Alarm.CountdownDuration("))
  #expect(scheduling.contains("preAlert: countdownPlan.countdownWindow"))
  #expect(!scheduling.contains("if verifiedHandoff"))
  #expect(!scheduling.contains("let verifiedHandoff"))

  // The direct alert-only branch remains only for a genuine zero-length interval.
  #expect(scheduling.contains("schedule: .fixed(countdownPlan.scheduledAlertAt)"))
  #expect(scheduling.contains("attributes: alertOnlyAttributes"))
}

#endif

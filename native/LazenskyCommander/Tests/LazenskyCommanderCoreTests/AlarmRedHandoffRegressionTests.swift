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
  #expect(stopIntent.contains("let canBridgeHandoff = handoff != nil && startDate > now"))
  #expect(stopIntent.contains("await alarmActivity.end(nil, dismissalPolicy: .immediate)"))
  #expect(stopIntent.contains("await handoff.end("))
  #expect(stopIntent.contains("dismissalPolicy: .after(startDate)"))
  #expect(stopIntent.contains("Červená karta předána"))

  // If there is no existing handoff card (for example the first event of the day),
  // keep the AlarmKit alert itself visible as the fallback until the event starts.
  #expect(stopIntent.contains("await alarmActivity.end(alarmActivity.content, dismissalPolicy: .after(startDate))"))
  #expect(stopIntent.contains("Červená AlarmKit karta ponechána"))

  // The widget must still render the bridge as the approved red VYRAZIT TEĎ state.
  #expect(live.contains("isDepartureBridge"))
  #expect(live.contains("VYRAZIT TEĎ"))
  #expect(live.contains("criticalRed"))
}
#endif

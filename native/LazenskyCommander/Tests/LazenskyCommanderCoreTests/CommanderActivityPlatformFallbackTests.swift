import Foundation
import Testing
@testable import LazenskyCommanderCore

// PLATFORM LIMIT tests, NOT acceptance of the required no-wake story.
// Simulates the archived view receiving no second structural update.
private let fallbackSeed = CommanderAlarmEventSnapshot(stableId: "event", iconKey: "",
  title: "Masáž", location: "A", kind: .procedure, startAt: "2026-09-28T10:00:00",
  endAt: "2026-09-28T10:20:00", leaveAt: "2026-09-28T09:40:00")

@Test(arguments: [CommanderLiveActivityPresentationMode.departureCountdown, .startCountdown, .eventContext])
func platformFallbackArchivedAtStalenessCannotCountIntoPastOrClaimProgress(mode: CommanderLiveActivityPresentationMode) throws {
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-28T10:00:00")
  // An early stale signal (e.g. window lifetime cap) is not proof of completion.
  let frozen = CommanderActivityPresentation.resolve(seed: fallbackSeed, events: [fallbackSeed],
    focusStableId: nil, presentationMode: mode, isStale: true, at: now,
    renderingPolicy: .suspendedActivity)
  #expect(frozen.isScheduleFallback)
  #expect(!frozen.isFinished)
  #expect(frozen.status == "Časový plán")
  #expect(frozen.timing.symbol == "clock")
  #expect(frozen.countdownLabel.isEmpty)
  #expect(frozen.countdownTarget == nil)
  // Intentionally reuse frozen instead of calling resolve at every future instant.
  for elapsed in [0.0, 1_199, 1_200, 1_201, 86_400] {
    #expect(frozen.timing.countdownText(at: now.addingTimeInterval(elapsed)) == nil)
    #expect(frozen.status != "Právě probíhá")
    #expect(!frozen.status.contains("Vyrazit"))
  }
}

@Test func platformFallbackIsLimitedToExpiredSnapshotAndRecoversOnContentUpdate() throws {
  let start = try NativeAlarmContract.date(fromLocalISO: fallbackSeed.startAt)
  func render(_ mode: CommanderLiveActivityPresentationMode, _ stale: Bool, _ now: Date) -> CommanderActivityPresentation {
    .resolve(seed: fallbackSeed, events: [fallbackSeed], focusStableId: nil,
      presentationMode: mode, isStale: stale, at: now, renderingPolicy: .suspendedActivity)
  }
  #expect(render(.startCountdown, false, start.addingTimeInterval(-1)).status == "Začátek za")
  // Clock guard also protects renders when isStale delivery lags the boundary.
  #expect(render(.startCountdown, false, start).isScheduleFallback)
  #expect(render(.startCountdown, true, start).isScheduleFallback)
  #expect(render(.eventContext, false, start).status == "Právě probíhá")
  #expect(!render(.eventContext, false, start).isScheduleFallback)
  let end = try NativeAlarmContract.date(fromLocalISO: fallbackSeed.endAt)
  #expect(render(.eventContext, true, end).status == "Skončilo")
  #expect(render(.startCountdown, true, end).countdownTarget == nil)
}

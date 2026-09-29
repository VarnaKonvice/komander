#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func watchAcceptanceProbeRoundTripsWithoutScheduleCacheVersion() throws {
  let leaveAt = Date(timeIntervalSince1970: 1_800_000_000)
  let startAt = leaveAt.addingTimeInterval(5 * 60)
  let endAt = startAt.addingTimeInterval(15 * 60)
  let probe = WatchAcceptanceProbe(
    stableId: "acceptance-magnet",
    title: "TEST – Magnetoterapie",
    location: "Vizuální test",
    kind: .procedure,
    procedureType: "Magnetoterapie",
    leaveAt: leaveAt,
    startAt: startAt,
    endAt: endAt
  )

  let context = try WatchAcceptanceProbeCodec.applicationContext(for: probe)
  let decodedProbe = try WatchAcceptanceProbeCodec.decode(applicationContext: context)
  let decoded = try #require(decodedProbe)

  #expect(decoded == probe)
  #expect(decoded.event?.title == "TEST – Magnetoterapie")
  #expect(decoded.event?.procedureType == "Magnetoterapie")
}

@Test func inactiveWatchAcceptanceProbeRoundTripsAndHasNoLiveState() throws {
  let context = try WatchAcceptanceProbeCodec.applicationContext(for: .inactive)
  let decodedProbe = try WatchAcceptanceProbeCodec.decode(applicationContext: context)
  let decoded = try #require(decodedProbe)

  #expect(decoded.isActive == false)
  #expect(decoded.liveState(at: Date()) == nil)
}

@Test func watchAcceptanceTransportNonceSurvivesProbeMergeAndMakesRepeatedCleanupDistinct() throws {
  let firstNonce = "nonce-1"
  let secondNonce = "nonce-2"

  let first = try WatchAcceptanceProbeCodec.merging(
    probe: .inactive,
    into: [WatchAcceptanceProbeCodec.transportNonceKey: firstNonce]
  )
  let second = try WatchAcceptanceProbeCodec.merging(
    probe: .inactive,
    into: [WatchAcceptanceProbeCodec.transportNonceKey: secondNonce]
  )

  #expect(first[WatchAcceptanceProbeCodec.transportNonceKey] as? String == firstNonce)
  #expect(second[WatchAcceptanceProbeCodec.transportNonceKey] as? String == secondNonce)
  #expect(first[WatchAcceptanceProbeCodec.transportNonceKey] as? String != second[WatchAcceptanceProbeCodec.transportNonceKey] as? String)
  #expect(try WatchAcceptanceProbeCodec.decode(applicationContext: first)?.isActive == false)
  #expect(try WatchAcceptanceProbeCodec.decode(applicationContext: second)?.isActive == false)
}

@Test func watchAcceptanceProbeMergesAndClearsWithoutTouchingScheduleContext() throws {
  let leaveAt = Date(timeIntervalSince1970: 1_800_000_000)
  let probe = WatchAcceptanceProbe(
    stableId: "acceptance-magnet",
    title: "TEST – Magnetoterapie",
    location: "Vizuální test",
    kind: .procedure,
    procedureType: "Magnetoterapie",
    leaveAt: leaveAt,
    startAt: leaveAt.addingTimeInterval(300),
    endAt: leaveAt.addingTimeInterval(1_200)
  )
  let scheduleBytes = Data([1, 2, 3, 4])
  let original: [String: Any] = [
    WatchScheduleTransportCodec.applicationContextKey: scheduleBytes,
    "foreign-key": "preserve-me"
  ]

  let withProbe = try WatchAcceptanceProbeCodec.merging(probe: probe, into: original)
  #expect(withProbe[WatchScheduleTransportCodec.applicationContextKey] as? Data == scheduleBytes)
  #expect(withProbe["foreign-key"] as? String == "preserve-me")
  #expect(withProbe[WatchAcceptanceProbeCodec.applicationContextKey] as? Data != nil)

  let cleared = try WatchAcceptanceProbeCodec.merging(probe: nil, into: withProbe)
  #expect(cleared[WatchScheduleTransportCodec.applicationContextKey] as? Data == scheduleBytes)
  #expect(cleared["foreign-key"] as? String == "preserve-me")
  #expect(cleared[WatchAcceptanceProbeCodec.applicationContextKey] == nil)
}

@Test func watchAcceptanceProbeTransitionsAcrossDepartureAndProcedure() throws {
  let leaveAt = Date(timeIntervalSince1970: 1_800_000_000)
  let startAt = leaveAt.addingTimeInterval(5 * 60)
  let endAt = startAt.addingTimeInterval(15 * 60)
  let probe = WatchAcceptanceProbe(
    stableId: "acceptance-magnet",
    title: "TEST – Magnetoterapie",
    location: "Vizuální test",
    kind: .procedure,
    procedureType: "Magnetoterapie",
    leaveAt: leaveAt,
    startAt: startAt,
    endAt: endAt
  )

  #expect(probe.liveState(at: leaveAt.addingTimeInterval(-1))?.state == .upcoming)
  #expect(probe.liveState(at: leaveAt)?.state == .leaveNow)
  #expect(probe.liveState(at: startAt)?.state == .inProgress)
  #expect(probe.liveState(at: endAt)?.state == .dayDone)
}

@Test func watchAcceptanceAcknowledgementIdentifiesExactProbeInstance() throws {
  let leaveAt = Date(timeIntervalSince1970: 1_800_000_000)
  let first = WatchAcceptanceProbe(
    stableId: "acceptance-magnet",
    title: "TEST – Magnetoterapie",
    location: "Vizuální test",
    kind: .procedure,
    procedureType: "Magnetoterapie",
    leaveAt: leaveAt,
    startAt: leaveAt.addingTimeInterval(300),
    endAt: leaveAt.addingTimeInterval(1_200)
  )
  let second = WatchAcceptanceProbe(
    stableId: "acceptance-magnet",
    title: "TEST – Magnetoterapie",
    location: "Vizuální test",
    kind: .procedure,
    procedureType: "Magnetoterapie",
    leaveAt: leaveAt.addingTimeInterval(1),
    startAt: leaveAt.addingTimeInterval(301),
    endAt: leaveAt.addingTimeInterval(1_201)
  )

  #expect(first.acknowledgementToken != second.acknowledgementToken)
  #expect(WatchAcceptanceProbe.inactive.acknowledgementToken == WatchAcceptanceProbe.inactiveAcknowledgementToken)
}

@Test func watchAcceptanceAcknowledgementTransportNonceSurvivesMerge() {
  let nonce = "ack-nonce-1"
  let original: [String: Any] = [
    WatchAcceptanceAcknowledgementCodec.transportNonceKey: nonce
  ]
  let merged = WatchAcceptanceAcknowledgementCodec.merging(
    token: WatchAcceptanceProbe.inactiveAcknowledgementToken,
    into: original
  )

  #expect(WatchAcceptanceAcknowledgementCodec.decode(applicationContext: merged) == "inactive")
  #expect(merged[WatchAcceptanceAcknowledgementCodec.transportNonceKey] as? String == nonce)
}

@Test func watchAcceptanceAcknowledgementMergesWithoutDestroyingOtherContext() {
  let original: [String: Any] = [
    WatchScheduleTransportCodec.applicationContextKey: Data([7, 8, 9]),
    "foreign-key": "preserve-me"
  ]
  let merged = WatchAcceptanceAcknowledgementCodec.merging(
    token: "acceptance-token",
    into: original
  )

  #expect(WatchAcceptanceAcknowledgementCodec.decode(applicationContext: merged) == "acceptance-token")
  #expect(merged[WatchScheduleTransportCodec.applicationContextKey] as? Data == Data([7, 8, 9]))
  #expect(merged["foreign-key"] as? String == "preserve-me")
}
#endif

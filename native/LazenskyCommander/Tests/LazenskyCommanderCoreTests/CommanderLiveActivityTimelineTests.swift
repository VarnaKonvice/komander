import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func liveActivityTimelineFollowsDepartureAndProcedureBoundaries() throws {
  let events = try timelineFixture()

  let beforeLeave = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("06:40")
  ))
  #expect(beforeLeave.primaryStableId == "breakfast")
  #expect(beforeLeave.phase == .upcoming)
  #expect(!beforeLeave.departureDue)
  let breakfastLeave = try timelineDate("06:45")
  #expect(beforeLeave.countdownTarget == breakfastLeave)
  #expect(beforeLeave.nextStableId == "magnet")
  #expect(beforeLeave.nextRelation == .following)

  let leaveBreakfast = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("06:45")
  ))
  #expect(leaveBreakfast.primaryStableId == "breakfast")
  #expect(leaveBreakfast.phase == .upcoming)
  #expect(leaveBreakfast.departureDue)
  let breakfastStart = try timelineDate("06:50")
  #expect(leaveBreakfast.countdownTarget == breakfastStart)

  let breakfastRunning = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("06:54")
  ))
  #expect(breakfastRunning.primaryStableId == "breakfast")
  #expect(breakfastRunning.phase == .active)
  let breakfastEnd = try timelineDate("07:05")
  #expect(breakfastRunning.countdownTarget == breakfastEnd)
  #expect(breakfastRunning.nextStableId == "magnet")

  let magnetDepartureDuringBreakfast = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("06:55")
  ))
  #expect(magnetDepartureDuringBreakfast.primaryStableId == "magnet")
  #expect(magnetDepartureDuringBreakfast.phase == .upcoming)
  #expect(magnetDepartureDuringBreakfast.departureDue)
  let magnetStart = try timelineDate("07:00")
  #expect(magnetDepartureDuringBreakfast.countdownTarget == magnetStart)
  #expect(magnetDepartureDuringBreakfast.nextStableId == "rehab")

  let magnetRunning = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("07:00")
  ))
  #expect(magnetRunning.primaryStableId == "magnet")
  #expect(magnetRunning.phase == .active)
  let magnetEnd = try timelineDate("07:10")
  #expect(magnetRunning.countdownTarget == magnetEnd)

  let finished = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("07:30")
  ))
  #expect(finished.primaryStableId == "rehab")
  #expect(finished.phase == .ended)
  #expect(!finished.departureDue)
  #expect(finished.nextStableId == nil)
}

@Test func liveActivityTimelineLabelsOverlappingFollowingEventAsConcurrent() throws {
  let events = [
    CommanderLiveActivityTimelineEvent(
      stableId: "a",
      leaveAt: try timelineDate("08:50"),
      startAt: try timelineDate("09:00"),
      endAt: try timelineDate("09:30")
    ),
    CommanderLiveActivityTimelineEvent(
      stableId: "b",
      leaveAt: try timelineDate("08:55"),
      startAt: try timelineDate("09:00"),
      endAt: try timelineDate("09:20")
    )
  ]

  let resolution = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("09:06")
  ))
  #expect(resolution.primaryStableId == "a")
  #expect(resolution.phase == .active)
  #expect(resolution.nextStableId == "b")
  #expect(resolution.nextRelation == .concurrent)
}

@Test func liveActivityTimelineStaleForcesEndedWithoutChangingPrimaryIdentity() throws {
  let events = try timelineFixture()
  let resolution = try #require(CommanderLiveActivityTimeline.resolve(
    events: events,
    at: timelineDate("07:00"),
    isStale: true
  ))
  #expect(resolution.primaryStableId == "magnet")
  #expect(resolution.phase == .ended)
  #expect(!resolution.departureDue)
  let magnetEnd = try timelineDate("07:10")
  #expect(resolution.countdownTarget == magnetEnd)
}

@Test func liveActivityTimelineBoundaryDatesContainEveryLeaveStartAndEndExactlyOnce() throws {
  let events = try timelineFixture()
  let dates = CommanderLiveActivityTimeline.boundaryDates(events: events)

  let expected = try [
    timelineDate("06:45"),
    timelineDate("06:50"),
    timelineDate("06:55"),
    timelineDate("07:00"),
    timelineDate("07:05"),
    timelineDate("07:08"),
    timelineDate("07:10"),
    timelineDate("07:12"),
    timelineDate("07:25")
  ]
  #expect(dates == expected)
}

private func timelineFixture() throws -> [CommanderLiveActivityTimelineEvent] {
  [
    CommanderLiveActivityTimelineEvent(
      stableId: "breakfast",
      leaveAt: try timelineDate("06:45"),
      startAt: try timelineDate("06:50"),
      endAt: try timelineDate("07:05")
    ),
    CommanderLiveActivityTimelineEvent(
      stableId: "magnet",
      leaveAt: try timelineDate("06:55"),
      startAt: try timelineDate("07:00"),
      endAt: try timelineDate("07:10")
    ),
    CommanderLiveActivityTimelineEvent(
      stableId: "rehab",
      leaveAt: try timelineDate("07:08"),
      startAt: try timelineDate("07:12"),
      endAt: try timelineDate("07:25")
    )
  ]
}

private func timelineDate(_ time: String) throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: "2026-09-27T\(time):00")
}

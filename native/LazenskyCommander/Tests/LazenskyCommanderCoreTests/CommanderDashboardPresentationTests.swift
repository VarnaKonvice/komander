#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func dashboardPresentationCoversAllLiveAndSnapshotStates() throws {
  let schedule = dashboardSchedule(events: [
    dashboardEvent("iodobrom", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    dashboardEvent("whirlpool", start: "10:00", end: "10:30", title: "Vířivá vana")
  ])
  let cases: [(String, CommanderDashboardMode, String?)] = [
    ("2026-08-20T08:30:00", .upcoming, "iodobrom"),
    ("2026-08-20T08:45:00", .leaveNow, "iodobrom"),
    ("2026-08-20T09:05:00", .inProgress, "iodobrom"),
    ("2026-08-20T20:00:00", .dayDone, nil)
  ]

  for (timestamp, expectedMode, stableId) in cases {
    let now = try NativeAlarmContract.date(fromLocalISO: timestamp)
    let presentation = CommanderDashboardPresentation.make(schedule: schedule, now: now)
    #expect(presentation.mode == expectedMode)
    #expect(presentation.currentEvent?.event.stableId == stableId)
  }

  let noScheduleNow = try NativeAlarmContract.date(fromLocalISO: "2026-08-21T09:00:00")
  let noSchedule = CommanderDashboardPresentation.make(schedule: schedule, now: noScheduleNow)
  #expect(noSchedule.mode == .noSchedule)
  #expect(noSchedule.timeline.isEmpty)

  let unsynchronized = CommanderDashboardPresentation.make(schedule: nil, now: noScheduleNow)
  #expect(unsynchronized.mode == .unsynchronized)
  #expect(unsynchronized.liveState.state == .noSchedule)
  #expect(unsynchronized.timeline.isEmpty)
}

@Test func dashboardPresentationSelectsCurrentNextAndTimelinePhases() throws {
  let schedule = dashboardSchedule(events: [
    dashboardEvent("past", start: "08:00", end: "08:30", title: "Snídaně", kind: .meal),
    dashboardEvent("current", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    dashboardEvent("future", start: "10:00", end: "10:30", title: "Vířivá vana")
  ])
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:05:00")
  let presentation = CommanderDashboardPresentation.make(schedule: schedule, now: now)

  #expect(presentation.currentEvent?.event.stableId == "current")
  #expect(presentation.nextEvent?.event.stableId == "future")
  #expect(presentation.timeline.map(\.phase) == [.past, .current, .future])
  #expect(presentation.timeline.map(\.event.stableId) == ["past", "current", "future"])
}

@Test func dashboardPresentationIdentifiesOnlyCanonicalMealEvents() throws {
  let schedule = dashboardSchedule(events: [
    dashboardEvent("breakfast", start: "07:30", end: "08:00", title: "Snídaně", kind: .meal),
    dashboardEvent("procedure", start: "09:00", end: "09:30", title: "Jodobromová koupel"),
    dashboardEvent("lunch", start: "12:00", end: "12:30", title: "Oběd", kind: .meal)
  ])
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:30:00")
  let presentation = CommanderDashboardPresentation.make(schedule: schedule, now: now)

  #expect(presentation.meals.map(\.event.stableId) == ["breakfast", "lunch"])
  #expect(presentation.meals.allSatisfy { $0.event.kind == .meal })
}

@Test func dashboardPresentationKeepsCanonicalLeaveAt() throws {
  let schedule = dashboardSchedule(events: [
    dashboardEvent("procedure", start: "09:00", end: "09:30", title: "Jodobromová koupel")
  ], lead: 20)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:30:00")
  let presentation = CommanderDashboardPresentation.make(schedule: schedule, now: now)
  let expected = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:40:00")

  #expect(presentation.currentEvent?.leaveAt == expected)
  #expect(presentation.liveState.leaveAt == expected)
}

@Test func dashboardUnknownProcedureDoesNotCreateFalseIcon() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let iconMapURL = root.appendingPathComponent("assets/icons/lazensky-v1/icon-map.json")
  let iconMap = try JSONDecoder().decode(CommanderIconMap.self, from: Data(contentsOf: iconMapURL))
  let unknown = dashboardEvent(
    "unknown",
    start: "11:00",
    end: "11:30",
    title: "Speciální procedura XYZ"
  )

  #expect(iconMap.classify(unknown) == nil)
  #expect(iconMap.fallback.key == nil)
}

private func dashboardSchedule(events: [ScheduleEvent], lead: Int = 20) -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: events,
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: lead,
      procedureTypeOverrides: [:],
      mealOverrides: [:]
    )
  )
}

private func dashboardEvent(
  _ stableId: String,
  start: String,
  end: String,
  title: String,
  kind: ScheduleKind = .procedure
) -> ScheduleEvent {
  ScheduleEvent(
    stableId: stableId,
    date: "2026-08-20",
    start: start,
    end: end,
    title: title,
    location: kind == .meal ? "Jídelna" : "Balneo",
    kind: kind,
    procedureType: kind == .procedure ? title : nil,
    mealType: kind == .meal ? title : nil,
    leadTimeMinutes: nil
  )
}
#endif

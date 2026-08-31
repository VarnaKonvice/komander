#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func daySummaryDescribesStandardDayWithoutCountingMealsAsProcedures() throws {
  let schedule = summarySchedule(Array(summaryEvents().reversed()))
  let original = schedule
  let presentation = summaryPresentation(schedule, "08:30")
  let summary = presentation.daySummary
  #expect(summary.procedureCount == 2)
  #expect(summary.firstEventStartAt == summaryDate("07:30"))
  #expect(summary.lastEventStartAt == summaryDate("17:30"))
  #expect(summary.lastEventEndAt == summaryDate("18:00"))
  #expect(summary.lastProcedureEndAt == summaryDate("14:20"))
  #expect(summary.dinnerStartAt == summaryDate("17:30"))
  #expect(summary.freeBeforeDinner == DateInterval(start: summaryDate("14:20"), end: summaryDate("17:30")))
  #expect(summary.freeBeforeDinnerMinutes == 190)
  #expect(summary.dinnerContext == nil)
  #expect(summary.minutesUntilDinner == nil)
  #expect(presentation.timeline.map(\.event.stableId) == ["breakfast", "morning", "lunch", "afternoon", "dinner"])
  #expect(schedule == original)
}

@Test func lastProcedureEndUsesLatestEndNotLatestStartOrDinnerEnd() {
  let schedule = summarySchedule([
    summaryEvent("long", "09:00", "15:00"),
    summaryEvent("later", "14:00", "14:20"),
    summaryEvent("dinner", "17:30", "18:00", kind: .meal, type: "Večeře")
  ])
  let presentation = summaryPresentation(schedule, "14:30")
  #expect(presentation.daySummary.lastProcedureEndAt == summaryDate("15:00"))
  #expect(presentation.daySummary.freeBeforeDinnerMinutes == 150)
  #expect(presentation.daySummary.dinnerContext == nil)
  #expect(presentation.mode == .inProgress)
  #expect(presentation.currentEvent?.event.stableId == "long")
  #expect(presentation.nextEvent?.event.stableId == "dinner")
}

@Test func mealsOnlyDayHasNoInventedProcedureEndAndUsesNowForFreeTime() {
  let schedule = summarySchedule(summaryEvents().filter { $0.kind == .meal })
  let presentation = summaryPresentation(schedule, "14:00")
  let summary = presentation.daySummary
  #expect(summary.procedureCount == 0)
  #expect(summary.lastProcedureEndAt == nil)
  #expect(summary.dinnerContext == .noProcedures)
  #expect(summary.minutesUntilDinner == 210)
  #expect(summary.freeBeforeDinner?.start == summaryDate("14:00"))
  #expect(summary.freeBeforeDinnerMinutes == 210)
  #expect(presentation.timeline.count == 3)
  #expect(presentation.meals.count == 3)
  #expect(presentation.currentEvent?.event.stableId == "dinner")
}

@Test func noDinnerMeansNoDinnerGapOrEveningContext() {
  let schedule = summarySchedule(summaryEvents().filter { $0.stableId != "dinner" })
  let summary = summaryPresentation(schedule, "15:00").daySummary
  #expect(summary.procedureCount == 2)
  #expect(summary.lastProcedureEndAt == summaryDate("14:20"))
  #expect(summary.dinnerStartAt == nil)
  #expect(summary.freeBeforeDinner == nil)
  #expect(summary.freeBeforeDinnerMinutes == nil)
  #expect(summary.dinnerContext == nil)
  #expect(summary.minutesUntilDinner == nil)
}

@Test func followingCardsContainTwoFutureEventsNotTheHero() {
  let presentation = summaryPresentation(summarySchedule(summaryEvents()), "08:30")
  #expect(presentation.mode == .upcoming)
  #expect(presentation.currentEvent?.event.stableId == "morning")
  #expect(presentation.nextEvent?.event.stableId == "lunch")
  #expect(presentation.thenEvent?.event.stableId == "afternoon")
  #expect(presentation.nextEvent?.phase == .future)
  #expect(presentation.thenEvent?.phase == .future)
}

@Test func inProgressHeroHasTwoDistinctFutureEvents() {
  let presentation = summaryPresentation(summarySchedule(summaryEvents()), "09:15")
  #expect(presentation.mode == .inProgress)
  #expect(presentation.currentEvent?.event.stableId == "morning")
  #expect(presentation.nextEvent?.event.stableId == "lunch")
  #expect(presentation.thenEvent?.event.stableId == "afternoon")
  #expect(presentation.timeline.map(\.phase) == [.past, .current, .future, .future, .future])
}

@Test func followingCardsSkipPastAndOverlappingCurrentEventsWithoutDeletingTimeline() {
  let schedule = summarySchedule([
    summaryEvent("hero", "09:00", "12:00"),
    summaryEvent("past", "09:30", "10:00"),
    summaryEvent("overlap", "10:00", "11:30"),
    summaryEvent("next", "12:00", "12:30"),
    summaryEvent("then", "14:00", "14:30")
  ])
  let presentation = summaryPresentation(schedule, "11:00")
  #expect(presentation.currentEvent?.event.stableId == "hero")
  #expect(presentation.nextEvent?.event.stableId == "next")
  #expect(presentation.thenEvent?.event.stableId == "then")
  #expect(presentation.timeline.map(\.phase) == [.current, .past, .current, .future, .future])
  #expect(presentation.timeline.count == schedule.events.count)
}

@Test func afterLastProcedureShowsEndedContextAndRemainingDinnerTime() {
  let schedule = summarySchedule(summaryEvents())
  let exactEnd = summaryPresentation(schedule, "14:20")
  #expect(exactEnd.daySummary.dinnerContext == .proceduresEnded)
  #expect(exactEnd.daySummary.minutesUntilDinner == 190)
  let later = summaryPresentation(schedule, "15:00")
  #expect(later.daySummary.dinnerContext == .proceduresEnded)
  #expect(later.daySummary.lastProcedureEndAt == summaryDate("14:20"))
  #expect(later.daySummary.minutesUntilDinner == 150)
  #expect(later.daySummary.freeBeforeDinnerMinutes == 190)
  #expect(later.mode == .upcoming)
  #expect(later.currentEvent?.event.stableId == "dinner")
  #expect(later.nextEvent == nil)
  #expect(later.thenEvent == nil)
}

@Test func dinnerBoundaryAndDayDoneAreStillDeterminedByExistingLiveState() {
  let schedule = summarySchedule(summaryEvents())
  for (time, mode) in [("17:10", CommanderDashboardMode.leaveNow), ("17:30", .inProgress), ("18:00", .dayDone)] {
    let presentation = summaryPresentation(schedule, time)
    #expect(presentation.mode == mode)
    #expect(presentation.liveState == CommanderLiveStateCalculator.compute(schedule: schedule, now: summaryDate(time)))
    #expect(presentation.timeline.count == 5)
    if time != "17:10" {
      #expect(presentation.daySummary.dinnerContext == nil)
      #expect(presentation.daySummary.minutesUntilDinner == nil)
      #expect(presentation.daySummary.freeBeforeDinner == nil)
    }
  }
  let done = summaryPresentation(schedule, "20:00")
  #expect(done.mode == .dayDone)
  #expect(done.currentEvent == nil)
  #expect(done.nextEvent == nil)
  #expect(done.thenEvent == nil)
  #expect(done.timeline.allSatisfy { $0.phase == .past })
  #expect(done.meals.count == 3)
  #expect(done.daySummary.procedureCount == 2)
}

@Test func futureEventAfterDinnerIsNotHiddenByAnEveningRule() {
  let schedule = summarySchedule(summaryEvents() + [summaryEvent("evening", "19:00", "19:30")])
  let presentation = summaryPresentation(schedule, "18:15")
  #expect(presentation.mode == .upcoming)
  #expect(presentation.currentEvent?.event.stableId == "evening")
  #expect(presentation.daySummary.lastProcedureEndAt == summaryDate("19:30"))
  #expect(presentation.daySummary.dinnerContext == nil)
  #expect(presentation.timeline.count == 6)
}

@Test func followingLeaveTimesUseContractOverridesIncludingZero() throws {
  let schedule = summarySchedule(summaryEvents())
  let overrides = LeadTimeOverrides(procedureTypeOverrides: ["Koupel": 35], mealOverrides: ["Oběd": 5], eventOverrides: ["afternoon": 0])
  let baseline = CommanderDashboardPresentation.make(schedule: schedule, now: summaryDate("08:30"))
  let presentation = CommanderDashboardPresentation.make(schedule: schedule, now: summaryDate("08:30"), overrides: overrides)
  let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
  for item in [presentation.currentEvent!, presentation.nextEvent!, presentation.thenEvent!] {
    let alarm = payload.alarms.first { $0.stableId == item.event.stableId }!
    #expect(item.leaveAt == (try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)))
  }
  #expect(presentation.liveState == CommanderLiveStateCalculator.compute(schedule: schedule, now: summaryDate("08:30"), overrides: overrides))
  #expect(presentation.nextEvent?.leaveAt == summaryDate("11:55"))
  #expect(presentation.thenEvent?.leaveAt == summaryDate("14:00"))
  #expect(presentation.nextEvent?.leaveAt != baseline.nextEvent?.leaveAt)
  #expect(presentation.thenEvent?.leaveAt != baseline.thenEvent?.leaveAt)
  #expect(presentation.daySummary == baseline.daySummary)
}

@Test func dinnerClassificationPrefersMealTypeAndNeverClassifiesAProcedureAsDinner() {
  for (title, type) in [("TEST - jídlo", Optional("Večeře")), (" veČEŘe ", nil), ("Jídlo", Optional("vecere"))] {
    let event = summaryEvent("meal", "17:30", "18:00", kind: .meal, type: type, title: title)
    #expect(summaryPresentation(summarySchedule([event]), "15:00").daySummary.dinnerStartAt == summaryDate("17:30"))
  }
  let nonDinner = summarySchedule([
    summaryEvent("procedure", "17:30", "18:00", title: "Večeře"),
    summaryEvent("lunch", "12:00", "12:45", kind: .meal, type: "Oběd", title: "Večeře")
  ])
  #expect(summaryPresentation(nonDinner, "11:00").daySummary.dinnerStartAt == nil)
}

@Test func freeDinnerGapDoesNotIncludeAnInterveningMealOrOverlap() {
  let dinner = summaryEvent("dinner", "17:30", "18:00", kind: .meal, type: "Večeře")
  let schedule = summarySchedule([
    summaryEvent("procedure", "10:00", "10:30"),
    summaryEvent("lunch", "12:00", "13:00", kind: .meal, type: "Oběd"), dinner
  ])
  let summary = summaryPresentation(schedule, "11:00").daySummary
  #expect(summary.freeBeforeDinner?.start == summaryDate("13:00"))
  #expect(summary.freeBeforeDinnerMinutes == 270)
  let overlapping = summarySchedule([summaryEvent("procedure", "17:00", "18:00"), dinner])
  let overlap = summaryPresentation(overlapping, "15:00").daySummary
  #expect(overlap.freeBeforeDinner == nil)
  #expect(overlap.dinnerContext == nil)
}

@Test func noScheduleAndUnsynchronizedDoNotInventTodaysMetadata() {
  let tomorrow = ScheduleEvent(stableId: "tomorrow", date: "2026-08-21", start: "17:30", end: "18:00", title: "Večeře", location: "Jídelna", kind: .meal, procedureType: nil, mealType: "Večeře", leadTimeMinutes: nil)
  let noSchedule = summaryPresentation(summarySchedule([tomorrow]), "10:00")
  #expect(noSchedule.mode == .noSchedule)
  #expect(noSchedule.daySummary.procedureCount == 0)
  #expect(noSchedule.daySummary.firstEventStartAt == nil)
  #expect(noSchedule.daySummary.lastEventEndAt == nil)
  #expect(noSchedule.daySummary.dinnerStartAt == nil)
  #expect(noSchedule.thenEvent == nil)
  let unsynchronized = CommanderDashboardPresentation.make(schedule: nil, now: summaryDate("10:00"))
  #expect(unsynchronized.mode == .unsynchronized)
  #expect(unsynchronized.daySummary == noSchedule.daySummary)
}

private func summaryPresentation(_ schedule: Schedule, _ time: String) -> CommanderDashboardPresentation {
  CommanderDashboardPresentation.make(schedule: schedule, now: summaryDate(time))
}

private func summaryDate(_ time: String) -> Date {
  try! NativeAlarmContract.dateTime(date: "2026-08-20", time: time)
}

private func summarySchedule(_ events: [ScheduleEvent]) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: "2026-08-20T00:00:00Z", stay: [:], events: events,
           settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:]))
}

private func summaryEvents() -> [ScheduleEvent] {
  [summaryEvent("breakfast", "07:30", "08:00", kind: .meal, type: "Snídaně"),
   summaryEvent("morning", "09:00", "09:30"),
   summaryEvent("lunch", "12:00", "12:45", kind: .meal, type: "Oběd"),
   summaryEvent("afternoon", "14:00", "14:20"),
   summaryEvent("dinner", "17:30", "18:00", kind: .meal, type: "Večeře")]
}

private func summaryEvent(_ id: String, _ start: String, _ end: String, kind: ScheduleKind = .procedure, type: String? = "Koupel", title: String? = nil) -> ScheduleEvent {
  ScheduleEvent(stableId: id, date: "2026-08-20", start: start, end: end, title: title ?? type ?? id,
                location: kind == .meal ? "Jídelna" : "Balneo", kind: kind,
                procedureType: kind == .procedure ? type : nil, mealType: kind == .meal ? type : nil,
                leadTimeMinutes: nil)
}

#endif

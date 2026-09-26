#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func liveActivityPlanStartsAnHourBeforeBreakfastAndCarriesNearbyProcedure() throws {
  let schedule = try liveActivitySchedule()
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T05:30:00")
  let plan = try #require(CommanderLiveActivityPlan.make(schedule: schedule, payload: payload, now: now))

  let expectedActivation = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T06:30:00")
  let expectedWindowEnd = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T08:40:00")
  #expect(plan.anchorStableID == "meal-breakfast")
  #expect(plan.activationStart == expectedActivation)
  #expect(plan.windowEnd == expectedWindowEnd)
  #expect(plan.includedStableIDs == ["meal-breakfast", "proc-morning"])
}

@Test func liveActivityPlanCreatesSuccessorWindowsAcrossLongFreeGaps() throws {
  let schedule = try liveActivitySchedule()
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T05:30:00")
  let plans = CommanderLiveActivityPlan.makeWindows(schedule: schedule, payload: payload, now: now)

  #expect(plans.map(\.anchorStableID) == [
    "meal-breakfast", "meal-lunch", "meal-dinner"
  ])
  #expect(plans.map(\.includedStableIDs) == [
    ["meal-breakfast", "proc-morning"],
    ["meal-lunch", "proc-afternoon"],
    ["meal-dinner"]
  ])
  let dinnerActivation = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T16:30:00")
  #expect(plans[2].activationStart == dinnerActivation)
}

@Test func liveActivityPlanKeepsMorningAnchorWhileItsWindowIsStillRunning() throws {
  let schedule = try liveActivitySchedule()
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T07:50:00")
  let plan = try #require(CommanderLiveActivityPlan.make(schedule: schedule, payload: payload, now: now))

  #expect(plan.anchorStableID == "meal-breakfast")
  #expect(plan.includedStableIDs == ["meal-breakfast", "proc-morning"])
}

@Test func liveActivityPlanFallsForwardAfterMorningWindowEnds() throws {
  let schedule = try liveActivitySchedule()
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T10:00:00")
  let plan = try #require(CommanderLiveActivityPlan.make(schedule: schedule, payload: payload, now: now))

  let expectedActivation = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T11:00:00")
  #expect(plan.anchorStableID == "meal-lunch")
  #expect(plan.activationStart == expectedActivation)
  #expect(plan.includedStableIDs == ["meal-lunch", "proc-afternoon"])
}

@Test func liveActivityPlanCreatesMealOnlyWindow() throws {
  let schedule = Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-09-26T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "meal-only", date: "2026-09-26", start: "12:00", end: "12:30",
        title: "Oběd", location: "Jídelna", kind: .meal,
        procedureType: nil, mealType: "Oběd", leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:])
  )
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T09:00:00")
  let plan = try #require(CommanderLiveActivityPlan.make(schedule: schedule, payload: payload, now: now))

  let expectedActivation = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T11:00:00")
  #expect(plan.anchorStableID == "meal-only")
  #expect(plan.activationStart == expectedActivation)
}

@Test func liveActivityPlanStartsByEarlierOverrideAdjustedLeaveAt() throws {
  let schedule = Schedule(
    schemaVersion: 1,
    scheduleVersion: 2,
    updatedAt: "2026-09-26T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "proc", date: "2026-09-26", start: "08:20", end: "08:40",
        title: "Magnetoterapie", location: "Budova A", kind: .procedure,
        procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:])
  )
  let overrides = LeadTimeOverrides(eventOverrides: ["proc": 90])
  let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T05:30:00")
  let plan = try #require(CommanderLiveActivityPlan.make(schedule: schedule, payload: payload, now: now))

  let expectedActivation = try NativeAlarmContract.date(fromLocalISO: "2026-09-26T06:50:00")
  #expect(plan.activationStart == expectedActivation)
}

private func liveActivitySchedule() throws -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 9,
    updatedAt: "2026-09-26T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "meal-breakfast", date: "2026-09-26", start: "07:30", end: "08:00",
        title: "Snídaně", location: "Jídelna", kind: .meal,
        procedureType: nil, mealType: "Snídaně", leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "proc-morning", date: "2026-09-26", start: "08:20", end: "08:40",
        title: "Magnetoterapie", location: "Budova A", kind: .procedure,
        procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "meal-lunch", date: "2026-09-26", start: "12:00", end: "12:30",
        title: "Oběd", location: "Jídelna", kind: .meal,
        procedureType: nil, mealType: "Oběd", leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "proc-afternoon", date: "2026-09-26", start: "14:30", end: "15:00",
        title: "Bazén", location: "Bazén", kind: .procedure,
        procedureType: "Bazén", mealType: nil, leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "meal-dinner", date: "2026-09-26", start: "17:30", end: "18:00",
        title: "Večeře", location: "Jídelna", kind: .meal,
        procedureType: nil, mealType: "Večeře", leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:])
  )
}
#endif

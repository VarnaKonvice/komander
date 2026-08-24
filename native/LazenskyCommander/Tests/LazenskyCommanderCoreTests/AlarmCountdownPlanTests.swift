#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func alarmCountdownPlanSchedulesWindowSoItEndsAtLeaveAt() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "first" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
  let expectedStart = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:10:00")

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledStartAt == expectedStart)
  #expect(plan.duration == 30 * 60)
  #expect(plan.scheduledStartAt?.addingTimeInterval(plan.duration) == leaveAt)
}

@Test func alarmCountdownPlanStartsImmediatelyWhenSyncHappensInsideWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "first" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:25:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledStartAt == nil)
  #expect(plan.duration == 15 * 60)
  #expect(now.addingTimeInterval(plan.duration) == leaveAt)
}

@Test func alarmCountdownPlanUsesPreviousEventEndForNextActivityWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "next" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
  let expectedStart = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:30:00")

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledStartAt == expectedStart)
  #expect(plan.duration == 10 * 60)
  #expect(plan.scheduledStartAt?.addingTimeInterval(plan.duration) == leaveAt)
}

private func countdownTestSchedule() -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "first",
        date: "2026-08-20",
        start: "10:00",
        end: "10:30",
        title: "Jodobromová koupel",
        location: "Bazén",
        kind: .procedure,
        procedureType: "Jodobromová koupel",
        mealType: nil,
        leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "next",
        date: "2026-08-20",
        start: "10:00",
        end: "10:30",
        title: "Masáž",
        location: "Rehabilitace",
        kind: .procedure,
        procedureType: "Masáž",
        mealType: nil,
        leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 20,
      procedureTypeOverrides: [:],
      mealOverrides: [:]
    )
  )
}
#endif

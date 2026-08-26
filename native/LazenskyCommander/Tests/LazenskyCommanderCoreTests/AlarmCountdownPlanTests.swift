#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func alarmCountdownPlanKeepsAlertAtLeaveAtAndUsesThirtyMinuteWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "first" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 30 * 60)
}

@Test func alarmCountdownPlanShortensWindowWhenSyncHappensInsideWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "first" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:25:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 15 * 60)
  #expect(now.addingTimeInterval(plan.countdownWindow) == leaveAt)
}

@Test func alarmCountdownPlanUsesPreviousEventEndForNextActivityWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "next" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 10 * 60)
}

@Test func alarmCountdownPlanHasZeroWindowForBackToBackHandoffButStillAlertsAtLeaveAt() throws {
  let schedule = backToBackCountdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "next" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 0)
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
        start: "09:00",
        end: "09:30",
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

private func backToBackCountdownTestSchedule() -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "current",
        date: "2026-08-20",
        start: "10:00",
        end: "10:30",
        title: "Jodobromová koupel",
        location: "Bazén",
        kind: .procedure,
        procedureType: "Jodobromová koupel",
        mealType: nil,
        leadTimeMinutes: 15
      ),
      ScheduleEvent(
        stableId: "next",
        date: "2026-08-20",
        start: "10:45",
        end: "11:00",
        title: "Masáž",
        location: "Rehabilitace",
        kind: .procedure,
        procedureType: "Masáž",
        mealType: nil,
        leadTimeMinutes: 15
      )
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 15,
      procedureTypeOverrides: [:],
      mealOverrides: [:]
    )
  )
}
#endif

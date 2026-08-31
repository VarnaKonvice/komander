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
  #expect(plan.scheduledStartAt == leaveAt.addingTimeInterval(-30 * 60))
  #expect(plan.scheduledStartAt?.addingTimeInterval(plan.countdownWindow) == leaveAt)
}

@Test func alarmCountdownPlanShortensWindowWhenSyncHappensInsideWindow() throws {
  let schedule = countdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "first" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T08:25:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 15 * 60)
  #expect(plan.scheduledStartAt == nil)
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
  #expect(plan.scheduledStartAt == leaveAt.addingTimeInterval(-10 * 60))
}

@Test func alarmCountdownPlanHasZeroWindowForBackToBackHandoffButStillAlertsAtLeaveAt() throws {
  let schedule = backToBackCountdownTestSchedule()
  let alarm = try NativeAlarmContract.payload(schedule: schedule).alarms.first(where: { $0.stableId == "next" })!
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T10:00:00")
  let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)

  let plan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)

  #expect(plan.scheduledAlertAt == leaveAt)
  #expect(plan.countdownWindow == 0)
  #expect(plan.scheduledStartAt == nil)
}

@Test func countdownWindowBoundaryStartsImmediatelyAndExpiredDeadlineHasNoCountdown() {
  let leaveAt = Date(timeIntervalSince1970: 10_000)
  for remaining in [300.0, 1.0, 0.0, -1.0] {
    let now = leaveAt.addingTimeInterval(-remaining)
    let plan = AlarmCountdown.plan(leaveAt: leaveAt, countdownWindow: 300, now: now)
    #expect(plan.scheduledStartAt == nil)
    #expect(plan.countdownWindow == max(0, remaining))
    #expect(plan.scheduledAlertAt == leaveAt)
  }
}

@Test func readbackUsesCountdownEndpointNotRawFixedScheduleOrDesiredMetadata() {
  let start = Date(timeIntervalSince1970: 10_000)
  let observed = start.addingTimeInterval(301)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: start, preAlert: 300, countdownFireDate: nil) == start.addingTimeInterval(300))
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: start, preAlert: nil, countdownFireDate: nil) == start)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: start, preAlert: 0, countdownFireDate: nil) == start)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: start, preAlert: 300, countdownFireDate: observed) == observed)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: nil, preAlert: 300, countdownFireDate: observed) == observed)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: nil, preAlert: 300, countdownFireDate: nil) == nil)
  #expect(AlarmCountdown.effectiveAlertDate(fixedScheduleAt: start, preAlert: -1, countdownFireDate: nil) == nil)
}

@Test func editableLeadTimeMovesLeaveAtForFifteenTwentyAndThirtyMinutes() throws {
  let schedule = countdownTestSchedule()

  for (minutes, expectedLeaveAt) in [
    (15, "2026-08-20T08:45:00"),
    (20, "2026-08-20T08:40:00"),
    (30, "2026-08-20T08:30:00")
  ] {
    let overrides = LeadTimeOverrides(defaultLeadTimeMinutes: minutes)
    let alarm = try NativeAlarmContract.payload(
      schedule: schedule,
      overrides: overrides
    ).alarms.first(where: { $0.stableId == "first" })!

    #expect(alarm.effectiveLeadTimeMinutes == minutes)
    #expect(alarm.leaveAt == expectedLeaveAt)
  }
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

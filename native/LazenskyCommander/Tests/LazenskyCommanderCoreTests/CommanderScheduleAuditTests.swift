import Testing
@testable import LazenskyCommanderCore

struct CommanderScheduleAuditTests {
  @Test func stayLengthIsDerivedFromDatesAndSupportsExtensions() {
    let report28 = CommanderScheduleAudit.run(schedule(from: "2026-09-01", to: "2026-09-28", events: []))
    #expect(report28.stayDayCount == 28)

    let report35 = CommanderScheduleAudit.run(schedule(from: "2026-09-01", to: "2026-10-05", events: []))
    #expect(report35.stayDayCount == 35)
  }

  @Test func eventOutsideStayIsBlockingError() {
    let event = makeEvent(id: "outside", date: "2026-09-29", start: "09:00", end: "09:30", title: "Masáž")
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-01", to: "2026-09-28", events: [event]))
    #expect(report.issues.contains { $0.code == "event-outside-stay" && $0.severity == .error })
  }

  @Test func semanticDuplicateIsDetectedEvenWithDifferentStableIds() {
    let first = makeEvent(id: "a", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž")
    let second = makeEvent(id: "b", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž")
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-01", to: "2026-09-03", events: [first, second]))
    #expect(report.issues.contains { $0.code == "semantic-duplicate" && $0.severity == .error })
  }

  @Test func overlapAndEmptyStayDaysRequireReview() {
    let first = makeEvent(id: "a", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž")
    let second = makeEvent(id: "b", date: "2026-09-02", start: "09:20", end: "09:50", title: "Ergoterapie")
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-01", to: "2026-09-03", events: [first, second]))
    #expect(report.issues.contains { $0.code == "overlap-review" && $0.severity == .warning })
    #expect(report.issues.filter { $0.code == "day-without-events" }.count == 2)
  }


  @Test func sundayOperationalPolicyExpectsMealsAndNoProcedures() {
    let sundayMeals = [
      meal(id: "sun.breakfast", date: "2026-09-06", start: "07:30", end: "08:00", title: "Snídaně"),
      meal(id: "sun.lunch", date: "2026-09-06", start: "12:00", end: "12:40", title: "Oběd"),
      meal(id: "sun.dinner", date: "2026-09-06", start: "17:30", end: "18:00", title: "Večeře")
    ]
    let report = CommanderScheduleAudit.run(
      schedule(from: "2026-09-06", to: "2026-09-06", events: sundayMeals),
      policy: .petrSpaOperational
    )
    #expect(!report.issues.contains { $0.code == "sunday-procedure-review" })
    #expect(!report.issues.contains { $0.code == "sunday-meals-review" })
  }

  @Test func saturdayBelowThreeProceduresIsReviewWarningNotBlockingError() {
    let events = [
      makeEvent(id: "sat.a", date: "2026-09-05", start: "09:00", end: "09:20", title: "Masáž"),
      makeEvent(id: "sat.b", date: "2026-09-05", start: "10:00", end: "10:20", title: "Magnetoterapie")
    ]
    let report = CommanderScheduleAudit.run(
      schedule(from: "2026-09-05", to: "2026-09-05", events: events),
      policy: .petrSpaOperational
    )
    #expect(report.issues.contains { $0.code == "low-procedure-count-review" && $0.severity == .warning })
    #expect(!report.hasErrors)
  }

  @Test func sundayProcedureOrMissingMealRequiresHumanReview() {
    let events = [
      meal(id: "sun.breakfast", date: "2026-09-06", start: "07:30", end: "08:00", title: "Snídaně"),
      makeEvent(id: "sun.proc", date: "2026-09-06", start: "10:00", end: "10:20", title: "Masáž")
    ]
    let report = CommanderScheduleAudit.run(
      schedule(from: "2026-09-06", to: "2026-09-06", events: events),
      policy: .petrSpaOperational
    )
    #expect(report.issues.contains { $0.code == "sunday-procedure-review" })
    #expect(report.issues.contains { $0.code == "sunday-meals-review" })
  }

  private func schedule(from: String, to: String, events: [ScheduleEvent]) -> Schedule {
    Schedule(
      schemaVersion: 1,
      scheduleVersion: 1,
      updatedAt: "2026-09-01T08:00:00Z",
      stay: ["dateFrom": from, "dateTo": to],
      events: events,
      settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
    )
  }

  private func meal(id: String, date: String, start: String, end: String, title: String) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id,
      date: date,
      start: start,
      end: end,
      title: title,
      location: "Jídelna",
      kind: .meal,
      procedureType: nil,
      mealType: title,
      leadTimeMinutes: nil
    )
  }

  private func makeEvent(id: String, date: String, start: String, end: String, title: String) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id,
      date: date,
      start: start,
      end: end,
      title: title,
      location: "Rehabilitace",
      kind: .procedure,
      procedureType: title,
      mealType: nil,
      leadTimeMinutes: nil
    )
  }
}

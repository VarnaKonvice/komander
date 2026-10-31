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
    #expect(report.issues.contains { $0.code == "procedure-overlap-review" && $0.severity == .warning })
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

  @Test func visitsAreReportedSeparatelyAndDoNotCountAsProcedures() {
    let events = [
      meal(id: "sun.breakfast", date: "2026-09-06", start: "07:30", end: "08:00", title: "Snídaně"),
      meal(id: "sun.lunch", date: "2026-09-06", start: "12:00", end: "12:40", title: "Oběd"),
      meal(id: "sun.dinner", date: "2026-09-06", start: "17:30", end: "18:00", title: "Večeře"),
      makeEvent(id: "sun.visit", date: "2026-09-06", start: "06:35", end: "06:40", title: "Vizita")
    ]
    let report = CommanderScheduleAudit.run(
      schedule(from: "2026-09-06", to: "2026-09-06", events: events),
      policy: .petrSpaOperational
    )

    #expect(report.eventCount == 4)
    #expect(report.procedureCount == 0)
    #expect(report.visitCount == 1)
    #expect(report.mealCount == 3)
    #expect(!report.issues.contains { $0.code == "sunday-procedure-review" })
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


  @Test func mealProcedureOverlapReportsRemainingMealWindowAndNeedsReview() {
    let events = [
      meal(id: "dinner", date: "2026-09-07", start: "17:30", end: "18:15", title: "Večeře"),
      makeEvent(id: "short.proc", date: "2026-09-07", start: "17:30", end: "17:40", title: "Magnetoterapie")
    ]
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-07", to: "2026-09-07", events: events))
    let issue = report.issues.first { $0.code == "meal-procedure-overlap-review" }
    #expect(issue != nil)
    #expect(issue?.message.contains("zbývá 35 z 45 min") == true)
    #expect(issue?.message.contains("čas přesunu není započítán") == true)
  }

  @Test func nestedProcedureOverlapsAreAllDetectedNotOnlyAdjacentEvents() {
    let events = [
      makeEvent(id: "long", date: "2026-09-07", start: "09:00", end: "11:00", title: "Fyzioterapie"),
      makeEvent(id: "short1", date: "2026-09-07", start: "09:15", end: "09:30", title: "Cvičení A"),
      makeEvent(id: "short2", date: "2026-09-07", start: "10:00", end: "10:15", title: "Cvičení B")
    ]
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-07", to: "2026-09-07", events: events))
    #expect(report.issues.filter { $0.code == "procedure-overlap-review" }.count == 2)
  }

  @Test func acknowledgedWarningRemainsAcceptedAcrossUnrelatedScheduleVersions() {
    let events = [
      makeEvent(id: "a", date: "2026-09-07", start: "09:00", end: "09:30", title: "Masáž"),
      makeEvent(id: "b", date: "2026-09-07", start: "09:20", end: "09:40", title: "Ergoterapie")
    ]
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-07", to: "2026-09-07", events: events))
    let warning = report.issues.first { $0.code == "procedure-overlap-review" }!
    let acknowledgement = CommanderScheduleAuditAcknowledgement(
      scheduleVersion: report.scheduleVersion - 1,
      reviewKey: warning.reviewKey,
      confirmedAt: "2026-09-07T08:00:00Z",
      note: "Záměrný souběh fyzioterapie"
    )
    let resolved = CommanderScheduleAuditReview.resolve(report: report, acknowledgements: [acknowledgement])
    #expect(resolved.openWarnings.isEmpty)
    #expect(resolved.acknowledgedWarnings.count == 1)
    #expect(resolved.canBeAccepted)

    let changedWarning = CommanderScheduleAuditIssue(
      severity: .warning,
      code: warning.code,
      message: warning.message + " Změněný kontext.",
      stableId: warning.stableId,
      date: warning.date
    )
    let changedReport = CommanderScheduleAuditReport(
      scheduleVersion: report.scheduleVersion + 1,
      stayFrom: report.stayFrom,
      stayTo: report.stayTo,
      stayDayCount: report.stayDayCount,
      eventCount: report.eventCount,
      procedureCount: report.procedureCount,
      visitCount: report.visitCount,
      mealCount: report.mealCount,
      issues: [changedWarning]
    )
    let unresolved = CommanderScheduleAuditReview.resolve(report: changedReport, acknowledgements: [acknowledgement])
    #expect(unresolved.openWarnings.count == 1)
    #expect(!unresolved.canBeAccepted)
  }

  @Test func operationalAcknowledgementSurvivesCountWordingChangeOnSameDay() {
    let original = CommanderScheduleAuditIssue(
      severity: .warning,
      code: "low-procedure-count-review",
      message: "Den má jen 2 procedur, provozní očekávání je alespoň 3; ověřit proti papíru nebo lékařské změně.",
      date: "2026-10-24"
    )
    let changed = CommanderScheduleAuditIssue(
      severity: .warning,
      code: "low-procedure-count-review",
      message: "Den má jen 1 procedur, provozní očekávání je alespoň 3; ověřit proti papíru nebo lékařské změně.",
      date: "2026-10-24"
    )
    let report = CommanderScheduleAuditReport(
      scheduleVersion: 14,
      stayFrom: "2026-09-30",
      stayTo: "2026-10-28",
      stayDayCount: 29,
      eventCount: 194,
      procedureCount: 82,
      visitCount: 28,
      mealCount: 84,
      issues: [changed]
    )
    let acknowledgement = CommanderScheduleAuditAcknowledgement(
      scheduleVersion: 13,
      reviewKey: original.reviewKey,
      confirmedAt: "2026-10-20T10:00:00Z"
    )

    let resolved = CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: [acknowledgement],
      operationalWarningsOnOrAfter: "2026-10-21"
    )
    #expect(resolved.openWarnings.isEmpty)
    #expect(resolved.acknowledgedWarnings == [changed])
  }

  @Test func elapsedOperationalWarningsStopRequestingConfirmation() {
    let past = CommanderScheduleAuditIssue(
      severity: .warning,
      code: "low-procedure-count-review",
      message: "Den má jen 2 procedur, provozní očekávání je alespoň 3; ověřit proti papíru nebo lékařské změně.",
      date: "2026-10-17"
    )
    let future = CommanderScheduleAuditIssue(
      severity: .warning,
      code: "low-procedure-count-review",
      message: "Den má jen 1 procedur, provozní očekávání je alespoň 3; ověřit proti papíru nebo lékařské změně.",
      date: "2026-10-24"
    )
    let report = CommanderScheduleAuditReport(
      scheduleVersion: 14,
      stayFrom: "2026-09-30",
      stayTo: "2026-10-28",
      stayDayCount: 29,
      eventCount: 194,
      procedureCount: 82,
      visitCount: 28,
      mealCount: 84,
      issues: [past, future]
    )

    let resolved = CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: [],
      operationalWarningsOnOrAfter: "2026-10-21"
    )
    #expect(resolved.openWarnings == [future])
  }

  @Test func acknowledgementCanNeverHideBlockingError() {
    let event = makeEvent(id: "outside", date: "2026-09-08", start: "09:00", end: "09:30", title: "Masáž")
    let report = CommanderScheduleAudit.run(schedule(from: "2026-09-07", to: "2026-09-07", events: [event]))
    let error = report.issues.first { $0.severity == .error }!
    let acknowledgement = CommanderScheduleAuditAcknowledgement(
      scheduleVersion: report.scheduleVersion,
      reviewKey: error.reviewKey,
      confirmedAt: "2026-09-07T08:00:00Z"
    )
    let resolved = CommanderScheduleAuditReview.resolve(report: report, acknowledgements: [acknowledgement])
    #expect(!resolved.errors.isEmpty)
    #expect(!resolved.canBeAccepted)
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

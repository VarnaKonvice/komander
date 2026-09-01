#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func weekOrdersEveryDayAndUsesStableTieBreaksWithoutMutatingSchedule() throws {
  let schedule = overviewSchedule(events: [
    overviewEvent("last", date: "2026-08-29"),
    overviewEvent("z", start: "10:00", end: "10:30"),
    overviewEvent("early-end", start: "10:00", end: "10:15"),
    overviewEvent("a", start: "10:00", end: "10:30"),
    overviewEvent("first", date: "2026-08-19"),
    overviewEvent("morning", start: "08:00", end: "08:30")
  ])
  let original = schedule
  let days = try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow())
  #expect(days.map { $0.events.first!.event.date } == ["2026-08-19", "2026-08-20", "2026-08-29"])
  #expect(days[1].events.map(\.event.stableId) == ["morning", "early-end", "a", "z"])
  #expect(days[1].summary.procedureCount == 4)
  #expect(days[1].summary.firstEventStartAt == (try overviewNow("2026-08-20T08:00:00")))
  #expect(days[1].summary.lastEventEndAt == (try overviewNow("2026-08-20T10:30:00")))
  #expect(schedule == original)
}

@Test func weekLeaveAtMatchesContractDashboardAndAllOverridePriorities() throws {
  let schedule = overviewSchedule(events: [
    overviewEvent("meal", start: "07:30", end: "08:00", kind: .meal, type: "Snídaně", lead: 12),
    overviewEvent("procedure", start: "09:00", end: "09:30", type: "Koupel", lead: 25)
  ])
  let cases: [LeadTimeOverrides?] = [
    nil,
    LeadTimeOverrides(defaultLeadTimeMinutes: 0),
    LeadTimeOverrides(defaultLeadTimeMinutes: 8, procedureTypeOverrides: ["Koupel": 30], mealOverrides: ["Snídaně": 5]),
    LeadTimeOverrides(defaultLeadTimeMinutes: 8, procedureTypeOverrides: ["Koupel": 30], mealOverrides: ["Snídaně": 5], eventOverrides: ["procedure": 0, "meal": 3])
  ]
  for overrides in cases {
    let now = try overviewNow("2026-08-20T07:00:00")
    let week = try CommanderWeekPresentation.make(schedule: schedule, now: now, overrides: overrides)
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    let dashboard = CommanderDashboardPresentation.make(schedule: schedule, now: now, overrides: overrides)
    #expect(week[0].events == dashboard.timeline)
    for item in week[0].events {
      let alarm = payload.alarms.first { $0.stableId == item.event.stableId }!
      #expect(item.leaveAt == (try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)))
    }
  }
  let zero = try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow(), overrides: cases[1])
  #expect(zero[0].events.allSatisfy { $0.leaveAt == $0.startAt })
}

@Test func weekDepartureCanBelongToPreviousDayAndScheduleTypeOverridesApply() throws {
  let schedule = overviewSchedule(events: [
    overviewEvent("midnight", start: "00:10", end: "00:30", type: "Koupel")
  ])
  let days = try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow())
  #expect(days[0].date == (try overviewNow("2026-08-20T00:00:00")))
  #expect(days[0].events[0].leaveAt == (try overviewNow("2026-08-19T23:40:00")))
}

@Test func weekBuildsCollapsedSummariesForEveryStayDay() throws {
  let schedule = overviewSchedule(stay: ["dateFrom": "2026-08-20", "dateTo": "2026-08-22"], events: [
    overviewEvent("breakfast", start: "07:30", end: "08:00", kind: .meal, type: "Snídaně"),
    overviewEvent("procedure", start: "09:00", end: "09:30", type: "Koupel"),
    overviewEvent("last-day", date: "2026-08-22", start: "10:00", end: "10:30", type: "Masáž")
  ])

  let days = try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow("2026-08-20T06:00:00"))

  #expect(days.map { CommanderDateText.numericDate($0.date) } == ["20. 8. 2026", "21. 8. 2026", "22. 8. 2026"])
  #expect(days.map { $0.events.map(\.event.stableId) } == [["breakfast", "procedure"], [], ["last-day"]])
  #expect(days.map(\.summary.procedureCount) == [1, 0, 1])
  #expect(days.map(\.overview.procedureCount) == [1, 0, 1])
  #expect(days[0].overview.procedureEndAt == (try overviewNow("2026-08-20T09:30:00")))
  #expect(days[1].overview.procedureEndAt == nil)
  #expect(days[0].summary.firstEventStartAt == (try overviewNow("2026-08-20T07:30:00")))
  #expect(days[0].summary.lastEventEndAt == (try overviewNow("2026-08-20T09:30:00")))
  #expect(days[1].summary.firstEventStartAt == nil)
  #expect(days[1].summary.lastEventEndAt == nil)
}

@Test func stayCountsOnlyEndedProceduresAndGroupsByTypeOrTitle() throws {
  let schedule = overviewSchedule(events: [
    overviewEvent("past", start: "08:00", end: "08:20", title: "První koupel", type: "Koupel"),
    overviewEvent("ongoing", title: "Druhá koupel", type: "Koupel"),
    overviewEvent("future", date: "2026-08-21", title: "Speciální procedura", type: nil),
    overviewEvent("blank-type", date: "2026-08-21", title: "Speciální procedura", type: "  "),
    overviewEvent("meal", start: "07:00", end: "07:30", kind: .meal, type: "Snídaně")
  ])
  let summary = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow("2026-08-20T09:15:00"))
  #expect(summary.totalProcedures == 4)
  #expect(summary.completedProcedures == 1)
  #expect(summary.procedures.map(\.name) == ["Koupel", "Speciální procedura"])
  #expect(summary.procedures.map(\.total) == [2, 2])
  #expect(summary.procedures.map(\.completed) == [1, 0])
  #expect(summary.procedures.map(\.representativeEvent.stableId) == ["past", "future"])
  let atEnd = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow("2026-08-20T09:30:00"))
  #expect(atEnd.completedProcedures == 2)
}

@Test func stayPeriodIsInclusiveAndDoesNotInventCurrentDayOutsideStay() throws {
  let schedule = overviewSchedule(stay: ["dateFrom": "2026-08-20", "dateTo": "2026-08-22"])
  let cases: [(String, CommanderStayPhase, Int?)] = [
    ("2026-08-19T23:59:00", .upcoming, nil),
    ("2026-08-20T00:00:00", .active, 1),
    ("2026-08-21T12:00:00", .active, 2),
    ("2026-08-22T23:59:00", .active, 3),
    ("2026-08-23T00:00:00", .finished, nil)
  ]
  for (time, phase, currentDay) in cases {
    let summary = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow(time))
    #expect(summary.period?.totalDays == 3)
    #expect(summary.period?.phase == phase)
    #expect(summary.period?.currentDay == currentDay)
  }
}

@Test func stayUsesPragueCalendarDaysAcrossDSTAndForSingleDayStay() throws {
  for (from, to, now, total, day) in [
    ("2026-03-28", "2026-03-30", "2026-03-29T23:30:00", 3, 2),
    ("2026-10-24", "2026-10-26", "2026-10-25T23:30:00", 3, 2),
    ("2026-08-20", "2026-08-20", "2026-08-20T23:59:00", 1, 1)
  ] {
    let schedule = overviewSchedule(stay: ["dateFrom": from, "dateTo": to])
    let summary = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow(now))
    #expect(summary.period?.totalDays == total)
    #expect(summary.period?.currentDay == day)
  }
}

@Test func missingInvalidOrReversedStayDatesAreNotInferredFromEvents() throws {
  for metadata in [[:], ["dateFrom": "2026-08-20"], ["dateTo": "2026-08-20"],
                   ["dateFrom": "2026-02-30", "dateTo": "2026-08-20"],
                   ["dateFrom": "2026-08-22", "dateTo": "2026-08-20"]] {
    let schedule = overviewSchedule(stay: metadata, events: [overviewEvent("known-event")])
    let summary = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow())
    #expect(summary.period == nil)
    #expect(summary.totalProcedures == 1)
  }
}

@Test func infoKeepsCanonicalMetadataAndOmitsOnlyMissingOrBlankValues() {
  let stay = ["spa": "Lázně", "dateFrom": "2026-08-20", "dateTo": "2026-08-22", "room": "208", "doctor": "MUDr. Test", "mealShift": "II. směna", "contact": "Recepce", "empty": "  "]
  let fields = CommanderInfoPresentation.fields(stay: stay)
  #expect(fields.map(\.key) == ["spa", "dateFrom", "dateTo", "room", "doctor", "mealShift", "contact"])
  #expect(fields.first { $0.key == "dateFrom" }?.value == "20. 8. 2026")
  #expect(fields.first { $0.key == "dateTo" }?.value == "22. 8. 2026")
  #expect(fields.first { $0.key == "room" }?.value == "208")
  #expect(fields.first { $0.key == "doctor" }?.value == "MUDr. Test")
  #expect(CommanderInfoPresentation.fields(stay: [:]).isEmpty)
  #expect(CommanderInfoPresentation.fields(stay: ["room": "208"]).map(\.key) == ["room"])
}

@Test func commanderDateTextUsesShortCzechNumericDates() throws {
  let date = try overviewNow("2026-08-31T12:00:00")
  #expect(CommanderDateText.shortDay(date) == "Po 31. 8.")
  #expect(CommanderDateText.numericDate(date) == "31. 8. 2026")
  #expect(CommanderDateText.numericDate(isoDate: "2026-08-15") == "15. 8. 2026")
  #expect(CommanderDateText.numericDate(isoDate: "2026-02-30") == nil)
}

@Test func emptyScheduleHasNoWeekEventsOrProcedures() throws {
  let schedule = overviewSchedule()
  #expect(try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow()).isEmpty)
  let stay = try CommanderStayPresentation.make(schedule: schedule, now: overviewNow())
  #expect(stay.totalProcedures == 0)
  #expect(stay.completedProcedures == 0)
  #expect(stay.procedures.isEmpty)
}

@Test func invalidScheduleIsReportedInsteadOfPartiallyPresented() throws {
  let duplicate = overviewEvent("duplicate")
  let schedule = overviewSchedule(events: [duplicate, duplicate])
  #expect(throws: ScheduleValidationError.self) {
    try CommanderWeekPresentation.make(schedule: schedule, now: overviewNow())
  }
  #expect(throws: ScheduleValidationError.self) {
    try CommanderStayPresentation.make(schedule: schedule, now: overviewNow())
  }
}

private func overviewNow(_ value: String = "2026-08-20T08:00:00") throws -> Date {
  try NativeAlarmContract.date(fromLocalISO: value)
}

private func overviewSchedule(stay: [String: String] = [:], events: [ScheduleEvent] = []) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: "2026-08-20T00:00:00Z", stay: stay, events: events,
           settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: ["Koupel": 30], mealOverrides: ["Snídaně": 15]))
}

private func overviewEvent(
  _ id: String, date: String = "2026-08-20", start: String = "09:00", end: String = "09:30",
  title: String = "Procedura", kind: ScheduleKind = .procedure, type: String? = "Koupel", lead: Int? = nil
) -> ScheduleEvent {
  ScheduleEvent(stableId: id, date: date, start: start, end: end, title: title,
                location: kind == .meal ? "Jídelna" : "Balneo", kind: kind,
                procedureType: kind == .procedure ? type : nil,
                mealType: kind == .meal ? type : nil, leadTimeMinutes: lead)
}
#endif

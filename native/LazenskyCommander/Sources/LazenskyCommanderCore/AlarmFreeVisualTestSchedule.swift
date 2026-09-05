#if DEBUG
import Foundation

public enum AlarmFreeVisualTestSchedule {
  public static let stableIDPrefix = "alarm-free-visual-"

  private struct ProcedureTemplate {
    let title: String
    let location: String
  }

  private static let prague = TimeZone(identifier: "Europe/Prague")!
  private static let procedures = [
    ProcedureTemplate(title: "Slatinná koupel", location: "LDB-Slatina 1"),
    ProcedureTemplate(title: "Klasická masáž částečná", location: "Bertiny lázně"),
    ProcedureTemplate(title: "Vysokoindukční magnet", location: "LDB-Elektroléčba"),
    ProcedureTemplate(title: "Vířivka dolní končetiny", location: "LDB-Vodoléčba"),
    ProcedureTemplate(title: "Hydro Jet", location: "Bertiny lázně"),
    ProcedureTemplate(title: "IMOOVE", location: "Bertiny lázně"),
    ProcedureTemplate(title: "Fyzioterapie", location: "Bertiny lázně"),
    ProcedureTemplate(title: "Cvičení", location: "Bertiny lázně")
  ]

  public static func make(now: Date = Date()) -> Schedule {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = prague
    let today = calendar.startOfDay(for: now)
    let dateFrom = calendar.date(byAdding: .day, value: -7, to: today)!
    let dateTo = calendar.date(byAdding: .day, value: 20, to: today)!
    var events: [ScheduleEvent] = []

    for dayOffset in -7...20 {
      let day = calendar.date(byAdding: .day, value: dayOffset, to: today)!
      let date = dateText(day)
      let dayNumber = dayOffset + 7

      events.append(meal(id: "\(date)-breakfast", date: date, start: "07:00", end: "07:45", title: "Snídaně"))

      let morningA = procedures[(dayNumber * 3) % procedures.count]
      let morningB = procedures[(dayNumber * 3 + 1) % procedures.count]
      let afternoon = procedures[(dayNumber * 3 + 2) % procedures.count]
      events.append(procedure(id: "\(date)-p1", date: date, start: "08:00", end: "08:20", template: morningA))
      events.append(procedure(id: "\(date)-p2", date: date, start: "09:30", end: "09:50", template: morningB))

      events.append(meal(id: "\(date)-lunch", date: date, start: "11:00", end: "11:45", title: "Oběd"))
      events.append(procedure(id: "\(date)-p3", date: date, start: "13:00", end: "13:20", template: afternoon))
      events.append(meal(id: "\(date)-dinner", date: date, start: "17:00", end: "17:45", title: "Večeře"))
    }

    let activeStart = now.addingTimeInterval(-5 * 60)
    let activeEnd = now.addingTimeInterval(30 * 60)
    let activeDate = dateText(today)

    // Keep the realistic three-procedure day: the live test replaces the second
    // morning procedure instead of creating an artificial fourth procedure.
    events.removeAll { $0.stableId == stableIDPrefix + "\(activeDate)-p2" }
    events.append(
      ScheduleEvent(
        stableId: stableIDPrefix + "running",
        date: activeDate,
        start: timeText(activeStart),
        end: timeText(activeEnd),
        title: "Fyzioterapie",
        location: "Bertiny lázně",
        kind: .procedure,
        procedureType: "Fyzioterapie",
        mealType: nil,
        leadTimeMinutes: nil
      )
    )

    events.sort {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.start != $1.start { return $0.start < $1.start }
      return $0.stableId < $1.stableId
    }

    return Schedule(
      schemaVersion: 1,
      scheduleVersion: 990_001,
      updatedAt: ISO8601DateFormatter().string(from: now),
      stay: [
        "spa": "Bertiny lázně, Třeboň",
        "dateFrom": dateText(dateFrom),
        "dateTo": dateText(dateTo)
      ],
      events: events,
      settings: ScheduleSettings(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: [:],
        mealOverrides: ["Snídaně": 15, "Oběd": 15, "Večeře": 15]
      )
    )
  }

  private static func meal(id: String, date: String, start: String, end: String, title: String) -> ScheduleEvent {
    ScheduleEvent(
      stableId: stableIDPrefix + id,
      date: date,
      start: start,
      end: end,
      title: title,
      location: "Bertiny lázně",
      kind: .meal,
      procedureType: nil,
      mealType: title,
      leadTimeMinutes: nil
    )
  }

  private static func procedure(id: String, date: String, start: String, end: String, template: ProcedureTemplate) -> ScheduleEvent {
    ScheduleEvent(
      stableId: stableIDPrefix + id,
      date: date,
      start: start,
      end: end,
      title: template.title,
      location: template.location,
      kind: .procedure,
      procedureType: template.title,
      mealType: nil,
      leadTimeMinutes: nil
    )
  }

  private static func dateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = prague
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private static func timeText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = prague
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
#endif

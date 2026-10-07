import Foundation

/// Explicit preview input only. Dataset and IDs prevent acceptance by live caches
/// and schedulers even if a caller accidentally passes this through normal sync.
public enum CommanderWidgetDemoSchedule {
  public static func make(now: Date = Date()) -> Schedule {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return Schedule(
      schemaVersion: 1,
      scheduleVersion: max(1, Int(now.timeIntervalSince1970)),
      updatedAt: ISO8601DateFormatter().string(from: now),
      stay: ["spa": "Ukázkový rozpis", "commanderDataset": "widgetDemo"],
      events: [ScheduleEvent(
        stableId: "widgetDemo.procedure", date: formatter.string(from: now),
        start: "10:00", end: "10:20", title: "Ukázková procedura",
        location: "Ukázková lokalita", kind: .procedure, procedureType: nil,
        mealType: nil, leadTimeMinutes: 20
      )],
      settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
    )
  }
}

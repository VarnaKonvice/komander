import Foundation

public enum CommanderVisualReviewSchedule {
  public static func make(now: Date = Date()) -> Schedule {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

    let dayFormatter = DateFormatter()
    dayFormatter.calendar = calendar
    dayFormatter.timeZone = calendar.timeZone
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.dateFormat = "yyyy-MM-dd"

    let timeFormatter = DateFormatter()
    timeFormatter.calendar = calendar
    timeFormatter.timeZone = calendar.timeZone
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.dateFormat = "HH:mm"

    func event(
      id: String,
      offsetMinutes: Int,
      durationMinutes: Int,
      title: String,
      location: String,
      kind: ScheduleKind,
      procedureType: String? = nil,
      mealType: String? = nil,
      leadTimeMinutes: Int? = nil
    ) -> ScheduleEvent {
      let start = calendar.date(byAdding: .minute, value: offsetMinutes, to: now) ?? now
      let end = calendar.date(byAdding: .minute, value: durationMinutes, to: start) ?? start
      return ScheduleEvent(
        stableId: "visual-review.\(id)",
        date: dayFormatter.string(from: start),
        start: timeFormatter.string(from: start),
        end: timeFormatter.string(from: end),
        title: title,
        location: location,
        kind: kind,
        procedureType: procedureType,
        mealType: mealType,
        leadTimeMinutes: leadTimeMinutes
      )
    }

    var events: [ScheduleEvent] = [
      event(
        id: "current-rehab",
        offsetMinutes: -5,
        durationMinutes: 20,
        title: "Individuální rehabilitace",
        location: "Rehabilitace · tělocvična",
        kind: .procedure,
        procedureType: "Individuální rehabilitace"
      ),
      event(
        id: "magnet",
        offsetMinutes: 30,
        durationMinutes: 20,
        title: "Magnetoterapie",
        location: "Elektroléčba · budova 2",
        kind: .procedure,
        procedureType: "Magnetoterapie"
      ),
      event(
        id: "breakfast",
        offsetMinutes: 70,
        durationMinutes: 30,
        title: "Snídaně",
        location: "Jídelna",
        kind: .meal,
        mealType: "Snídaně"
      ),
      event(
        id: "hydrojet",
        offsetMinutes: 125,
        durationMinutes: 20,
        title: "Hydrojet",
        location: "Vodoléčba",
        kind: .procedure,
        procedureType: "Hydrojet",
        leadTimeMinutes: 12
      ),
      event(
        id: "pearl-bath",
        offsetMinutes: 155,
        durationMinutes: 20,
        title: "Perličková koupel",
        location: "Vodoléčba",
        kind: .procedure,
        procedureType: "Perličková koupel"
      ),
      event(
        id: "dinner",
        offsetMinutes: 190,
        durationMinutes: 30,
        title: "Večeře",
        location: "Jídelna",
        kind: .meal,
        mealType: "Večeře"
      )
    ]

    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
    let tomorrowStart = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: tomorrow) ?? tomorrow
    let tomorrowEnd = calendar.date(byAdding: .minute, value: 25, to: tomorrowStart) ?? tomorrowStart
    events.append(ScheduleEvent(
      stableId: "visual-review.tomorrow-iodobrom",
      date: dayFormatter.string(from: tomorrowStart),
      start: timeFormatter.string(from: tomorrowStart),
      end: timeFormatter.string(from: tomorrowEnd),
      title: "Jodobromová koupel",
      location: "Vodoléčba",
      kind: .procedure,
      procedureType: "Jodobromová koupel",
      mealType: nil,
      leadTimeMinutes: nil
    ))

    let stayEnd = calendar.date(byAdding: .day, value: 6, to: now) ?? now
    return Schedule(
      schemaVersion: 1,
      scheduleVersion: Int(now.timeIntervalSince1970),
      updatedAt: ISO8601DateFormatter().string(from: now),
      stay: [
        "spa": "Rehabilitační sanatorium Darkov",
        "dateFrom": dayFormatter.string(from: now),
        "dateTo": dayFormatter.string(from: stayEnd),
        "room": "208",
        "doctor": "MUDr. Commander",
        "diagnosis": "Diagnóza – chybí ve zdrojových datech",
        "mealShift": "Kontrolní režim"
      ],
      events: events,
      settings: ScheduleSettings(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: [
          "Magnetoterapie": 25,
          "Individuální rehabilitace": 15
        ],
        mealOverrides: [
          "Snídaně": 10,
          "Večeře": 15
        ]
      )
    )
  }
}

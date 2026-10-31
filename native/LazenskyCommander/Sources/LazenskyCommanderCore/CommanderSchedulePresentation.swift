import Foundation

public struct CommanderWeekDay: Equatable, Sendable {
  public let date: Date
  public let summary: CommanderDaySummary
  public let overview: CommanderDayOverview
  public let events: [CommanderDashboardEvent]
}

public enum CommanderWeekPresentation {
  public static func make(
    schedule: Schedule,
    now: Date,
    overrides: LeadTimeOverrides? = nil
  ) throws -> [CommanderWeekDay] {
    let projection = try CommanderScheduleProjection(schedule: schedule, overrides: overrides)
    let items = projection.events.map { $0.dashboardEvent(at: now) }
    let grouped = Dictionary(grouping: items) { CommanderScheduleCalendar.prague.startOfDay(for: $0.startAt) }
    let days = stayDays(schedule: schedule) ?? grouped.keys.sorted()
    return days.map { day in
      let events = (grouped[day] ?? []).sorted {
        if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
        if $0.endAt != $1.endAt { return $0.endAt < $1.endAt }
        return $0.event.stableId < $1.event.stableId
      }
      return CommanderWeekDay(
        date: day,
        summary: CommanderDaySummary.make(timeline: events, now: now),
        overview: CommanderDayOverview.make(date: day, timeline: events, now: now),
        events: events
      )
    }
  }

  private static func stayDays(schedule: Schedule) -> [Date]? {
    guard let from = schedule.stay["dateFrom"], let to = schedule.stay["dateTo"],
          let start = try? NativeAlarmContract.dateTime(date: from, time: "00:00"),
          let end = try? NativeAlarmContract.dateTime(date: to, time: "00:00"),
          start <= end
    else { return nil }
    let calendar = CommanderScheduleCalendar.prague
    guard let count = calendar.dateComponents([.day], from: start, to: end).day else { return nil }
    return (0...count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
}

public enum CommanderStayPhase: Equatable, Sendable {
  case upcoming, active, finished
}

public struct CommanderStayPeriod: Equatable, Sendable {
  public let dateFrom: Date
  public let dateTo: Date
  public let totalDays: Int
  public let currentDay: Int?
  public let phase: CommanderStayPhase
}

public struct CommanderProcedureSummary: Equatable, Sendable {
  public let name: String
  public let completed: Int
  public let total: Int
  public let representativeEvent: ScheduleEvent
}

public struct CommanderStayPresentation: Equatable, Sendable {
  public let period: CommanderStayPeriod?
  public let completedProcedures: Int
  public let totalProcedures: Int
  public let procedures: [CommanderProcedureSummary]
  public let visits: CommanderProcedureSummary?

  public static func make(schedule: Schedule, now: Date) throws -> Self {
    try NativeAlarmContract.validate(schedule)
    let allProcedures = schedule.events.filter { $0.kind == .procedure }
    // Schedule has no attendance records: completion means the scheduled end has passed.
    let completedIDs = Set(try allProcedures.filter {
      try NativeAlarmContract.dateTime(date: $0.date, time: $0.end) <= now
    }.map(\.stableId))
    let visitEvents = allProcedures.filter(isVisit)
    let procedures = allProcedures.filter { !isVisit($0) }
    let groups = Dictionary(grouping: procedures, by: procedureSummaryName)

    return Self(
      period: period(stay: schedule.stay, now: now),
      completedProcedures: procedures.filter { completedIDs.contains($0.stableId) }.count,
      totalProcedures: procedures.count,
      procedures: groups.keys.sorted(by: procedureSummaryComesBefore).map { name in
        let events = groups[name]!
        return CommanderProcedureSummary(
          name: name,
          completed: events.filter { completedIDs.contains($0.stableId) }.count,
          total: events.count,
          representativeEvent: events[0]
        )
      },
      visits: visitEvents.first.map { representative in
        CommanderProcedureSummary(
          name: "Vizita",
          completed: visitEvents.filter { completedIDs.contains($0.stableId) }.count,
          total: visitEvents.count,
          representativeEvent: representative
        )
      }
    )
  }

  private static func procedureSummaryName(for event: ScheduleEvent) -> String {
    let type = event.procedureType?.trimmingCharacters(in: .whitespacesAndNewlines)
    let nonEmptyType = type.flatMap { $0.isEmpty ? nil : $0 }

    // "Individuální LTV" is an umbrella type in the canonical schedule. For the stay
    // overview only, keep its concrete exercise names visible (walking belt, Motomed,
    // ergotherapy, individual LTV). Other procedure types stay grouped as before.
    if normalized(nonEmptyType) == "individualni ltv" {
      let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
      if !title.isEmpty { return title }
    }
    return nonEmptyType ?? event.title
  }

  private static func procedureSummaryComesBefore(_ lhs: String, _ rhs: String) -> Bool {
    let priority: [String: Int] = [
      "elektricky chodnik": 0,
      "iltv imoove": 1,
      "iltv ergoterapie": 2,
      "individualni ltv": 3,
      "motomed": 4
    ]

    let lhsPriority = priority[normalized(lhs)] ?? Int.max
    let rhsPriority = priority[normalized(rhs)] ?? Int.max
    if lhsPriority != rhsPriority {
      return lhsPriority < rhsPriority
    }
    return lhs.localizedStandardCompare(rhs) == .orderedAscending
  }

  private static func isVisit(_ event: ScheduleEvent) -> Bool {
    normalized(event.procedureType) == "vizita" || normalized(event.title) == "vizita"
  }

  private static func normalized(_ value: String?) -> String {
    value?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
      ?? ""
  }

  public static func period(stay: [String: String], now: Date) -> CommanderStayPeriod? {
    guard let from = stay["dateFrom"], let to = stay["dateTo"],
          let start = try? NativeAlarmContract.dateTime(date: from, time: "00:00"),
          let end = try? NativeAlarmContract.dateTime(date: to, time: "00:00"),
          start <= end
    else { return nil }
    let calendar = CommanderScheduleCalendar.prague
    let today = calendar.startOfDay(for: now)
    guard let days = calendar.dateComponents([.day], from: start, to: end).day else { return nil }
    let phase: CommanderStayPhase = today < start ? .upcoming : today > end ? .finished : .active
    let day = phase == .active
      ? calendar.dateComponents([.day], from: start, to: today).day.map { $0 + 1 }
      : nil
    return CommanderStayPeriod(dateFrom: start, dateTo: end, totalDays: days + 1, currentDay: day, phase: phase)
  }
}

public struct CommanderStayField: Equatable, Sendable {
  public let key: String
  public let value: String
}

public enum CommanderInfoPresentation {
  public static func fields(stay: [String: String]) -> [CommanderStayField] {
    let known = ["spa", "dateFrom", "dateTo", "mealShift", "room", "doctor", "diagnosis"]
    let keys = known + stay.keys.filter { !known.contains($0) }.sorted()
    return keys.compactMap { key in
      guard let value = stay[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
      return CommanderStayField(key: key, value: displayValue(value, key: key))
    }
  }

  private static func displayValue(_ value: String, key: String) -> String {
    guard key == "dateFrom" || key == "dateTo" else { return value }
    return CommanderDateText.numericDate(isoDate: value) ?? value
  }
}

private enum CommanderScheduleCalendar {
  static var prague: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }
}

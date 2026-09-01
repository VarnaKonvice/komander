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
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    let events = Dictionary(uniqueKeysWithValues: schedule.events.map { ($0.stableId, $0) })
    let items = try payload.alarms.map { alarm in
      let start = try NativeAlarmContract.date(fromLocalISO: alarm.startAt)
      let end = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      return CommanderDashboardEvent(
        event: events[alarm.stableId]!,
        startAt: start,
        endAt: end,
        leaveAt: try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
        phase: now >= end ? .past : now >= start ? .current : .future
      )
    }
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
}

public struct CommanderStayPresentation: Equatable, Sendable {
  public let period: CommanderStayPeriod?
  public let completedProcedures: Int
  public let totalProcedures: Int
  public let procedures: [CommanderProcedureSummary]

  public static func make(schedule: Schedule, now: Date) throws -> Self {
    try NativeAlarmContract.validate(schedule)
    let procedures = schedule.events.filter { $0.kind == .procedure }
    // Schedule has no attendance records: completion means the scheduled end has passed.
    let completedIDs = Set(try procedures.filter {
      try NativeAlarmContract.dateTime(date: $0.date, time: $0.end) <= now
    }.map(\.stableId))
    let groups = Dictionary(grouping: procedures) { event in
      let type = event.procedureType?.trimmingCharacters(in: .whitespacesAndNewlines)
      return type.flatMap { $0.isEmpty ? nil : $0 } ?? event.title
    }
    return Self(
      period: period(stay: schedule.stay, now: now),
      completedProcedures: completedIDs.count,
      totalProcedures: procedures.count,
      procedures: groups.keys.sorted().map { name in
        let events = groups[name]!
        return CommanderProcedureSummary(
          name: name,
          completed: events.filter { completedIDs.contains($0.stableId) }.count,
          total: events.count
        )
      }
    )
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
    let known = ["spa", "dateFrom", "dateTo", "room", "doctor", "mealShift"]
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

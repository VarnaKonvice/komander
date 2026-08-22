import Foundation

public enum CommanderLiveState: String, Codable, Equatable, Sendable {
  case upcoming = "UPCOMING"
  case leaveNow = "LEAVE_NOW"
  case inProgress = "IN_PROGRESS"
  case dayDone = "DAY_DONE"
  case noSchedule = "NO_SCHEDULE"
}

public struct CommanderLiveStateResult: Equatable, Sendable {
  public let state: CommanderLiveState
  public let event: ScheduleEvent?
  public let nextEvent: ScheduleEvent?
  public let startAt: Date?
  public let endAt: Date?
  public let leaveAt: Date?
  public let now: Date
  public let leadTimeMinutes: Int?

  public var minutesUntilStart: Int? { startAt.map { Int(ceil($0.timeIntervalSince(now) / 60)) } }
  public var minutesUntilLeave: Int? { leaveAt.map { Int(ceil($0.timeIntervalSince(now) / 60)) } }

  public init(state: CommanderLiveState, event: ScheduleEvent? = nil, nextEvent: ScheduleEvent? = nil, startAt: Date? = nil, endAt: Date? = nil, leaveAt: Date? = nil, now: Date, leadTimeMinutes: Int? = nil) {
    self.state = state
    self.event = event
    self.nextEvent = nextEvent
    self.startAt = startAt
    self.endAt = endAt
    self.leaveAt = leaveAt
    self.now = now
    self.leadTimeMinutes = leadTimeMinutes
  }
}

public enum CommanderLiveStateCalculator {
  private static let prague = TimeZone(identifier: "Europe/Prague")!

  public static func compute(schedule: Schedule?, now: Date = Date(), overrides: LeadTimeOverrides? = nil) -> CommanderLiveStateResult {
    guard let schedule, !now.timeIntervalSince1970.isNaN else { return .init(state: .noSchedule, now: now) }
    do {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = prague
      let today = calendar.dateComponents([.year, .month, .day], from: now)
      let todayEvents = schedule.events
        .filter { event in
          let date = try? NativeAlarmContract.dateTime(date: event.date, time: event.start)
          return date.map { calendar.dateComponents([.year, .month, .day], from: $0) == today } ?? false
        }
        .sorted { [$0.date, $0.start, $0.end, $0.stableId].joined(separator: "|") < [$1.date, $1.start, $1.end, $1.stableId].joined(separator: "|") }
      for event in todayEvents {
        let alarm = try NativeAlarmContract.alarm(event: event, schedule: schedule, overrides: overrides)
        let startAt = try NativeAlarmContract.date(fromLocalISO: alarm.startAt)
        let endAt = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
        let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
        let lead = alarm.effectiveLeadTimeMinutes
        if now < leaveAt { return .init(state: .upcoming, event: event, nextEvent: event, startAt: startAt, endAt: endAt, leaveAt: leaveAt, now: now, leadTimeMinutes: lead) }
        if now < startAt { return .init(state: .leaveNow, event: event, nextEvent: event, startAt: startAt, endAt: endAt, leaveAt: leaveAt, now: now, leadTimeMinutes: lead) }
        if now < endAt { return .init(state: .inProgress, event: event, nextEvent: event, startAt: startAt, endAt: endAt, leaveAt: leaveAt, now: now, leadTimeMinutes: lead) }
      }
      let next = try schedule.events
        .sorted { [$0.date, $0.start, $0.end, $0.stableId].joined(separator: "|") < [$1.date, $1.start, $1.end, $1.stableId].joined(separator: "|") }
        .first { try NativeAlarmContract.dateTime(date: $0.date, time: $0.start) > now }
      return .init(state: .dayDone, nextEvent: next, now: now)
    } catch {
      return .init(state: .noSchedule, now: now)
    }
  }
}

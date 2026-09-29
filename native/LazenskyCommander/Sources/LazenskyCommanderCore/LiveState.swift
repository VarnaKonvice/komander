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
  public static func compute(schedule: Schedule?, now: Date = Date(), overrides: LeadTimeOverrides? = nil) -> CommanderLiveStateResult {
    guard let schedule,
          let projection = try? CommanderScheduleProjection(schedule: schedule, overrides: overrides)
    else { return .init(state: .noSchedule, now: now) }
    return projection.liveState(at: now)
  }
}

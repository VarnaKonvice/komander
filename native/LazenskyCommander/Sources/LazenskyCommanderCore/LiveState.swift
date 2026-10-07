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

    let result = projection.liveState(at: now)
    guard result.state == .dayDone,
          result.event == nil,
          let nextEvent = result.nextEvent,
          let alarm = try? NativeAlarmContract.alarm(event: nextEvent, schedule: schedule, overrides: overrides),
          let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
          let endAt = try? NativeAlarmContract.date(fromLocalISO: alarm.endAt),
          let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    else { return result }

    // DAY_DONE remains semantically "today is finished", but carry the next
    // canonical event timing so Watch complications can show tomorrow instead
    // of going visually empty overnight.
    return .init(
      state: .dayDone,
      nextEvent: nextEvent,
      startAt: startAt,
      endAt: endAt,
      leaveAt: leaveAt,
      now: now,
      leadTimeMinutes: alarm.effectiveLeadTimeMinutes
    )
  }
}

/// Shared snapshots select the same canonical event as iPhone/Watch. Widget text
/// intentionally shows start/end only. A caller without preferences cannot infer departure.
public enum CommanderHomeWidgetPresentation {
  public static func compute(schedule: Schedule?, now: Date, overrides: LeadTimeOverrides? = nil) -> CommanderLiveStateResult {
    guard let schedule else { return .init(state: .noSchedule, now: now) }
    let selectionOverrides = overrides ?? LeadTimeOverrides(eventOverrides: Dictionary(
      schedule.events.map { ($0.stableId, 0) }, uniquingKeysWith: { first, _ in first }))
    let result = CommanderLiveStateCalculator.compute(schedule: schedule, now: now, overrides: selectionOverrides)
    return .init(state: result.state == .leaveNow ? .upcoming : result.state, event: result.event, nextEvent: result.nextEvent,
      startAt: result.startAt, endAt: result.endAt, now: now)
  }
}

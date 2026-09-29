import Foundation

public enum CommanderDashboardMode: Equatable, Sendable {
  case unsynchronized
  case upcoming
  case leaveNow
  case inProgress
  case dayDone
  case noSchedule
}

public enum CommanderTimelinePhase: Equatable, Sendable {
  case past
  case current
  case future
}

public struct CommanderDashboardEvent: Equatable, Sendable {
  public let event: ScheduleEvent
  public let startAt: Date
  public let endAt: Date
  public let leaveAt: Date
  public let phase: CommanderTimelinePhase

  public init(
    event: ScheduleEvent,
    startAt: Date,
    endAt: Date,
    leaveAt: Date,
    phase: CommanderTimelinePhase
  ) {
    self.event = event
    self.startAt = startAt
    self.endAt = endAt
    self.leaveAt = leaveAt
    self.phase = phase
  }
}

public struct CommanderDashboardPresentation: Equatable, Sendable {
  public let mode: CommanderDashboardMode
  public let liveState: CommanderLiveStateResult
  public let currentEvent: CommanderDashboardEvent?
  public let nextEvent: CommanderDashboardEvent?
  public let thenEvent: CommanderDashboardEvent?
  public let nextProcedure: CommanderDashboardEvent?
  public let stayPeriod: CommanderStayPeriod?
  public let daySummary: CommanderDaySummary
  public let dayOverview: CommanderDayOverview
  public let timeline: [CommanderDashboardEvent]
  public let meals: [CommanderDashboardEvent]
  public let now: Date

  public var minutesUntilNextProcedureLeave: Int? {
    guard let leaveAt = nextProcedure?.leaveAt, leaveAt > now else { return nil }
    return Int(ceil(leaveAt.timeIntervalSince(now) / 60))
  }

  public static func make(
    schedule: Schedule?,
    now: Date,
    overrides: LeadTimeOverrides? = nil
  ) -> CommanderDashboardPresentation {
    let projection = schedule.flatMap { try? CommanderScheduleProjection(schedule: $0, overrides: overrides) }
    let liveState = projection?.liveState(at: now) ?? .init(state: .noSchedule, now: now)
    guard let schedule else {
      return CommanderDashboardPresentation(
        mode: .unsynchronized,
        liveState: liveState,
        currentEvent: nil,
        nextEvent: nil,
        thenEvent: nil,
        nextProcedure: nil,
        stayPeriod: nil,
        daySummary: CommanderDaySummary.make(timeline: [], now: now),
        dayOverview: CommanderDayOverview.make(
          date: pragueCalendar.startOfDay(for: now),
          timeline: [],
          now: now
        ),
        timeline: [],
        meals: [],
        now: now
      )
    }

    let timeline = projection?.events(on: now).map { $0.dashboardEvent(at: now) } ?? []
    let day = pragueCalendar.startOfDay(for: now)
    let mode = timeline.isEmpty ? .noSchedule : dashboardMode(for: liveState.state)
    let currentEvent = liveState.event.flatMap { liveEvent in
      timeline.first { $0.event.stableId == liveEvent.stableId }
    }
    let following = currentEvent.map { current in
      Array(timeline.filter {
        $0.phase == .future && $0.event.stableId != current.event.stableId
      }.prefix(2))
    } ?? []
    let stayPeriod = CommanderStayPresentation.period(stay: schedule.stay, now: now)
    let nextProcedure = stayPeriod?.phase != .finished
      ? projection?.events.first { $0.event.kind == .procedure && $0.startAt > now }?.dashboardEvent(at: now)
      : nil

    return CommanderDashboardPresentation(
      mode: mode,
      liveState: liveState,
      currentEvent: currentEvent,
      nextEvent: following.first,
      thenEvent: following.count > 1 ? following[1] : nil,
      nextProcedure: nextProcedure,
      stayPeriod: stayPeriod,
      daySummary: CommanderDaySummary.make(timeline: timeline, now: now),
      dayOverview: CommanderDayOverview.make(date: day, timeline: timeline, now: now),
      timeline: timeline,
      meals: timeline.filter { $0.event.kind == .meal },
      now: now
    )
  }

  private static func dashboardMode(for state: CommanderLiveState) -> CommanderDashboardMode {
    switch state {
    case .upcoming: .upcoming
    case .leaveNow: .leaveNow
    case .inProgress: .inProgress
    case .dayDone: .dayDone
    case .noSchedule: .noSchedule
    }
  }

  private static var pragueCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }
}

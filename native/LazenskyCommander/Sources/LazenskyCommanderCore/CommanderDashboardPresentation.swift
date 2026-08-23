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
  public let timeline: [CommanderDashboardEvent]
  public let meals: [CommanderDashboardEvent]
  public let now: Date

  public static func make(
    schedule: Schedule?,
    now: Date,
    overrides: LeadTimeOverrides? = nil
  ) -> CommanderDashboardPresentation {
    let liveState = CommanderLiveStateCalculator.compute(
      schedule: schedule,
      now: now,
      overrides: overrides
    )
    guard let schedule else {
      return CommanderDashboardPresentation(
        mode: .unsynchronized,
        liveState: liveState,
        currentEvent: nil,
        nextEvent: nil,
        timeline: [],
        meals: [],
        now: now
      )
    }

    let timeline = todayEvents(schedule: schedule, now: now, overrides: overrides)
    let mode = timeline.isEmpty ? .noSchedule : dashboardMode(for: liveState.state)
    let currentEvent = liveState.event.flatMap { liveEvent in
      timeline.first { $0.event.stableId == liveEvent.stableId }
    }
    let nextEvent = currentEvent.flatMap { item -> CommanderDashboardEvent? in
      guard let index = timeline.firstIndex(where: { $0.event.stableId == item.event.stableId }) else {
        return nil
      }
      let nextIndex = timeline.index(after: index)
      return nextIndex < timeline.endIndex ? timeline[nextIndex] : nil
    }

    return CommanderDashboardPresentation(
      mode: mode,
      liveState: liveState,
      currentEvent: currentEvent,
      nextEvent: nextEvent,
      timeline: timeline,
      meals: timeline.filter { $0.event.kind == .meal },
      now: now
    )
  }

  private static func todayEvents(
    schedule: Schedule,
    now: Date,
    overrides: LeadTimeOverrides?
  ) -> [CommanderDashboardEvent] {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let today = calendar.dateComponents([.year, .month, .day], from: now)

    return schedule.events.compactMap { event in
      guard
        let alarm = try? NativeAlarmContract.alarm(event: event, schedule: schedule, overrides: overrides),
        let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
        let endAt = try? NativeAlarmContract.date(fromLocalISO: alarm.endAt),
        let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
        calendar.dateComponents([.year, .month, .day], from: startAt) == today
      else {
        return nil
      }

      let phase: CommanderTimelinePhase
      if now >= endAt {
        phase = .past
      } else if now >= startAt {
        phase = .current
      } else {
        phase = .future
      }
      return CommanderDashboardEvent(
        event: event,
        startAt: startAt,
        endAt: endAt,
        leaveAt: leaveAt,
        phase: phase
      )
    }
    .sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      if $0.endAt != $1.endAt { return $0.endAt < $1.endAt }
      return $0.event.stableId < $1.event.stableId
    }
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
}

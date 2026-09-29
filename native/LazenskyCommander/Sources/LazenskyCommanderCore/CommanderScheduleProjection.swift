import Foundation

/// Read-only projection of one validated schedule and one captured override revision.
/// Every native surface consumes these exact times; no surface subtracts its own lead time.
public struct CommanderProjectedEvent: Equatable, Sendable {
  public let event: ScheduleEvent
  public let alarm: NativeAlarm
  public let leaveAt: Date
  public let startAt: Date
  public let endAt: Date

  public var timelineEvent: CommanderLiveActivityTimelineEvent {
    .init(stableId: event.stableId, leaveAt: leaveAt, startAt: startAt, endAt: endAt)
  }

  public func dashboardEvent(at now: Date) -> CommanderDashboardEvent {
    .init(event: event, startAt: startAt, endAt: endAt, leaveAt: leaveAt,
          phase: now >= endAt ? .past : now >= startAt ? .current : .future)
  }
}

public struct CommanderScheduleProjection: Equatable, Sendable {
  public let schedule: Schedule
  public let payload: NativeAlarmPayload
  public let events: [CommanderProjectedEvent]

  public init(schedule: Schedule, overrides: LeadTimeOverrides? = nil) throws {
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    self.schedule = schedule
    self.payload = payload
    events = try Self.events(schedule: schedule, payload: payload)
  }

  /// Adapter for callers that already captured the canonical alarm payload.
  public static func events(schedule: Schedule, payload: NativeAlarmPayload) throws -> [CommanderProjectedEvent] {
    try NativeAlarmContract.validate(schedule)
    let byID = Dictionary(uniqueKeysWithValues: schedule.events.map { ($0.stableId, $0) })
    return try payload.alarms.map { alarm in
      guard let event = byID[alarm.stableId] else { throw CocoaError(.coderReadCorrupt) }
      return CommanderProjectedEvent(
        event: event, alarm: alarm,
        leaveAt: try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
        startAt: try NativeAlarmContract.date(fromLocalISO: alarm.startAt),
        endAt: try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      )
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.event.stableId < $1.event.stableId
    }
  }

  public func events(on date: Date) -> [CommanderProjectedEvent] {
    events.filter { Self.calendar.isDate($0.startAt, inSameDayAs: date) }
  }

  public func liveState(at now: Date) -> CommanderLiveStateResult {
    guard now.timeIntervalSince1970.isFinite else { return .init(state: .noSchedule, now: now) }
    let today = events(on: now)
    guard let resolution = CommanderLiveActivityTimeline.resolve(events: today.map(\.timelineEvent), at: now),
          resolution.phase != .ended,
          let primary = today.first(where: { $0.event.stableId == resolution.primaryStableId })
    else {
      return .init(state: .dayDone, nextEvent: events.first { $0.startAt > now }?.event, now: now)
    }
    let state: CommanderLiveState = resolution.phase == .active
      ? .inProgress : resolution.departureDue ? .leaveNow : .upcoming
    return .init(
      state: state, event: primary.event,
      nextEvent: events.first { $0.event.stableId == resolution.nextStableId }?.event,
      startAt: primary.startAt, endAt: primary.endAt, leaveAt: primary.leaveAt,
      now: now, leadTimeMinutes: primary.alarm.effectiveLeadTimeMinutes
    )
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }
}

import Foundation

public struct WatchScheduleProjectionIdentity: Codable, Equatable, Sendable {
  public let scheduleVersion: Int
  public let projectionRevision: Int

  public func isOlder(than other: Self) -> Bool {
    scheduleVersion < other.scheduleVersion ||
      (scheduleVersion == other.scheduleVersion && projectionRevision < other.projectionRevision)
  }

  public init(scheduleVersion: Int, projectionRevision: Int) {
    self.scheduleVersion = scheduleVersion
    self.projectionRevision = projectionRevision
  }
}

public struct WatchScheduleSnapshot: Codable, Equatable, Sendable {
  public static let currentContractVersion = 1
  public let contractVersion: Int
  public let schedule: Schedule
  public let leadTimeOverrides: LeadTimeOverrides
  public let projectionRevision: Int

  public init(
    contractVersion: Int = currentContractVersion,
    schedule: Schedule,
    leadTimeOverrides: LeadTimeOverrides = LeadTimeOverrides(),
    projectionRevision: Int = 0
  ) {
    self.contractVersion = contractVersion
    self.schedule = schedule
    self.leadTimeOverrides = leadTimeOverrides
    self.projectionRevision = max(0, projectionRevision)
  }

  public var projectionIdentity: WatchScheduleProjectionIdentity {
    WatchScheduleProjectionIdentity(
      scheduleVersion: schedule.scheduleVersion,
      projectionRevision: projectionRevision
    )
  }

  private enum CodingKeys: String, CodingKey {
    case contractVersion
    case schedule
    case leadTimeOverrides
    case projectionRevision
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    contractVersion = try values.decode(Int.self, forKey: .contractVersion)
    schedule = try values.decode(Schedule.self, forKey: .schedule)
    leadTimeOverrides = try values.decodeIfPresent(LeadTimeOverrides.self, forKey: .leadTimeOverrides) ?? LeadTimeOverrides()
    projectionRevision = max(0, try values.decodeIfPresent(Int.self, forKey: .projectionRevision) ?? 0)
  }
}

public enum CommanderWatchWidgetContract {
  public static let kind = "LazenskyCommanderWatchWidget"
  public static let iPhoneKind = "LazenskyCommanderHomeWidget"
  public static let iPhoneDayOverviewKind = "LazenskyCommanderDayOverviewWidget"
  public static let iPhoneProcedureCountKind = "LazenskyCommanderProcedureCountWidget"
  public static let appGroupIdentifier = "group.com.varnakonvice.lazenskycommander.watch"
  public static let cacheDirectoryName = "LazenskyCommanderWatchCache"
  public static let expiryGracePeriod: TimeInterval = 24 * 60 * 60
  public static let timelineHorizon: TimeInterval = 24 * 60 * 60
}

public enum WatchScheduleCachePolicy {
  public static func decision(
    incoming: WatchScheduleSnapshot,
    existing: WatchScheduleSnapshot?
  ) -> WatchScheduleCacheDecision {
    guard
      incoming.contractVersion == WatchScheduleSnapshot.currentContractVersion,
      incoming.projectionRevision >= 0,
      (try? WatchScheduleTransportCodec.encode(incoming)) != nil
    else { return .rejectedInvalid }
    guard let existing else { return .stored }
    if incoming == existing { return .unchanged }

    let incomingVersion = incoming.schedule.scheduleVersion
    let existingVersion = existing.schedule.scheduleVersion
    if incomingVersion > existingVersion { return .stored }
    if incomingVersion < existingVersion {
      return .rejectedVersion(current: existingVersion, incoming: incomingVersion)
    }

    // A local lead-time edit intentionally keeps the canonical scheduleVersion unchanged.
    // Only a strictly newer local projection revision may replace the cached projection.
    if incoming.schedule == existing.schedule,
       incoming.projectionRevision > existing.projectionRevision { return .stored }
    return .rejectedVersion(current: existingVersion, incoming: incomingVersion)
  }

  public static func shouldAccept(incoming: Schedule, existing: Schedule?) -> Bool {
    let existingSnapshot = existing.map { WatchScheduleSnapshot(schedule: $0) }
    switch decision(incoming: WatchScheduleSnapshot(schedule: incoming), existing: existingSnapshot) {
    case .stored, .unchanged: return true
    case .rejectedInvalid, .rejectedVersion: return false
    }
  }
}

public enum WatchTimelineTransition: String, Equatable, Sendable {
  case now
  case dayStart
  case countdownStart
  case leaveAt
  case startAt
  case endAt
  case expired
}

public struct WatchTimelinePoint: Equatable, Sendable {
  public let date: Date
  public let transition: WatchTimelineTransition
  public let state: CommanderLiveState
  public let stableId: String?
  public init(date: Date, transition: WatchTimelineTransition, state: CommanderLiveState, stableId: String?) {
    self.date = date
    self.transition = transition
    self.state = state
    self.stableId = stableId
  }
}

public struct WatchWidgetRelevanceWindow: Equatable, Sendable {
  public let stableId: String
  public let interval: DateInterval

  public init(stableId: String, interval: DateInterval) {
    self.stableId = stableId
    self.interval = interval
  }
}

public struct WatchPreparedTimelineEntry: Equatable, Sendable {
  public let date: Date
  public let liveState: CommanderLiveStateResult

  public init(date: Date, liveState: CommanderLiveStateResult) {
    self.date = date
    self.liveState = liveState
  }
}

/// Fast read-only planner for snapshots that already passed the strict cache
/// write/read-back boundary. It intentionally avoids revalidating the complete
/// alarm transport projection inside the WidgetKit extension.
public enum WatchPreparedTimelinePlanner {
  public static func currentState(
    schedule: Schedule,
    now: Date = Date(),
    overrides: LeadTimeOverrides? = nil
  ) throws -> CommanderLiveStateResult {
    state(projectedEvents: try projectedEvents(schedule: schedule, overrides: overrides), at: now)
  }

  public static func entries(
    schedule: Schedule,
    now: Date = Date(),
    horizon: Date,
    overrides: LeadTimeOverrides? = nil
  ) throws -> [WatchPreparedTimelineEntry] {
    guard horizon >= now else { return [] }
    let projected = try projectedEvents(schedule: schedule, overrides: overrides)
    guard !projected.isEmpty else {
      return [.init(date: now, liveState: .init(state: .noSchedule, now: now))]
    }

    var dates = Set<Date>([now])
    for event in projected where event.endAt >= now {
      for boundary in [event.leaveAt, event.startAt, event.endAt]
        where boundary >= now && boundary <= horizon {
        dates.insert(boundary)
      }
    }

    // Always On reduces the fidelity of SwiftUI timer text. Add minute
    // checkpoints around the current countdown so the reduced-luminance
    // complication can keep showing a real countdown without relying on
    // seconds that watchOS intentionally suppresses.
    let current = state(projectedEvents: projected, at: now)
    let countdownTarget: Date? = switch current.state {
    case .upcoming: current.leaveAt
    case .leaveNow: current.startAt
    case .inProgress: current.endAt
    case .dayDone, .noSchedule: nil
    }
    if let countdownTarget, countdownTarget > now {
      let minuteWindowEnd = min(
        countdownTarget,
        horizon,
        now.addingTimeInterval(3 * 60 * 60)
      )
      var tick = Date(
        timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 60) * 60
      )
      while tick <= minuteWindowEnd {
        dates.insert(tick)
        tick = tick.addingTimeInterval(60)
      }
    }

    var dayStart = calendar.startOfDay(for: now)
    while let next = calendar.date(byAdding: .day, value: 1, to: dayStart),
          next <= horizon {
      dates.insert(next)
      dayStart = next
    }

    if let finalEnd = projected.map(\.endAt).max() {
      let expiration = finalEnd.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod)
      if expiration >= now && expiration <= horizon { dates.insert(expiration) }
    }

    return dates.sorted().map {
      WatchPreparedTimelineEntry(date: $0, liveState: state(projectedEvents: projected, at: $0))
    }
  }

  public static func relevanceWindows(
    schedule: Schedule,
    now: Date = Date(),
    horizon: Date,
    overrides: LeadTimeOverrides? = nil
  ) throws -> [WatchWidgetRelevanceWindow] {
    try projectedEvents(schedule: schedule, overrides: overrides).compactMap { projected in
      guard projected.endAt > now, projected.leaveAt <= horizon else { return nil }
      let countdownDuration = try AlarmCountdown.countdownWindow(for: projected.alarm, in: schedule)
      let countdownStart = projected.leaveAt.addingTimeInterval(-countdownDuration)
      return WatchWidgetRelevanceWindow(
        stableId: projected.event.stableId,
        interval: DateInterval(start: countdownStart, end: projected.endAt)
      )
    }
  }

  public static func isExpired(
    _ schedule: Schedule,
    at date: Date = Date(),
    overrides: LeadTimeOverrides? = nil
  ) -> Bool {
    guard let projected = try? projectedEvents(schedule: schedule, overrides: overrides),
          let finalEnd = projected.map(\.endAt).max() else { return true }
    return date >= finalEnd.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod)
  }

  private static func projectedEvents(
    schedule: Schedule,
    overrides: LeadTimeOverrides?
  ) throws -> [CommanderProjectedEvent] {
    try schedule.events.map { event in
      let alarm = try NativeAlarmContract.alarm(event: event, schedule: schedule, overrides: overrides)
      return CommanderProjectedEvent(
        event: event,
        alarm: alarm,
        leaveAt: try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
        startAt: try NativeAlarmContract.date(fromLocalISO: alarm.startAt),
        endAt: try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      )
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.event.stableId < $1.event.stableId
    }
  }

  private static func state(
    projectedEvents: [CommanderProjectedEvent],
    at now: Date
  ) -> CommanderLiveStateResult {
    guard now.timeIntervalSince1970.isFinite,
          let finalEnd = projectedEvents.map(\.endAt).max(),
          now < finalEnd.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod)
    else { return .init(state: .noSchedule, now: now) }

    let today = projectedEvents.filter {
      calendar.isDate($0.startAt, inSameDayAs: now) || ($0.leaveAt <= now && now < $0.endAt)
    }

    guard let resolution = CommanderLiveActivityTimeline.resolve(
      events: today.map(\.timelineEvent),
      at: now
    ),
    resolution.phase != .ended,
    let primary = today.first(where: { $0.event.stableId == resolution.primaryStableId })
    else {
      guard let next = projectedEvents.first(where: { $0.startAt > now }) else {
        return .init(state: .dayDone, now: now)
      }
      return .init(
        state: .dayDone,
        nextEvent: next.event,
        startAt: next.startAt,
        endAt: next.endAt,
        leaveAt: next.leaveAt,
        now: now,
        leadTimeMinutes: next.alarm.effectiveLeadTimeMinutes
      )
    }

    let state: CommanderLiveState = resolution.phase == .active
      ? .inProgress : resolution.departureDue ? .leaveNow : .upcoming
    return .init(
      state: state,
      event: primary.event,
      nextEvent: projectedEvents.first(where: { $0.event.stableId == resolution.nextStableId })?.event,
      startAt: primary.startAt,
      endAt: primary.endAt,
      leaveAt: primary.leaveAt,
      now: now,
      leadTimeMinutes: primary.alarm.effectiveLeadTimeMinutes
    )
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }
}

public enum WatchScheduleExpiryPolicy {
  public static func expirationDate(for schedule: Schedule) throws -> Date? {
    try NativeAlarmContract.validateCanonical(schedule)
    let finalEnd = try schedule.events.map {
      try NativeAlarmContract.dateTime(date: $0.date, time: $0.end)
    }.max()
    return finalEnd?.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod)
  }

  public static func isExpired(_ schedule: Schedule, at date: Date = Date()) -> Bool {
    do {
      guard let expiration = try expirationDate(for: schedule) else { return true }
      return date >= expiration
    } catch {
      return true
    }
  }

  public static func activeSchedule(_ schedule: Schedule?, at date: Date = Date()) -> Schedule? {
    guard let schedule, !isExpired(schedule, at: date) else { return nil }
    return schedule
  }
}

public enum WatchTimelinePlanner {
  public static func points(schedule: Schedule, now: Date = Date(), overrides: LeadTimeOverrides? = nil) throws -> [WatchTimelinePoint] {
    try NativeAlarmContract.validateCanonical(schedule)
    guard !WatchScheduleExpiryPolicy.isExpired(schedule, at: now) else {
      return [WatchTimelinePoint(date: now, transition: .now, state: .noSchedule, stableId: nil)]
    }

    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    let current = CommanderLiveStateCalculator.compute(schedule: schedule, now: now, overrides: overrides)
    var candidates = [WatchTimelinePoint(date: now, transition: .now, state: current.state, stableId: current.event?.stableId)]

    for eventDate in Set(schedule.events.map(\.date)).sorted() {
      let dayStart = try NativeAlarmContract.dateTime(date: eventDate, time: "00:00")
      if let point = point(at: dayStart, transition: .dayStart, schedule: schedule, now: now, overrides: overrides) {
        candidates.append(point)
      }
    }

    for alarm in payload.alarms {
      let start = try NativeAlarmContract.date(fromLocalISO: alarm.startAt)
      let leave = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
      let end = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      guard end >= now else { continue }

      let countdownDuration = try AlarmCountdown.countdownWindow(for: alarm, in: schedule)
      let countdownStart = leave.addingTimeInterval(-countdownDuration)
      candidates.append(contentsOf: [
        point(at: countdownStart, transition: .countdownStart, schedule: schedule, now: now, overrides: overrides),
        point(at: leave, transition: .leaveAt, schedule: schedule, now: now, overrides: overrides),
        point(at: start, transition: .startAt, schedule: schedule, now: now, overrides: overrides),
        point(at: end, transition: .endAt, schedule: schedule, now: now, overrides: overrides)
      ].compactMap { $0 })
    }

    if let expiration = try WatchScheduleExpiryPolicy.expirationDate(for: schedule), expiration >= now {
      candidates.append(WatchTimelinePoint(date: expiration, transition: .expired, state: .noSchedule, stableId: nil))
    }

    var seenDates = Set<Date>()
    return candidates.sorted(by: timelineOrder).filter { seenDates.insert($0.date).inserted }
  }

  public static func relevanceWindows(schedule: Schedule, now: Date = Date(), overrides: LeadTimeOverrides? = nil) throws -> [WatchWidgetRelevanceWindow] {
    try NativeAlarmContract.validateCanonical(schedule)
    guard !WatchScheduleExpiryPolicy.isExpired(schedule, at: now) else { return [] }

    return try NativeAlarmContract.payload(schedule: schedule, overrides: overrides).alarms.compactMap { alarm -> WatchWidgetRelevanceWindow? in
      let leave = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
      let end = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      guard end > now else { return nil }
      let countdownDuration = try AlarmCountdown.countdownWindow(for: alarm, in: schedule)
      let countdownStart = leave.addingTimeInterval(-countdownDuration)
      return WatchWidgetRelevanceWindow(
        stableId: alarm.stableId,
        interval: DateInterval(start: countdownStart, end: end)
      )
    }
  }

  private static func point(
    at date: Date,
    transition: WatchTimelineTransition,
    schedule: Schedule,
    now: Date,
    overrides: LeadTimeOverrides?
  ) -> WatchTimelinePoint? {
    guard date >= now else { return nil }
    let liveState = CommanderLiveStateCalculator.compute(schedule: schedule, now: date, overrides: overrides)
    return WatchTimelinePoint(
      date: date,
      transition: transition,
      state: liveState.state,
      stableId: liveState.event?.stableId
    )
  }

  private static func timelineOrder(_ lhs: WatchTimelinePoint, _ rhs: WatchTimelinePoint) -> Bool {
    if lhs.date != rhs.date { return lhs.date < rhs.date }
    return transitionPriority(lhs.transition) > transitionPriority(rhs.transition)
  }

  private static func transitionPriority(_ transition: WatchTimelineTransition) -> Int {
    switch transition {
    case .expired: return 7
    case .endAt: return 6
    case .startAt: return 5
    case .leaveAt: return 4
    case .countdownStart: return 3
    case .dayStart: return 2
    case .now: return 1
    }
  }
}

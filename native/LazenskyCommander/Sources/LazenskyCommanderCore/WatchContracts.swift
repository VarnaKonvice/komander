import Foundation

public struct WatchScheduleSnapshot: Codable, Equatable, Sendable {
  public static let currentContractVersion = 1
  public let contractVersion: Int
  public let schedule: Schedule
  public init(contractVersion: Int = currentContractVersion, schedule: Schedule) {
    self.contractVersion = contractVersion
    self.schedule = schedule
  }
}

public enum CommanderWatchWidgetContract {
  public static let kind = "LazenskyCommanderWatchWidget"
  public static let appGroupIdentifier = "group.com.varnakonvice.lazenskycommander.watch"
  public static let cacheDirectoryName = "LazenskyCommanderWatchCache"
  public static let expiryGracePeriod: TimeInterval = 24 * 60 * 60
}

public enum WatchScheduleCachePolicy {
  public static func decision(
    incoming: WatchScheduleSnapshot,
    existing: WatchScheduleSnapshot?
  ) -> WatchScheduleCacheDecision {
    guard
      incoming.contractVersion == WatchScheduleSnapshot.currentContractVersion,
      (try? NativeAlarmContract.validate(incoming.schedule)) != nil
    else { return .rejectedInvalid }
    guard let existing else { return .stored }
    if incoming == existing { return .unchanged }
    guard incoming.schedule.scheduleVersion > existing.schedule.scheduleVersion else {
      return .rejectedVersion(
        current: existing.schedule.scheduleVersion,
        incoming: incoming.schedule.scheduleVersion
      )
    }
    return .stored
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

public enum WatchScheduleExpiryPolicy {
  public static func expirationDate(for schedule: Schedule) throws -> Date? {
    try NativeAlarmContract.validate(schedule)
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
    try NativeAlarmContract.validate(schedule)
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

      let countdownDuration = try AlarmCountdown.preAlertDuration(for: alarm, in: schedule)
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
    try NativeAlarmContract.validate(schedule)
    guard !WatchScheduleExpiryPolicy.isExpired(schedule, at: now) else { return [] }

    return try NativeAlarmContract.payload(schedule: schedule, overrides: overrides).alarms.compactMap { alarm -> WatchWidgetRelevanceWindow? in
      let leave = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
      let end = try NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      guard end > now else { return nil }
      let countdownDuration = try AlarmCountdown.preAlertDuration(for: alarm, in: schedule)
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

import Foundation

/// Decisions shared by the real stop intent, reconciliation and acceptance preflight.
/// ActivityKit remains responsible for rendering and scheduling these decisions.
public enum CommanderLiveActivityHandoff {
  public static let maximumPreparedActivities = 3

  /// Each event needs its own foreground-created activity: ActivityKit attributes
  /// are immutable, and Stop must never create the next event's activity.
  public static func runningEvents(in schedule: Schedule, now: Date) -> [ScheduleEvent] {
    Array(schedule.events.filter {
      guard let end = try? NativeAlarmContract.dateTime(date: $0.date, time: $0.end) else { return false }
      return end > now
    }.sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.start != $1.start { return $0.start < $1.start }
      return $0.stableId < $1.stableId
    }.prefix(maximumPreparedActivities))
  }

  /// A schedule-derived proof carried by the alarm's Stop intent, not a second schedule.
  public struct Identity: Codable, Equatable, Sendable {
    public let scheduleVersion: Int
    public let sourceStableId: String
    public let sourceTitle: String
    public let sourceLocation: String
    public let sourceKind: ScheduleKind
    public let sourceStartAt: Date
    public let sourceEndAt: Date
    public let target: NativeAlarm

    public init(scheduleVersion: Int, sourceStableId: String, sourceTitle: String,
                sourceLocation: String, sourceKind: ScheduleKind,
                sourceStartAt: Date, sourceEndAt: Date, target: NativeAlarm) {
      self.scheduleVersion = scheduleVersion
      self.sourceStableId = sourceStableId
      self.sourceTitle = sourceTitle
      self.sourceLocation = sourceLocation
      self.sourceKind = sourceKind
      self.sourceStartAt = sourceStartAt
      self.sourceEndAt = sourceEndAt
      self.target = target
    }
  }

  public static func identity(for alarm: NativeAlarm, in schedule: Schedule) -> Identity? {
    let sources = schedule.events.filter { event in
      guard let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end) else { return false }
      return isCanonicalFreeTimeSource(stableId: event.stableId, endAt: end, for: alarm, in: schedule)
    }.sorted {
      if $0.end != $1.end { return $0.end > $1.end }
      return $0.stableId < $1.stableId
    }
    guard let source = sources.first,
          let start = try? NativeAlarmContract.dateTime(date: source.date, time: source.start),
          let end = try? NativeAlarmContract.dateTime(date: source.date, time: source.end) else { return nil }
    return Identity(scheduleVersion: schedule.scheduleVersion, sourceStableId: source.stableId,
      sourceTitle: source.title, sourceLocation: source.location, sourceKind: source.kind,
      sourceStartAt: start, sourceEndAt: end, target: alarm)
  }

  public static func matches(actual: Identity?, expected: Identity?, now: Date) -> Bool {
    guard let actual, let expected, actual == expected,
          let start = try? NativeAlarmContract.date(fromLocalISO: expected.target.startAt),
          let leave = try? NativeAlarmContract.date(fromLocalISO: expected.target.leaveAt),
          expected.sourceEndAt <= leave else { return false }
    return retainsFreeTime(previousEnd: expected.sourceEndAt, targetStart: start, now: now)
  }

  public static func retainPrepared(stableId: String, matchesCanonical: Bool, ongoing: Bool,
                                    retainedIDs: inout Set<String>) -> Bool {
    matchesCanonical && ongoing && retainedIDs.insert(stableId).inserted
  }

  /// Staleness is not an end signal. An expired event may still own a verified handoff.
  public static func needsCleanup(endAt: Date, hasVerifiedHandoff: Bool, now: Date) -> Bool {
    endAt <= now && !hasVerifiedHandoff
  }

  public static func hasCompleteRunningPreparation(expectedIDs: [String], preparedIDs: [String]) -> Bool {
    expectedIDs.count == preparedIDs.count && Set(expectedIDs) == Set(preparedIDs)
      && Set(preparedIDs).count == preparedIDs.count
  }

  public enum StopDisposition: Equatable, Sendable {
    case bridgeUntilStart
    case retainAlarmUntilStart
    case dismiss
  }

  public static func stopDisposition(hasHandoff: Bool, startAt: Date, now: Date) -> StopDisposition {
    guard now < startAt else { return .dismiss }
    return hasHandoff ? .bridgeUntilStart : .retainAlarmUntilStart
  }

  public static func retainsBridge(
    storedTarget: NativeAlarm?, currentTarget: NativeAlarm?, now: Date
  ) -> Bool {
    guard let storedTarget, let currentTarget,
          storedTarget == currentTarget,
          let start = try? NativeAlarmContract.date(fromLocalISO: currentTarget.startAt),
          let leave = try? NativeAlarmContract.date(fromLocalISO: currentTarget.leaveAt)
    else { return false }
    return leave <= now && now < start
  }

  public static func retainsFreeTime(
    previousEnd: Date, targetStart: Date, now: Date
  ) -> Bool {
    previousEnd <= now && now < targetStart
  }

  public static func nextEvent(after event: ScheduleEvent, in schedule: Schedule) -> ScheduleEvent? {
    guard let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end) else { return nil }
    return schedule.events.filter { candidate in
      guard candidate.stableId != event.stableId, candidate.date == event.date,
            let start = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.start)
      else { return false }
      return start >= end
    }.sorted {
      if $0.start != $1.start { return $0.start < $1.start }
      return $0.stableId < $1.stableId
    }.first
  }

  public static func isCanonicalFreeTimeSource(
    stableId: String, endAt: Date, for alarm: NativeAlarm, in schedule: Schedule
  ) -> Bool {
    guard let source = schedule.events.first(where: { $0.stableId == stableId }),
          let canonicalEnd = try? NativeAlarmContract.dateTime(date: source.date, time: source.end),
          let leave = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
          abs(canonicalEnd.timeIntervalSince(endAt)) <= 1,
          canonicalEnd <= leave else { return false }
    return nextEvent(after: source, in: schedule)?.stableId == alarm.stableId
  }

  public static func hasFreeTimeSource(for alarm: NativeAlarm, in schedule: Schedule) -> Bool {
    guard let leave = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt) else { return false }
    return schedule.events.contains { candidate in
      guard candidate.stableId != alarm.stableId,
            let end = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.end),
            end <= leave
      else { return false }
      return nextEvent(after: candidate, in: schedule)?.stableId == alarm.stableId
    }
  }
}

/// Persisted adapter context outside the canonical payload. A neighbour change can alter
/// an alarm's countdown ownership or stop intent without changing its own leaveAt.
public struct AlarmPresentationContext: Codable, Equatable, Sendable {
  public let departureHolderVerified: Bool?
  public let liveActivityContractRevision: Int?
  public let liveActivityScheduleVersion: Int?
  public let handoffIdentity: CommanderLiveActivityHandoff.Identity?
  public let countdownWindow: TimeInterval
  public let hasFreeTimeSource: Bool
  public let procedureType: String?
  public let mealType: String?
  public let nextAlarm: NativeAlarm?
  public let nextProcedureType: String?
  public let nextMealType: String?

  public init(alarm: NativeAlarm, schedule: Schedule, overrides: LeadTimeOverrides?, departureHolderVerified: Bool? = nil) throws {
    self.departureHolderVerified = departureHolderVerified
    liveActivityContractRevision = 1
    liveActivityScheduleVersion = schedule.scheduleVersion
    handoffIdentity = CommanderLiveActivityHandoff.identity(for: alarm, in: schedule)
    countdownWindow = try AlarmCountdown.countdownWindow(for: alarm, in: schedule)
    hasFreeTimeSource = CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarm, in: schedule)
    let current = schedule.events.first { $0.stableId == alarm.stableId }
    procedureType = current?.procedureType
    mealType = current?.mealType
    let next = current.flatMap { CommanderLiveActivityHandoff.nextEvent(after: $0, in: schedule) }
    nextAlarm = try next.map { try NativeAlarmContract.alarm(event: $0, schedule: schedule, overrides: overrides) }
    nextProcedureType = next?.procedureType
    nextMealType = next?.mealType
  }
}

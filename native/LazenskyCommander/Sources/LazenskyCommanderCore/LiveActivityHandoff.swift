import Foundation

/// Decisions shared by the real stop intent, reconciliation and acceptance preflight.
/// ActivityKit remains responsible for rendering and scheduling these decisions.
public enum CommanderLiveActivityHandoff {
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
  public let countdownWindow: TimeInterval
  public let hasFreeTimeSource: Bool
  public let procedureType: String?
  public let mealType: String?
  public let nextAlarm: NativeAlarm?
  public let nextProcedureType: String?
  public let nextMealType: String?

  public init(alarm: NativeAlarm, schedule: Schedule, overrides: LeadTimeOverrides?) throws {
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

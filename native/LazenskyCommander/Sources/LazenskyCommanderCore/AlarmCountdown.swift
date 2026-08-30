import Foundation

public struct AlarmCountdownPlan: Equatable, Sendable {
  /// The instant at which AlarmKit must actually alert. A countdown window never changes this value.
  public let scheduledAlertAt: Date
  /// AlarmKit's fixed date starts preAlert. nil starts the remaining countdown immediately.
  public let scheduledStartAt: Date?
  public let countdownWindow: TimeInterval

  public init(scheduledAlertAt: Date, scheduledStartAt: Date?, countdownWindow: TimeInterval) {
    self.scheduledAlertAt = scheduledAlertAt
    self.scheduledStartAt = scheduledStartAt
    self.countdownWindow = countdownWindow
  }
}

public enum AlarmCountdown {
  public static let maximumWindow: TimeInterval = 30 * 60

  public static func countdownWindow(for alarm: NativeAlarm, in schedule: Schedule) throws -> TimeInterval {
    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let sameDayPreviousEnd = try schedule.events.compactMap { event -> Date? in
      guard event.date == String(alarm.startAt.prefix(10)) else { return nil }
      let endAt = try NativeAlarmContract.dateTime(date: event.date, time: event.end)
      return endAt <= leaveAt ? endAt : nil
    }.max()
    if let endAt = sameDayPreviousEnd {
      return min(maximumWindow, max(0, leaveAt.timeIntervalSince(endAt)))
    }
    return maximumWindow
  }

  /// Compatibility for existing Watch timeline code; new code should use countdownWindow.
  public static func preAlertDuration(for alarm: NativeAlarm, in schedule: Schedule) throws -> TimeInterval {
    try countdownWindow(for: alarm, in: schedule)
  }

  public static func plan(for alarm: NativeAlarm, in schedule: Schedule, now: Date) throws -> AlarmCountdownPlan {
    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let desiredWindow = try countdownWindow(for: alarm, in: schedule)
    return plan(leaveAt: leaveAt, countdownWindow: desiredWindow, now: now)
  }

  public static func plan(leaveAt: Date, countdownWindow: TimeInterval, now: Date) -> AlarmCountdownPlan {
    let desiredWindow = min(maximumWindow, max(0, countdownWindow))
    let remaining = max(0, leaveAt.timeIntervalSince(now))
    let startAt = leaveAt.addingTimeInterval(-desiredWindow)

    return AlarmCountdownPlan(
      scheduledAlertAt: leaveAt,
      scheduledStartAt: desiredWindow > 0 && startAt > now ? startAt : nil,
      countdownWindow: min(desiredWindow, remaining)
    )
  }

  /// Read-back uses platform values, never metadata or the desired canonical deadline.
  public static func effectiveAlertDate(
    fixedScheduleAt: Date?, preAlert: TimeInterval?, countdownFireDate: Date?
  ) -> Date? {
    if let countdownFireDate { return countdownFireDate }
    guard let fixedScheduleAt else { return nil }
    let duration = preAlert ?? 0
    guard duration.isFinite, duration >= 0 else { return nil }
    return fixedScheduleAt.addingTimeInterval(duration)
  }
}

import Foundation

public struct AlarmCountdownPlan: Equatable, Sendable {
  /// The instant at which AlarmKit must actually alert. A countdown window never changes this value.
  public let scheduledAlertAt: Date
  public let countdownWindow: TimeInterval

  public init(scheduledAlertAt: Date, countdownWindow: TimeInterval) {
    self.scheduledAlertAt = scheduledAlertAt
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
    let remaining = max(0, leaveAt.timeIntervalSince(now))

    return AlarmCountdownPlan(
      scheduledAlertAt: leaveAt,
      countdownWindow: min(desiredWindow, remaining)
    )
  }
}

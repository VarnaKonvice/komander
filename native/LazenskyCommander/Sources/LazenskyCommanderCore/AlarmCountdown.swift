import Foundation

public struct AlarmCountdownPlan: Equatable, Sendable {
  public let scheduledStartAt: Date?
  public let duration: TimeInterval

  public init(scheduledStartAt: Date?, duration: TimeInterval) {
    self.scheduledStartAt = scheduledStartAt
    self.duration = duration
  }
}

public enum AlarmCountdown {
  public static func preAlertDuration(for alarm: NativeAlarm, in schedule: Schedule) throws -> TimeInterval {
    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let sameDayPreviousEnd = try schedule.events.compactMap { event -> Date? in
      guard event.date == String(alarm.startAt.prefix(10)) else { return nil }
      let endAt = try NativeAlarmContract.dateTime(date: event.date, time: event.end)
      return endAt < leaveAt ? endAt : nil
    }.max()
    if let endAt = sameDayPreviousEnd { return max(0, leaveAt.timeIntervalSince(endAt)) }
    return 30 * 60
  }

  public static func plan(for alarm: NativeAlarm, in schedule: Schedule, now: Date) throws -> AlarmCountdownPlan {
    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let desiredDuration = try preAlertDuration(for: alarm, in: schedule)
    let desiredStartAt = leaveAt.addingTimeInterval(-desiredDuration)

    if desiredStartAt > now {
      return AlarmCountdownPlan(scheduledStartAt: desiredStartAt, duration: desiredDuration)
    }

    return AlarmCountdownPlan(
      scheduledStartAt: nil,
      duration: max(0, leaveAt.timeIntervalSince(now))
    )
  }
}

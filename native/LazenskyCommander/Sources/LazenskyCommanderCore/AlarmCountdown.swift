import Foundation

public enum AlarmCountdown {
  public static func preAlertDuration(for alarm: NativeAlarm, in schedule: Schedule) throws -> TimeInterval {
    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    let sameDayPreviousEnd = try schedule.events.compactMap { event -> Date? in
      guard event.date == String(alarm.startAt.prefix(10)) else { return nil }
      let endAt = try NativeAlarmContract.dateTime(date: event.date, time: event.end)
      return endAt < leaveAt ? endAt : nil
    }.max()
    if let endAt = sameDayPreviousEnd { return max(0, leaveAt.timeIntervalSince(endAt)) }
    return max(0, min(30 * 60, leaveAt.timeIntervalSince(Date(timeIntervalSince1970: leaveAt.timeIntervalSince1970 - 30 * 60))))
  }
}

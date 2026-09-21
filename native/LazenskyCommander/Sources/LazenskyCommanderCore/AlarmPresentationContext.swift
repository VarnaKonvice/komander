import Foundation

/// Persisted AlarmKit presentation dependencies that are not part of NativeAlarm.
/// A previous event can change the countdown window without changing this alarm's leaveAt;
/// current procedure/meal type can change its visual classification without changing title.
public struct AlarmPresentationContext: Codable, Equatable, Sendable {
  public let countdownWindow: TimeInterval
  public let procedureType: String?
  public let mealType: String?

  public init(alarm: NativeAlarm, schedule: Schedule) throws {
    countdownWindow = try AlarmCountdown.countdownWindow(for: alarm, in: schedule)
    let current = schedule.events.first { $0.stableId == alarm.stableId }
    procedureType = current?.procedureType
    mealType = current?.mealType
  }
}

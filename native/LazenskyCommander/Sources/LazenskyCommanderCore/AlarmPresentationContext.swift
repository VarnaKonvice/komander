import Foundation

/// Persisted AlarmKit presentation dependencies that are not part of NativeAlarm.
///
/// AlarmKit is intentionally alert-only. Commander owns the visible pre-departure
/// countdown, so a previous event must not cause an AlarmKit reschedule merely because
/// it changes a possible countdown window.
///
/// `deliveryStyle` is optional for backward decoding. Older stored records decode it as
/// nil, which deliberately forces one reconciliation update to the alert-only contract.
public struct AlarmPresentationContext: Codable, Equatable, Sendable {
  public static let currentDeliveryStyle = "alertOnlyV1"

  public let procedureType: String?
  public let mealType: String?
  public let deliveryStyle: String?

  public init(alarm: NativeAlarm, schedule: Schedule) throws {
    let current = schedule.events.first { $0.stableId == alarm.stableId }
    procedureType = current?.procedureType
    mealType = current?.mealType
    deliveryStyle = Self.currentDeliveryStyle
  }
}

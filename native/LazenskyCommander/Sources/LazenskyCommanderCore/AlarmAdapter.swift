import Foundation

public enum AlarmKitAvailability: Equatable, Sendable {
  case available
  case unavailable(String)
}

public enum AlarmAuthorizationStatus: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
}

public enum AlarmAdapterError: LocalizedError, Equatable, Sendable {
  case unavailable(String)
  case authorizationDenied
  case verificationFailed

  public var errorDescription: String? {
    switch self {
    case .unavailable(let message): return message
    case .authorizationDenied: return "Alarm authorization was denied."
    case .verificationFailed: return "AlarmKit verification did not match the desired alarm set."
    }
  }
}

public protocol AlarmAdapting: Sendable {
  func prepare(schedule: Schedule) async
  func availability() async -> AlarmKitAvailability
  func authorizationStatus() async -> AlarmAuthorizationStatus
  func requestAuthorization() async throws
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String
  func cancel(platformAlarmID: String) async throws
  func existingPlatformAlarmIDs() async throws -> Set<String>?

  /// Returns the real fixed alert date for each AlarmKit alarm when the platform adapter
  /// can inspect it. nil means this verification capability is unavailable in that adapter.
  func existingPlatformFixedAlertDates() async throws -> [String: Date]?
}

public extension AlarmAdapting {
  func prepare(schedule: Schedule) async {}

  /// Returns nil when the backing platform cannot enumerate alarms.
  func existingPlatformAlarmIDs() async throws -> Set<String>? { nil }

  /// Non-iOS/test adapters may not expose schedule details. The real AlarmKit adapter does.
  func existingPlatformFixedAlertDates() async throws -> [String: Date]? { nil }
}

public enum PlatformAlarmIdentifier {
  public static func uuid(from persistedValue: String) -> UUID? {
    UUID(uuidString: persistedValue)
  }

  public static func newPersistedValue() -> String {
    UUID().uuidString
  }
}

public enum NativeAlarmPresentation {
  public static func title(for alarm: NativeAlarm) -> String {
    switch alarm.kind {
    case .procedure: return "Čas vyrazit: \(alarm.title)"
    case .meal: return "Čas vyrazit: \(alarm.title)"
    }
  }
}

/// This implementation is for CoreCheck and non-iOS test environments.
/// The Xcode app uses the SDK-verified adapter in LazenskyCommanderApp/AlarmKitAdapter.swift.
public struct UnavailableAlarmKitAdapter: AlarmAdapting {
  public init() {}
  public func availability() async -> AlarmKitAvailability { .unavailable("AlarmKit was not compiled because this environment has no iOS SDK.") }
  public func authorizationStatus() async -> AlarmAuthorizationStatus { .notDetermined }
  public func requestAuthorization() async throws { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
  public func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
  public func cancel(platformAlarmID: String) async throws { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
}

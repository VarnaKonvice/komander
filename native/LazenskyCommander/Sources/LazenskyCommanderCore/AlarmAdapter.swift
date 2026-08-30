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
  case timingReadbackUnavailable

  public var errorDescription: String? {
    switch self {
    case .unavailable(let message): return message
    case .authorizationDenied: return "Alarm authorization was denied."
    case .verificationFailed: return "AlarmKit verification did not match the desired alarm set."
    case .timingReadbackUnavailable: return "AlarmKit zatím neposkytl čas konce countdownu. Alarm zůstává beze změny; ověření zopakujeme."
    }
  }
}

public protocol AlarmAdapting: Sendable {
  func prepare(schedule: Schedule) async
  func prepare(schedule: Schedule, projectionRevision: Int) async
  func availability() async -> AlarmKitAvailability
  func authorizationStatus() async -> AlarmAuthorizationStatus
  func requestAuthorization() async throws
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String
  func cancel(platformAlarmID: String) async throws
  func existingPlatformAlarmIDs() async throws -> Set<String>?

  /// Returns effective alert deadlines (fixed countdown start + preAlert, or observed fireDate),
  /// not raw fixed schedule dates. nil means this capability is unavailable in that adapter.
  func existingPlatformFixedAlertDates() async throws -> [String: Date]?
  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) async throws -> [String: Date]?
}

public extension AlarmAdapting {
  func prepare(schedule: Schedule) async {}
  func prepare(schedule: Schedule, projectionRevision: Int) async {
    await prepare(schedule: schedule)
  }

  /// Returns nil when the backing platform cannot enumerate alarms.
  func existingPlatformAlarmIDs() async throws -> Set<String>? { nil }

  /// Non-iOS/test adapters may not expose schedule details. The real AlarmKit adapter does.
  func existingPlatformFixedAlertDates() async throws -> [String: Date]? { nil }

  /// Limit timing inspection to managed future alarms; expired/orphan alarms still reconcile by ID.
  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) async throws -> [String: Date]? {
    try await existingPlatformFixedAlertDates()?.filter { platformAlarmIDs.contains($0.key) }
  }
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

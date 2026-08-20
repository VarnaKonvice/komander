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

  public var errorDescription: String? {
    switch self {
    case .unavailable(let message): return message
    case .authorizationDenied: return "Alarm authorization was denied."
    }
  }
}

public protocol AlarmAdapting: Sendable {
  func availability() async -> AlarmKitAvailability
  func authorizationStatus() async -> AlarmAuthorizationStatus
  func requestAuthorization() async throws
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String
  func cancel(platformAlarmID: String) async throws
}

/// This implementation deliberately does not invent AlarmKit calls when the iOS 26 SDK is unavailable.
/// Replace it with the SDK-verified adapter described in AlarmKitSDKBoundary.swift on a machine with Xcode.
public struct UnavailableAlarmKitAdapter: AlarmAdapting {
  public init() {}
  public func availability() async -> AlarmKitAvailability { .unavailable("AlarmKit was not compiled because this environment has no iOS SDK.") }
  public func authorizationStatus() async -> AlarmAuthorizationStatus { .notDetermined }
  public func requestAuthorization() async throws { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
  public func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
  public func cancel(platformAlarmID: String) async throws { throw AlarmAdapterError.unavailable("AlarmKit is unavailable.") }
}

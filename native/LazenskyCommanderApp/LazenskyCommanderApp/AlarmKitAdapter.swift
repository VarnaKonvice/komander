import AlarmKit
import Foundation
import SwiftUI
import LazenskyCommanderCore

struct CommanderAlarmMetadata: AlarmMetadata {}

enum AlarmKitAdapterError: LocalizedError {
  case invalidPlatformAlarmID(String)
  case invalidLeaveAt(String)
  case missingUsageDescription

  var errorDescription: String? {
    switch self {
    case .invalidPlatformAlarmID(let value): return "Neplatné uložené AlarmKit ID: \(value)."
    case .invalidLeaveAt(let value): return "Neplatný čas odchodu: \(value)."
    case .missingUsageDescription: return "Chybí NSAlarmKitUsageDescription v Info.plist."
    }
  }
}

struct AlarmKitAdapter: AlarmAdapting {
  func availability() async -> AlarmKitAvailability {
    guard Self.hasUsageDescription else {
      return .unavailable("Chybí NSAlarmKitUsageDescription v Info.plist.")
    }
    return .available
  }

  func authorizationStatus() async -> AlarmAuthorizationStatus {
    Self.map(AlarmManager.shared.authorizationState)
  }

  func requestAuthorization() async throws {
    guard Self.hasUsageDescription else { throw AlarmKitAdapterError.missingUsageDescription }
    let state = try await AlarmManager.shared.requestAuthorization()
    guard Self.map(state) == .authorized else { throw AlarmAdapterError.authorizationDenied }
  }

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String {
    guard Self.hasUsageDescription else { throw AlarmKitAdapterError.missingUsageDescription }
    if let replacing = platformAlarmID, PlatformAlarmIdentifier.uuid(from: replacing) == nil {
      throw AlarmKitAdapterError.invalidPlatformAlarmID(replacing)
    }
    guard let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt) else {
      throw AlarmKitAdapterError.invalidLeaveAt(alarm.leaveAt)
    }

    let id = UUID()
    let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: NativeAlarmPresentation.title(for: alarm)))
    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: CommanderAlarmMetadata(),
      tintColor: .teal
    )
    let configuration = AlarmManager.AlarmConfiguration.alarm(
      schedule: .fixed(leaveAt),
      attributes: attributes,
      sound: .default
    )
    let scheduled = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    return scheduled.id.uuidString
  }

  func cancel(platformAlarmID: String) async throws {
    guard let id = PlatformAlarmIdentifier.uuid(from: platformAlarmID) else {
      throw AlarmKitAdapterError.invalidPlatformAlarmID(platformAlarmID)
    }
    try AlarmManager.shared.cancel(id: id)
  }

  func existingPlatformAlarmIDs() async throws -> Set<String>? {
    let alarms = try AlarmManager.shared.alarms
    return Set(alarms.map { $0.id.uuidString })
  }

  static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorizationStatus {
    switch state {
    case .notDetermined: return .notDetermined
    case .authorized: return .authorized
    case .denied: return .denied
    @unknown default: return .denied
    }
  }

  static var hasUsageDescription: Bool {
    let value = Bundle.main.object(forInfoDictionaryKey: "NSAlarmKitUsageDescription") as? String
    return !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }
}

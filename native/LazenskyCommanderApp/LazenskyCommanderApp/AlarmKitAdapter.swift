import AlarmKit
import Foundation
import SwiftUI
import UserNotifications
import LazenskyCommanderCore

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

actor AlarmKitAdapter: AlarmAdapting {
  private var scheduleContext: Schedule?

  func prepare(schedule: Schedule) {
    scheduleContext = schedule
  }

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
    let schedule = scheduleContext
    let event = schedule?.events.first(where: { $0.stableId == alarm.stableId })
    let iconKey = event.flatMap { CommanderVisualAssets.icon(for: $0)?.key } ?? ""
    let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: "Odchod za \(alarm.title)"))
    let attributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert, countdown: countdown),
      metadata: CommanderAlarmMetadata(stableId: alarm.stableId, scheduleVersion: schedule?.scheduleVersion ?? 0, iconKey: iconKey, title: alarm.title, location: alarm.location, kind: alarm.kind, startAt: alarm.startAt, leaveAt: alarm.leaveAt),
      tintColor: .teal
    )

    let now = Date()
    let countdownPlan: AlarmCountdownPlan
    if let schedule {
      countdownPlan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
    } else {
      countdownPlan = AlarmCountdownPlan(
        scheduledStartAt: nil,
        duration: min(AlarmCountdown.maximumWindow, max(0, leaveAt.timeIntervalSince(now)))
      )
    }

    let configuration: AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>
    if countdownPlan.duration > 0 {
      let countdownSchedule: Alarm.Schedule? = countdownPlan.scheduledStartAt.map { .fixed($0) }
      configuration = AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>(
        countdownDuration: Alarm.CountdownDuration(preAlert: countdownPlan.duration, postAlert: nil),
        schedule: countdownSchedule,
        attributes: attributes,
        sound: .default
      )
    } else {
      configuration = .alarm(
        schedule: .fixed(leaveAt),
        attributes: attributes,
        sound: .default
      )
    }

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

enum IPhoneAlarmSafetyNetState: Equatable, Sendable {
  case notNeeded
  case active(Int)

  var coversCriticalGap: Bool {
    switch self {
    case .notNeeded: return true
    case .active: return true
    }
  }

  var diagnosticText: String {
    switch self {
    case .notNeeded: return "Nepotřebné"
    case .active(let count): return "Aktivní · \(count)"
    }
  }
}

enum IPhoneAlarmSafetyNetError: LocalizedError {
  case notificationsDenied
  case verificationFailed(Int)

  var errorDescription: String? {
    switch self {
    case .notificationsDenied:
      return "Zapni upozornění pro Lázeňský Commander, aby tě mohl bezpečně upozornit na odchod."
    case .verificationFailed:
      return "Záložní upozornění se nepodařilo bezpečně ověřit."
    }
  }
}

actor IPhoneAlarmSafetyNet {
  private static let identifierPrefix = "lazensky.commander.iphone.fallback."
  private static let prague = TimeZone(identifier: "Europe/Prague")!

  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func reconcile(
    schedule: Schedule,
    uncoveredStableIds: [String],
    now: Date = Date()
  ) async throws -> IPhoneAlarmSafetyNetState {
    let uncovered = Set(uncoveredStableIds)
    let payload = try NativeAlarmContract.payload(schedule: schedule)
    let desired = try payload.alarms.filter { alarm in
      uncovered.contains(alarm.stableId) && NativeAlarmContract.date(fromLocalISO: alarm.leaveAt) > now
    }
    let desiredIdentifiers = Set(desired.map { Self.identifier(for: $0.stableId) })

    let pending = await center.pendingNotificationRequests()
    let currentManaged = Set(pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) })
    let stale = currentManaged.subtracting(desiredIdentifiers)
    if !stale.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: Array(stale))
    }

    guard !desired.isEmpty else {
      if !currentManaged.isEmpty {
        center.removePendingNotificationRequests(withIdentifiers: Array(currentManaged))
      }
      return .notNeeded
    }

    var settings = await center.notificationSettings()
    if settings.authorizationStatus == .notDetermined {
      _ = try await center.requestAuthorization(options: [.alert, .sound])
      settings = await center.notificationSettings()
    }
    guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
      throw IPhoneAlarmSafetyNetError.notificationsDenied
    }

    for alarm in desired {
      try await center.add(request(for: alarm, scheduleVersion: schedule.scheduleVersion))
    }

    let verified = await center.pendingNotificationRequests()
    let verifiedManaged = Set(verified.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) })
    let missing = desiredIdentifiers.subtracting(verifiedManaged)
    guard missing.isEmpty else {
      throw IPhoneAlarmSafetyNetError.verificationFailed(missing.count)
    }

    return .active(desired.count)
  }

  private func request(for alarm: NativeAlarm, scheduleVersion: Int) throws -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = NativeAlarmPresentation.title(for: alarm)
    content.body = alarm.location
    content.sound = .default
    content.interruptionLevel = .timeSensitive
    content.userInfo = [
      "stableId": alarm.stableId,
      "scheduleVersion": scheduleVersion,
      "leaveAt": alarm.leaveAt
    ]

    let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Self.prague
    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: leaveAt
    )
    components.timeZone = Self.prague

    return UNNotificationRequest(
      identifier: Self.identifier(for: alarm.stableId),
      content: content,
      trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    )
  }

  private static func identifier(for stableId: String) -> String {
    identifierPrefix + stableId
  }
}

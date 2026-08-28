import ActivityKit
import AlarmKit
import Foundation
import SwiftUI
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
  private static let maximumPreparedProcedureActivities = 3
  private static let e2eOwnershipKey = "lazensky.commander.alarmkitOwned.e2e.v1"
  private let channel: ScheduleChannel
  private var scheduleContext: Schedule?

  init(channel: ScheduleChannel = .production) {
    self.channel = channel
  }

  func prepare(schedule: Schedule) async {
    scheduleContext = schedule
    guard channel == .production else { return }
    // This projection is deliberately best-effort and independent from AlarmKit safety.
    // A Live Activity failure must never block alarm reconciliation.
    await reconcileProcedureLiveActivities(schedule: schedule)
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
        scheduledAlertAt: leaveAt,
        countdownWindow: min(AlarmCountdown.maximumWindow, max(0, leaveAt.timeIntervalSince(now)))
      )
    }

    let configuration: AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>
    if countdownPlan.countdownWindow > 0 {
      configuration = AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>(
        countdownDuration: Alarm.CountdownDuration(preAlert: countdownPlan.countdownWindow, postAlert: nil),
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: attributes,
        sound: .default
      )
    } else {
      configuration = .alarm(
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: attributes,
        sound: .default
      )
    }

    let scheduled = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    let platformID = scheduled.id.uuidString
    rememberE2EOwnership(platformID)
    return platformID
  }

  func cancel(platformAlarmID: String) async throws {
    guard let id = PlatformAlarmIdentifier.uuid(from: platformAlarmID) else {
      throw AlarmKitAdapterError.invalidPlatformAlarmID(platformAlarmID)
    }
    try AlarmManager.shared.cancel(id: id)
    forgetE2EOwnership(platformAlarmID)
  }

  func existingPlatformAlarmIDs() async throws -> Set<String>? {
    let alarms = try AlarmManager.shared.alarms
    let allIDs = Set(alarms.map { $0.id.uuidString })
    guard channel == .e2e else { return allIDs }
    return allIDs.intersection(e2eOwnedPlatformIDs())
  }

  func existingPlatformFixedAlertDates() async throws -> [String: Date]? {
    let alarms = try AlarmManager.shared.alarms
    let visibleIDs = channel == .e2e ? e2eOwnedPlatformIDs() : nil
    var result: [String: Date] = [:]
    for alarm in alarms {
      let platformID = alarm.id.uuidString
      if let visibleIDs, !visibleIDs.contains(platformID) { continue }
      if case .fixed(let date)? = alarm.schedule {
        result[platformID] = date
      }
    }
    return result
  }

  private func e2eOwnedPlatformIDs() -> Set<String> {
    guard channel == .e2e else { return [] }
    return Set(UserDefaults.standard.stringArray(forKey: Self.e2eOwnershipKey) ?? [])
  }

  private func rememberE2EOwnership(_ platformAlarmID: String) {
    guard channel == .e2e else { return }
    var ids = e2eOwnedPlatformIDs()
    ids.insert(platformAlarmID)
    UserDefaults.standard.set(ids.sorted(), forKey: Self.e2eOwnershipKey)
  }

  private func forgetE2EOwnership(_ platformAlarmID: String) {
    guard channel == .e2e else { return }
    var ids = e2eOwnedPlatformIDs()
    ids.remove(platformAlarmID)
    UserDefaults.standard.set(ids.sorted(), forKey: Self.e2eOwnershipKey)
  }

  private func reconcileProcedureLiveActivities(schedule: Schedule, now: Date = Date()) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    let candidates: [(event: ScheduleEvent, startAt: Date, endAt: Date)] = schedule.events.compactMap { event in
      guard event.kind == .procedure,
            let startAt = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
            let endAt = try? NativeAlarmContract.dateTime(date: event.date, time: event.end),
            endAt > now
      else { return nil }
      return (event: event, startAt: startAt, endAt: endAt)
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.event.stableId < $1.event.stableId
    }

    let desired = Array(candidates.prefix(Self.maximumPreparedProcedureActivities))
    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities

    for activity in existing {
      let match = desired.first { item in
        activity.attributes.stableId == item.event.stableId
          && activity.attributes.scheduleVersion == schedule.scheduleVersion
          && activity.attributes.title == item.event.title
          && activity.attributes.location == item.event.location
          && abs(activity.attributes.startAt.timeIntervalSince(item.startAt)) <= 1
          && abs(activity.attributes.endAt.timeIntervalSince(item.endAt)) <= 1
      }
      guard match == nil else { continue }
      let finalContent = ActivityContent(
        state: CommanderProcedureLiveActivityAttributes.ContentState(projectionRevision: 0),
        staleDate: now
      )
      await activity.end(finalContent, dismissalPolicy: .immediate)
    }

    let remaining = Activity<CommanderProcedureLiveActivityAttributes>.activities
    for item in desired {
      let alreadyPrepared = remaining.contains { activity in
        activity.attributes.stableId == item.event.stableId
          && activity.attributes.scheduleVersion == schedule.scheduleVersion
          && abs(activity.attributes.startAt.timeIntervalSince(item.startAt)) <= 1
          && abs(activity.attributes.endAt.timeIntervalSince(item.endAt)) <= 1
      }
      if alreadyPrepared { continue }

      let iconKey = CommanderVisualAssets.icon(for: item.event)?.key ?? ""
      let attributes = CommanderProcedureLiveActivityAttributes(
        stableId: item.event.stableId,
        scheduleVersion: schedule.scheduleVersion,
        iconKey: iconKey,
        title: item.event.title,
        location: item.event.location,
        kind: item.event.kind,
        startAt: item.startAt,
        endAt: item.endAt
      )
      let content = ActivityContent(
        state: CommanderProcedureLiveActivityAttributes.ContentState(projectionRevision: 0),
        staleDate: item.endAt,
        relevanceScore: 1
      )

      do {
        if item.startAt <= now {
          _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil,
            style: .standard
          )
        } else {
          let alert = ActivityKit.AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: "Procedura začíná"),
            body: LocalizedStringResource(stringLiteral: item.event.title),
            sound: .default
          )
          _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
            attributes: attributes,
            content: content,
            pushType: nil,
            style: .standard,
            alertConfiguration: alert,
            start: item.startAt
          )
        }
      } catch {
        // Alarm reconciliation must remain independent. A later foreground/sync pass retries.
        continue
      }
    }

    // Read after write. Missing activities are left for the next automatic reconciliation pass;
    // they never downgrade or invalidate the already verified alarm projection.
    _ = Activity<CommanderProcedureLiveActivityAttributes>.activities
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

import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import LazenskyCommanderCore

enum AlarmKitAdapterError: LocalizedError {
  case invalidPlatformAlarmID(String)
  case invalidLeaveAt(String)
  case departureDeadlinePassed
  case missingUsageDescription

  var errorDescription: String? {
    switch self {
    case .invalidPlatformAlarmID(let value): return "Neplatné uložené AlarmKit ID: \(value)."
    case .invalidLeaveAt(let value): return "Neplatný čas odchodu: \(value)."
    case .departureDeadlinePassed: return "Čas odchodu během přípravy uplynul. Rozpis se znovu zkontroluje."
    case .missingUsageDescription: return "Chybí NSAlarmKitUsageDescription v Info.plist."
    }
  }
}

struct CommanderAlarmStopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Potvrdit odchod"
  static let description = IntentDescription("Zastaví systémový AlarmKit alarm. Commander Live Activity má vlastní životní cyklus.")
  static let supportedModes: IntentModes = [.background]
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID") var alarmID: String

  init() {
    alarmID = ""
  }

  init(alarmID: UUID) {
    self.alarmID = alarmID.uuidString
  }

  func perform() async throws -> some IntentResult {
    CommanderPhysicalAcceptanceDiagnostics.record("Zastavit proběhlo · \(alarmID)")
    return .result()
  }
}

actor AlarmKitAdapter: AlarmAdapting {
  private static let e2eOwnershipKey = "lazensky.commander.alarmkitOwned.e2e.v1"
  private let channel: ScheduleChannel
  private var scheduleContext: Schedule?
  private var physicalRunID: UUID?
  private var physicalOwnership: PhysicalAcceptanceOwnershipStore?
  private var physicalAttempts: [String: (stableID: String, configuredAt: Date)] = [:]

  init(channel: ScheduleChannel) {
    self.channel = channel
  }

  init(physicalAcceptanceRunID: UUID, ownership: PhysicalAcceptanceOwnershipStore) throws {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else {
      throw PhysicalAcceptanceError.wrongApplication
    }
    channel = .e2e
    physicalRunID = physicalAcceptanceRunID
    physicalOwnership = ownership
  }

  func prepare(schedule: Schedule, projectionRevision: Int) async {
    await prepare(schedule: schedule, projectionRevision: projectionRevision, overrides: nil)
  }

  func prepare(
    schedule: Schedule,
    projectionRevision: Int,
    overrides: LeadTimeOverrides?
  ) async {
    scheduleContext = schedule
  }

  func presentationContext(for alarm: NativeAlarm) throws -> AlarmPresentationContext? {
    guard let schedule = scheduleContext else { return nil }
    return try AlarmPresentationContext(alarm: alarm, schedule: schedule)
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
    let alert = AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: NativeAlarmPresentation.title(for: alarm))
    )
    let schedule = scheduleContext
    let event = schedule?.events.first(where: { $0.stableId == alarm.stableId })
    let iconKey = event.flatMap { CommanderVisualAssets.icon(for: $0)?.key } ?? ""
    let countdown = AlarmPresentation.Countdown(
      title: LocalizedStringResource(stringLiteral: "Odchod za \(alarm.title)")
    )
    let eventEndAt = event.map { Self.localISO(date: $0.date, time: $0.end) }
    let metadata = CommanderAlarmMetadata(
      stableId: alarm.stableId,
      scheduleVersion: schedule?.scheduleVersion ?? 0,
      iconKey: iconKey,
      title: alarm.title,
      location: alarm.location,
      kind: alarm.kind,
      startAt: alarm.startAt,
      leaveAt: alarm.leaveAt,
      endAt: eventEndAt
    )
    let tintColor = Self.alarmTint(kind: alarm.kind, iconKey: iconKey, title: alarm.title)
    let countdownAttributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert, countdown: countdown),
      metadata: metadata,
      tintColor: tintColor
    )
    let alertOnlyAttributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: metadata,
      tintColor: tintColor
    )
    let stopIntent = CommanderAlarmStopIntent(alarmID: id)

    let now = Date()
    guard leaveAt > now else { throw AlarmKitAdapterError.departureDeadlinePassed }
    let countdownPlan: AlarmCountdownPlan
    if let schedule {
      countdownPlan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
    } else {
      countdownPlan = AlarmCountdown.plan(
        leaveAt: leaveAt,
        countdownWindow: AlarmCountdown.maximumWindow,
        now: now
      )
    }

    let configuration: AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>
    if countdownPlan.countdownWindow > 0 {
      configuration = AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>(
        countdownDuration: Alarm.CountdownDuration(
          preAlert: countdownPlan.countdownWindow,
          postAlert: nil
        ),
        schedule: countdownPlan.scheduledStartAt.map { .fixed($0) },
        attributes: countdownAttributes,
        stopIntent: stopIntent,
        sound: .default
      )
    } else {
      configuration = .alarm(
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: alertOnlyAttributes,
        stopIntent: stopIntent,
        sound: .default
      )
    }

    if let physicalRunID, let physicalOwnership {
      await physicalOwnership.remember(id.uuidString, runID: physicalRunID)
    }
    let scheduled = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    let platformID = scheduled.id.uuidString
    if physicalRunID != nil {
      physicalAttempts[platformID] = (alarm.stableId, now)
    } else {
      rememberE2EOwnership(platformID)
    }
    return platformID
  }

  func cancel(platformAlarmID: String) async throws {
    if let physicalRunID, let physicalOwnership,
       !(await physicalOwnership.ids(runID: physicalRunID)).contains(platformAlarmID) {
      throw AlarmAdapterError.unavailable("Alarm nepatří aktuálnímu fyzickému testu.")
    }
    guard let id = PlatformAlarmIdentifier.uuid(from: platformAlarmID) else {
      throw AlarmKitAdapterError.invalidPlatformAlarmID(platformAlarmID)
    }
    try AlarmManager.shared.cancel(id: id)
    if let physicalOwnership {
      await physicalOwnership.forget(platformAlarmID)
      physicalAttempts.removeValue(forKey: platformAlarmID)
    } else {
      forgetE2EOwnership(platformAlarmID)
    }
  }

  func existingPlatformAlarmIDs() async throws -> Set<String>? {
    let alarms = try AlarmManager.shared.alarms
    let allIDs = Set(alarms.map { $0.id.uuidString })
    if let physicalRunID, let physicalOwnership {
      return allIDs.intersection(await physicalOwnership.ids(runID: physicalRunID))
    }
    guard channel == .e2e else { return allIDs }
    return allIDs.intersection(e2eOwnedPlatformIDs())
  }

  func existingPlatformAlertingAlarmIDs() async throws -> Set<String> {
    let owned = try await existingPlatformAlarmIDs() ?? []
    return Set(try AlarmManager.shared.alarms.filter { $0.state == .alerting }
      .map { $0.id.uuidString }).intersection(owned)
  }

  func existingPlatformFixedAlertDates() async throws -> [String: Date]? {
    try await existingPlatformFixedAlertDates(for: existingPlatformAlarmIDs() ?? [])
  }

  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) async throws -> [String: Date]? {
    guard let observations = try await existingPlatformTimingObservations(for: platformAlarmIDs) else { return nil }
    return observations.compactMapValues(\.effectiveAlertDate)
  }

  func existingPlatformTimingObservations(
    for platformAlarmIDs: Set<String>
  ) async throws -> [String: PlatformAlarmTimingObservation]? {
    let alarms = try AlarmManager.shared.alarms
    let visibleIDs: Set<String>?
    if let physicalRunID, let physicalOwnership {
      visibleIDs = await physicalOwnership.ids(runID: physicalRunID)
    } else {
      visibleIDs = channel == .e2e ? e2eOwnedPlatformIDs() : nil
    }

    var countdownDeadlines: [String: Date] = [:]
    for activity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities {
      guard Self.isOngoing(activity.activityState),
            case .countdown(let countdown) = activity.content.state.mode else { continue }
      countdownDeadlines[activity.content.state.alarmID.uuidString] = countdown.fireDate
    }

    var result: [String: PlatformAlarmTimingObservation] = [:]
    for alarm in alarms {
      let platformID = alarm.id.uuidString
      guard platformAlarmIDs.contains(platformID) else { continue }
      if let visibleIDs, !visibleIDs.contains(platformID) { continue }

      var fixedStartAt: Date?
      if case .fixed(let date)? = alarm.schedule { fixedStartAt = date }
      let preAlert = alarm.countdownDuration?.preAlert
      let fireDate = countdownDeadlines[platformID]
      if let deadline = AlarmCountdown.effectiveAlertDate(
        fixedScheduleAt: fixedStartAt,
        preAlert: preAlert,
        countdownFireDate: fireDate
      ) {
        result[platformID] = PlatformAlarmTimingObservation(effectiveAlertDate: deadline)
        continue
      }

      if alarm.schedule == nil,
         alarm.state == .countdown,
         let preAlert, preAlert.isFinite, preAlert > 0 {
        // iOS can run an immediate AlarmKit countdown without publishing its Activity fireDate.
        // This is limited read-back evidence, not a reason to cancel/recreate a working alarm.
        result[platformID] = PlatformAlarmTimingObservation(
          effectiveAlertDate: nil,
          isImmediateCountdownWithoutFireDate: true
        )
        continue
      }

      throw AlarmAdapterError.timingReadbackUnavailable
    }
    return result
  }

  private func e2eOwnedPlatformIDs() -> Set<String> {
    guard channel == .e2e else { return [] }
    return Set(UserDefaults.standard.stringArray(forKey: Self.e2eOwnershipKey) ?? [])
  }

  func physicalObservations() throws -> [PhysicalAlarmObservation] {
    guard physicalRunID != nil, Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else {
      throw PhysicalAcceptanceError.wrongApplication
    }
    var fireDates: [String: Date] = [:]
    for activity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities {
      if Self.isOngoing(activity.activityState),
         case .countdown(let countdown) = activity.content.state.mode {
        fireDates[activity.content.state.alarmID.uuidString] = countdown.fireDate
      }
    }
    return try AlarmManager.shared.alarms.map { alarm in
      let id = alarm.id.uuidString
      let kind: String
      let fixed: Date?
      switch alarm.schedule {
      case .fixed(let date)?: kind = "fixed"; fixed = date
      case nil: kind = "none"; fixed = nil
      default: kind = "relative"; fixed = nil
      }
      return PhysicalAlarmObservation(
        platformID: id,
        stableID: physicalAttempts[id]?.stableID,
        configuredAt: physicalAttempts[id]?.configuredAt,
        scheduleKind: kind,
        fixedScheduleAt: fixed,
        preAlert: alarm.countdownDuration?.preAlert,
        postAlert: alarm.countdownDuration?.postAlert,
        state: String(describing: alarm.state),
        fireDate: fireDates[id]
      )
    }
  }

  static func clearPreviousPhysicalAcceptance(
    ownership: PhysicalAcceptanceOwnershipStore
  ) async throws {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else {
      throw PhysicalAcceptanceError.wrongApplication
    }
    CommanderPhysicalAcceptanceDiagnostics.clear()
    let ownedIDs = await ownership.allIDs()
    let alarms = try AlarmManager.shared.alarms
    let cleanup = PhysicalAcceptanceCleanupPlan(
      ownedIDs: ownedIDs,
      platformIDs: Set(alarms.map { $0.id.uuidString })
    )
    guard cleanup.unknownIDs.isEmpty else { throw PhysicalAcceptanceError.cleanupIncomplete }
    for alarm in alarms where cleanup.cancelIDs.contains(alarm.id.uuidString) {
      try AlarmManager.shared.cancel(id: alarm.id)
    }
    guard try AlarmManager.shared.alarms.isEmpty else {
      throw PhysicalAcceptanceError.cleanupIncomplete
    }
    for id in ownedIDs { await ownership.forget(id) }
    for activity in Activity<CommanderProcedureLiveActivityAttributes>.activities
      where activity.attributes.stableId.hasPrefix(PhysicalAcceptanceRun.stableIDPrefix) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    for activity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities
      where activity.attributes.metadata?.stableId.hasPrefix(PhysicalAcceptanceRun.stableIDPrefix) == true {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
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

  fileprivate static func isOngoing(_ state: ActivityState) -> Bool {
    state == .pending || state == .active || state == .stale
  }

  private static func localISO(date: String, time: String) -> String {
    let normalized = time.count == 5 ? time + ":00" : time
    return "\(date)T\(normalized)"
  }

  private static func alarmTint(kind: ScheduleKind, iconKey: String, title: String) -> Color {
    Color(commanderAlarmHex: CommanderBrandAssets.procedureAccentHex(
      iconKey: iconKey,
      title: title,
      isMeal: kind == .meal
    ))
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

private extension Color {
  init(commanderAlarmHex: String) {
    let value = commanderAlarmHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    let r = Double((rgb >> 16) & 0xFF) / 255
    let g = Double((rgb >> 8) & 0xFF) / 255
    let b = Double(rgb & 0xFF) / 255
    self.init(red: r, green: g, blue: b)
  }
}

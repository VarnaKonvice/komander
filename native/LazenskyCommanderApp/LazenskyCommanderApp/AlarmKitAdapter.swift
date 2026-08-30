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
  private var physicalRunID: UUID?
  private var physicalOwnership: PhysicalAcceptanceOwnershipStore?
  private var physicalAttempts: [String: (stableID: String, configuredAt: Date)] = [:]

  init(channel: ScheduleChannel) {
    self.channel = channel
  }

  init(procedureLiveActivitiesEnabled: Bool = true) {
    self.channel = procedureLiveActivitiesEnabled ? .production : .e2e
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
    scheduleContext = schedule
    guard channel == .production || physicalRunID != nil else { return }
    // This projection is deliberately best-effort and independent from AlarmKit safety.
    // A Live Activity failure must never block alarm reconciliation.
    await reconcileProcedureLiveActivities(
      schedule: schedule,
      projectionRevision: max(0, projectionRevision)
    )
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
      countdownPlan = AlarmCountdown.plan(
        leaveAt: leaveAt,
        countdownWindow: AlarmCountdown.maximumWindow,
        now: now
      )
    }

    let configuration: AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>
    if countdownPlan.countdownWindow > 0 {
      configuration = AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>(
        countdownDuration: Alarm.CountdownDuration(preAlert: countdownPlan.countdownWindow, postAlert: nil),
        schedule: countdownPlan.scheduledStartAt.map { .fixed($0) },
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

    if let physicalRunID, let physicalOwnership {
      // Reserve ownership before SDK I/O, so interrupted scheduling remains recoverable.
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

  func existingPlatformFixedAlertDates() async throws -> [String: Date]? {
    try await existingPlatformFixedAlertDates(for: existingPlatformAlarmIDs() ?? [])
  }

  func existingPlatformFixedAlertDates(for platformAlarmIDs: Set<String>) async throws -> [String: Date]? {
    let alarms = try AlarmManager.shared.alarms
    let visibleIDs: Set<String>?
    if let physicalRunID, let physicalOwnership {
      visibleIDs = await physicalOwnership.ids(runID: physicalRunID)
    } else {
      visibleIDs = channel == .e2e ? e2eOwnedPlatformIDs() : nil
    }
    var countdownDeadlines: [String: Date] = [:]
    for activity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities {
      guard activity.activityState == .active || activity.activityState == .stale,
            case .countdown(let countdown) = activity.content.state.mode else { continue }
      countdownDeadlines[activity.content.state.alarmID.uuidString] = countdown.fireDate
    }
    var result: [String: Date] = [:]
    for alarm in alarms {
      let platformID = alarm.id.uuidString
      guard platformAlarmIDs.contains(platformID) else { continue }
      if let visibleIDs, !visibleIDs.contains(platformID) { continue }
      var fixedStartAt: Date?
      if case .fixed(let date)? = alarm.schedule {
        fixedStartAt = date
      }
      guard let deadline = AlarmCountdown.effectiveAlertDate(
        fixedScheduleAt: fixedStartAt,
        preAlert: alarm.countdownDuration?.preAlert,
        countdownFireDate: countdownDeadlines[platformID]
      ) else {
        // A timer's activity may arrive after schedule() returns. Do not cancel it or
        // claim verification from desired metadata; the existing retry will re-read it.
        throw AlarmAdapterError.timingReadbackUnavailable
      }
      result[platformID] = deadline
    }
    return result
  }

  private func e2eOwnedPlatformIDs() -> Set<String> {
    guard channel == .e2e else { return [] }
    return Set(UserDefaults.standard.stringArray(forKey: Self.e2eOwnershipKey) ?? [])
  }

  /// Read-only observation includes unexpected IDs so preflight rejects rather than hides them.
  func physicalObservations() throws -> [PhysicalAlarmObservation] {
    guard physicalRunID != nil, Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else {
      throw PhysicalAcceptanceError.wrongApplication
    }
    var fireDates: [String: Date] = [:]
    for activity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities {
      if (activity.activityState == .active || activity.activityState == .stale),
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
      return PhysicalAlarmObservation(platformID: id, stableID: physicalAttempts[id]?.stableID, configuredAt: physicalAttempts[id]?.configuredAt, scheduleKind: kind, fixedScheduleAt: fixed, preAlert: alarm.countdownDuration?.preAlert, postAlert: alarm.countdownDuration?.postAlert, state: String(describing: alarm.state), fireDate: fireDates[id])
    }
  }

  func physicalProcedureActivityPrepared(run: PhysicalAcceptanceRun) -> Bool {
    guard physicalRunID == run.id,
          let procedure = run.schedule.events.first(where: { $0.kind == .procedure }),
          let start = try? NativeAlarmContract.dateTime(date: procedure.date, time: procedure.start)
    else { return false }
    return Activity<CommanderProcedureLiveActivityAttributes>.activities.contains {
      $0.attributes.stableId == procedure.stableId
        && $0.attributes.startAt == start
        && $0.content.state.projectionRevision == run.projectionRevision
        && ($0.activityState == .pending || $0.activityState == .active)
    }
  }

  static func clearPreviousPhysicalAcceptance(ownership: PhysicalAcceptanceOwnershipStore) async throws {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else {
      throw PhysicalAcceptanceError.wrongApplication
    }
    let ownedIDs = await ownership.allIDs()
    let alarms = try AlarmManager.shared.alarms
    let cleanup = PhysicalAcceptanceCleanupPlan(ownedIDs: ownedIDs, platformIDs: Set(alarms.map { $0.id.uuidString }))
    guard cleanup.unknownIDs.isEmpty else { throw PhysicalAcceptanceError.cleanupIncomplete }
    for alarm in alarms where cleanup.cancelIDs.contains(alarm.id.uuidString) {
      try AlarmManager.shared.cancel(id: alarm.id)
    }
    // Unknown IDs are never cancelled. They prevent a clean preflight instead.
    guard try AlarmManager.shared.alarms.isEmpty else { throw PhysicalAcceptanceError.cleanupIncomplete }
    for id in ownedIDs { await ownership.forget(id) }
    for activity in Activity<CommanderProcedureLiveActivityAttributes>.activities
      where activity.attributes.stableId.hasPrefix(PhysicalAcceptanceRun.stableIDPrefix) {
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

  private func reconcileProcedureLiveActivities(
    schedule: Schedule,
    projectionRevision: Int,
    now: Date = Date()
  ) async {
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
      if let match {
        let updatedContent = ActivityContent(
          state: CommanderProcedureLiveActivityAttributes.ContentState(
            projectionRevision: projectionRevision
          ),
          staleDate: match.endAt,
          relevanceScore: 1
        )
        await activity.update(updatedContent)
        continue
      }
      let finalContent = ActivityContent(
        state: CommanderProcedureLiveActivityAttributes.ContentState(
          projectionRevision: projectionRevision
        ),
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
        state: CommanderProcedureLiveActivityAttributes.ContentState(
          projectionRevision: projectionRevision
        ),
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

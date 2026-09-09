import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import OSLog
import SwiftUI
import UIKit
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

@MainActor
private enum CommanderRollingLiveActivity {
  nonisolated static func target(_ state: CommanderProcedureLiveActivityAttributes.ContentState) -> NativeAlarm? {
    guard let id = state.nextStableId, let title = state.nextTitle,
          let location = state.nextLocation, let kind = state.nextKind,
          let start = state.nextStartAt, let end = state.nextEndAt, let leave = state.nextLeaveAt else { return nil }
    return NativeAlarm(stableId: id, kind: kind, title: title, location: location,
      startAt: AlarmKitAdapter.localISO(start), endAt: AlarmKitAdapter.localISO(end),
      effectiveLeadTimeMinutes: Int(start.timeIntervalSince(leave) / 60), leaveAt: AlarmKitAdapter.localISO(leave))
  }

  nonisolated static func identity(_ activity: Activity<CommanderProcedureLiveActivityAttributes>) -> CommanderLiveActivityHandoff.Identity? {
    guard let target = target(activity.content.state) else { return nil }
    let source = activity.attributes
    return CommanderLiveActivityHandoff.Identity(scheduleVersion: source.scheduleVersion,
      sourceStableId: source.stableId, sourceTitle: source.title, sourceLocation: source.location,
      sourceKind: source.kind, sourceStartAt: source.startAt,
      sourceEndAt: source.endAt, target: target)
  }

  nonisolated static func matchesHandoff(_ activity: Activity<CommanderProcedureLiveActivityAttributes>,
    expected: CommanderLiveActivityHandoff.Identity?, now: Date) -> Bool {
    !activity.content.state.isDepartureStandby
      && CommanderLiveActivityHandoff.matches(actual: identity(activity), expected: expected, now: now)
  }

  static func cleanupExpired(protectedIDs: Set<String>, now: Date) async {
    for activity in Activity<CommanderProcedureLiveActivityAttributes>.activities
      where CommanderLiveActivityHandoff.needsCleanup(endAt: activity.attributes.endAt,
        hasVerifiedHandoff: protectedIDs.contains(activity.id), now: now) {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  nonisolated static func isPrepared(event: CommanderAlarmEventSnapshot, scheduleVersion: Int) -> Bool {
    guard let startAt = date(event.startAt), let endAt = date(event.endAt) else { return false }
    return Activity<CommanderProcedureLiveActivityAttributes>.activities.contains {
      !$0.content.state.isDepartureStandby && !$0.content.state.isDepartureBridge
        && $0.attributes.stableId == event.stableId
        && $0.attributes.scheduleVersion == scheduleVersion
        && $0.attributes.title == event.title && $0.attributes.location == event.location
        && $0.attributes.kind == event.kind && $0.attributes.iconKey == event.iconKey
        && abs($0.attributes.startAt.timeIntervalSince(startAt)) <= 1
        && abs($0.attributes.endAt.timeIntervalSince(endAt)) <= 1
        && AlarmKitAdapter.isOngoing($0.activityState)
    }
  }

  nonisolated static func date(_ localISO: String) -> Date? {
    try? NativeAlarmContract.date(fromLocalISO: localISO)
  }

  nonisolated static func state(
    projectionRevision: Int,
    next: CommanderAlarmEventSnapshot?
  ) -> CommanderProcedureLiveActivityAttributes.ContentState {
    guard let next,
          let startAt = date(next.startAt),
          let endAt = date(next.endAt),
          let leaveAt = date(next.leaveAt)
    else {
      return CommanderProcedureLiveActivityAttributes.ContentState(
        projectionRevision: projectionRevision
      )
    }
    return CommanderProcedureLiveActivityAttributes.ContentState(
      projectionRevision: projectionRevision,
      nextStableId: next.stableId,
      nextTitle: next.title,
      nextLocation: next.location,
      nextKind: next.kind,
      nextIconKey: next.iconKey,
      nextStartAt: startAt,
      nextEndAt: endAt,
      nextLeaveAt: leaveAt
    )
  }

  @discardableResult
  static func scheduleRunning(
    event: CommanderAlarmEventSnapshot,
    next: CommanderAlarmEventSnapshot?,
    scheduleVersion: Int,
    projectionRevision: Int = -1
  ) async -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "Živé aktivity nejsou povolené." }
    guard let startAt = date(event.startAt), let endAt = date(event.endAt) else {
      return "Živá aktivita má neplatný čas události."
    }
    guard endAt > Date() else { return nil }

    if isPrepared(event: event, scheduleVersion: scheduleVersion) { return nil }
    guard UIApplication.shared.applicationState == .active else {
      return "Chybí předem připravená živá aktivita: \(event.title). V backgroundu ji nelze vytvořit."
    }

    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: event.stableId,
      scheduleVersion: scheduleVersion,
      iconKey: event.iconKey,
      title: event.title,
      location: event.location,
      kind: event.kind,
      startAt: startAt,
      endAt: endAt
    )
    let content = ActivityContent(
      state: state(projectionRevision: projectionRevision, next: next),
      staleDate: endAt,
      relevanceScore: 1
    )

    do {
      if startAt <= Date() {
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard
        )
      } else {
        let alertTitle = event.kind == .meal ? "Jídlo začíná" : "Procedura začíná"
        let alert = ActivityKit.AlertConfiguration(
          title: LocalizedStringResource(stringLiteral: alertTitle),
          body: LocalizedStringResource(stringLiteral: event.title),
          sound: .default
        )
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard,
          alertConfiguration: alert,
          start: startAt
        )
      }
    } catch {
      let message = "Živou aktivitu se nepodařilo připravit: " + error.localizedDescription
      Logger(subsystem: Bundle.main.bundleIdentifier ?? "LazenskyCommander", category: "LiveActivity").error("\(message, privacy: .public)")
      CommanderPhysicalAcceptanceDiagnostics.record(message)
      return message
    }
    return nil
  }
}

struct CommanderAlarmStopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Pokračovat k události"
  static let description = IntentDescription("Po zastavení alarmu zachová stav VYRAZIT TEĎ až do začátku události.")
  static let supportedModes: IntentModes = [.background]
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID") var alarmID: String
  @Parameter(title: "Stable ID") var stableId: String
  @Parameter(title: "Verze rozpisu") var scheduleVersion: Int
  @Parameter(title: "Začátek") var startAt: String
  @Parameter(title: "Událost alarmu") var currentEventJSON: String
  @Parameter(title: "Další událost") var nextEventJSON: String
  @Parameter(title: "Canonical předání") var handoffJSON: String

  init() {
    alarmID = ""
    stableId = ""
    scheduleVersion = 0
    startAt = ""
    currentEventJSON = ""
    nextEventJSON = ""
    handoffJSON = ""
  }

  init(alarmID: UUID, metadata: CommanderAlarmMetadata, handoff: CommanderLiveActivityHandoff.Identity?) {
    self.alarmID = alarmID.uuidString
    stableId = metadata.stableId
    scheduleVersion = metadata.scheduleVersion
    startAt = metadata.startAt
    let current = CommanderAlarmEventSnapshot(
      stableId: metadata.stableId,
      iconKey: metadata.iconKey,
      title: metadata.title,
      location: metadata.location,
      kind: metadata.kind,
      startAt: metadata.startAt,
      endAt: metadata.endAt ?? metadata.startAt,
      leaveAt: metadata.leaveAt
    )
    currentEventJSON = Self.encode(current)
    nextEventJSON = Self.encode(metadata.nextEvent)
    handoffJSON = Self.encode(handoff)
  }

  func perform() async throws -> some IntentResult {
    CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno · \(stableId)")
    guard let startDate = CommanderRollingLiveActivity.date(startAt) else {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno, neplatný začátek · \(stableId)")
      return .result()
    }

    let now = Date()
    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities
    let expected = handoffJSON.data(using: .utf8).flatMap {
      try? JSONDecoder().decode(CommanderLiveActivityHandoff.Identity.self, from: $0)
    }
    let matches = activities.filter {
      expected?.target.stableId == stableId && expected?.scheduleVersion == scheduleVersion
        && expected?.target.startAt == startAt
        && CommanderRollingLiveActivity.matchesHandoff($0, expected: expected, now: now)
    }.sorted { $0.id < $1.id }
    let existingRed = matches.first {
      $0.content.state.isDepartureBridge && $0.activityState != .dismissed
    }
    let handoff = matches.first {
      existingRed == nil && !$0.content.state.isDepartureBridge
        && ($0.activityState == .active || $0.activityState == .stale)
    }
    let stopDisposition = CommanderLiveActivityHandoff.stopDisposition(
      hasHandoff: handoff != nil || existingRed != nil, startAt: startDate, now: now
    )
    let canBridgeHandoff = stopDisposition == .bridgeUntilStart

    var keptAlarmCard = false
    if let stoppedAlarmID = UUID(uuidString: alarmID) {
      for alarmActivity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities
        where alarmActivity.content.state.alarmID == stoppedAlarmID {
        if canBridgeHandoff {
          await alarmActivity.end(nil, dismissalPolicy: .immediate)
        } else if startDate > now {
          await alarmActivity.end(alarmActivity.content, dismissalPolicy: .after(startDate))
          keptAlarmCard = true
        } else {
          await alarmActivity.end(nil, dismissalPolicy: .immediate)
        }
      }
    }

    var bridgedHandoff = existingRed != nil
    if let handoff {
      if startDate > now {
        let old = handoff.content.state
        let red = CommanderProcedureLiveActivityAttributes.ContentState(
          projectionRevision: old.projectionRevision,
          phase: .departureBridge,
          nextStableId: old.nextStableId,
          nextTitle: old.nextTitle,
          nextLocation: old.nextLocation,
          nextKind: old.nextKind,
          nextIconKey: old.nextIconKey,
          nextStartAt: old.nextStartAt,
          nextEndAt: old.nextEndAt,
          nextLeaveAt: old.nextLeaveAt
        )
        await handoff.end(
          ActivityContent(state: red, staleDate: nil, relevanceScore: 1),
          dismissalPolicy: .after(startDate)
        )
        bridgedHandoff = true
      } else {
        await handoff.end(nil, dismissalPolicy: .immediate)
      }
    }

    if bridgedHandoff {
      CommanderPhysicalAcceptanceDiagnostics.record("Červená karta předána · \(stableId)")
    } else if keptAlarmCard {
      CommanderPhysicalAcceptanceDiagnostics.record("Červená AlarmKit karta ponechána · \(stableId)")
    } else if startDate <= now {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit proběhlo až po začátku · \(stableId)")
    } else {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno, chybí karta pro červený stav · \(stableId)")
    }

    if let current = Self.decode(currentEventJSON) {
      // The OS will start the pending activity. Stop only checks preparation;
      // it must not depend on foreground-only Activity.request succeeding here.
      if !CommanderRollingLiveActivity.isPrepared(event: current, scheduleVersion: scheduleVersion) {
        let message = "Chybí předem připravená živá aktivita po Zastavit · \(stableId)"
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "LazenskyCommander", category: "LiveActivity").error("\(message, privacy: .public)")
        CommanderPhysicalAcceptanceDiagnostics.record(message)
      }
    }

    let ownerID = existingRed?.id ?? handoff?.id
    await CommanderRollingLiveActivity.cleanupExpired(
      protectedIDs: Set([ownerID].compactMap { $0 }), now: now)

    return .result()
  }

  private static func encode<T: Encodable>(_ snapshot: T?) -> String {
    guard let snapshot,
          let data = try? JSONEncoder().encode(snapshot),
          let value = String(data: data, encoding: .utf8)
    else { return "" }
    return value
  }

  private static func decode(_ value: String) -> CommanderAlarmEventSnapshot? {
    guard !value.isEmpty, let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(CommanderAlarmEventSnapshot.self, from: data)
  }
}

actor AlarmKitAdapter: AlarmAdapting {
  private static let e2eOwnershipKey = "lazensky.commander.alarmkitOwned.e2e.v1"
  private let channel: ScheduleChannel
  private(set) var liveActivityIssue: String?
  private var scheduleContext: Schedule?
  private var leadTimeOverridesContext: LeadTimeOverrides?
  private var physicalRunID: UUID?
  private var physicalOwnership: PhysicalAcceptanceOwnershipStore?
  private var physicalAttempts: [String: (stableID: String, configuredAt: Date)] = [:]

  private struct ProcedureActivityCandidate {
    let event: ScheduleEvent
    let startAt: Date
    let endAt: Date
    let contentState: CommanderProcedureLiveActivityAttributes.ContentState
  }

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
    await prepare(schedule: schedule, projectionRevision: projectionRevision, overrides: nil)
  }

  func prepare(
    schedule: Schedule,
    projectionRevision: Int,
    overrides: LeadTimeOverrides?
  ) async {
    liveActivityIssue = nil
    scheduleContext = schedule
    leadTimeOverridesContext = overrides
    guard channel == .production || physicalRunID != nil else { return }
    await reconcileProcedureLiveActivities(
      schedule: schedule,
      projectionRevision: max(0, projectionRevision),
      overrides: overrides
    )
  }

  func presentationContext(for alarm: NativeAlarm) throws -> AlarmPresentationContext? {
    guard let schedule = scheduleContext else { return nil }
    return try AlarmPresentationContext(alarm: alarm, schedule: schedule, overrides: leadTimeOverridesContext)
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
    let nextSnapshot: CommanderAlarmEventSnapshot?
    if let event, let schedule {
      nextSnapshot = snapshotAfter(
        event: event,
        schedule: schedule,
        overrides: leadTimeOverridesContext
      )
    } else {
      nextSnapshot = nil
    }
    let metadata = CommanderAlarmMetadata(
      stableId: alarm.stableId,
      scheduleVersion: schedule?.scheduleVersion ?? 0,
      iconKey: iconKey,
      title: alarm.title,
      location: alarm.location,
      kind: alarm.kind,
      startAt: alarm.startAt,
      leaveAt: alarm.leaveAt,
      endAt: eventEndAt,
      nextEvent: nextSnapshot
    )
    let countdownAttributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert, countdown: countdown),
      metadata: metadata,
      tintColor: .teal
    )
    let alertOnlyAttributes = AlarmAttributes(
      presentation: AlarmPresentation(alert: alert),
      metadata: metadata,
      tintColor: .teal
    )
    let stopIntent = CommanderAlarmStopIntent(alarmID: id, metadata: metadata,
      handoff: schedule.flatMap { CommanderLiveActivityHandoff.identity(for: alarm, in: $0) })

    let now = Date()
    guard leaveAt > now else { throw AlarmKitAdapterError.departureDeadlinePassed }
    let verifiedHandoff = hasVerifiedFreeTimeHandoff(for: alarm, now: now)
    var countdownPlan: AlarmCountdownPlan
    if let schedule {
      countdownPlan = try AlarmCountdown.plan(for: alarm, in: schedule, now: now)
    } else {
      countdownPlan = AlarmCountdown.plan(
        leaveAt: leaveAt,
        countdownWindow: AlarmCountdown.maximumWindow,
        now: now
      )
    }

    // A zero gap in the schedule is not evidence of a visible handoff either.
    if !verifiedHandoff, countdownPlan.countdownWindow == 0 {
      countdownPlan = AlarmCountdown.plan(leaveAt: leaveAt, countdownWindow: AlarmCountdown.maximumWindow, now: now)
    }
    let configuration: AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>
    if verifiedHandoff {
      configuration = .alarm(
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: alertOnlyAttributes,
        stopIntent: stopIntent,
        sound: .default
      )
    } else if countdownPlan.countdownWindow > 0 {
      if let schedule, CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarm, in: schedule) {
        CommanderPhysicalAcceptanceDiagnostics.record("Handoff chybí, používám vlastní countdown · \(alarm.stableId)")
      }
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
      throw AlarmKitAdapterError.departureDeadlinePassed
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
        throw AlarmAdapterError.timingReadbackUnavailable
      }
      result[platformID] = deadline
    }
    return result
  }

  func invalidPlatformPresentationAlarmIDs(for alarms: [String: NativeAlarm]) async throws -> Set<String> {
    let now = Date()
    return Set(try AlarmManager.shared.alarms.compactMap { observed in
      let id = observed.id.uuidString
      guard let expected = alarms[id],
            (observed.countdownDuration?.preAlert ?? 0) <= 0,
            !hasVerifiedFreeTimeHandoff(for: expected, now: now) else { return nil }
      return id
    })
  }

  private func hasVerifiedFreeTimeHandoff(for alarm: NativeAlarm, now: Date) -> Bool {
    guard let schedule = scheduleContext else { return false }
    let expected = CommanderLiveActivityHandoff.identity(for: alarm, in: schedule)
    return Activity<CommanderProcedureLiveActivityAttributes>.activities.contains { activity in
      !activity.content.state.isDepartureBridge
        && (activity.activityState == .active || activity.activityState == .stale)
        && CommanderRollingLiveActivity.matchesHandoff(activity, expected: expected, now: now)
    }
  }

  func cleanupFinishedLiveActivities(now: Date = Date()) async {
    guard let schedule = scheduleContext else { return }
    var retainedTargets = Set<String>()
    let protected = Activity<CommanderProcedureLiveActivityAttributes>.activities.sorted {
      if $0.content.state.isDepartureBridge != $1.content.state.isDepartureBridge {
        return $0.content.state.isDepartureBridge
      }
      return $0.id < $1.id
    }.filter { activity in
      guard let storedTarget = bridgeTarget(activity.content.state),
            let event = schedule.events.first(where: { $0.stableId == storedTarget.stableId }),
            let alarm = try? NativeAlarmContract.alarm(event: event, schedule: schedule, overrides: leadTimeOverridesContext),
            CommanderRollingLiveActivity.matchesHandoff(activity,
              expected: CommanderLiveActivityHandoff.identity(for: alarm, in: schedule), now: now),
            activity.activityState != .dismissed,
            activity.content.state.isDepartureBridge || activity.activityState == .active || activity.activityState == .stale
      else { return false }
      return retainedTargets.insert(alarm.stableId).inserted
    }
    await CommanderRollingLiveActivity.cleanupExpired(protectedIDs: Set(protected.map(\.id)), now: now)
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

  func physicalVerifiedHandoffStableIDs(run: PhysicalAcceptanceRun) throws -> Set<String> {
    guard physicalRunID == run.id else { return [] }
    let now = Date()
    return Set(try run.payload().alarms.filter { hasVerifiedFreeTimeHandoff(for: $0, now: now) }.map(\.stableId))
  }

  func physicalProcedureActivityPrepared(run: PhysicalAcceptanceRun) -> Bool {
    guard physicalRunID == run.id else { return false }
    let expected = CommanderLiveActivityHandoff.runningEvents(in: run.schedule, now: run.now)
    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities.filter {
      $0.attributes.stableId.hasPrefix(run.namespace) && Self.isOngoing($0.activityState)
    }
    return CommanderLiveActivityHandoff.hasCompleteRunningPreparation(
      expectedIDs: expected.map(\.stableId), preparedIDs: activities.map { $0.attributes.stableId }
    ) && expected.allSatisfy { event in
      guard let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
            let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end),
            let snapshot = eventSnapshot(event, startAt: start, endAt: end,
                                         schedule: run.schedule, overrides: run.overrides) else { return false }
      return CommanderRollingLiveActivity.isPrepared(event: snapshot, scheduleVersion: run.schedule.scheduleVersion)
        && activities.filter { $0.attributes.stableId == event.stableId
          && $0.content.state.projectionRevision == run.projectionRevision }.count == 1
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

  private func reconcileProcedureLiveActivities(
    schedule: Schedule,
    projectionRevision: Int,
    overrides: LeadTimeOverrides?,
    now: Date = Date()
  ) async {
    await cleanupFinishedLiveActivities(now: now)
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      liveActivityIssue = "Živé aktivity nejsou povolené."
      return
    }

    let candidates: [ProcedureActivityCandidate] = CommanderLiveActivityHandoff.runningEvents(in: schedule, now: now).compactMap { event in
      guard let startAt = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
            let endAt = try? NativeAlarmContract.dateTime(date: event.date, time: event.end),
            endAt > now
      else { return nil }
      return ProcedureActivityCandidate(
        event: event,
        startAt: startAt,
        endAt: endAt,
        contentState: procedureContentState(
          after: event,
          endAt: endAt,
          schedule: schedule,
          overrides: overrides,
          projectionRevision: projectionRevision
        )
      )
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.event.stableId < $1.event.stableId
    }

    guard let primary = candidates.first else {
      for activity in Activity<CommanderProcedureLiveActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      return
    }

    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities.sorted { $0.id < $1.id }
    let primaryAlarm = try? NativeAlarmContract.alarm(event: primary.event, schedule: schedule, overrides: overrides)
    let expectedHandoff = primaryAlarm.flatMap { CommanderLiveActivityHandoff.identity(for: $0, in: schedule) }
    let redHandoff = existing.first {
      $0.content.state.isDepartureBridge && $0.activityState != .dismissed
        && CommanderRollingLiveActivity.matchesHandoff($0, expected: expectedHandoff, now: now)
    }
    let priorHandoff = existing.first { activity in
      let state = activity.content.state
      return redHandoff == nil && !state.isDepartureStandby
        && !state.isDepartureBridge
        && CommanderRollingLiveActivity.matchesHandoff(activity, expected: expectedHandoff, now: now)
        && (activity.activityState == .active || activity.activityState == .stale)
    }
    // A prior free-time/red card cannot substitute for the target event's
    // scheduled activity. Keep one pending/running activity per canonical event.
    let desiredRunning = candidates
    var retainedRunningIDs = Set<String>()
    var retainedBridge = false
    for activity in existing {
      let state = activity.content.state
      if let priorHandoff, activity.id == priorHandoff.id {
        // The retained card must use the newly accepted schedule and local lead time.
        let next = eventSnapshot(primary.event, startAt: primary.startAt, endAt: primary.endAt,
                                 schedule: schedule, overrides: overrides)
        await activity.update(ActivityContent(
          state: CommanderRollingLiveActivity.state(projectionRevision: projectionRevision, next: next),
          staleDate: activity.attributes.endAt, relevanceScore: 1
        ))
        continue
      }

      if state.isDepartureBridge, activity.id == redHandoff?.id, !retainedBridge, priorHandoff == nil,
         activity.activityState != .dismissed,
         CommanderRollingLiveActivity.matchesHandoff(activity, expected: expectedHandoff, now: now) {
        // An ended activity can still be visible under .after(startAt). Do not dismiss it early.
        retainedBridge = true
        continue
      }

      // Compatibility cleanup for older builds that created a hidden standby activity.
      if state.isDepartureStandby || state.isDepartureBridge {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }

      let match = desiredRunning.first { item in
        activity.attributes.stableId == item.event.stableId
          && activity.attributes.scheduleVersion == schedule.scheduleVersion
          && activity.attributes.title == item.event.title
          && activity.attributes.location == item.event.location
          && activity.attributes.kind == item.event.kind
          && activity.attributes.iconKey == (CommanderVisualAssets.icon(for: item.event)?.key ?? "")
          && abs(activity.attributes.startAt.timeIntervalSince(item.startAt)) <= 1
          && abs(activity.attributes.endAt.timeIntervalSince(item.endAt)) <= 1
      }
      if let match, CommanderLiveActivityHandoff.retainPrepared(stableId: match.event.stableId,
        matchesCanonical: true, ongoing: Self.isOngoing(activity.activityState), retainedIDs: &retainedRunningIDs) {
        await activity.update(ActivityContent(
          state: match.contentState,
          staleDate: match.endAt,
          relevanceScore: 1
        ))
      } else {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }

    for item in desiredRunning {
      await prepareRunning(item, scheduleVersion: schedule.scheduleVersion, now: now)
    }
  }

  private func prepareRunning(
    _ item: ProcedureActivityCandidate,
    scheduleVersion: Int,
    now: Date
  ) async {
    guard let schedule = scheduleContext,
          let event = eventSnapshot(item.event, startAt: item.startAt, endAt: item.endAt,
                                    schedule: schedule, overrides: leadTimeOverridesContext) else { return }
    if let issue = await CommanderRollingLiveActivity.scheduleRunning(
      event: event,
      next: snapshotAfter(event: item.event, schedule: schedule, overrides: leadTimeOverridesContext),
      scheduleVersion: scheduleVersion,
      projectionRevision: item.contentState.projectionRevision
    ) {
      liveActivityIssue = liveActivityIssue.map { $0 + "\n" + issue } ?? issue
    }
  }

  private func bridgeTarget(_ state: CommanderProcedureLiveActivityAttributes.ContentState) -> NativeAlarm? {
    CommanderRollingLiveActivity.target(state)
  }

  private func procedureContentState(
    after event: ScheduleEvent,
    endAt: Date,
    schedule: Schedule,
    overrides: LeadTimeOverrides?,
    projectionRevision: Int
  ) -> CommanderProcedureLiveActivityAttributes.ContentState {
    guard let next = nextEvent(after: event, endAt: endAt, schedule: schedule),
          let lead = try? NativeAlarmContract.effectiveLeadTime(
            event: next.event,
            schedule: schedule,
            overrides: overrides
          )
    else {
      return CommanderProcedureLiveActivityAttributes.ContentState(
        projectionRevision: projectionRevision
      )
    }
    return CommanderProcedureLiveActivityAttributes.ContentState(
      projectionRevision: projectionRevision,
      nextStableId: next.event.stableId,
      nextTitle: next.event.title,
      nextLocation: next.event.location,
      nextKind: next.event.kind,
      nextIconKey: CommanderVisualAssets.icon(for: next.event)?.key,
      nextStartAt: next.startAt,
      nextEndAt: next.endAt,
      nextLeaveAt: next.startAt.addingTimeInterval(TimeInterval(-lead * 60))
    )
  }

  private func snapshotAfter(
    event: ScheduleEvent,
    schedule: Schedule,
    overrides: LeadTimeOverrides?
  ) -> CommanderAlarmEventSnapshot? {
    guard let endAt = try? NativeAlarmContract.dateTime(date: event.date, time: event.end),
          let next = nextEvent(after: event, endAt: endAt, schedule: schedule)
    else { return nil }
    return eventSnapshot(
      next.event,
      startAt: next.startAt,
      endAt: next.endAt,
      schedule: schedule,
      overrides: overrides
    )
  }

  private func eventSnapshot(
    _ event: ScheduleEvent,
    startAt: Date,
    endAt: Date,
    schedule: Schedule,
    overrides: LeadTimeOverrides?
  ) -> CommanderAlarmEventSnapshot? {
    guard let lead = try? NativeAlarmContract.effectiveLeadTime(
      event: event,
      schedule: schedule,
      overrides: overrides
    ) else { return nil }
    return CommanderAlarmEventSnapshot(
      stableId: event.stableId,
      iconKey: CommanderVisualAssets.icon(for: event)?.key ?? "",
      title: event.title,
      location: event.location,
      kind: event.kind,
      startAt: Self.localISO(startAt),
      endAt: Self.localISO(endAt),
      leaveAt: Self.localISO(startAt.addingTimeInterval(TimeInterval(-lead * 60)))
    )
  }

  private func nextEvent(
    after event: ScheduleEvent,
    endAt: Date,
    schedule: Schedule
  ) -> (event: ScheduleEvent, startAt: Date, endAt: Date)? {
    guard let next = CommanderLiveActivityHandoff.nextEvent(after: event, in: schedule),
          let start = try? NativeAlarmContract.dateTime(date: next.date, time: next.start),
          let end = try? NativeAlarmContract.dateTime(date: next.date, time: next.end)
    else { return nil }
    return (event: next, startAt: start, endAt: end)
  }

  fileprivate static func isOngoing(_ state: ActivityState) -> Bool {
    state == .pending || state == .active || state == .stale
  }

  private static func eventOrder(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
    if lhs.date != rhs.date { return lhs.date < rhs.date }
    if lhs.start != rhs.start { return lhs.start < rhs.start }
    return lhs.stableId < rhs.stableId
  }

  private static func localISO(date: String, time: String) -> String {
    let normalized = time.count == 5 ? time + ":00" : time
    return "\(date)T\(normalized)"
  }

  fileprivate static func localISO(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")!
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
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

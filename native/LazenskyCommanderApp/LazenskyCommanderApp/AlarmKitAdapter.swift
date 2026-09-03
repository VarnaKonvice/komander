import ActivityKit
import AlarmKit
import AppIntents
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

private enum CommanderRollingLiveActivity {
  static func date(_ localISO: String) -> Date? {
    try? NativeAlarmContract.date(fromLocalISO: localISO)
  }

  static func state(
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

  static func scheduleRunning(
    event: CommanderAlarmEventSnapshot,
    next: CommanderAlarmEventSnapshot?,
    scheduleVersion: Int,
    projectionRevision: Int = -1
  ) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled,
          let startAt = date(event.startAt),
          let endAt = date(event.endAt),
          endAt > Date()
    else { return }

    let exists = Activity<CommanderProcedureLiveActivityAttributes>.activities.contains {
      !$0.content.state.isDepartureStandby
        && !$0.content.state.isDepartureBridge
        && $0.attributes.stableId == event.stableId
        && abs($0.attributes.startAt.timeIntervalSince(startAt)) <= 1
        && AlarmKitAdapter.isOngoing($0.activityState)
    }
    if exists { return }

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
      return
    }
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

  init() {
    alarmID = ""
    stableId = ""
    scheduleVersion = 0
    startAt = ""
    currentEventJSON = ""
    nextEventJSON = ""
  }

  init(alarmID: UUID, metadata: CommanderAlarmMetadata) {
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
  }

  func perform() async throws -> some IntentResult {
    CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno · \(stableId)")
    guard let startDate = CommanderRollingLiveActivity.date(startAt) else {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno, neplatný začátek · \(stableId)")
      return .result()
    }

    var keptAlarmCard = false
    if let stoppedAlarmID = UUID(uuidString: alarmID) {
      for alarmActivity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities
        where alarmActivity.content.state.alarmID == stoppedAlarmID {
        if startDate > Date() {
          await alarmActivity.end(nil, dismissalPolicy: .after(startDate))
          keptAlarmCard = true
        } else {
          await alarmActivity.end(nil, dismissalPolicy: .immediate)
        }
      }
    }

    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities
    let handoff = activities.first {
      let state = $0.content.state
      return !state.isDepartureStandby
        && !state.isDepartureBridge
        && state.nextStableId == stableId
        && state.nextStartAt.map { abs($0.timeIntervalSince(startDate)) <= 1 } == true
        && AlarmKitAdapter.isOngoing($0.activityState)
    }
    if let handoff {
      await handoff.end(nil, dismissalPolicy: .immediate)
    }

    if keptAlarmCard {
      CommanderPhysicalAcceptanceDiagnostics.record("Červená AlarmKit karta ponechána · \(stableId)")
    } else if startDate <= Date() {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit proběhlo až po začátku · \(stableId)")
    } else {
      CommanderPhysicalAcceptanceDiagnostics.record("Zastavit spuštěno, chybí AlarmKit karta · \(stableId)")
    }

    if let current = Self.decode(currentEventJSON) {
      await CommanderRollingLiveActivity.scheduleRunning(
        event: current,
        next: Self.decode(nextEventJSON),
        scheduleVersion: scheduleVersion
      )
    }

    return .result()
  }

  private static func encode(_ snapshot: CommanderAlarmEventSnapshot?) -> String {
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
  fileprivate static let maximumCommanderActivities = 1
  private static let e2eOwnershipKey = "lazensky.commander.alarmkitOwned.e2e.v1"
  private let channel: ScheduleChannel
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
    scheduleContext = schedule
    leadTimeOverridesContext = overrides
    guard channel == .production || physicalRunID != nil else { return }
    await reconcileProcedureLiveActivities(
      schedule: schedule,
      projectionRevision: max(0, projectionRevision),
      overrides: overrides
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
    let stopIntent = CommanderAlarmStopIntent(alarmID: id, metadata: metadata)

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
    if hasFreeTimeHandoff(for: alarm) {
      configuration = .alarm(
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: alertOnlyAttributes,
        stopIntent: stopIntent,
        sound: .default
      )
    } else if countdownPlan.countdownWindow > 0 {
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

  private func hasFreeTimeHandoff(for alarm: NativeAlarm) -> Bool {
    guard let schedule = scheduleContext,
          let target = schedule.events.first(where: { $0.stableId == alarm.stableId }),
          let targetStart = try? NativeAlarmContract.dateTime(date: target.date, time: target.start),
          let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    else { return false }

    for candidate in schedule.events
      where candidate.stableId != target.stableId && candidate.date == target.date {
      guard let candidateEnd = try? NativeAlarmContract.dateTime(
        date: candidate.date,
        time: candidate.end
      ), candidateEnd <= leaveAt else { continue }

      let next = schedule.events.compactMap { event -> (ScheduleEvent, Date)? in
        guard event.stableId != candidate.stableId,
              event.date == candidate.date,
              let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
              start >= candidateEnd
        else { return nil }
        return (event, start)
      }.sorted {
        if $0.1 != $1.1 { return $0.1 < $1.1 }
        return $0.0.stableId < $1.0.stableId
      }.first

      if next?.0.stableId == target.stableId,
         next.map({ abs($0.1.timeIntervalSince(targetStart)) <= 1 }) == true {
        return true
      }
    }
    return false
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

  func physicalProcedureActivityPrepared(run: PhysicalAcceptanceRun) -> Bool {
    guard physicalRunID == run.id,
          let first = run.schedule.events.sorted(by: Self.eventOrder).first,
          let firstStart = try? NativeAlarmContract.dateTime(date: first.date, time: first.start)
    else { return false }

    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities.filter {
      $0.attributes.stableId.hasPrefix(run.namespace) && Self.isOngoing($0.activityState)
    }
    let running = activities.filter {
      !$0.content.state.isDepartureStandby
        && !$0.content.state.isDepartureBridge
        && $0.attributes.stableId == first.stableId
        && abs($0.attributes.startAt.timeIntervalSince(firstStart)) <= 1
        && $0.content.state.projectionRevision == run.projectionRevision
    }
    return activities.count == Self.maximumCommanderActivities
      && running.count == 1
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
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

    let candidates: [ProcedureActivityCandidate] = schedule.events.compactMap { event in
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

    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities
    let priorHandoff = existing.first { activity in
      let state = activity.content.state
      return !state.isDepartureStandby
        && !state.isDepartureBridge
        && state.nextStableId == primary.event.stableId
        && Self.isOngoing(activity.activityState)
    }
    let desiredRunning: [ProcedureActivityCandidate]
    if priorHandoff != nil {
      desiredRunning = []
    } else {
      desiredRunning = [primary]
    }

    for activity in existing {
      let state = activity.content.state
      if let priorHandoff, activity.id == priorHandoff.id { continue }

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
          && abs(activity.attributes.startAt.timeIntervalSince(item.startAt)) <= 1
          && abs(activity.attributes.endAt.timeIntervalSince(item.endAt)) <= 1
      }
      if let match {
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
    let exists = Activity<CommanderProcedureLiveActivityAttributes>.activities.contains {
      !$0.content.state.isDepartureStandby
        && !$0.content.state.isDepartureBridge
        && $0.attributes.stableId == item.event.stableId
        && abs($0.attributes.startAt.timeIntervalSince(item.startAt)) <= 1
        && Self.isOngoing($0.activityState)
    }
    if exists { return }

    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: item.event.stableId,
      scheduleVersion: scheduleVersion,
      iconKey: CommanderVisualAssets.icon(for: item.event)?.key ?? "",
      title: item.event.title,
      location: item.event.location,
      kind: item.event.kind,
      startAt: item.startAt,
      endAt: item.endAt
    )
    let content = ActivityContent(
      state: item.contentState,
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
        let alertTitle = item.event.kind == .meal ? "Jídlo začíná" : "Procedura začíná"
        let alert = ActivityKit.AlertConfiguration(
          title: LocalizedStringResource(stringLiteral: alertTitle),
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
      return
    }
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
    schedule.events.compactMap { candidate -> (ScheduleEvent, Date, Date)? in
      guard candidate.stableId != event.stableId,
            candidate.date == event.date,
            let startAt = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.start),
            let candidateEndAt = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.end),
            startAt >= endAt
      else { return nil }
      return (candidate, startAt, candidateEndAt)
    }.sorted {
      if $0.1 != $1.1 { return $0.1 < $1.1 }
      return $0.0.stableId < $1.0.stableId
    }.first.map { (event: $0.0, startAt: $0.1, endAt: $0.2) }
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

  private static func localISO(_ date: Date) -> String {
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
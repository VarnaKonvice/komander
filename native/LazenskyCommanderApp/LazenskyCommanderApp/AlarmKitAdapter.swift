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

struct CommanderAlarmStopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Pokračovat k události"
  static let description = IntentDescription("Po zastavení alarmu zachová stav VYRAZIT TEĎ až do začátku události.")
  static let supportedModes: IntentModes = [.background]
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID") var alarmID: String
  @Parameter(title: "Stable ID") var stableId: String
  @Parameter(title: "Verze rozpisu") var scheduleVersion: Int
  @Parameter(title: "Ikona") var iconKey: String
  @Parameter(title: "Název") var eventTitle: String
  @Parameter(title: "Místo") var location: String
  @Parameter(title: "Jídlo") var isMeal: Bool
  @Parameter(title: "Začátek") var startAt: String
  @Parameter(title: "Odchod") var leaveAt: String
  @Parameter(title: "Konec") var endAt: String

  init() {
    alarmID = ""
    stableId = ""
    scheduleVersion = 0
    iconKey = ""
    eventTitle = ""
    location = ""
    isMeal = false
    startAt = ""
    leaveAt = ""
    endAt = ""
  }

  init(alarmID: UUID, metadata: CommanderAlarmMetadata) {
    self.alarmID = alarmID.uuidString
    stableId = metadata.stableId
    scheduleVersion = metadata.scheduleVersion
    iconKey = metadata.iconKey
    eventTitle = metadata.title
    location = metadata.location
    isMeal = metadata.kind == .meal
    startAt = metadata.startAt
    leaveAt = metadata.leaveAt
    endAt = metadata.endAt ?? metadata.startAt
  }

  func perform() async throws -> some IntentResult {
    guard let startDate = try? NativeAlarmContract.date(fromLocalISO: startAt),
          let endDate = try? NativeAlarmContract.date(fromLocalISO: endAt)
    else { return .result() }

    let bridgeStableID = stableId + ".departureBridge"
    let now = Date()

    // Scheduled Live Activities count against the same ActivityKit limit as active ones.
    // The AlarmKit activity can still exist while its stop intent is running, so end that
    // just-stopped system activity before asking ActivityKit for the Commander red bridge.
    if let stoppedAlarmID = UUID(uuidString: alarmID) {
      for alarmActivity in Activity<AlarmAttributes<CommanderAlarmMetadata>>.activities
        where alarmActivity.content.state.alarmID == stoppedAlarmID {
        await alarmActivity.end(nil, dismissalPolicy: .immediate)
      }
    }

    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities
    let matchingHandoffs = activities.filter { activity in
      let state = activity.content.state
      guard !state.isDepartureBridge,
            activity.attributes.endAt <= now
      else { return false }
      let sameNextStart = state.nextStartAt.map { abs($0.timeIntervalSince(startDate)) <= 1 } == true
      return state.nextTitle == eventTitle && sameNextStart
    }

    if activities.contains(where: {
      $0.content.state.isDepartureBridge
        && $0.attributes.stableId == bridgeStableID
        && ($0.activityState == .pending || $0.activityState == .active)
    }) {
      for handoff in matchingHandoffs {
        await handoff.end(nil, dismissalPolicy: .immediate)
      }
      return .result()
    }

    guard startDate > now, ActivityAuthorizationInfo().areActivitiesEnabled else {
      for handoff in matchingHandoffs {
        await handoff.end(nil, dismissalPolicy: .immediate)
      }
      return .result()
    }

    let kind: ScheduleKind = isMeal ? .meal : .procedure
    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: bridgeStableID,
      scheduleVersion: scheduleVersion,
      iconKey: iconKey,
      title: eventTitle,
      location: location,
      kind: kind,
      startAt: startDate,
      endAt: endDate
    )
    let content = ActivityContent(
      state: CommanderProcedureLiveActivityAttributes.ContentState(
        projectionRevision: -1,
        phase: .departureBridge
      ),
      staleDate: startDate,
      relevanceScore: 1
    )

    do {
      _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: nil,
        style: .standard
      )
      // Only remove the blue handoff after ActivityKit accepted the red bridge.
      // If the bridge request fails, keeping the blue card is safer than a blank lock screen.
      for handoff in matchingHandoffs {
        await handoff.end(nil, dismissalPolicy: .immediate)
      }
    } catch {
      // The existing handoff deliberately remains visible as a fail-safe.
    }

    return .result()
  }
}

actor AlarmKitAdapter: AlarmAdapting {
  private static let maximumPreparedProcedureActivities = 3
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
    // This projection is deliberately best-effort and independent from AlarmKit safety.
    // A Live Activity failure must never block alarm reconciliation.
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
    let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: NativeAlarmPresentation.title(for: alarm)))
    let schedule = scheduleContext
    let event = schedule?.events.first(where: { $0.stableId == alarm.stableId })
    let iconKey = event.flatMap { CommanderVisualAssets.icon(for: $0)?.key } ?? ""
    let countdown = AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: "Odchod za \(alarm.title)"))
    let eventEndAt = event.map { event in
      let normalizedEnd = event.end.count == 5 ? event.end + ":00" : event.end
      return "\(event.date)T\(normalizedEnd)"
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
      endAt: eventEndAt
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
    if hasPreparedHandoff(for: alarm) {
      // A Commander event owns a real free interval through leaveAt. Schedule only
      // the system alert; a pre-alert countdown would duplicate the blue handoff.
      // AlarmKit's own sample uses an alert-only presentation for alarms without countdown mode.
      configuration = .alarm(
        schedule: .fixed(countdownPlan.scheduledAlertAt),
        attributes: alertOnlyAttributes,
        stopIntent: stopIntent,
        sound: .default
      )
    } else if countdownPlan.countdownWindow > 0 {
      configuration = AlarmManager.AlarmConfiguration<CommanderAlarmMetadata>(
        countdownDuration: Alarm.CountdownDuration(preAlert: countdownPlan.countdownWindow, postAlert: nil),
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
        throw AlarmAdapterError.timingReadbackUnavailable
      }
      result[platformID] = deadline
    }
    return result
  }

  private func hasPreparedHandoff(for alarm: NativeAlarm) -> Bool {
    guard let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
          let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    else { return false }

    return Activity<CommanderProcedureLiveActivityAttributes>.activities.contains { activity in
      let state = activity.content.state
      guard !state.isDepartureBridge,
            activity.attributes.endAt <= leaveAt,
            state.nextTitle == alarm.title,
            state.nextStartAt.map({ abs($0.timeIntervalSince(startAt)) <= 1 }) == true,
            state.nextLeaveAt.map({ abs($0.timeIntervalSince(leaveAt)) <= 1 }) == true
      else { return false }
      return activity.activityState == .pending
        || activity.activityState == .active
        || activity.activityState == .stale
    }
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
    guard physicalRunID == run.id else { return false }
    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities
    return run.schedule.events.allSatisfy { event in
      guard let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start) else {
        return false
      }
      return activities.contains {
        $0.attributes.stableId == event.stableId
          && $0.attributes.startAt == start
          && !$0.content.state.isDepartureBridge
          && $0.content.state.projectionRevision == run.projectionRevision
          && ($0.activityState == .pending || $0.activityState == .active)
      }
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
    guard try AlarmManager.shared.alarms.isEmpty else { throw PhysicalAcceptanceError.cleanupIncomplete }
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

    let desired = Array(candidates.prefix(Self.maximumPreparedProcedureActivities))
    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities

    for activity in existing {
      if activity.content.state.isDepartureBridge {
        if activity.activityState == .stale || activity.attributes.startAt <= now {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        continue
      }

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
          state: match.contentState,
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
        !activity.content.state.isDepartureBridge
          && activity.attributes.stableId == item.event.stableId
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
        continue
      }
    }

    _ = Activity<CommanderProcedureLiveActivityAttributes>.activities
  }

  private func procedureContentState(
    after event: ScheduleEvent,
    endAt: Date,
    schedule: Schedule,
    overrides: LeadTimeOverrides?,
    projectionRevision: Int
  ) -> CommanderProcedureLiveActivityAttributes.ContentState {
    let nextCandidates: [(event: ScheduleEvent, startAt: Date, endAt: Date)] = schedule.events.compactMap {
      (candidate: ScheduleEvent) -> (event: ScheduleEvent, startAt: Date, endAt: Date)? in
      guard candidate.stableId != event.stableId,
            candidate.date == event.date,
            let startAt = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.start),
            let candidateEndAt = try? NativeAlarmContract.dateTime(date: candidate.date, time: candidate.end),
            startAt >= endAt
      else { return nil }
      return (event: candidate, startAt: startAt, endAt: candidateEndAt)
    }
    let next = nextCandidates.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.event.stableId < $1.event.stableId
    }.first

    guard let next,
          let leadTimeMinutes = try? NativeAlarmContract.effectiveLeadTime(
            event: next.event,
            schedule: schedule,
            overrides: overrides
          )
    else {
      return CommanderProcedureLiveActivityAttributes.ContentState(
        projectionRevision: projectionRevision
      )
    }

    let leaveAt = next.startAt.addingTimeInterval(TimeInterval(-leadTimeMinutes * 60))
    return CommanderProcedureLiveActivityAttributes.ContentState(
      projectionRevision: projectionRevision,
      nextTitle: next.event.title,
      nextLocation: next.event.location,
      nextKind: next.event.kind,
      nextIconKey: CommanderVisualAssets.icon(for: next.event)?.key,
      nextStartAt: next.startAt,
      nextEndAt: next.endAt,
      nextLeaveAt: leaveAt
    )
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

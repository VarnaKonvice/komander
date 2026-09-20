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

private actor CommanderAlarmStopHandoffGate {
  static let shared = CommanderAlarmStopHandoffGate()

  private var tail: Task<Void, Never>?
  private var generation = 0

  func run(_ operation: @escaping @Sendable () async -> Void) async {
    generation += 1
    let currentGeneration = generation
    let previous = tail
    let task = Task {
      if let previous { await previous.value }
      await operation()
    }
    tail = task
    await task.value
    if currentGeneration == generation {
      tail = nil
    }
  }
}

struct CommanderAlarmStopIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "Potvrdit odchod"
  static let description = IntentDescription("Zastaví systémový AlarmKit alarm. Commander Live Activity má vlastní životní cyklus.")
  static let supportedModes: IntentModes = [.background]
  static let isDiscoverable = false

  @Parameter(title: "Alarm ID") var alarmID: String
  @Parameter(title: "Commander payload") var activityPayload: String

  init() {
    alarmID = ""
    activityPayload = ""
  }

  init(alarmID: UUID, metadata: CommanderAlarmMetadata) {
    self.alarmID = alarmID.uuidString
    activityPayload = (try? JSONEncoder().encode(metadata).base64EncodedString()) ?? ""
  }

  func perform() async throws -> some IntentResult {
    CommanderPhysicalAcceptanceDiagnostics.record("Stop · \(alarmID)")
    guard let data = Data(base64Encoded: activityPayload),
          let metadata = try? JSONDecoder().decode(CommanderAlarmMetadata.self, from: data)
    else {
      CommanderPhysicalAcceptanceDiagnostics.record("Stop → Commander nevytvořen · neplatný payload")
      return .result()
    }

    await CommanderAlarmStopHandoffGate.shared.run {
      await Self.applyHandoff(metadata: metadata)
    }
    return .result()
  }

  private static func applyHandoff(metadata: CommanderAlarmMetadata) async {
    guard let endISO = metadata.endAt,
          let leaveAt = try? NativeAlarmContract.date(fromLocalISO: metadata.leaveAt),
          let startAt = try? NativeAlarmContract.date(fromLocalISO: metadata.startAt),
          let endAt = try? NativeAlarmContract.date(fromLocalISO: endISO),
          endAt > Date(),
          ActivityAuthorizationInfo().areActivitiesEnabled
    else {
      CommanderPhysicalAcceptanceDiagnostics.record(
        "Stop → Commander nevytvořen · událost skončila nebo Live Activities nejsou povolené"
      )
      return
    }

    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: metadata.stableId,
      scheduleVersion: metadata.scheduleVersion,
      iconKey: metadata.iconKey,
      title: metadata.title,
      location: metadata.location,
      kind: metadata.kind,
      leaveAt: leaveAt,
      startAt: startAt,
      endAt: endAt,
      nextEvent: nil
    )
    let currentEvent = CommanderAlarmEventSnapshot(
      stableId: metadata.stableId,
      iconKey: metadata.iconKey,
      title: metadata.title,
      location: metadata.location,
      kind: metadata.kind,
      startAt: metadata.startAt,
      endAt: endISO,
      leaveAt: metadata.leaveAt
    )
    let incomingEvents = [currentEvent, metadata.nextEvent].compactMap { $0 }
    let ongoing = Activity<CommanderProcedureLiveActivityAttributes>.activities
      .filter { Self.isOngoing($0.activityState) }
      .sorted { Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState) }

    if let keeper = ongoing.first {
      let existingEvents = keeper.content.state.events.isEmpty
        ? Self.seedEvents(from: keeper.attributes)
        : keeper.content.state.events
      let events = Self.mergeEvents(existing: existingEvents, incoming: incomingEvents, now: Date())
      let state = CommanderProcedureLiveActivityPolicy.contentState(
        scheduleVersion: metadata.scheduleVersion,
        projectionRevision: metadata.projectionRevision ?? 0,
        events: events,
        attributes: keeper.attributes
      )
      let content = ActivityContent(
        state: state,
        staleDate: Self.staleDate(for: state.events),
        relevanceScore: 1_000
      )
      await keeper.update(content)
      for duplicate in ongoing.dropFirst() {
        await duplicate.end(nil, dismissalPolicy: .immediate)
      }
      CommanderPhysicalAcceptanceDiagnostics.record("Stop → jediný Commander aktualizován · \(metadata.stableId)")
      return
    }

    let events = Self.mergeEvents(existing: [], incoming: incomingEvents, now: Date())
    let state = CommanderProcedureLiveActivityPolicy.contentState(
      scheduleVersion: metadata.scheduleVersion,
      projectionRevision: metadata.projectionRevision ?? 0,
      events: events,
      attributes: attributes
    )
    let content = ActivityContent(
      state: state,
      staleDate: Self.staleDate(for: state.events),
      relevanceScore: 1_000
    )

    do {
      _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
        attributes: attributes,
        content: content,
        pushType: nil,
        style: .standard
      )
      CommanderPhysicalAcceptanceDiagnostics.record("Stop → jediný Commander spuštěn · \(metadata.stableId)")
    } catch {
      CommanderPhysicalAcceptanceDiagnostics.record("Stop → Commander chyba · \(error.localizedDescription)")
    }
  }

  private static func seedEvents(
    from attributes: CommanderProcedureLiveActivityAttributes
  ) -> [CommanderAlarmEventSnapshot] {
    let seed = CommanderAlarmEventSnapshot(
      stableId: attributes.stableId,
      iconKey: attributes.iconKey,
      title: attributes.title,
      location: attributes.location,
      kind: attributes.kind,
      startAt: localISO(attributes.startAt),
      endAt: localISO(attributes.endAt),
      leaveAt: localISO(attributes.leaveAt)
    )
    return [seed, attributes.nextEvent].compactMap { $0 }
  }

  private static func mergeEvents(
    existing: [CommanderAlarmEventSnapshot],
    incoming: [CommanderAlarmEventSnapshot],
    now: Date
  ) -> [CommanderAlarmEventSnapshot] {
    var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.stableId, $0) })
    for event in incoming { byID[event.stableId] = event }
    return byID.values
      .filter {
        guard let endAt = try? NativeAlarmContract.date(fromLocalISO: $0.endAt) else { return false }
        return endAt > now
      }
      .sorted {
        let lhs = try? NativeAlarmContract.date(fromLocalISO: $0.startAt)
        let rhs = try? NativeAlarmContract.date(fromLocalISO: $1.startAt)
        if lhs != rhs { return (lhs ?? .distantFuture) < (rhs ?? .distantFuture) }
        return $0.stableId < $1.stableId
      }
      .prefix(CommanderProcedureLiveActivityPolicy.maximumQueuedEvents)
      .map { $0 }
  }

  private static func staleDate(for events: [CommanderAlarmEventSnapshot]) -> Date? {
    events.compactMap { try? NativeAlarmContract.date(fromLocalISO: $0.endAt) }.max()
  }

  private static func localISO(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }

  private static func isOngoing(_ state: ActivityState) -> Bool {
    state == .pending || state == .active || state == .stale
  }

  private static func retentionRank(_ state: ActivityState) -> Int {
    switch state {
    case .active: 0
    case .pending: 1
    case .stale: 2
    case .ended: 3
    case .dismissed: 4
    @unknown default: 5
    }
  }
}

actor AlarmKitAdapter: AlarmAdapting {
  private static let e2eOwnershipKey = "lazensky.commander.alarmkitOwned.e2e.v1"
  private let channel: ScheduleChannel
  private var scheduleContext: Schedule?
  private var scheduleOverrides: LeadTimeOverrides?
  private var scheduleProjectionRevision = 0
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
    scheduleOverrides = overrides
    scheduleProjectionRevision = max(0, projectionRevision)
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
    let nextEvent = schedule.flatMap {
      Self.nextEventSnapshot(after: alarm, schedule: $0, overrides: scheduleOverrides)
    }
    let metadata = CommanderAlarmMetadata(
      stableId: alarm.stableId,
      scheduleVersion: schedule?.scheduleVersion ?? 0,
      projectionRevision: scheduleProjectionRevision,
      iconKey: iconKey,
      title: alarm.title,
      location: alarm.location,
      kind: alarm.kind,
      startAt: alarm.startAt,
      leaveAt: alarm.leaveAt,
      endAt: eventEndAt,
      nextEvent: nextEvent
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
    let stopIntent = CommanderAlarmStopIntent(alarmID: id, metadata: metadata)

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

  private static func nextEventSnapshot(
    after alarm: NativeAlarm,
    schedule: Schedule,
    overrides: LeadTimeOverrides?
  ) -> CommanderAlarmEventSnapshot? {
    guard let payload = try? NativeAlarmContract.payload(schedule: schedule, overrides: overrides),
          let index = payload.alarms.firstIndex(where: { $0.stableId == alarm.stableId }),
          payload.alarms.indices.contains(index + 1)
    else { return nil }

    let nextAlarm = payload.alarms[index + 1]
    guard let nextEvent = schedule.events.first(where: { $0.stableId == nextAlarm.stableId }) else {
      return nil
    }
    return CommanderAlarmEventSnapshot(
      stableId: nextAlarm.stableId,
      iconKey: CommanderVisualAssets.icon(for: nextEvent)?.key ?? "",
      title: nextAlarm.title,
      location: nextAlarm.location,
      kind: nextAlarm.kind,
      startAt: nextAlarm.startAt,
      endAt: nextAlarm.endAt,
      leaveAt: nextAlarm.leaveAt
    )
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

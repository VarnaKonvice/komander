import Foundation
import SwiftUI
import LazenskyCommanderCore
import UserNotifications
import WidgetKit

private enum CommanderDesignPreview {
  private static let flagKey = "commander.visualReview.enabled"

  static let enabled: Bool = {
    #if COMMANDER_VISUAL_REVIEW
    return true
    #elseif DEBUG
    let arguments = ProcessInfo.processInfo.arguments
    let defaults = UserDefaults(
      suiteName: CommanderWatchWidgetContract.appGroupIdentifier
    )

    if arguments.contains("-CommanderDisableDesignPreview") {
      defaults?.set(false, forKey: flagKey)
      return false
    }

    if arguments.contains("-CommanderDesignPreview")
      || arguments.contains("-CommanderApprovedVisualProof") {
      defaults?.set(true, forKey: flagKey)
      return true
    }

    return defaults?.bool(forKey: flagKey) ?? false
    #else
    return false
    #endif
  }()

  static var schedule: Schedule {
    CommanderVisualReviewSchedule.make(now: .now)
  }

  static func publishSharedFlag() {
    guard let defaults = UserDefaults(
      suiteName: CommanderWatchWidgetContract.appGroupIdentifier
    ) else { return }
    defaults.set(enabled, forKey: flagKey)
  }
}

@MainActor
final class CommanderViewModel: ObservableObject {
  @Published private(set) var accessStatus = "Kontroluji přístup k alarmům..."
  @Published private(set) var summary: AlarmSyncSummary?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isSynchronizing = false
  @Published private(set) var latestSchedule: Schedule?
  @Published private(set) var watchTransferStatus = "Aktivuji WatchConnectivity…"
  @Published private(set) var liveActivityIssue: String?
  @Published private(set) var recoveryStatus = "Čekám na první kontrolu"
  @Published private(set) var fallbackStatus = "Nevyužito"
  @Published private(set) var requiresUserAction = false
  @Published private(set) var userActionMessage: String?
  @Published private(set) var leadTimeOverrides = LeadTimeOverrides()
  @Published private(set) var leadTimeProjectionRevision = 0
  @Published private(set) var scheduleAuditAcknowledgements: [CommanderScheduleAuditAcknowledgement] = []

  private let adapter: AlarmKitAdapter
  private let procedureActivities: CommanderProcedureLiveActivityCoordinator
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let fallbackNotifications = IPhoneFallbackNotificationService()
  private let leadTimePreferences: LeadTimePreferencesStore
  private let scheduleAuditReviewStore: ScheduleAuditReviewStore
  private let channel: ScheduleChannel
  private var lastAutomaticAttempt: Date?
  private var delayedRecoveryTask: Task<Void, Never>?
  private var synchronizationRequests = CommanderSynchronizationRequestQueue()

  private let clock: @Sendable () -> Date

  init(clock: @escaping @Sendable () -> Date = { Date() }) {
    self.clock = clock
    let configuration = AppConfiguration()
    let adapter = AlarmKitAdapter(channel: configuration.channel)
    let procedureActivities = CommanderProcedureLiveActivityCoordinator(
      enabled: configuration.channel == .production && !CommanderDesignPreview.enabled
    )
    let input = CommanderLaunchInput(configuration: configuration, now: clock())
    let scheduleService = input.scheduleService
    let namespace = input.namespace
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(key: "lazensky.commander.managedAlarms.\(configuration.channel.rawValue).v1"),
      adapter: adapter
    )
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    let leadTimePreferences = LeadTimePreferencesStore(
      key: "lazensky.commander.leadTimePreferences.\(namespace).v1"
    )
    let scheduleAuditReviewStore = ScheduleAuditReviewStore(
      key: "lazensky.commander.scheduleAuditReview.\(namespace).v1"
    )
    let savedPreferences = leadTimePreferences.load()

    self.adapter = adapter
    self.procedureActivities = procedureActivities
    self.service = service
    self.watchConnectivity = watchConnectivity
    self.leadTimePreferences = leadTimePreferences
    self.scheduleAuditReviewStore = scheduleAuditReviewStore
    self.channel = configuration.channel
    self.leadTimeOverrides = CommanderDesignPreview.enabled ? LeadTimeOverrides() : savedPreferences.overrides
    self.leadTimeProjectionRevision = CommanderDesignPreview.enabled ? 0 : savedPreferences.revision
    self.scheduleAuditAcknowledgements = scheduleAuditReviewStore.load()
    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(key: "lazensky.commander.scheduleSnapshot.\(namespace).v1"),
      watchDelivery: configuration.channel == .production ? watchConnectivity : nil,
      clock: clock
    )
  }

  var watchScheduleSnapshot: WatchScheduleSnapshot? {
    latestSchedule.map {
      WatchScheduleSnapshot(
        schedule: $0,
        leadTimeOverrides: leadTimeOverrides,
        projectionRevision: leadTimeProjectionRevision
      )
    }
  }

  #if COMMANDER_ACCEPTANCE_FIXTURES
  private func writeAcceptanceStatus(
    phase: String, expectedToken: String? = nil, observedToken: String? = nil,
    message: String? = nil
  ) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    var payload: [String: Any] = [
      "phase": phase, "timestamp": ISO8601DateFormatter().string(from: clock())
    ]
    payload["expectedToken"] = expectedToken
    payload["observedToken"] = observedToken
    payload["message"] = message
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: documents.appendingPathComponent("commander-acceptance-status.json"), options: .atomic)
    }
  }

  // Observes the result of the same bootstrap used by a normal launch. It does
  // not request activities, schedule alarms or send an alternate Watch payload.
  func reportAcceptanceBootstrap() async {
    guard summary?.readbackCoverage.isComplete == true, let snapshot = watchScheduleSnapshot else {
      writeAcceptanceStatus(phase: "failed-alarm-sync", message: errorMessage ?? "AlarmKit read-back není úplný")
      return
    }
    let mode = CommanderAcceptanceLaunchMode.current
    if mode == .cleanup, await procedureActivities.hasOngoingActivities() {
      writeAcceptanceStatus(phase: "failed-live-activity", message: "ActivityKit stále obsahuje aktivní nebo čekající aktivitu")
      return
    }
    let prepared = await procedureActivities.preparedStableIDs(
      schedule: snapshot.schedule, overrides: snapshot.leadTimeOverrides,
      projectionRevision: snapshot.projectionRevision
    )
    if mode != .cleanup, !snapshot.schedule.events.isEmpty, prepared.isEmpty {
      writeAcceptanceStatus(phase: "failed-live-activity", message: liveActivityIssue ?? "Chybí plánovaná aktivita")
      return
    }
    let expected = snapshot.projectionIdentity
    let expectedToken = "\(expected.scheduleVersion)/\(expected.projectionRevision)"
    for attempt in 0..<120 {
      if await watchConnectivity.verifiedProjectionIdentity() == expected {
        let state = await procedureActivities.activityState(schedule: snapshot.schedule)
        let phase = mode == .cleanup ? "cleaned"
          : mode == .readback ? (state == "active" ? "activity-active" : "activity-not-active")
          : "watch-acknowledged"
        writeAcceptanceStatus(phase: phase, expectedToken: expectedToken, observedToken: expectedToken,
          message: "state=\(state); alarms=\(summary?.desiredAlarmCount ?? 0); prepared=\(prepared.count)")
        return
      }
      if attempt < 119 { try? await Task.sleep(for: .milliseconds(250)) }
    }
    writeAcceptanceStatus(phase: "failed-watch-ack", expectedToken: expectedToken,
      message: "Watch nepotvrdily canonical snapshot z cache")
  }
  #endif

  private func reloadHomeWidgets() {
    WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneKind)
    WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneDayOverviewKind)
    WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneProcedureCountKind)
  }

  var defaultLeadTimeMinutes: Int {
    leadTimeOverrides.defaultLeadTimeMinutes
      ?? latestSchedule?.settings.defaultLeadTimeMinutes
      ?? 20
  }

  func effectiveLeadTimeMinutes(for event: ScheduleEvent) -> Int {
    guard let schedule = latestSchedule else { return defaultLeadTimeMinutes }
    return (try? NativeAlarmContract.effectiveLeadTime(
      event: event,
      schedule: schedule,
      overrides: leadTimeOverrides
    )) ?? schedule.settings.defaultLeadTimeMinutes
  }

  func bootstrap() async {
    CommanderDesignPreview.publishSharedFlag()
    if CommanderDesignPreview.enabled {
      latestSchedule = CommanderDesignPreview.schedule
      reloadHomeWidgets()
      accessStatus = "Designový náhled – alarmy jsou vypnuté"
      watchTransferStatus = "Designový náhled"
      recoveryStatus = "Náhledový týden načten"
      fallbackStatus = "Vypnuto v designovém náhledu"
      requiresUserAction = false
      userActionMessage = nil
      errorMessage = nil
      return
    }

    latestSchedule = try? await scheduleSync.loadLastSchedule()
    reloadHomeWidgets()
    if channel == .production, let watchScheduleSnapshot {
      do {
        watchTransferStatus = try await watchConnectivity.deliver(watchScheduleSnapshot).diagnosticText
      } catch {
        watchTransferStatus = "Čeká na automatické předání"
      }
    } else if channel == .e2e {
      watchTransferStatus = "Testovací kanál je od Watch oddělený"
    }
    await refreshAccess()
    if latestSchedule != nil {
      await synchronizeWithRecovery(maxAttempts: 3, automatic: true, source: .cached)
    }
    await synchronizeWithRecovery(maxAttempts: 3, automatic: true)
  }

  func handleForeground() async {
    if CommanderDesignPreview.enabled { return }
    await reconcileProcedureActivitiesFromLatestSchedule()
    if let lastAutomaticAttempt, clock().timeIntervalSince(lastAutomaticAttempt) < 10 { return }
    if latestSchedule != nil {
      await synchronizeWithRecovery(maxAttempts: 3, automatic: true, source: .cached)
    }
    await synchronizeWithRecovery(maxAttempts: 3, automatic: true)
  }

  private func reconcileProcedureActivitiesFromLatestSchedule() async {
    if CommanderDesignPreview.enabled { return }
    guard let latestSchedule else { return }
    await procedureActivities.reconcile(
      schedule: latestSchedule,
      overrides: leadTimeOverrides,
      projectionRevision: leadTimeProjectionRevision,
      now: clock()
    )
    liveActivityIssue = await procedureActivities.issue
  }

  func refreshAccess() async {
    accessStatus = await service.alarmAccessDescription()
  }

  func requestAuthorization() {
    if CommanderDesignPreview.enabled {
      accessStatus = "Designový náhled – alarmy jsou vypnuté"
      return
    }
    Task {
      do {
        try await adapter.requestAuthorization()
        requiresUserAction = false
        userActionMessage = nil
        errorMessage = nil
        await synchronizeWithRecovery(maxAttempts: 3, automatic: false)
      } catch {
        requiresUserAction = true
        userActionMessage = "Povol alarmy, aby tě Commander mohl spolehlivě upozornit na odchod."
        errorMessage = error.localizedDescription
      }
      await refreshAccess()
    }
  }

  func synchronize() {
    if CommanderDesignPreview.enabled {
      latestSchedule = CommanderDesignPreview.schedule
      recoveryStatus = "Náhledový týden načten"
      errorMessage = nil
      return
    }
    Task { await synchronizeWithRecovery(maxAttempts: 3, automatic: false) }
  }

  func setDefaultLeadTimeMinutes(_ minutes: Int) {
    var updated = leadTimeOverrides
    updated.defaultLeadTimeMinutes = Self.clampedLeadTime(minutes)
    applyLeadTimeOverrides(updated)
  }

  func resetDefaultLeadTime() {
    var updated = leadTimeOverrides
    updated.defaultLeadTimeMinutes = nil
    applyLeadTimeOverrides(updated)
  }

  func setProcedureLeadTimeMinutes(_ minutes: Int, procedureType: String) {
    var updated = leadTimeOverrides
    updated.procedureTypeOverrides[procedureType] = Self.clampedLeadTime(minutes)
    applyLeadTimeOverrides(updated)
  }

  func resetProcedureLeadTime(procedureType: String) {
    var updated = leadTimeOverrides
    updated.procedureTypeOverrides.removeValue(forKey: procedureType)
    applyLeadTimeOverrides(updated)
  }

  func setProcedureCategoryLeadTimeMinutes(_ minutes: Int, category: CommanderProcedureCategory) {
    var updated = leadTimeOverrides
    updated.procedureCategoryOverrides[category.rawValue] = Self.clampedLeadTime(minutes)
    for key in updated.procedureTypeOverrides.keys
      where CommanderProcedureCategory.classify(key) == category {
      updated.procedureTypeOverrides.removeValue(forKey: key)
    }
    applyLeadTimeOverrides(updated)
  }

  func resetProcedureCategoryLeadTime(category: CommanderProcedureCategory) {
    var updated = leadTimeOverrides
    updated.procedureCategoryOverrides.removeValue(forKey: category.rawValue)
    applyLeadTimeOverrides(updated)
  }

  func setMealLeadTimeMinutes(_ minutes: Int, mealType: String) {
    var updated = leadTimeOverrides
    updated.mealOverrides[mealType] = Self.clampedLeadTime(minutes)
    applyLeadTimeOverrides(updated)
  }

  func resetMealLeadTime(mealType: String) {
    var updated = leadTimeOverrides
    updated.mealOverrides.removeValue(forKey: mealType)
    applyLeadTimeOverrides(updated)
  }

  func setEventLeadTimeMinutes(_ minutes: Int, stableId: String) {
    var updated = leadTimeOverrides
    updated.eventOverrides[stableId] = Self.clampedLeadTime(minutes)
    applyLeadTimeOverrides(updated)
  }

  func resetEventLeadTime(stableId: String) {
    var updated = leadTimeOverrides
    updated.eventOverrides.removeValue(forKey: stableId)
    applyLeadTimeOverrides(updated)
  }

  func resetAllLeadTimeOverrides() {
    applyLeadTimeOverrides(LeadTimeOverrides())
  }

  func acknowledgeScheduleAuditIssue(_ issue: CommanderScheduleAuditIssue, note: String? = nil) {
    guard issue.severity == .warning, let schedule = latestSchedule else { return }
    let acknowledgement = CommanderScheduleAuditAcknowledgement(
      scheduleVersion: schedule.scheduleVersion,
      reviewKey: issue.reviewKey,
      confirmedAt: ISO8601DateFormatter().string(from: Date()),
      note: note
    )
    var current = scheduleAuditAcknowledgements.filter {
      !($0.scheduleVersion == acknowledgement.scheduleVersion && $0.reviewKey == acknowledgement.reviewKey)
    }
    current.append(acknowledgement)
    scheduleAuditAcknowledgements = current.sorted {
      ($0.scheduleVersion, $0.confirmedAt, $0.reviewKey) < ($1.scheduleVersion, $1.confirmedAt, $1.reviewKey)
    }
    scheduleAuditReviewStore.save(scheduleAuditAcknowledgements)
  }

  func revokeScheduleAuditAcknowledgement(for issue: CommanderScheduleAuditIssue) {
    guard let schedule = latestSchedule else { return }
    let filtered = scheduleAuditAcknowledgements.filter {
      !($0.scheduleVersion == schedule.scheduleVersion && $0.reviewKey == issue.reviewKey)
    }
    guard filtered != scheduleAuditAcknowledgements else { return }
    scheduleAuditAcknowledgements = filtered
    scheduleAuditReviewStore.save(filtered)
  }

  func scheduleAuditReviewState() -> CommanderScheduleAuditReviewState? {
    guard let schedule = latestSchedule else { return nil }
    let report = CommanderScheduleAudit.run(schedule, policy: .petrSpaOperational)
    return CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: scheduleAuditAcknowledgements
    )
  }

  private func applyLeadTimeOverrides(_ updated: LeadTimeOverrides) {
    let normalized = LeadTimePreferencesStore.normalized(updated)
    guard normalized != leadTimeOverrides else { return }
    leadTimeOverrides = normalized
    leadTimeProjectionRevision += 1
    leadTimePreferences.save(
      LeadTimePreferences(
        overrides: normalized,
        revision: leadTimeProjectionRevision
      )
    )
    if CommanderDesignPreview.enabled {
      latestSchedule = CommanderDesignPreview.schedule
      recoveryStatus = "Náhledový týden načten"
      Task { reloadHomeWidgets() }
      return
    }
    recoveryStatus = "Přepočítávám čas odchodu"
    reloadHomeWidgets()
    Task { await synchronizeWithRecovery(maxAttempts: 3, automatic: false, source: .cached) }
  }

  private static func clampedLeadTime(_ value: Int) -> Int {
    min(180, max(0, value))
  }

  private func synchronizeWithRecovery(
    maxAttempts: Int,
    automatic: Bool,
    source: CommanderScheduleSource = .remote
  ) async {
    guard !CommanderDesignPreview.enabled else { return }
    guard var request = synchronizationRequests.submit(
      maxAttempts: maxAttempts,
      automatic: automatic,
      source: source
    ) else { return }

    isSynchronizing = true
    defer { isSynchronizing = false }

    while true {
      await performSynchronizationWithRecovery(
        maxAttempts: request.maxAttempts,
        automatic: request.automatic,
        source: request.source
      )
      guard let next = synchronizationRequests.completeCurrentAndTakeNext() else {
        return
      }
      request = next
    }
  }

  private func performSynchronizationWithRecovery(
    maxAttempts: Int,
    automatic: Bool,
    source: CommanderScheduleSource
  ) async {
    if automatic { lastAutomaticAttempt = clock() }
    delayedRecoveryTask?.cancel()
    delayedRecoveryTask = nil

    var recovery = CommanderSynchronizationRecovery()

    for attempt in 0..<maxAttempts {
      do {
        let projectionOverrides = leadTimeOverrides
        let projectionRevision = leadTimeProjectionRevision
        let result = try await scheduleSync.synchronize(
          source: source,
          overrides: projectionOverrides,
          projectionRevision: projectionRevision
        )
        latestSchedule = result.schedule
        summary = result.alarmSummary
        reloadHomeWidgets()
        await procedureActivities.reconcile(
          schedule: result.schedule,
          overrides: projectionOverrides,
          projectionRevision: projectionRevision,
          now: clock()
        )
        liveActivityIssue = await procedureActivities.issue
        watchTransferStatus = result.watchDeliveryStatus.diagnosticText
        recovery.recordAlarmVerification(succeeded: result.alarmSummary.succeeded)

        if result.alarmSummary.succeeded {
          guard await fallbackNotifications.clear() else {
            fallbackStatus = "Automaticky uklízím zálohu"
            recoveryStatus = "AlarmKit ověřen, dokončuji úklid zálohy"
            recovery.requestRetry()
            errorMessage = "Záložní upozornění se zatím nepodařilo ověřeně odstranit."
            break
          }

          fallbackStatus = "Nevyužito"
          requiresUserAction = false
          userActionMessage = nil
          errorMessage = nil

          recoveryStatus = result.alarmSummary.repairAttempts > 0 ? "Opraveno a ověřeno"
            : source == .cached ? "Ověřeno z uloženého rozpisu" : "Ověřeno"
          await refreshAccess()
          return
        } else {
          recoveryStatus = "Automaticky opravuji alarmy"
          errorMessage = result.alarmSummary.errorMessage
        }
      } catch AlarmAdapterError.authorizationDenied {
        recovery.recordAlarmVerification(succeeded: false)
        recoveryStatus = "AlarmKit nemá oprávnění, zapínám zálohu"
        errorMessage = AlarmAdapterError.authorizationDenied.localizedDescription
      } catch {
        recovery.requestRetry()
        errorMessage = error.localizedDescription
        recoveryStatus = latestSchedule == nil ? "Čekám na platný rozpis" : "Automatická kontrola se zopakuje"
      }

      // A local edit queued during a fetch must not wait for more network retry attempts.
      if synchronizationRequests.hasPendingCachedProjection { return }

      if attempt + 1 < maxAttempts {
        let delay = UInt64(attempt + 1) * 1_000_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
    }

    if recovery.needsFallback, let latestSchedule {
      do {
        if try await fallbackNotifications.arm(
          schedule: latestSchedule,
          overrides: leadTimeOverrides,
          now: clock()
        ) {
          fallbackStatus = "Aktivní a ověřená bezpečnostní pojistka"
          requiresUserAction = false
          userActionMessage = nil
        } else {
          fallbackStatus = "Není povolena"
          requiresUserAction = true
          userActionMessage = "Commander nemůže zajistit záložní upozornění. Povol oznámení pro Lázeňský Commander."
        }
      } catch {
        fallbackStatus = "Nelze ověřit"
        requiresUserAction = true
        userActionMessage = "Commander nemůže zajistit záložní upozornění. Povol oznámení pro Lázeňský Commander."
        errorMessage = error.localizedDescription
      }
    }

    if recovery.shouldRetry {
      scheduleDelayedRecovery(source: source)
    }
    await refreshAccess()
  }

  private func scheduleDelayedRecovery(source: CommanderScheduleSource) {
    guard delayedRecoveryTask == nil else { return }
    delayedRecoveryTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard !Task.isCancelled, let self else { return }
      self.delayedRecoveryTask = nil
      await self.synchronizeWithRecovery(maxAttempts: 2, automatic: true, source: source)
    }
  }
}

private struct LeadTimePreferences: Codable {
  let overrides: LeadTimeOverrides
  let revision: Int
}

@MainActor
private final class LeadTimePreferencesStore {
  private let defaults: UserDefaults
  private let key: String

  init(defaults: UserDefaults = .standard, key: String) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> LeadTimePreferences {
    guard
      let data = defaults.data(forKey: key),
      let saved = try? JSONDecoder().decode(LeadTimePreferences.self, from: data)
    else {
      return LeadTimePreferences(overrides: LeadTimeOverrides(), revision: 0)
    }
    return LeadTimePreferences(
      overrides: Self.normalized(saved.overrides),
      revision: max(0, saved.revision)
    )
  }

  func save(_ preferences: LeadTimePreferences) {
    guard let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: key)
  }

  static func normalized(_ overrides: LeadTimeOverrides) -> LeadTimeOverrides {
    LeadTimeOverrides(
      defaultLeadTimeMinutes: valid(overrides.defaultLeadTimeMinutes),
      procedureTypeOverrides: valid(overrides.procedureTypeOverrides),
      procedureCategoryOverrides: valid(overrides.procedureCategoryOverrides),
      mealOverrides: valid(overrides.mealOverrides),
      eventOverrides: valid(overrides.eventOverrides)
    )
  }

  private static func valid(_ value: Int?) -> Int? {
    guard let value, (0...180).contains(value) else { return nil }
    return value
  }

  private static func valid(_ values: [String: Int]) -> [String: Int] {
    values.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...180).contains($0.value) }
  }
}

@MainActor
private final class ScheduleAuditReviewStore {
  private let defaults: UserDefaults
  private let key: String

  init(defaults: UserDefaults = .standard, key: String) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> [CommanderScheduleAuditAcknowledgement] {
    guard
      let data = defaults.data(forKey: key),
      let saved = try? JSONDecoder().decode([CommanderScheduleAuditAcknowledgement].self, from: data)
    else { return [] }
    return saved
  }

  func save(_ acknowledgements: [CommanderScheduleAuditAcknowledgement]) {
    guard let data = try? JSONEncoder().encode(acknowledgements) else { return }
    defaults.set(data, forKey: key)
  }
}

@MainActor
private final class IPhoneFallbackNotificationService {
  private static let identifierPrefix = "lazensky.commander.iphone.fallback."
  private static let prague = TimeZone(identifier: "Europe/Prague")!
  private let center = UNUserNotificationCenter.current()

  func clear() async -> Bool {
    for _ in 0..<2 {
      let pending = await center.pendingNotificationRequests()
      let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
      if identifiers.isEmpty { return true }
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
      await Task.yield()
      let remaining = await center.pendingNotificationRequests()
      if !remaining.contains(where: { $0.identifier.hasPrefix(Self.identifierPrefix) }) {
        return true
      }
    }
    return false
  }

  func arm(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    now: Date = Date()
  ) async throws -> Bool {
    guard try await ensureAuthorization() else { return false }
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    let desired = try payload.alarms
      .filter { try NativeAlarmContract.date(fromLocalISO: $0.leaveAt) > now }
      .sorted { $0.leaveAt < $1.leaveAt }
      .prefix(60)

    var desiredDates: [String: Date] = [:]
    for alarm in desired {
      desiredDates[Self.identifierPrefix + alarm.stableId] = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
    }

    var lastError: Error?
    for _ in 0..<2 {
      _ = await clear()
      do {
        for alarm in desired {
          let content = UNMutableNotificationContent()
          content.title = "Čas vyrazit"
          content.body = alarm.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? alarm.title
            : "\(alarm.title) · \(alarm.location)"
          content.sound = .default
          content.interruptionLevel = .active
          content.userInfo = ["stableId": alarm.stableId, "scheduleVersion": schedule.scheduleVersion]

          let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = Self.prague
          var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: leaveAt)
          components.timeZone = Self.prague
          let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
          let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + alarm.stableId,
            content: content,
            trigger: trigger
          )
          try await center.add(request)
        }
      } catch {
        lastError = error
        continue
      }

      if await verify(desiredDates: desiredDates) {
        return true
      }
    }

    if let lastError { throw lastError }
    return false
  }

  private func verify(desiredDates: [String: Date]) async -> Bool {
    let pending = await center.pendingNotificationRequests()
    let fallback = pending.filter { $0.identifier.hasPrefix(Self.identifierPrefix) }
    guard Set(fallback.map(\.identifier)) == Set(desiredDates.keys) else { return false }

    for request in fallback {
      guard let expected = desiredDates[request.identifier],
            let trigger = request.trigger as? UNCalendarNotificationTrigger,
            let actual = trigger.nextTriggerDate(),
            abs(actual.timeIntervalSince(expected)) <= 1
      else { return false }
    }
    return true
  }

  private func ensureAuthorization() async throws -> Bool {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .notDetermined:
      return try await center.requestAuthorization(options: [.alert, .sound])
    case .denied:
      return false
    @unknown default:
      return false
    }
  }
}

// Only input selection differs in an acceptance build. All lifecycle and UI
// code below is shared; reopening without arguments reuses the persisted times.
private enum CommanderAcceptanceLaunchMode {
  case none, visual, cleanup, readback

  static var current: Self {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--acceptance-cleanup") { return .cleanup }
    if arguments.contains("--acceptance-readback") { return .readback }
    if arguments.contains("--acceptance-visual") || arguments.contains("--acceptance-iphone-visual") { return .visual }
    #endif
    return .none
  }
}

private struct CommanderLaunchInput {
  let scheduleService: any ScheduleServing
  let namespace: String

  init(configuration: AppConfiguration, now: Date) {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    let key = "lazensky.commander.acceptance.input.v1"
    let saved = UserDefaults.standard.data(forKey: key).flatMap {
      try? JSONDecoder().decode(Schedule.self, from: $0)
    }
    let mode = CommanderAcceptanceLaunchMode.current
    let result = Result<Schedule, Error> {
      if mode != .visual && mode != .cleanup {
        guard let saved else { throw CommanderScheduleSyncError.noValidatedSnapshot }
        return saved
      }
      let fixture = try CommanderAcceptanceSchedule(
        now: now, previousVersion: saved?.scheduleVersion ?? 0,
        cleanup: mode != .visual
      ).schedule
      UserDefaults.standard.set(try JSONEncoder().encode(fixture), forKey: key)
      return fixture
    }
    scheduleService = InjectedScheduleService(result: result)
    // A new fixture starts with an empty snapshot store, so bootstrap cannot
    // reconcile a previous run before fetching the new input. Relaunches reuse it.
    namespace = "acceptance.\((try? result.get().scheduleVersion) ?? 0)"
    #else
    scheduleService = URLSessionScheduleService(configuration: configuration)
    namespace = CommanderDesignPreview.enabled ? "designPreview" : configuration.channel.rawValue
    #endif
  }
}

private struct InjectedScheduleService: ScheduleServing {
  let result: Result<Schedule, Error>
  func fetchSchedule() async throws -> Schedule { try result.get() }
}

@main
struct LazenskyCommanderApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = CommanderViewModel()

  var body: some Scene {
    WindowGroup {
      CommanderAppTabs(model: model)
        .preferredColorScheme(.dark)
        .task {
          await model.bootstrap()
          #if COMMANDER_ACCEPTANCE_FIXTURES
          await model.reportAcceptanceBootstrap()
          #endif
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          Task { await model.handleForeground() }
        }
    }
  }
}

private extension WatchScheduleDeliveryDisposition {
  var diagnosticText: String {
    switch self {
    case .queued: "Čeká na aktivaci"
    case .sent: "Předáno, čeká na potvrzení"
    }
  }
}

private extension WatchScheduleDeliveryStatus {
  var diagnosticText: String {
    switch self {
    case .notConfigured: "Není nakonfigurováno"
    case .notAttempted: "Neprovedeno"
    case .queued: "Čeká na aktivaci"
    case .sent: "Předáno, čeká na potvrzení"
    case .verified: "Ověřeno"
    case .failed: "Čeká na automatické předání"
    }
  }
}

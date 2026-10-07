import Foundation
import SwiftUI
import LazenskyCommanderCore
import UserNotifications
import WidgetKit

private enum CommanderDesignPreview {
  static let enabled: Bool = {
    #if COMMANDER_WIDGET_DEMO
    return true
    #elseif COMMANDER_VISUAL_REVIEW
    return true
    #elseif DEBUG
    return CommanderPreviewPolicy.enabled(arguments: ProcessInfo.processInfo.arguments)
    #else
    return false
    #endif
  }()

  static var schedule: Schedule {
    #if COMMANDER_WIDGET_DEMO
    CommanderWidgetDemoSchedule.make()
    #else
    CommanderVisualReviewSchedule.make(now: .now)
    #endif
  }
}

@MainActor
final class CommanderViewModel: ObservableObject {
  @Published private(set) var todayRouteRevision = 0
  private var notificationsVerified = false

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

  @Published private(set) var phoneWidgetIssue: String?
  private var phoneWidgetCache: FileWatchScheduleCache?
  private let adapter: AlarmKitAdapter
  private let procedureActivities: CommanderProcedureLiveActivityCoordinator
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let eventNotifications = IPhoneEventNotificationService()
  private var acceptedSnapshot: WatchScheduleSnapshot?
  private let leadTimePreferences: LeadTimePreferencesStore
  private let scheduleAuditReviewStore: ScheduleAuditReviewStore
  private let channel: ScheduleChannel
  private var lastAutomaticAttempt: Date?
  private var delayedRecoveryTask: Task<Void, Never>?
  private var leadTimeSyncTask: Task<Void, Never>?
  private var launchMaintenanceTask: Task<Void, Never>?
  private var suppressAutomaticForegroundUntil: Date?
  private var synchronizationRequests = CommanderSynchronizationRequestQueue()

  private static let automaticForegroundRefreshInterval: TimeInterval = 5 * 60
  private static let launchForegroundGraceInterval: TimeInterval = 8
  private static let spaLeadTimePresetKey = "lazensky.commander.leadTimePreset.20-vizita5.v1"

  private let clock: @Sendable () -> Date

  init(clock: @escaping @Sendable () -> Date = { Date() }) {
    self.clock = clock
    let configuration = AppConfiguration()
    let adapter = AlarmKitAdapter(channel: configuration.channel)
    let procedureActivities = CommanderProcedureLiveActivityCoordinator(
      enabled: CommanderMVPPolicy.createsLiveActivities && configuration.channel == .production && !CommanderDesignPreview.enabled
    )
    let input = CommanderLaunchInput(configuration: configuration, now: clock())
    let scheduleService = input.scheduleService
    let namespace = input.namespace
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(key: "lazensky.commander.managedAlarms.\(configuration.channel.rawValue).v1",
        dataset: configuration.channel == .production ? CommanderRuntimeDataset.current : nil),
      adapter: adapter
    )
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    let leadTimePreferences = LeadTimePreferencesStore(
      key: "lazensky.commander.leadTimePreferences.\(namespace).v1",
      isPersistent: !CommanderDesignPreview.enabled
    )
    let scheduleAuditReviewStore = ScheduleAuditReviewStore(
      key: "lazensky.commander.scheduleAuditReview.\(namespace).v1"
    )
    let savedPreferences = leadTimePreferences.load()
    let scheduleSnapshotKey = "lazensky.commander.scheduleSnapshot.\(namespace).v1"
    let initialSchedule: Schedule? = {
      guard !CommanderDesignPreview.enabled,
            let data = UserDefaults.standard.data(forKey: scheduleSnapshotKey),
            let schedule = try? JSONDecoder().decode(Schedule.self, from: data)
      else { return nil }
      do {
        try NativeAlarmContract.validateCanonical(schedule)
        return schedule
      } catch {
        return nil
      }
    }()

    self.adapter = adapter
    self.procedureActivities = procedureActivities
    self.service = service
    self.watchConnectivity = watchConnectivity
    self.leadTimePreferences = leadTimePreferences
    self.scheduleAuditReviewStore = scheduleAuditReviewStore
    self.channel = configuration.channel
    self.suppressAutomaticForegroundUntil = clock().addingTimeInterval(Self.launchForegroundGraceInterval)
    self.leadTimeOverrides = CommanderDesignPreview.enabled ? LeadTimeOverrides() : savedPreferences.overrides
    self.leadTimeProjectionRevision = CommanderDesignPreview.enabled ? 0 : savedPreferences.revision
    self.scheduleAuditAcknowledgements = CommanderDesignPreview.enabled ? [] : scheduleAuditReviewStore.load()
    #if COMMANDER_ACCEPTANCE_FIXTURES
    let acceptanceWatchDeliveryEnabled = CommanderAcceptanceLaunchMode.current != .cleanup
    #else
    let acceptanceWatchDeliveryEnabled = true
    #endif
    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(key: scheduleSnapshotKey),
      watchDelivery: configuration.channel == .production && acceptanceWatchDeliveryEnabled ? watchConnectivity : nil,
      dataset: CommanderRuntimeDataset.current,
      clock: clock
    )
    if let initialSchedule {
      self.latestSchedule = initialSchedule
    }
  }

  var watchScheduleSnapshot: WatchScheduleSnapshot? {
    acceptedSnapshot ?? latestSchedule.map {
      WatchScheduleSnapshot(
        schedule: $0,
        leadTimeOverrides: leadTimeOverrides,
        projectionRevision: leadTimeProjectionRevision
      )
    }
  }

  private func writeAcceptanceStatus(
    phase: String, expectedToken: String? = nil, observedToken: String? = nil,
    message: String? = nil, verifiedAlarmCount: Int? = nil
  ) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else { return }
    var payload: [String: Any] = [
      "phase": phase, "timestamp": ISO8601DateFormatter().string(from: clock())
    ]
    payload["requestID"] = CommanderAcceptanceLaunchMode.requestID
    payload["dataset"] = CommanderRuntimeDataset.current.rawValue
    payload["notificationsVerified"] = notificationsVerified
    payload["alarmCount"] = verifiedAlarmCount ?? summary?.desiredAlarmCount
    payload["alarmsVerified"] = verifiedAlarmCount != nil || (summary?.succeeded == true && summary?.readbackCoverage.isComplete == true)
    payload["expectedToken"] = expectedToken
    payload["observedToken"] = observedToken
    payload["message"] = message
    if let summary {
      let coverage = summary.readbackCoverage
      payload["alarmSyncSucceeded"] = summary.succeeded
      payload["evidencedAlarmCount"] = coverage.evidencedAlarmCount
      payload["readbackComplete"] = coverage.isComplete
    }
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
      try? data.write(to: documents.appendingPathComponent("commander-acceptance-status.json"), options: .atomic)
    }
  }

  // Observes the result of the same bootstrap used by a normal launch. It does
  // not request activities, schedule alarms or send an alternate Watch payload.
  func reportAcceptanceBootstrap() async {
    let coverage = summary?.readbackCoverage
    guard summary?.succeeded == true, coverage?.isComplete == true, let snapshot = watchScheduleSnapshot else {
      let detail: String
      if let summary, let coverage {
        detail = "AlarmKit read-back \(coverage.evidencedAlarmCount)/\(coverage.desiredAlarmCount); sync=\(summary.succeeded ? "ok" : "failed")"
      } else {
        detail = errorMessage ?? "AlarmKit synchronizace ještě nemá výsledek"
      }
      writeAcceptanceStatus(phase: "failed-alarm-sync", message: detail)
      return
    }
    guard notificationsVerified else {
      writeAcceptanceStatus(phase: "failed-notifications", message: errorMessage ?? "Oznámení nejsou ověřena")
      return
    }
    let mode = CommanderAcceptanceLaunchMode.current
    if mode == .cleanup || !CommanderMVPPolicy.createsLiveActivities, await procedureActivities.hasOngoingActivities() {
      writeAcceptanceStatus(phase: "failed-live-activity", message: "ActivityKit stále obsahuje aktivní nebo čekající aktivitu")
      return
    }
    let prepared = await procedureActivities.preparedStableIDs(
      schedule: snapshot.schedule, overrides: snapshot.leadTimeOverrides,
      projectionRevision: snapshot.projectionRevision
    )
    if CommanderMVPPolicy.createsLiveActivities, mode != .cleanup && mode != .none, !snapshot.schedule.events.isEmpty, prepared.isEmpty {
      writeAcceptanceStatus(phase: "failed-live-activity", message: liveActivityIssue ?? "Chybí plánovaná aktivita")
      return
    }
    let expected = snapshot.projectionIdentity
    let expectedToken = "\(expected.scheduleVersion)/\(expected.projectionRevision)"
    if mode == .cleanup {
      guard let remaining = try? await adapter.existingPlatformAlarmIDs(), remaining.isEmpty else {
        writeAcceptanceStatus(phase: "failed-alarm-sync", message: "Acceptance alarmy ještě existují")
        return
      }
      // Queue the empty dataset but never wait for an empty-snapshot ACK.
      _ = try? await watchConnectivity.deliver(snapshot)
      let state = await procedureActivities.activityState(schedule: snapshot.schedule, projectionRevision: snapshot.projectionRevision)
      writeAcceptanceStatus(
        phase: "cleaned",
        expectedToken: expectedToken,
        message: "iPhone cleanup potvrzen; state=\(state); alarms=\(summary?.desiredAlarmCount ?? 0); prepared=\(prepared.count); Watch cleanup se záměrně nečeká"
      )
      return
    }
    for attempt in 0..<120 {
      if await watchConnectivity.verifiedProjectionIdentity() == expected {
        let state = await procedureActivities.activityState(schedule: snapshot.schedule, projectionRevision: snapshot.projectionRevision)
        if mode == .none {
          let defaults = UserDefaults.standard
          for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix("lazensky.commander.acceptance.") ||
            key.hasPrefix("lazensky.commander.scheduleSnapshot.acceptance.") ||
            key.hasPrefix("lazensky.commander.leadTimePreferences.acceptance.") ||
            key.hasPrefix("lazensky.commander.scheduleAuditReview.acceptance.") {
            defaults.removeObject(forKey: key)
          }
          try? await CommanderPhoneWidgetCache.make(dataset: .acceptance)?.remove()
        }
        let phase = mode == .none ? "production-verified" : "watch-acknowledged"
        writeAcceptanceStatus(phase: phase, expectedToken: expectedToken, observedToken: expectedToken,
          message: "state=\(state); alarms=\(summary?.desiredAlarmCount ?? 0); prepared=\(prepared.count)")
        return
      }
      if attempt < 119 { try? await Task.sleep(for: .milliseconds(250)) }
    }
    let observed = await watchConnectivity.verifiedProjectionIdentity()
    let observedToken = observed.map { "\($0.scheduleVersion)/\($0.projectionRevision)" }
    writeAcceptanceStatus(
      phase: "failed-watch-ack",
      expectedToken: expectedToken,
      observedToken: observedToken,
      message: "Watch nepotvrdily canonical snapshot z cache; observed=\(observedToken ?? "none")"
    )
  }

  /// A diagnostic read must not repair/recreate the object it is testing.
  func reportPassiveActivityReadback() async {
    latestSchedule = try? await scheduleSync.loadLastSchedule()
    guard let snapshot = watchScheduleSnapshot,
          let payload = try? NativeAlarmContract.payload(schedule: snapshot.schedule, overrides: snapshot.leadTimeOverrides),
          let actual = try? await adapter.existingPlatformFixedAlertDates() else {
      writeAcceptanceStatus(phase: "failed-alarm-sync", message: "Chybí přesný AlarmKit read-back")
      return
    }
    let expectedDates = payload.alarms.compactMap { try? NativeAlarmContract.date(fromLocalISO: $0.leaveAt) }
      .filter { $0 > clock() }.sorted()
    let actualDates = actual.values.sorted()
    guard expectedDates == actualDates else {
      writeAcceptanceStatus(phase: "failed-alarm-sync", message: "Počet/časy alarmů neodpovídají novému běhu")
      return
    }
    let prepared = await procedureActivities.preparedStableIDs(schedule: snapshot.schedule,
      overrides: snapshot.leadTimeOverrides, projectionRevision: snapshot.projectionRevision)
    let state = await procedureActivities.activityState(schedule: snapshot.schedule,
      projectionRevision: snapshot.projectionRevision)
    let identity = snapshot.projectionIdentity
    let token = "\(identity.scheduleVersion)/\(identity.projectionRevision)"
    // The first bootstrap proved the ACK; this readback checks unchanged exact identity.
    writeAcceptanceStatus(phase: state == "active" && !prepared.isEmpty ? "activity-active" : "activity-not-active",
      expectedToken: token, observedToken: token,
      message: "passive read-back; state=\(state); alarms=\(actualDates.count)", verifiedAlarmCount: actualDates.count)
  }

  private func recordAcceptanceProgress(_ phase: String, message: String? = nil) {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    writeAcceptanceStatus(phase: phase, message: message)
    #endif
  }

  private func reloadHomeWidgets() async {
    guard !CommanderDesignPreview.enabled else { return }
    var diagnostic: [String: Any] = [
      "timestamp": ISO8601DateFormatter().string(from: clock()),
      "dataset": CommanderRuntimeDataset.current.rawValue,
      "appGroup": CommanderWatchWidgetContract.appGroupIdentifier,
      "timelinesReloadRequested": false
    ]
    do {
      // Keep a single serial writer, but retry container resolution after failure.
      let cache: FileWatchScheduleCache
      if let existing = phoneWidgetCache {
        cache = existing
      } else {
        cache = try CommanderPhoneWidgetCache.require(dataset: CommanderRuntimeDataset.current)
        phoneWidgetCache = cache
      }
      diagnostic["absoluteSnapshotPath"] = await cache.fileURL.path
      guard let snapshot = watchScheduleSnapshot else {
        diagnostic["status"] = "waiting-for-validated-schedule"
        recordPhoneWidgetPublication(diagnostic)
        return
      }
      diagnostic["scheduleVersion"] = snapshot.schedule.scheduleVersion
      diagnostic["projectionRevision"] = snapshot.projectionRevision
      let receipt = try await cache.acceptAndLoad(snapshot)
      diagnostic["decision"] = String(describing: receipt.decision)
      diagnostic["readbackScheduleVersion"] = receipt.snapshot?.schedule.scheduleVersion
      try receipt.verifyPublished(snapshot)
      #if DEBUG
      // CoreDevice only exports Library/Documents/tmp in App Group containers.
      // Export disk bytes for diagnostics; widgets NEVER consume this copy.
      do {
        let source = await cache.fileURL
        let bytes = try Data(contentsOf: source)
        guard try JSONDecoder().decode(WatchScheduleSnapshot.self, from: bytes) == snapshot else {
          throw CommanderPhoneWidgetPublishError.readbackMismatch
        }
        let exportDirectory = source.deletingLastPathComponent().deletingLastPathComponent()
          .appendingPathComponent("Library/Caches/CommanderPhoneWidgetVerification-" + CommanderRuntimeDataset.current.rawValue)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exportURL = exportDirectory.appendingPathComponent(FileWatchScheduleCache.defaultFileName)
        try bytes.write(to: exportURL, options: .atomic)
        diagnostic["verificationExportPath"] = exportURL.path
      } catch {
        diagnostic["verificationExportError"] = error.localizedDescription
      }
      #endif
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneKind)
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneDayOverviewKind)
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.iPhoneProcedureCountKind)
      phoneWidgetIssue = nil
      diagnostic["status"] = "verified"
      diagnostic["timelinesReloadRequested"] = true
      diagnostic["snapshotPath"] = CommanderPhoneWidgetCache.directoryName(dataset: CommanderRuntimeDataset.current)
        + "/" + FileWatchScheduleCache.defaultFileName
    } catch {
      phoneWidgetIssue = "Widget cache: \(error.localizedDescription)"
      diagnostic["status"] = "failed"
      diagnostic["error"] = String(describing: error)
      diagnostic["message"] = error.localizedDescription
    }
    recordPhoneWidgetPublication(diagnostic)
  }

  private func recordPhoneWidgetPublication(_ diagnostic: [String: Any]) {
    do {
      let data = try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys])
      NSLog("CommanderPhoneWidget publish: %@", String(decoding: data, as: UTF8.self))
      let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
        appropriateFor: nil, create: true)
      try data.write(to: documents.appendingPathComponent("commander-phone-widget-publication.json"), options: .atomic)
    } catch {
      NSLog("CommanderPhoneWidget diagnostic write failed: %@", error.localizedDescription)
    }
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
    recordAcceptanceProgress("bootstrap-start")
    if CommanderDesignPreview.enabled {
      latestSchedule = CommanderDesignPreview.schedule
      await reloadHomeWidgets()
      accessStatus = "Designový náhled – alarmy jsou vypnuté"
      watchTransferStatus = "Designový náhled"
      recoveryStatus = "Náhledový týden načten"
      fallbackStatus = "Vypnuto v designovém náhledu"
      requiresUserAction = false
      userActionMessage = nil
      errorMessage = nil
      return
    }

    applySpaLeadTimePresetIfNeeded()
    let cachedSchedule = try? await scheduleSync.loadLastSchedule()
    if cachedSchedule != latestSchedule {
      latestSchedule = cachedSchedule
    }
    recordAcceptanceProgress(
      "bootstrap-cache-loaded",
      message: latestSchedule == nil ? "cache=empty" : "cache=present"
    )

    // Acceptance/read-back launches must prove the result of the real maintenance
    // pass, not race the delayed normal-launch task and inspect an empty summary.
    if CommanderAcceptanceLaunchMode.current != .none || CommanderAcceptanceLaunchMode.productionReadback {
      await performLaunchMaintenance()
      return
    }

    // The cached schedule is already preloaded before the first frame. Keep the
    // expensive AlarmKit/Watch/widget maintenance away from the ordinary launch gesture.
    launchMaintenanceTask?.cancel()
    launchMaintenanceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      guard !Task.isCancelled, let self else { return }
      await self.performLaunchMaintenance()
    }
  }

  private func performLaunchMaintenance() async {
    await procedureActivities.retireActivitiesForMVP()
    await reloadHomeWidgets()
    if channel == .production, let watchScheduleSnapshot {
      do {
        watchTransferStatus = try await watchConnectivity.deliver(watchScheduleSnapshot).diagnosticText
      } catch {
        watchTransferStatus = "Čeká na automatické předání"
      }
    } else if channel == .e2e {
      watchTransferStatus = "Testovací kanál je od Watch oddělený"
    }

    recordAcceptanceProgress("bootstrap-before-access")
    await refreshAccess()
    recordAcceptanceProgress("bootstrap-access-ready", message: accessStatus)

    // One canonical remote reconciliation is enough for a normal launch. The
    // previously scheduled alarms remain owned by AlarmKit while this runs.
    recordAcceptanceProgress("bootstrap-before-remote-sync")
    await synchronizeWithRecovery(maxAttempts: 2, automatic: true)
    recordAcceptanceProgress(
      "bootstrap-complete",
      message: "alarms=\(summary?.desiredAlarmCount ?? -1); succeeded=\(summary?.succeeded ?? false)"
    )
  }

  func handleForeground() async {
    if CommanderDesignPreview.enabled { return }
    if let until = suppressAutomaticForegroundUntil, clock() < until { return }
    suppressAutomaticForegroundUntil = nil
    await procedureActivities.retireActivitiesForMVP()
    await reconcileProcedureActivitiesFromLatestSchedule()
    if let lastAutomaticAttempt,
       clock().timeIntervalSince(lastAutomaticAttempt) < Self.automaticForegroundRefreshInterval {
      return
    }
    await synchronizeWithRecovery(maxAttempts: 1, automatic: true)
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

  func openNotification(action: String, category: String, payload: [String: String]) {
    guard CommanderNotificationContract.routesToCurrent(actionIdentifier: action,
      defaultActionIdentifier: UNNotificationDefaultActionIdentifier, category: category,
      payload: payload, dataset: CommanderRuntimeDataset.current) else { return }
    todayRouteRevision += 1
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

  func applySpaLeadTimePreset() {
    UserDefaults.standard.set(true, forKey: Self.spaLeadTimePresetKey)
    applyLeadTimeOverrides(Self.spaLeadTimePreset())
  }

  private func applySpaLeadTimePresetIfNeeded() {
    guard channel == .production,
          !UserDefaults.standard.bool(forKey: Self.spaLeadTimePresetKey) else { return }
    let normalized = LeadTimePreferencesStore.normalized(Self.spaLeadTimePreset())
    leadTimeOverrides = normalized
    leadTimeProjectionRevision += 1
    leadTimePreferences.save(
      LeadTimePreferences(overrides: normalized, revision: leadTimeProjectionRevision)
    )
    UserDefaults.standard.set(true, forKey: Self.spaLeadTimePresetKey)
  }

  private static func spaLeadTimePreset() -> LeadTimeOverrides {
    var preset = LeadTimeOverrides()
    preset.defaultLeadTimeMinutes = 20
    preset.procedureTypeOverrides["Vizita"] = 5
    return preset
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
    if !CommanderDesignPreview.enabled { scheduleAuditReviewStore.save(scheduleAuditAcknowledgements) }
  }

  func revokeScheduleAuditAcknowledgement(for issue: CommanderScheduleAuditIssue) {
    guard let schedule = latestSchedule else { return }
    let filtered = scheduleAuditAcknowledgements.filter {
      !($0.scheduleVersion == schedule.scheduleVersion && $0.reviewKey == issue.reviewKey)
    }
    guard filtered != scheduleAuditAcknowledgements else { return }
    scheduleAuditAcknowledgements = filtered
    if !CommanderDesignPreview.enabled { scheduleAuditReviewStore.save(filtered) }
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
      Task { await reloadHomeWidgets() }
      return
    }

    // +/- controls can generate many changes in a few hundred milliseconds.
    // Persist immediately, but coalesce expensive AlarmKit/widget reconciliation.
    recoveryStatus = "Přepočítávám čas odchodu"
    leadTimeSyncTask?.cancel()
    leadTimeSyncTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 450_000_000)
      guard !Task.isCancelled, let self else { return }
      await self.reloadHomeWidgets()
      await self.synchronizeWithRecovery(maxAttempts: 3, automatic: false, source: .cached)
    }
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
        acceptedSnapshot = result.watchSnapshot
        latestSchedule = result.schedule
        summary = result.alarmSummary
        await reloadHomeWidgets()
        await procedureActivities.reconcile(
          schedule: result.schedule,
          overrides: projectionOverrides,
          projectionRevision: projectionRevision,
          now: clock()
        )
        liveActivityIssue = await procedureActivities.issue
        watchTransferStatus = result.watchDeliveryStatus.diagnosticText
        recovery.recordAlarmVerification(succeeded: result.alarmSummary.succeeded)

        var notificationIssue: String?
        notificationsVerified = false
        do {
          // A partial AlarmKit failure can leave valid alarms armed. Never add a
          // departure fallback for an existing alarm, or when absence is unproven.
          let existingAlarmEvents = result.alarmSummary.succeeded ? Set<String>() :
            (try? await adapter.existingEventStableIDs())
          try await eventNotifications.reconcile(snapshot: result.watchSnapshot,
            dataset: CommanderRuntimeDataset.current, channel: channel.rawValue,
            includeDeparture: !result.alarmSummary.succeeded && existingAlarmEvents != nil, now: clock(),
            departureExclusions: existingAlarmEvents ?? Set(result.schedule.events.map(\.stableId)))
          notificationsVerified = true
          fallbackStatus = result.alarmSummary.succeeded ? "Začátky událostí ověřeny" :
            existingAlarmEvents == nil ? "Začátky ověřeny; odchod nelze ověřit" : "Záloha odchodu a začátky ověřeny"
        } catch {
          notificationIssue = error.localizedDescription
          fallbackStatus = "Oznámení nejsou ověřena"
          requiresUserAction = true
          userActionMessage = "Zkontroluj povolení oznámení pro Lázeňský Commander."
        }

        if result.alarmSummary.succeeded {
          if let notificationIssue {
            requiresUserAction = true
            userActionMessage = "Zkontroluj povolení oznámení pro Lázeňský Commander."
            errorMessage = notificationIssue
            recoveryStatus = "AlarmKit ověřen; oznámení začátku vyžadují kontrolu"
            recovery.requestRetry()
            break
          }

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
private final class IPhoneEventNotificationService {
  private let center = UNUserNotificationCenter.current()

  func reconcile(snapshot: WatchScheduleSnapshot, dataset: CommanderScheduleDataset,
                 channel: String, includeDeparture: Bool, now: Date,
                 departureExclusions: Set<String> = []) async throws {
    // Validate before removing anything, even when permission has been revoked.
    _ = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: dataset,
      channel: channel, includeDeparture: includeDeparture, now: now, departureExclusions: departureExclusions)
    let prefix = CommanderNotificationContract.prefix(dataset: dataset, channel: channel)
    let pending = await center.pendingNotificationRequests()
    // Migrate only legacy fallback IDs belonging to this dataset. Other namespaces,
    // including provisioning reminders and production during acceptance, are untouched.
    let legacyPrefix = "lazensky.commander.iphone.fallback."
    let legacy = pending.filter {
      channel == "production" && $0.identifier.hasPrefix(legacyPrefix) &&
        dataset.accepts(stableID: String($0.identifier.dropFirst(legacyPrefix.count)))
    }.map(\.identifier)
    let otherCount = pending.filter { !$0.identifier.hasPrefix(prefix) && !legacy.contains($0.identifier) }.count
    let desired = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: dataset,
      channel: channel, includeDeparture: includeDeparture, now: now, limit: max(0, 60 - otherCount), departureExclusions: departureExclusions)
    let current = pending.map { request in
      CommanderScheduledNotification(identifier: request.identifier, title: request.content.title,
        body: request.content.body, fireAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? .distantPast,
        payload: request.content.userInfo as? [String: String] ?? [:])
    }
    let changes = CommanderNotificationContract.reconcile(current: current, desired: desired,
      dataset: dataset, channel: channel)
    let obsolete = changes.remove
    let upserts = Set(changes.upsert.map(\.identifier))
    center.removePendingNotificationRequests(withIdentifiers: obsolete + legacy)
    let allEvents = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: dataset,
      channel: channel, includeDeparture: includeDeparture, now: .distantPast,
      limit: Int.max, departureExclusions: departureExclusions)
    let delivered = await center.deliveredNotifications()
    center.removeDeliveredNotifications(withIdentifiers: delivered.filter { notification in
      let request = notification.request
      if request.identifier.hasPrefix(prefix) {
        // Preserve valid delivered alerts so opening/syncing the app doesn't erase
        // Notification Center history or the user's opportunity to tap on Watch.
        return !allEvents.contains { item in
          item.identifier == request.identifier && item.payload == request.content.userInfo as? [String: String] &&
            item.title == request.content.title && item.body == request.content.body
        }
      }
      return channel == "production" && request.identifier.hasPrefix(legacyPrefix) &&
        dataset.accepts(stableID: String(request.identifier.dropFirst(legacyPrefix.count)))
    }.map { $0.request.identifier })
    var categories = await center.notificationCategories()
    categories.insert(UNNotificationCategory(identifier: CommanderNotificationContract.category,
      actions: [], intentIdentifiers: [], options: []))
    center.setNotificationCategories(categories)
    if desired.isEmpty {
      let remaining = await center.pendingNotificationRequests()
      guard !remaining.contains(where: { obsolete.contains($0.identifier) || legacy.contains($0.identifier) }) else {
        throw NSError(domain: "CommanderNotifications", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Úklid oznámení se nepodařilo ověřit."])
      }
      let future = try CommanderNotificationContract.desired(snapshot: snapshot, dataset: dataset,
        channel: channel, includeDeparture: includeDeparture, now: now, departureExclusions: departureExclusions)
      guard future.isEmpty else {
        throw NSError(domain: "CommanderNotifications", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Pro oznámení začátků nezbývá místo v systémové frontě."])
      }
      return
    }
    let settings = await center.notificationSettings()
    let permitted: Bool
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: permitted = true
    case .notDetermined: permitted = try await center.requestAuthorization(options: [.alert, .sound])
    default: permitted = false
    }
    guard permitted else {
      throw NSError(domain: "CommanderNotifications", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Oznámení začátku událostí nejsou povolena."])
    }
    for item in desired where upserts.contains(item.identifier) || !pending.contains(where: { matches($0, item) }) {
      let content = UNMutableNotificationContent()
      content.title = item.title
      content.body = item.body
      content.sound = .default
      content.interruptionLevel = .active
      content.categoryIdentifier = CommanderNotificationContract.category
      content.userInfo = item.payload
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
      var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
      components.timeZone = calendar.timeZone
      try await center.add(UNNotificationRequest(identifier: item.identifier, content: content,
        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
    let observed = await center.pendingNotificationRequests()
    let verificationTime = Date()
    guard desired.filter({ $0.fireAt > verificationTime }).allSatisfy({ item in observed.contains { matches($0, item) } }),
          !observed.contains(where: { obsolete.contains($0.identifier) || legacy.contains($0.identifier) }) else {
      throw NSError(domain: "CommanderNotifications", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Naplánovaná oznámení neodpovídají rozpisu; kontrola se zopakuje."])
    }
  }

  private func matches(_ request: UNNotificationRequest, _ item: CommanderScheduledNotification) -> Bool {
    guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
          !trigger.repeats, let date = trigger.nextTriggerDate() else { return false }
    return request.identifier == item.identifier && request.content.title == item.title &&
      request.content.body == item.body && request.content.categoryIdentifier == CommanderNotificationContract.category &&
      request.content.userInfo as? [String: String] == item.payload && request.content.sound != nil &&
      request.content.interruptionLevel == .active && abs(date.timeIntervalSince(item.fireAt)) < 1
  }
}

// Only input selection differs in an acceptance build. All lifecycle and UI
// code below is shared; reopening without arguments reuses the persisted times.
private enum CommanderAcceptanceLaunchMode {
  case none, visual, single, cleanup, readback

  static var requestID: String? {
    let args = ProcessInfo.processInfo.arguments
    guard let i = args.firstIndex(of: "--commander-request-id"), args.indices.contains(i + 1) else { return nil }
    return args[i + 1]
  }
  static var productionReadback: Bool {
    ProcessInfo.processInfo.arguments.contains("--production-readback")
  }

  static var current: Self {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    let arguments = ProcessInfo.processInfo.arguments
    if arguments.contains("--acceptance-cleanup") { return .cleanup }
    if arguments.contains("--acceptance-readback") { return .readback }
    if arguments.contains("--acceptance-single") { return .single }
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
      if mode != .visual && mode != .single && mode != .cleanup {
        guard let saved else { throw CommanderScheduleSyncError.noValidatedSnapshot }
        return saved
      }

      let fixture: Schedule
      if mode == .cleanup {
        fixture = try CommanderAcceptanceSchedule(
          now: now, previousVersion: saved?.scheduleVersion ?? 0,
          cleanup: true
        ).schedule
      } else {
        let scenario: PhysicalAcceptanceScenario = mode == .single ? .singleRenderer : .fullSpaDay
        fixture = try CommanderAcceptanceSchedule(
          now: now,
          previousVersion: saved?.scheduleVersion ?? 0,
          scenario: scenario
        ).schedule
      }
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
  @StateObject private var model: CommanderViewModel
  private let notificationDelegate: CommanderPhoneNotificationDelegate

  init() {
    let model = CommanderViewModel()
    _model = StateObject(wrappedValue: model)
    notificationDelegate = CommanderPhoneNotificationDelegate(model: model)
    UNUserNotificationCenter.current().delegate = notificationDelegate
  }

  var body: some Scene {
    WindowGroup {
      CommanderAppTabs(model: model)
        .preferredColorScheme(.dark)
        .task {
          if CommanderAcceptanceLaunchMode.current == .readback {
            await model.reportPassiveActivityReadback()
          } else {
            await model.bootstrap()
            if CommanderAcceptanceLaunchMode.current != .none || CommanderAcceptanceLaunchMode.productionReadback {
              await model.reportAcceptanceBootstrap()
            }
          }
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active, CommanderAcceptanceLaunchMode.current != .readback else { return }
          Task { await model.handleForeground() }
        }
    }
  }
}

private final class CommanderPhoneNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let model: CommanderViewModel
  init(model: CommanderViewModel) { self.model = model }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse) async {
    let content = response.notification.request.content
    await model.openNotification(action: response.actionIdentifier, category: content.categoryIdentifier,
                                 payload: content.userInfo as? [String: String] ?? [:])
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

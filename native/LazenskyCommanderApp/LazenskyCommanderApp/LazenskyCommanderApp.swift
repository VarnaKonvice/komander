import SwiftUI
import LazenskyCommanderCore
import UserNotifications
import WidgetKit
private enum CommanderDesignPreview {
#if targetEnvironment(simulator)
  static let enabled = true
#else
  // Preview data must never replace the real schedule on a physical production build.
  // It can still be enabled explicitly for a controlled device design session.
  static let enabled = true
#endif

  static let schedule: Schedule = {
    let data = Data(json.utf8)
    return try! JSONDecoder().decode(Schedule.self, from: data)
  }()

  private static let json = #"""
{
  "schemaVersion": 1,
  "scheduleVersion": 1001,
  "updatedAt": "2026-09-22T11:30:00.000Z",
  "stay": {
    "spa": "Rehabilitační sanatorium Darkov",
    "dateFrom": "2026-09-22",
    "dateTo": "2026-09-28",
    "room": "208",
    "doctor": "MUDr. Novák",
    "diagnosis": "Neuvedeno",
    "mealShift": "I. směna"
  },
  "events": [
    {
      "stableId": "demo-20260922-breakfast",
      "date": "2026-09-22",
      "start": "07:30",
      "end": "08:00",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260922-rehab",
      "date": "2026-09-22",
      "start": "09:00",
      "end": "09:30",
      "title": "Individuální rehabilitace",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Individuální rehabilitace"
    },
    {
      "stableId": "demo-20260922-magnet",
      "date": "2026-09-22",
      "start": "10:15",
      "end": "10:35",
      "title": "Magnetoterapie",
      "location": "Elektroléčba",
      "kind": "procedure",
      "procedureType": "Magnetoterapie"
    },
    {
      "stableId": "demo-20260922-lunch",
      "date": "2026-09-22",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260922-massage",
      "date": "2026-09-22",
      "start": "14:00",
      "end": "14:20",
      "title": "Masáž",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Masáž"
    },
    {
      "stableId": "demo-20260922-hydrojet",
      "date": "2026-09-22",
      "start": "15:30",
      "end": "15:50",
      "title": "Hydrojet",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Hydrojet"
    },
    {
      "stableId": "demo-20260922-dinner",
      "date": "2026-09-22",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260923-breakfast",
      "date": "2026-09-23",
      "start": "07:30",
      "end": "08:00",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260923-iodobrom",
      "date": "2026-09-23",
      "start": "08:20",
      "end": "08:40",
      "title": "Jodobromová koupel",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Jodobromová koupel"
    },
    {
      "stableId": "demo-20260923-ltv",
      "date": "2026-09-23",
      "start": "09:15",
      "end": "09:45",
      "title": "LTV",
      "location": "Tělocvična",
      "kind": "procedure",
      "procedureType": "LTV"
    },
    {
      "stableId": "demo-20260923-ultrasound",
      "date": "2026-09-23",
      "start": "10:15",
      "end": "10:30",
      "title": "Ultrazvuk",
      "location": "Elektroléčba",
      "kind": "procedure",
      "procedureType": "Ultrazvuk"
    },
    {
      "stableId": "demo-20260923-lunch",
      "date": "2026-09-23",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260923-imoove",
      "date": "2026-09-23",
      "start": "14:10",
      "end": "14:30",
      "title": "iMoove",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "iMoove"
    },
    {
      "stableId": "demo-20260923-dinner",
      "date": "2026-09-23",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260924-breakfast",
      "date": "2026-09-24",
      "start": "07:30",
      "end": "08:00",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260924-rehab",
      "date": "2026-09-24",
      "start": "08:30",
      "end": "09:00",
      "title": "Individuální rehabilitace",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Individuální rehabilitace"
    },
    {
      "stableId": "demo-20260924-peat",
      "date": "2026-09-24",
      "start": "09:30",
      "end": "09:50",
      "title": "Rašelinový zábal",
      "location": "Zábaly",
      "kind": "procedure",
      "procedureType": "Rašelinový zábal"
    },
    {
      "stableId": "demo-20260924-pool",
      "date": "2026-09-24",
      "start": "10:30",
      "end": "11:00",
      "title": "Bazén",
      "location": "Bazén",
      "kind": "procedure",
      "procedureType": "Bazén"
    },
    {
      "stableId": "demo-20260924-lunch",
      "date": "2026-09-24",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260924-massage",
      "date": "2026-09-24",
      "start": "14:00",
      "end": "14:20",
      "title": "Masáž",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Masáž"
    },
    {
      "stableId": "demo-20260924-dinner",
      "date": "2026-09-24",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260925-breakfast",
      "date": "2026-09-25",
      "start": "07:30",
      "end": "08:00",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260925-whirlpool",
      "date": "2026-09-25",
      "start": "08:30",
      "end": "08:50",
      "title": "Vířivá vana",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Vířivá vana"
    },
    {
      "stableId": "demo-20260925-ergo",
      "date": "2026-09-25",
      "start": "09:20",
      "end": "09:50",
      "title": "Ergoterapie",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Ergoterapie"
    },
    {
      "stableId": "demo-20260925-electro",
      "date": "2026-09-25",
      "start": "10:20",
      "end": "10:40",
      "title": "Elektroléčba",
      "location": "Elektroléčba",
      "kind": "procedure",
      "procedureType": "Elektroléčba"
    },
    {
      "stableId": "demo-20260925-lunch",
      "date": "2026-09-25",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260925-hydrojet",
      "date": "2026-09-25",
      "start": "14:30",
      "end": "14:50",
      "title": "Hydrojet",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Hydrojet"
    },
    {
      "stableId": "demo-20260925-dinner",
      "date": "2026-09-25",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260926-breakfast",
      "date": "2026-09-26",
      "start": "08:00",
      "end": "08:30",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260926-rehab",
      "date": "2026-09-26",
      "start": "09:15",
      "end": "09:45",
      "title": "Individuální rehabilitace",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Individuální rehabilitace"
    },
    {
      "stableId": "demo-20260926-massage",
      "date": "2026-09-26",
      "start": "10:20",
      "end": "10:40",
      "title": "Masáž",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Masáž"
    },
    {
      "stableId": "demo-20260926-lunch",
      "date": "2026-09-26",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260926-pool",
      "date": "2026-09-26",
      "start": "14:30",
      "end": "15:00",
      "title": "Bazén",
      "location": "Bazén",
      "kind": "procedure",
      "procedureType": "Bazén"
    },
    {
      "stableId": "demo-20260926-dinner",
      "date": "2026-09-26",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260927-breakfast",
      "date": "2026-09-27",
      "start": "08:00",
      "end": "08:30",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260927-imoove",
      "date": "2026-09-27",
      "start": "09:30",
      "end": "09:50",
      "title": "iMoove",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "iMoove"
    },
    {
      "stableId": "demo-20260927-lunch",
      "date": "2026-09-27",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260927-whirlpool",
      "date": "2026-09-27",
      "start": "14:30",
      "end": "14:50",
      "title": "Vířivá vana",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Vířivá vana"
    },
    {
      "stableId": "demo-20260927-dinner",
      "date": "2026-09-27",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    },
    {
      "stableId": "demo-20260928-breakfast",
      "date": "2026-09-28",
      "start": "07:30",
      "end": "08:00",
      "title": "Snídaně",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Snídaně"
    },
    {
      "stableId": "demo-20260928-rehab",
      "date": "2026-09-28",
      "start": "08:30",
      "end": "09:00",
      "title": "Individuální rehabilitace",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Individuální rehabilitace"
    },
    {
      "stableId": "demo-20260928-iodobrom",
      "date": "2026-09-28",
      "start": "09:30",
      "end": "09:50",
      "title": "Jodobromová koupel",
      "location": "Vodoléčba",
      "kind": "procedure",
      "procedureType": "Jodobromová koupel"
    },
    {
      "stableId": "demo-20260928-magnet",
      "date": "2026-09-28",
      "start": "10:20",
      "end": "10:40",
      "title": "Magnetoterapie",
      "location": "Elektroléčba",
      "kind": "procedure",
      "procedureType": "Magnetoterapie"
    },
    {
      "stableId": "demo-20260928-lunch",
      "date": "2026-09-28",
      "start": "12:00",
      "end": "12:40",
      "title": "Oběd",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Oběd"
    },
    {
      "stableId": "demo-20260928-massage",
      "date": "2026-09-28",
      "start": "14:00",
      "end": "14:20",
      "title": "Masáž",
      "location": "Rehabilitace",
      "kind": "procedure",
      "procedureType": "Masáž"
    },
    {
      "stableId": "demo-20260928-dinner",
      "date": "2026-09-28",
      "start": "17:30",
      "end": "18:00",
      "title": "Večeře",
      "location": "Jídelna",
      "kind": "meal",
      "mealType": "Večeře"
    }
  ],
  "settings": {
    "defaultLeadTimeMinutes": 20,
    "procedureTypeOverrides": {
      "Jodobromová koupel": 25,
      "Bazén": 25
    },
    "mealOverrides": {
      "Snídaně": 15,
      "Oběd": 15,
      "Večeře": 15
    }
  }
}
"""#
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

  private let adapter: AlarmKitAdapter
  private let procedureActivities: CommanderProcedureLiveActivityCoordinator
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let fallbackNotifications = IPhoneFallbackNotificationService()
  private let leadTimePreferences: LeadTimePreferencesStore
  private let channel: ScheduleChannel
  private var lastAutomaticAttempt: Date?
  private var delayedRecoveryTask: Task<Void, Never>?
  private var synchronizationRequests = CommanderSynchronizationRequestQueue()

  init() {
    let configuration = AppConfiguration()
    let adapter = AlarmKitAdapter(channel: configuration.channel)
    let procedureActivities = CommanderProcedureLiveActivityCoordinator(
      enabled: configuration.channel == .production
    )
    let scheduleService = URLSessionScheduleService(configuration: configuration)
    let namespace = configuration.channel.rawValue
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(key: "lazensky.commander.managedAlarms.\(namespace).v1"),
      adapter: adapter
    )
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    let leadTimePreferences = LeadTimePreferencesStore(
      key: "lazensky.commander.leadTimePreferences.\(namespace).v1"
    )
    let savedPreferences = leadTimePreferences.load()

    self.adapter = adapter
    self.procedureActivities = procedureActivities
    self.service = service
    self.watchConnectivity = watchConnectivity
    self.leadTimePreferences = leadTimePreferences
    self.channel = configuration.channel
    self.leadTimeOverrides = CommanderDesignPreview.enabled ? LeadTimeOverrides() : savedPreferences.overrides
    self.leadTimeProjectionRevision = CommanderDesignPreview.enabled ? 0 : savedPreferences.revision
    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(key: "lazensky.commander.scheduleSnapshot.\(namespace).v1"),
      watchDelivery: configuration.channel == .production ? watchConnectivity : nil
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
    if let lastAutomaticAttempt, Date().timeIntervalSince(lastAutomaticAttempt) < 10 { return }
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
      projectionRevision: leadTimeProjectionRevision
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
    if automatic { lastAutomaticAttempt = Date() }
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
          projectionRevision: projectionRevision
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
          overrides: leadTimeOverrides
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

@main
struct LazenskyCommanderApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = CommanderViewModel()

  var body: some Scene {
    WindowGroup {
      CommanderAppTabs(model: model)
      .preferredColorScheme(.dark)
      .task { await model.bootstrap() }
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

import SwiftUI
import LazenskyCommanderCore
import UserNotifications

@MainActor
final class CommanderViewModel: ObservableObject {
  @Published private(set) var accessStatus = "Kontroluji přístup k alarmům..."
  @Published private(set) var summary: AlarmSyncSummary?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isSynchronizing = false
  @Published private(set) var latestSchedule: Schedule?
  @Published private(set) var watchTransferStatus = "Aktivuji WatchConnectivity…"
  @Published private(set) var recoveryStatus = "Čekám na první kontrolu"
  @Published private(set) var fallbackStatus = "Nevyužito"
  @Published private(set) var requiresUserAction = false
  @Published private(set) var userActionMessage: String?

  private let adapter: AlarmKitAdapter
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let fallbackNotifications = IPhoneFallbackNotificationService()
  private let channel: ScheduleChannel
  private var lastAutomaticAttempt: Date?
  private var delayedRecoveryTask: Task<Void, Never>?

  init() {
    let configuration = AppConfiguration()
    let adapter = AlarmKitAdapter()
    let scheduleService = URLSessionScheduleService(configuration: configuration)
    let namespace = configuration.channel.rawValue
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(key: "lazensky.commander.managedAlarms.\(namespace).v1"),
      adapter: adapter
    )
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    self.adapter = adapter
    self.service = service
    self.watchConnectivity = watchConnectivity
    self.channel = configuration.channel
    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(key: "lazensky.commander.scheduleSnapshot.\(namespace).v1"),
      watchDelivery: configuration.channel == .production ? watchConnectivity : nil
    )
  }

  var watchScheduleSnapshot: WatchScheduleSnapshot? {
    latestSchedule.map { WatchScheduleSnapshot(schedule: $0) }
  }

  func bootstrap() async {
    latestSchedule = try? await scheduleSync.loadLastSchedule()
    if channel == .production, let watchScheduleSnapshot {
      do {
        watchTransferStatus = try await watchConnectivity.deliver(watchScheduleSnapshot).diagnosticText
      } catch {
        watchTransferStatus = "Čeká na automatické předání"
        errorMessage = error.localizedDescription
      }
    } else if channel == .e2e {
      watchTransferStatus = "Testovací kanál je od Watch oddělený"
    }
    await refreshAccess()
    await synchronizeWithRecovery(maxAttempts: 3, automatic: true)
  }

  func handleForeground() async {
    if let lastAutomaticAttempt, Date().timeIntervalSince(lastAutomaticAttempt) < 10 { return }
    await synchronizeWithRecovery(maxAttempts: 3, automatic: true)
  }

  func refreshAccess() async {
    accessStatus = await service.alarmAccessDescription()
  }

  func requestAuthorization() {
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
    Task { await synchronizeWithRecovery(maxAttempts: 3, automatic: false) }
  }

  private func synchronizeWithRecovery(maxAttempts: Int, automatic: Bool) async {
    guard !isSynchronizing else { return }
    if automatic { lastAutomaticAttempt = Date() }
    isSynchronizing = true
    delayedRecoveryTask?.cancel()
    delayedRecoveryTask = nil
    defer { isSynchronizing = false }

    var alarmProjectionFailed = false
    var shouldRetryLater = false

    for attempt in 0..<maxAttempts {
      do {
        let result = try await scheduleSync.synchronize()
        latestSchedule = result.schedule
        summary = result.alarmSummary
        watchTransferStatus = result.watchDeliveryStatus.diagnosticText

        if result.alarmSummary.succeeded {
          await fallbackNotifications.clear()
          fallbackStatus = "Nevyužito"
          recoveryStatus = result.alarmSummary.repairAttempts > 0 ? "Opraveno a ověřeno" : "Ověřeno"
          errorMessage = nil
          requiresUserAction = false
          userActionMessage = nil
          await refreshAccess()
          return
        }

        alarmProjectionFailed = true
        shouldRetryLater = true
        recoveryStatus = "Automaticky opravuji alarmy"
        errorMessage = result.alarmSummary.errorMessage
      } catch AlarmAdapterError.authorizationDenied {
        requiresUserAction = true
        userActionMessage = "Povol alarmy, aby tě Commander mohl spolehlivě upozornit na odchod."
        errorMessage = AlarmAdapterError.authorizationDenied.localizedDescription
        recoveryStatus = "Čeká na povolení alarmů"
        await refreshAccess()
        return
      } catch {
        shouldRetryLater = true
        errorMessage = error.localizedDescription
        recoveryStatus = latestSchedule == nil ? "Čekám na platný rozpis" : "Automatická kontrola se zopakuje"
      }

      if attempt + 1 < maxAttempts {
        let delay = UInt64(attempt + 1) * 1_000_000_000
        try? await Task.sleep(nanoseconds: delay)
      }
    }

    if alarmProjectionFailed, let latestSchedule {
      do {
        if try await fallbackNotifications.arm(schedule: latestSchedule) {
          fallbackStatus = "Aktivní bezpečnostní pojistka"
          requiresUserAction = false
          userActionMessage = nil
        } else {
          fallbackStatus = "Není povolena"
          requiresUserAction = true
          userActionMessage = "Commander nemůže zajistit záložní upozornění. Povol oznámení pro Lázeňský Commander."
        }
      } catch {
        fallbackStatus = "Nelze aktivovat"
        requiresUserAction = true
        userActionMessage = "Commander nemůže zajistit záložní upozornění. Povol oznámení pro Lázeňský Commander."
        errorMessage = error.localizedDescription
      }
    }

    if shouldRetryLater {
      scheduleDelayedRecovery()
    }
    await refreshAccess()
  }

  private func scheduleDelayedRecovery() {
    guard delayedRecoveryTask == nil else { return }
    delayedRecoveryTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard !Task.isCancelled, let self else { return }
      self.delayedRecoveryTask = nil
      await self.synchronizeWithRecovery(maxAttempts: 2, automatic: true)
    }
  }
}

@MainActor
private final class IPhoneFallbackNotificationService {
  private static let identifierPrefix = "lazensky.commander.iphone.fallback."
  private static let prague = TimeZone(identifier: "Europe/Prague")!
  private let center = UNUserNotificationCenter.current()

  func clear() async {
    let pending = await center.pendingNotificationRequests()
    let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
    if !identifiers.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
  }

  func arm(schedule: Schedule, now: Date = Date()) async throws -> Bool {
    guard try await ensureAuthorization() else { return false }
    let payload = try NativeAlarmContract.payload(schedule: schedule)
    let desired = try payload.alarms
      .filter { try NativeAlarmContract.date(fromLocalISO: $0.leaveAt) > now }
      .sorted { $0.leaveAt < $1.leaveAt }
      .prefix(60)

    await clear()
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
      NavigationStack {
        CommanderDashboardView(model: model)
      }
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
    case .sent: "Předáno"
    }
  }
}

private extension WatchScheduleDeliveryStatus {
  var diagnosticText: String {
    switch self {
    case .notConfigured: "Není nakonfigurováno"
    case .notAttempted: "Neprovedeno"
    case .queued: "Čeká na aktivaci"
    case .sent: "Předáno"
    case .failed: "Čeká na automatické předání"
    }
  }
}

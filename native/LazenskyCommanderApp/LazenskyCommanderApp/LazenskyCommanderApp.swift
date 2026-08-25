import SwiftUI
import LazenskyCommanderCore

@MainActor
final class CommanderViewModel: ObservableObject {
  @Published private(set) var accessStatus = "Kontroluji přístup k alarmům..."
  @Published private(set) var summary: AlarmSyncSummary?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isSynchronizing = false
  @Published private(set) var latestSchedule: Schedule?
  @Published private(set) var watchTransferStatus = "Aktivuji WatchConnectivity…"
  @Published private(set) var alarmRecoveryAttempts = 0

  private let adapter: AlarmKitAdapter
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let usesWatchTransport: Bool

  init() {
    let adapter = AlarmKitAdapter()
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()

    #if LC_E2E
    let configuration = AppConfiguration.e2e
    let usesWatchTransport = false
    #else
    let configuration = AppConfiguration()
    let usesWatchTransport = true
    #endif

    let scheduleService = URLSessionScheduleService(configuration: configuration)
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(),
      adapter: adapter
    )

    self.adapter = adapter
    self.service = service
    self.watchConnectivity = watchConnectivity
    self.usesWatchTransport = usesWatchTransport
    self.watchTransferStatus = usesWatchTransport ? "Aktivuji WatchConnectivity…" : "E2E test – Watch transport vypnut"

    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(),
      watchDelivery: usesWatchTransport ? watchConnectivity : nil
    )
  }

  var watchScheduleSnapshot: WatchScheduleSnapshot? {
    latestSchedule.map { WatchScheduleSnapshot(schedule: $0) }
  }

  func bootstrap() async {
    do {
      latestSchedule = try await scheduleSync.loadLastSchedule()
      if usesWatchTransport, let watchScheduleSnapshot {
        do {
          watchTransferStatus = try await watchConnectivity.deliver(watchScheduleSnapshot).diagnosticText
        } catch {
          watchTransferStatus = "Přenos se obnoví automaticky"
        }
      }
    } catch {
      errorMessage = "Uložený rozpis nelze načíst: \(error.localizedDescription)"
    }
    await refreshAccess()
  }

  func refreshAccess() async {
    accessStatus = await service.alarmAccessDescription()
  }

  func requestAuthorization() {
    Task {
      do {
        try await adapter.requestAuthorization()
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      await refreshAccess()
    }
  }

  func synchronize() {
    guard !isSynchronizing else { return }
    isSynchronizing = true
    errorMessage = nil
    Task {
      do {
        let result = try await scheduleSync.synchronize()
        summary = result.alarmSummary
        alarmRecoveryAttempts = result.alarmRecoveryAttempts
        latestSchedule = result.schedule
        errorMessage = result.alarmSummary.errorMessage
        if usesWatchTransport {
          watchTransferStatus = result.watchDeliveryStatus.diagnosticText
        }
      } catch {
        errorMessage = error.localizedDescription
      }
      await refreshAccess()
      isSynchronizing = false
    }
  }
}

@main
struct LazenskyCommanderApp: App {
  @StateObject private var model = CommanderViewModel()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CommanderDashboardView(model: model)
      }
      .preferredColorScheme(.dark)
      .task { await model.bootstrap() }
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
    case .failed: "Přenos se obnoví automaticky"
    }
  }
}

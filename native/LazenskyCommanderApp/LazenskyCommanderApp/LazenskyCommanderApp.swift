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
  @Published private(set) var safetyNetStatus = "Nepotřebné"

  private let adapter: AlarmKitAdapter
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator
  private let safetyNet: IPhoneAlarmSafetyNet
  private let usesWatchTransport: Bool
  private var repairTask: Task<Void, Never>?

  init() {
    let adapter = AlarmKitAdapter()
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    let safetyNet = IPhoneAlarmSafetyNet()

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
    self.safetyNet = safetyNet
    self.usesWatchTransport = usesWatchTransport
    self.watchTransferStatus = usesWatchTransport ? "Aktivuji WatchConnectivity…" : "E2E test – Watch transport vypnut"

    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(),
      watchDelivery: usesWatchTransport ? watchConnectivity : nil
    )
  }

  deinit {
    repairTask?.cancel()
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
    await refreshFromNetwork(reportFetchFailure: latestSchedule == nil)
  }

  func refreshAccess() async {
    accessStatus = await service.alarmAccessDescription()
  }

  func requestAuthorization() {
    Task {
      do {
        try await adapter.requestAuthorization()
        errorMessage = nil
        await refreshFromNetwork(reportFetchFailure: true)
      } catch {
        errorMessage = error.localizedDescription
      }
      await refreshAccess()
    }
  }

  func synchronize() {
    Task { await refreshFromNetwork(reportFetchFailure: true) }
  }

  func refreshWhenActive() async {
    await refreshFromNetwork(reportFetchFailure: false)
  }

  private func refreshFromNetwork(reportFetchFailure: Bool) async {
    guard !isSynchronizing else { return }
    isSynchronizing = true
    defer { isSynchronizing = false }

    do {
      let result = try await scheduleSync.synchronize()
      summary = result.alarmSummary
      alarmRecoveryAttempts = result.alarmRecoveryAttempts
      latestSchedule = result.schedule
      if usesWatchTransport {
        watchTransferStatus = result.watchDeliveryStatus.diagnosticText
      }

      do {
        let safetyState = try await safetyNet.reconcile(
          schedule: result.schedule,
          uncoveredStableIds: result.alarmSummary.uncoveredStableIds
        )
        safetyNetStatus = safetyState.diagnosticText
        // A verified AlarmKit set or a verified fallback notification set both keep
        // the user covered. Technical recovery can continue silently in the background.
        errorMessage = nil
      } catch {
        safetyNetStatus = "Nelze zajistit zálohu"
        errorMessage = result.alarmSummary.uncoveredStableIds.isEmpty ? nil : error.localizedDescription
      }

      if result.alarmSummary.succeeded {
        cancelRepairRetry()
      } else {
        scheduleRepairRetry()
      }
    } catch {
      if reportFetchFailure || latestSchedule == nil {
        errorMessage = error.localizedDescription
      }
      scheduleRepairRetry()
    }

    await refreshAccess()
  }

  private func scheduleRepairRetry() {
    guard repairTask == nil else { return }
    repairTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(60))
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.repairTask = nil
      await self.refreshFromNetwork(reportFetchFailure: false)
    }
  }

  private func cancelRepairRetry() {
    repairTask?.cancel()
    repairTask = nil
  }
}

@main
struct LazenskyCommanderApp: App {
  @StateObject private var model = CommanderViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        CommanderDashboardView(model: model)
      }
      .preferredColorScheme(.dark)
      .task { await model.bootstrap() }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await model.refreshWhenActive() }
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
    case .failed: "Přenos se obnoví automaticky"
    }
  }
}

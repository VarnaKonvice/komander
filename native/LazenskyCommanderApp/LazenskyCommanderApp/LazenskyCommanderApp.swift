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

  private let adapter: AlarmKitAdapter
  private let service: AlarmSyncService
  private let scheduleSync: CommanderScheduleSyncCoordinator
  private let watchConnectivity: IPhoneWatchConnectivityCoordinator

  init() {
    let adapter = AlarmKitAdapter()
    let scheduleService = URLSessionScheduleService(configuration: AppConfiguration())
    let service = AlarmSyncService(
      scheduleService: scheduleService,
      store: UserDefaultsAlarmStateStore(),
      adapter: adapter
    )
    let watchConnectivity = IPhoneWatchConnectivityCoordinator()
    self.adapter = adapter
    self.service = service
    self.watchConnectivity = watchConnectivity
    scheduleSync = CommanderScheduleSyncCoordinator(
      scheduleService: scheduleService,
      alarmSyncService: service,
      scheduleStore: UserDefaultsScheduleSnapshotStore(),
      watchDelivery: watchConnectivity
    )
  }

  var watchScheduleSnapshot: WatchScheduleSnapshot? {
    latestSchedule.map { WatchScheduleSnapshot(schedule: $0) }
  }

  func bootstrap() async {
    do {
      latestSchedule = try await scheduleSync.loadLastSchedule()
      if let watchScheduleSnapshot {
        do {
          watchTransferStatus = try await watchConnectivity.deliver(watchScheduleSnapshot).diagnosticText
        } catch {
          watchTransferStatus = "Chyba přenosu: \(error.localizedDescription)"
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
    isSynchronizing = true
    errorMessage = nil
    Task {
      do {
        let result = try await scheduleSync.synchronize()
        summary = result.alarmSummary
        errorMessage = result.alarmSummary.errorMessage
        if result.succeeded {
          latestSchedule = result.schedule
        }
        watchTransferStatus = result.watchDeliveryStatus.diagnosticText
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
        Form {
          Section {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
              CommanderLiveCard(schedule: model.latestSchedule, now: timeline.date)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.clear)
          }

          Section("Synchronizace") {
            Button {
              model.synchronize()
            } label: {
              HStack {
                Text(model.isSynchronizing ? "Synchronizuji…" : "Synchronizovat rozpis")
                Spacer()
                if model.isSynchronizing { ProgressView() }
              }
            }
            .disabled(model.isSynchronizing)
            LabeledContent("Verze", value: model.summary.map { String($0.scheduleVersion ?? 0) } ?? "Dosud nesynchronizováno")
            LabeledContent("Požadované alarmy", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
            LabeledContent("Poslední úspěšný sync", value: model.summary?.completedAt?.formatted() ?? "Nikdy")
            LabeledContent("Apple Watch", value: model.watchTransferStatus)
          }
          Section("AlarmKit") {
            Text(model.accessStatus)
            if model.accessStatus.contains("not been requested") {
              Button("Povolit alarmy") { model.requestAuthorization() }
            }
          }
          Section("Poslední synchronizace") {
            LabeledContent("Vytvořeno", value: model.summary.map { String($0.appliedCreate) } ?? "0")
            LabeledContent("Aktualizováno", value: model.summary.map { String($0.appliedUpdate) } ?? "0")
            LabeledContent("Zrušeno", value: model.summary.map { String($0.appliedCancel) } ?? "0")
            LabeledContent("Beze změny", value: model.summary.map { String($0.plan.unchanged.count) } ?? "0")
          }
          if let error = model.errorMessage {
            Section("Chyba") { Text(error).foregroundStyle(.red) }
          }
        }
        .navigationTitle("Lázeňský Commander")
        .task { await model.bootstrap() }
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
    case .failed(let message): "Chyba přenosu: \(message)"
    }
  }
}

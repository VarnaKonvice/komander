import SwiftUI
import LazenskyCommanderCore

@MainActor
final class CommanderViewModel: ObservableObject {
  @Published private(set) var accessStatus = "Kontroluji přístup k alarmům..."
  @Published private(set) var summary: AlarmSyncSummary?
  @Published private(set) var errorMessage: String?
  @Published private(set) var isSynchronizing = false

  private let adapter: AlarmKitAdapter
  private let service: AlarmSyncService

  init() {
    let adapter = AlarmKitAdapter()
    self.adapter = adapter
    service = AlarmSyncService(
      scheduleService: URLSessionScheduleService(configuration: AppConfiguration()),
      store: UserDefaultsAlarmStateStore(),
      adapter: adapter
    )
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
        let result = try await service.synchronize()
        summary = result
        errorMessage = result.errorMessage
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
          Section("AlarmKit") {
            Text(model.accessStatus)
            if model.accessStatus.contains("not been requested") {
              Button("Povolit alarmy") { model.requestAuthorization() }
            }
          }
          Section("Rozpis") {
            LabeledContent("Verze", value: model.summary.map { String($0.scheduleVersion ?? 0) } ?? "Dosud nesynchronizováno")
            LabeledContent("Požadované alarmy", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
            LabeledContent("Poslední úspěšný sync", value: model.summary?.completedAt?.formatted() ?? "Nikdy")
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
        .toolbar {
          Button("Synchronizovat") { model.synchronize() }
            .disabled(model.isSynchronizing)
        }
        .task { await model.refreshAccess() }
      }
    }
  }
}

#if os(iOS)
import SwiftUI
import LazenskyCommanderCore

@MainActor
final class CompanionViewModel: ObservableObject {
  @Published var isSynchronizing = false
  @Published var summary: AlarmSyncSummary?
  @Published var errorMessage: String?
  @Published var authorizationText = "Checking alarm access..."

  private let service: AlarmSyncService

  init(service: AlarmSyncService = AlarmSyncService(scheduleService: URLSessionScheduleService(configuration: AppConfiguration()), store: UserDefaultsAlarmStateStore(), adapter: UnavailableAlarmKitAdapter())) {
    self.service = service
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
      authorizationText = await service.alarmAccessDescription()
      isSynchronizing = false
    }
  }

  func refreshAlarmAccess() async {
    authorizationText = await service.alarmAccessDescription()
  }
}

@main
struct LazenskyCommanderApp: App {
  @StateObject private var model = CompanionViewModel()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        Form {
          Section("Alarm access") { Text(model.authorizationText) }
          Section("Schedule") {
            LabeledContent("Version", value: model.summary.map { String($0.scheduleVersion ?? 0) } ?? "Not synchronized")
            LabeledContent("Required alarms", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
            LabeledContent("Last successful sync", value: model.summary?.completedAt?.formatted() ?? "Never")
          }
          Section("Last sync") {
            LabeledContent("Create", value: model.summary.map { String($0.appliedCreate) } ?? "0")
            LabeledContent("Update", value: model.summary.map { String($0.appliedUpdate) } ?? "0")
            LabeledContent("Cancel", value: model.summary.map { String($0.appliedCancel) } ?? "0")
            LabeledContent("Unchanged", value: model.summary.map { String($0.plan.unchanged.count) } ?? "0")
          }
          if let errorMessage = model.errorMessage {
            Section("Error") { Text(errorMessage).foregroundStyle(.red) }
          }
        }
        .navigationTitle("Lazensky Commander")
        .task { await model.refreshAlarmAccess() }
        .toolbar {
          Button("Synchronize") { model.synchronize() }.disabled(model.isSynchronizing)
        }
      }
    }
  }
}
#else
import Foundation

@main
enum LazenskyCommanderCommandLinePlaceholder {
  static func main() {
    print("Open native/LazenskyCommander/Package.swift in Xcode to build the iOS companion.")
  }
}
#endif

import SwiftUI

struct CommanderSystemStatusView: View {
  @ObservedObject var model: CommanderViewModel

  private var scheduleVersion: String {
    if let version = model.summary?.scheduleVersion ?? model.latestSchedule?.scheduleVersion {
      return String(version)
    }
    return "Dosud nesynchronizováno"
  }

  var body: some View {
    Form {
      Section("Synchronizace") {
        Button {
          model.synchronize()
        } label: {
          HStack {
            Label(
              model.isSynchronizing ? "Synchronizuji…" : "Synchronizovat rozpis",
              systemImage: "arrow.triangle.2.circlepath"
            )
            Spacer()
            if model.isSynchronizing { ProgressView() }
          }
        }
        .disabled(model.isSynchronizing)
        LabeledContent("Verze", value: scheduleVersion)
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
        Section("Chyba") {
          Text(error)
            .foregroundStyle(.red)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(CommanderDashboardPalette.background)
    .navigationTitle("Stav systému")
    .navigationBarTitleDisplayMode(.inline)
  }
}

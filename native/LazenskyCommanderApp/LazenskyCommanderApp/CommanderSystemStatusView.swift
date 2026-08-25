import SwiftUI

struct CommanderSystemStatusView: View {
  @ObservedObject var model: CommanderViewModel

  private var scheduleVersion: String {
    model.latestSchedule.map { "v\($0.scheduleVersion)" } ?? "Dosud nenačten"
  }

  private var alarmVersion: String {
    model.summary?.scheduleVersion.map { "v\($0)" } ?? "Dosud neověřen"
  }

  private var alarmState: String {
    guard let summary = model.summary else { return "Dosud neověřen" }
    return summary.succeeded ? "Ověřeno" : "Automatická oprava pokračuje"
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
        LabeledContent("Rozpis", value: scheduleVersion)
        LabeledContent("AlarmKit", value: alarmState)
        LabeledContent("Alarm verze", value: alarmVersion)
        LabeledContent("Požadované alarmy", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
        LabeledContent("Záložní upozornění", value: model.safetyNetStatus)
        LabeledContent("Pokusy o automatickou opravu", value: model.alarmRecoveryAttempts == 0 ? "—" : String(model.alarmRecoveryAttempts))
        LabeledContent("Poslední ověřený AlarmKit sync", value: model.summary?.completedAt?.formatted() ?? "Dosud neověřen")
        LabeledContent("Apple Watch", value: model.watchTransferStatus)
      }

      Section("AlarmKit oprávnění") {
        Text(model.accessStatus)
        if model.accessStatus.contains("not been requested") {
          Button("Povolit alarmy") { model.requestAuthorization() }
        }
      }

      Section("Poslední reconciliation") {
        LabeledContent("Vytvořeno", value: model.summary.map { String($0.appliedCreate) } ?? "0")
        LabeledContent("Aktualizováno", value: model.summary.map { String($0.appliedUpdate) } ?? "0")
        LabeledContent("Zrušeno", value: model.summary.map { String($0.appliedCancel) } ?? "0")
        LabeledContent("Beze změny", value: model.summary.map { String($0.plan.unchanged.count) } ?? "0")
        LabeledContent("Bez primárního krytí", value: model.summary.map { String($0.uncoveredStableIds.count) } ?? "0")
      }

      if let error = model.errorMessage {
        Section("Vyžaduje zásah") {
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

import SwiftUI

struct CommanderSystemStatusView: View {
  @ObservedObject var model: CommanderViewModel

  private var scheduleVersion: String {
    model.latestSchedule.map { "v\($0.scheduleVersion)" } ?? "Dosud nenačteno"
  }

  private var alarmState: String {
    guard let summary = model.summary else { return model.recoveryStatus }
    if summary.succeeded {
      return "v\(summary.scheduleVersion ?? 0) · ověřeno"
    }
    return "Automatická obnova"
  }

  var body: some View {
    Form {
      if model.requiresUserAction, let message = model.userActionMessage {
        Section("Potřebuje tvůj zásah") {
          Text(message)
        }
      }

      Section("Synchronizace") {
        Button {
          model.synchronize()
        } label: {
          HStack {
            Label(
              model.isSynchronizing ? "Kontroluji…" : "Zkontrolovat rozpis",
              systemImage: "arrow.triangle.2.circlepath"
            )
            Spacer()
            if model.isSynchronizing { ProgressView() }
          }
        }
        .disabled(model.isSynchronizing)

        LabeledContent("Rozpis", value: scheduleVersion)
        LabeledContent("AlarmKit", value: alarmState)
        LabeledContent("Bezpečnostní pojistka", value: model.fallbackStatus)
        LabeledContent("Apple Watch", value: model.watchTransferStatus)
        LabeledContent("Obnova", value: model.recoveryStatus)
        LabeledContent("Poslední ověření", value: model.summary?.completedAt?.formatted() ?? "Zatím neověřeno")
      }

      Section("AlarmKit oprávnění") {
        Text(model.accessStatus)
        if model.accessStatus.contains("not been requested") || model.accessStatus.contains("denied") {
          Button("Povolit alarmy") { model.requestAuthorization() }
        }
      }

      Section("Poslední reconciliation") {
        LabeledContent("Požadované alarmy", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
        LabeledContent("Vytvořeno", value: model.summary.map { String($0.appliedCreate) } ?? "0")
        LabeledContent("Aktualizováno", value: model.summary.map { String($0.appliedUpdate) } ?? "0")
        LabeledContent("Zrušeno", value: model.summary.map { String($0.appliedCancel) } ?? "0")
        LabeledContent("Automatické opravy", value: model.summary.map { String($0.repairAttempts) } ?? "0")
      }

      if let detail = model.errorMessage, !model.requiresUserAction {
        Section("Technická diagnostika") {
          Text(detail)
            .foregroundStyle(.secondary)
            .font(.footnote)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(CommanderDashboardPalette.background)
    .navigationTitle("Stav systému")
    .navigationBarTitleDisplayMode(.inline)
  }
}

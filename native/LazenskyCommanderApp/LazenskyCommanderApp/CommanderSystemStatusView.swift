import LazenskyCommanderCore
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

  private var alarmAccessText: String {
    if model.accessStatus.contains("authorized") { return "Přístup k alarmům je povolený." }
    if model.accessStatus.contains("not been requested") { return "Přístup k alarmům ještě nebyl vyžádán." }
    if model.accessStatus.contains("denied") { return "Přístup k alarmům je zamítnutý." }
    return model.accessStatus
  }

  private var recentHistory: [AlarmReconciliationHistoryEntry] {
    guard let history = model.summary?.reconciliationHistory else { return [] }
    var selected: [AlarmReconciliationHistoryEntry] = []
    if let latest = history.last { selected.append(latest) }
    for entry in history.dropLast().reversed() where entry.hasProblem {
      if selected.count >= 4 { break }
      selected.append(entry)
    }
    return selected
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

      Section("Oprávnění alarmů") {
        Text(alarmAccessText)
        if model.accessStatus.contains("not been requested") || model.accessStatus.contains("denied") {
          Button("Povolit alarmy") { model.requestAuthorization() }
        }
      }

      Section("Poslední kontrola alarmů") {
        LabeledContent("Požadované alarmy", value: model.summary.map { String($0.desiredAlarmCount) } ?? "0")
        LabeledContent("Vytvořeno", value: model.summary.map { String($0.appliedCreate) } ?? "0")
        LabeledContent("Aktualizováno", value: model.summary.map { String($0.appliedUpdate) } ?? "0")
        LabeledContent("Zrušeno", value: model.summary.map { String($0.appliedCancel) } ?? "0")
        LabeledContent("Opravné průchody", value: model.summary.map { String($0.repairAttempts) } ?? "0")
        Text("Počet opravných průchodů sám o sobě neznamená, že byl opraven konkrétní alarm. Rozhodující je uložená kontrola skutečného stavu před a po změně.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if !recentHistory.isEmpty {
        Section("Historie kontrol alarmů") {
          ForEach(recentHistory) { entry in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("Rozpis v\(entry.scheduleVersion)")
                  .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.startedAt.formatted(date: .numeric, time: .shortened))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Text(entry.verified ? "Výsledek: ověřeno" : "Výsledek: neověřeno")
                .font(.caption)
                .foregroundStyle(entry.verified ? .secondary : .orange)

              if entry.hadProblemBeforeChanges {
                Text("Před změnou byl zjištěn nesoulad:")
                  .font(.caption.weight(.semibold))
                ForEach(Array(entry.before.filter(\.hasMismatch).prefix(3))) { observation in
                  Text("• \(observation.title): \(observation.diagnosticText ?? "nesoulad")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              if let error = entry.errorMessage {
                Text(error)
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
            }
            .padding(.vertical, 2)
          }
        }
      }

      if let issue = model.liveActivityIssue {
        Section("Živé aktivity") {
          Text(issue)
          Text("Kontrola rozpisu nebo návrat do aplikace přípravu zopakuje. Ověření alarmů nepotvrzuje zobrazení živé aktivity.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
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
    .background(CommanderDashboardPalette.backgroundGradient.ignoresSafeArea())
    .navigationTitle("Diagnostika")
    .navigationBarTitleDisplayMode(.inline)
  }
}

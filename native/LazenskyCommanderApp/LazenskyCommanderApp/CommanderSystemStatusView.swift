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

  var body: some View {
    Form {
      if model.requiresUserAction, let message = model.userActionMessage {
        Section("Potřebuje tvůj zásah") {
          Text(message)
        }
      }

      Section("Nastavení") {
        NavigationLink {
          CommanderLeadTimeSettingsView(model: model)
        } label: {
          LabeledContent("Čas na odchod", value: "\(model.defaultLeadTimeMinutes) min")
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

private struct CommanderLeadTimeSettingsView: View {
  @ObservedObject var model: CommanderViewModel

  private var procedureTypes: [String] {
    guard let schedule = model.latestSchedule else { return [] }
    return Array(Set(schedule.events.compactMap { event -> String? in
      guard event.kind == .procedure else { return nil }
      let value = event.procedureType ?? event.title
      return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    })).sorted()
  }

  private var mealTypes: [String] {
    guard let schedule = model.latestSchedule else { return [] }
    return Array(Set(schedule.events.compactMap { event -> String? in
      guard event.kind == .meal else { return nil }
      let value = event.mealType ?? event.title
      return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    })).sorted()
  }

  private var events: [ScheduleEvent] {
    (model.latestSchedule?.events ?? []).sorted {
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.start != $1.start { return $0.start < $1.start }
      return $0.stableId < $1.stableId
    }
  }

  var body: some View {
    Form {
      Section("Výchozí čas") {
        Stepper(
          "\(model.defaultLeadTimeMinutes) min před začátkem",
          value: Binding(
            get: { model.defaultLeadTimeMinutes },
            set: { model.setDefaultLeadTimeMinutes($0) }
          ),
          in: 0...180,
          step: 1
        )
        if model.leadTimeOverrides.defaultLeadTimeMinutes != nil,
           let source = model.latestSchedule?.settings.defaultLeadTimeMinutes {
          Button("Použít hodnotu z rozpisu (\(source) min)") {
            model.resetDefaultLeadTime()
          }
        }
        Text("Tato hodnota určuje skutečný čas odchodu. Třicet minut je pouze maximální délka odpočtu před alarmem, ne pevný čas odchodu.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }

      if !procedureTypes.isEmpty {
        Section("Podle procedury") {
          ForEach(procedureTypes, id: \.self) { type in
            leadTimeRow(
              title: type,
              value: procedureLeadTime(type),
              isOverridden: model.leadTimeOverrides.procedureTypeOverrides[type] != nil,
              set: { model.setProcedureLeadTimeMinutes($0, procedureType: type) },
              reset: { model.resetProcedureLeadTime(procedureType: type) }
            )
          }
        }
      }

      if !mealTypes.isEmpty {
        Section("Podle jídla") {
          ForEach(mealTypes, id: \.self) { type in
            leadTimeRow(
              title: type,
              value: mealLeadTime(type),
              isOverridden: model.leadTimeOverrides.mealOverrides[type] != nil,
              set: { model.setMealLeadTimeMinutes($0, mealType: type) },
              reset: { model.resetMealLeadTime(mealType: type) }
            )
          }
        }
      }

      if !events.isEmpty {
        Section("Jednotlivé události") {
          ForEach(events, id: \.stableId) { event in
            VStack(alignment: .leading, spacing: 5) {
              Text("\(event.date) · \(event.start) · \(event.title)")
                .font(.subheadline)
              Stepper(
                "Odchod \(model.effectiveLeadTimeMinutes(for: event)) min předem",
                value: Binding(
                  get: { model.effectiveLeadTimeMinutes(for: event) },
                  set: { model.setEventLeadTimeMinutes($0, stableId: event.stableId) }
                ),
                in: 0...180,
                step: 1
              )
              if model.leadTimeOverrides.eventOverrides[event.stableId] != nil {
                Button("Zrušit výjimku") {
                  model.resetEventLeadTime(stableId: event.stableId)
                }
                .font(.footnote)
              }
            }
          }
        }
      }

      if model.leadTimeOverrides != LeadTimeOverrides() {
        Section {
          Button("Vrátit všechny časy k rozpisu", role: .destructive) {
            model.resetAllLeadTimeOverrides()
          }
        }
      }
    }
    .navigationTitle("Čas na odchod")
    .navigationBarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  private func leadTimeRow(
    title: String,
    value: Int,
    isOverridden: Bool,
    set: @escaping (Int) -> Void,
    reset: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline)
      Stepper(
        "\(value) min předem",
        value: Binding(get: { value }, set: set),
        in: 0...180,
        step: 1
      )
      if isOverridden {
        Button("Použít obecné nastavení") { reset() }
          .font(.footnote)
      }
    }
  }

  private func procedureLeadTime(_ type: String) -> Int {
    if let value = model.leadTimeOverrides.procedureTypeOverrides[type] { return value }
    guard let event = model.latestSchedule?.events.first(where: {
      $0.kind == .procedure && ($0.procedureType ?? $0.title) == type
    }) else { return model.defaultLeadTimeMinutes }
    return model.effectiveLeadTimeMinutes(for: event)
  }

  private func mealLeadTime(_ type: String) -> Int {
    if let value = model.leadTimeOverrides.mealOverrides[type] { return value }
    guard let event = model.latestSchedule?.events.first(where: {
      $0.kind == .meal && ($0.mealType ?? $0.title) == type
    }) else { return model.defaultLeadTimeMinutes }
    return model.effectiveLeadTimeMinutes(for: event)
  }
}

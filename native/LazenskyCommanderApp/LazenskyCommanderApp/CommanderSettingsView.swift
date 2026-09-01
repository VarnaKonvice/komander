import LazenskyCommanderCore
import SwiftUI

struct CommanderSettingsView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    CommanderTabScaffold(
      tab: "Nastavení",
      title: "Nastavení",
      subtitle: "Upravte si chování aplikace podle svých potřeb."
    ) {
      if model.requiresUserAction, let message = model.userActionMessage {
        CommanderSettingsAttentionCard(message: message)
      }

      CommanderSectionCard(
        title: "Čas odchodu",
        symbol: "clock.fill",
        accent: CommanderDesignTokens.Colors.amber
      ) {
        NavigationLink {
          CommanderLeadTimeSettingsView(model: model)
        } label: {
          CommanderNavigationRow(
            title: "Předstihy",
            subtitle: "Obecné, typové a individuální časy",
            symbol: "figure.walk.motion",
            accent: CommanderDesignTokens.Colors.amber,
            value: "\(model.defaultLeadTimeMinutes) min"
          )
        }
        .buttonStyle(.plain)
      }

      CommanderProvisioningSection()

      CommanderScheduleSettingsCard(model: model)

      CommanderSectionCard(
        title: "Pokročilé",
        symbol: "wrench.and.screwdriver.fill",
        accent: CommanderDesignTokens.Colors.textSecondary
      ) {
        NavigationLink {
          CommanderSystemStatusView(model: model)
        } label: {
          CommanderNavigationRow(
            title: "Diagnostika",
            subtitle: "Technický stav alarmů a synchronizace",
            symbol: "waveform.path.ecg",
            accent: CommanderDesignTokens.Colors.textSecondary
          )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

private struct CommanderSettingsAttentionCard: View {
  let message: String

  var body: some View {
    HStack(alignment: .top, spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: "exclamationmark.triangle.fill",
        color: CommanderDesignTokens.Colors.criticalRed,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text("Potřebuje váš zásah")
          .commanderFont(.eventTitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(message)
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: CommanderDesignTokens.Colors.criticalRed)
  }
}

private struct CommanderScheduleSettingsCard: View {
  @ObservedObject var model: CommanderViewModel

  private var needsAlarmPermission: Bool {
    model.accessStatus.contains("not been requested") || model.accessStatus.contains("denied")
  }

  var body: some View {
    CommanderSectionCard(
      title: "Rozpis",
      symbol: "calendar",
      accent: CommanderDesignTokens.Colors.locationBlue
    ) {
      Button {
        model.synchronize()
      } label: {
        CommanderSettingsActionRow(
          title: model.isSynchronizing ? "Kontroluji…" : "Zkontrolovat rozpis",
          subtitle: "Ověřit aktuální data a alarmy",
          symbol: "arrow.triangle.2.circlepath",
          accent: CommanderDesignTokens.Colors.locationBlue,
          isWorking: model.isSynchronizing
        )
      }
      .buttonStyle(.plain)
      .disabled(model.isSynchronizing)

      if let completed = model.summary?.completedAt {
        CommanderDetailRow(
          title: "Poslední ověření",
          value: completed.formatted(CommanderScheduleDateStyle.departure),
          symbol: "checkmark.circle.fill",
          accent: CommanderDesignTokens.Colors.mealGreen
        )
      }

      if needsAlarmPermission {
        Button("Povolit alarmy") { model.requestAuthorization() }
          .commanderFont(.metric)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .padding(CommanderDesignTokens.Spacing.small)
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(CommanderDesignTokens.Colors.urgentOrange.opacity(0.18))
          .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
          .overlay {
            RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
              .strokeBorder(CommanderDesignTokens.Colors.urgentOrange.opacity(0.5), lineWidth: 1)
          }
      }
    }
  }
}

private struct CommanderSettingsActionRow: View {
  let title: String
  let subtitle: String
  let symbol: String
  let accent: Color
  let isWorking: Bool

  var body: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: symbol,
        color: accent,
        size: CommanderDesignTokens.Size.rowMetricBadge
      )
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .commanderFont(.metric)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(subtitle)
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      Spacer(minLength: CommanderDesignTokens.Spacing.small)
      if isWorking {
        ProgressView().tint(accent)
      }
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .background(CommanderDesignTokens.Colors.panel.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(CommanderDesignTokens.Stroke.normal, lineWidth: CommanderDesignTokens.Stroke.width)
    }
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
    .scrollContentBackground(.hidden)
    .background(CommanderDashboardPalette.backgroundGradient.ignoresSafeArea())
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
    guard let schedule = model.latestSchedule else { return model.defaultLeadTimeMinutes }
    return (try? NativeAlarmContract.typeLeadTime(
      kind: .procedure,
      type: type,
      schedule: schedule,
      overrides: model.leadTimeOverrides
    )) ?? model.defaultLeadTimeMinutes
  }

  private func mealLeadTime(_ type: String) -> Int {
    guard let schedule = model.latestSchedule else { return model.defaultLeadTimeMinutes }
    return (try? NativeAlarmContract.typeLeadTime(
      kind: .meal,
      type: type,
      schedule: schedule,
      overrides: model.leadTimeOverrides
    )) ?? model.defaultLeadTimeMinutes
  }
}

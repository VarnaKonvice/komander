import LazenskyCommanderCore
import SwiftUI

struct CommanderSettingsView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    CommanderTabScaffold(
      tab: "Nastavení",
      title: "Nastavení",
      subtitle: "Upravte si chování aplikace podle svých potřeb.",
      schedule: model.latestSchedule
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

struct CommanderScheduleAuditView: View {
  let schedule: Schedule?
  let onClose: () -> Void

  private var report: CommanderScheduleAuditReport? {
    schedule.map { CommanderScheduleAudit.run($0, policy: .petrSpaOperational) }
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        CommanderGlassHeader(tab: "", showsTabPill: false)
        CommanderScreenHeading(
          title: "Kontrola rozpisu",
          subtitle: "Bezpečnostní kontrola aktuální verze"
        )

        if let report {
          statusCard(report)
          summaryCard(report)
          issuesCard(report)
        } else {
          CommanderSectionCard(
            title: "Rozpis není načten",
            symbol: "questionmark.circle.fill",
            accent: CommanderDesignTokens.Colors.textSecondary
          ) {
            Text("Po načtení rozpisu se zde zobrazí kontrola dnů, událostí a anomálií.")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          }
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, CommanderDesignTokens.Spacing.scrollTop)
      .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
    }
    .scrollIndicators(.hidden)
    .background(CommanderDepthBackground().ignoresSafeArea())
    .toolbar(.visible, for: .navigationBar)
    .navigationTitle("Kontrola rozpisu")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          onClose()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 17, weight: .bold))
        }
        .accessibilityLabel("Zpět")
      }
    }
  }

  private func statusCard(_ report: CommanderScheduleAuditReport) -> some View {
    let errors = report.issues.filter { $0.severity == .error }.count
    let warnings = report.issues.filter { $0.severity == .warning }.count
    let color = errors > 0 ? CommanderDesignTokens.Colors.criticalRed
      : warnings > 0 ? CommanderDesignTokens.Colors.urgentOrange
      : CommanderDesignTokens.Colors.mealGreen
    let title = errors > 0 ? "Rozpis obsahuje chybu"
      : warnings > 0 ? "Rozpis vyžaduje kontrolu"
      : "Rozpis bez upozornění"
    let detail = errors > 0 ? "\(errors) chyb · \(warnings) kontrol"
      : warnings > 0 ? "\(warnings) položek k potvrzení"
      : "Strukturální kontrola je čistá"

    return HStack(spacing: 10) {
      CommanderSymbolBadge(
        symbol: errors > 0 ? "exclamationmark.octagon.fill"
          : warnings > 0 ? "exclamationmark.triangle.fill"
          : "checkmark.circle.fill",
        color: color,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .commanderFont(.eventTitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(detail)
          .commanderFont(.subtitle)
          .foregroundStyle(color)
      }
      Spacer(minLength: 0)
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .commanderCard(accent: color, surface: .depthCard)
  }

  private func summaryCard(_ report: CommanderScheduleAuditReport) -> some View {
    CommanderSectionCard(
      title: "Souhrn",
      symbol: "checklist",
      accent: CommanderDesignTokens.Colors.locationBlue
    ) {
      VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
        auditMetric("Pobyt", value: report.stayDayCount.map { "\($0) dní" } ?? "—")
        auditMetric("Události", value: "\(report.eventCount)")
        auditMetric("Procedury", value: "\(report.procedureCount)")
        auditMetric("Jídla", value: "\(report.mealCount)")
        auditMetric("Verze rozpisu", value: "v\(report.scheduleVersion)")
      }
    }
  }

  @ViewBuilder
  private func issuesCard(_ report: CommanderScheduleAuditReport) -> some View {
    if report.issues.isEmpty {
      CommanderSectionCard(
        title: "Kontroly",
        symbol: "checkmark.seal.fill",
        accent: CommanderDesignTokens.Colors.mealGreen
      ) {
        Text("Žádná strukturální anomálie. Přesná shoda se zdrojovým papírem bude samostatný acceptance krok.")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
    } else {
      CommanderSectionCard(
        title: "Vyžaduje pozornost",
        symbol: "exclamationmark.triangle.fill",
        accent: report.hasErrors ? CommanderDesignTokens.Colors.criticalRed : CommanderDesignTokens.Colors.urgentOrange
      ) {
        VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
          ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
            auditIssueRow(issue)
          }
        }
      }
    }
  }

  private func auditMetric(_ title: String, value: String) -> some View {
    HStack {
      Text(title)
        .commanderFont(.label)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      Spacer()
      Text(value)
        .commanderFont(.metric)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
  }

  private func auditIssueRow(_ issue: CommanderScheduleAuditIssue) -> some View {
    let color = issue.severity == .error
      ? CommanderDesignTokens.Colors.criticalRed
      : CommanderDesignTokens.Colors.urgentOrange
    return HStack(alignment: .top, spacing: 9) {
      Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 3) {
        if let date = issue.date {
          Text(CommanderDateText.numericDate(isoDate: date) ?? date)
            .commanderFont(.label)
            .foregroundStyle(color)
        }
        Text(issue.message)
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        if issue.severity == .warning {
          Text("Čeká na vaše potvrzení")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .commanderCard(accent: color, surface: .depthInset)
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
    .commanderCard(accent: CommanderDesignTokens.Colors.criticalRed, surface: .depthCard)
  }
}

private struct CommanderScheduleSettingsCard: View {
  @ObservedObject var model: CommanderViewModel
  @Environment(\.commanderOpenScheduleAudit) private var openScheduleAudit

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
        openScheduleAudit()
      } label: {
        CommanderNavigationRow(
          title: "Kontrola rozpisu",
          subtitle: "Anomálie, změny a potvrzení",
          symbol: "checkmark.shield.fill",
          accent: CommanderDesignTokens.Colors.locationBlue
        )
      }
      .buttonStyle(.plain)

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
          .frame(maxWidth: .infinity, minHeight: 48)
          .commanderCard(accent: CommanderDesignTokens.Colors.urgentOrange, surface: .depthInset)
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
    .commanderCard(accent: accent, surface: .depthInset)
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
    .background(CommanderDepthBackground().ignoresSafeArea())
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
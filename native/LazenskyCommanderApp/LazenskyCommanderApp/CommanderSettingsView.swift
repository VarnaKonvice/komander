import LazenskyCommanderCore
import SwiftUI

enum CommanderScheduleAuditVisualStatus: Equatable {
  case unavailable
  case ok
  case warning(Int)
  case error(Int)

  var attentionColor: Color? {
    switch self {
    case .unavailable, .ok: nil
    case .warning: CommanderDesignTokens.Colors.urgentOrange
    case .error: CommanderDesignTokens.Colors.criticalRed
    }
  }

  var sectionAccent: Color {
    switch self {
    case .unavailable: CommanderDesignTokens.Colors.locationBlue
    case .ok: CommanderDesignTokens.Colors.mealGreen
    case .warning: CommanderDesignTokens.Colors.urgentOrange
    case .error: CommanderDesignTokens.Colors.criticalRed
    }
  }

  var shouldOpenAuditFromSettingsTab: Bool {
    switch self {
    case .warning: true
    case .unavailable, .ok, .error: false
    }
  }

  var symbol: String {
    switch self {
    case .unavailable: "checkmark.shield.fill"
    case .ok: "checkmark.circle.fill"
    case .warning: "exclamationmark.triangle.fill"
    case .error: "exclamationmark.octagon.fill"
    }
  }

  var subtitle: String {
    switch self {
    case .unavailable:
      "Rozpis ještě není načten"
    case .ok:
      "Rozpis je v pořádku"
    case .warning(let count):
      switch count {
      case 1: "1 položka čeká na kontrolu"
      case 2...4: "\(count) položky čekají na kontrolu"
      default: "\(count) položek čeká na kontrolu"
      }
    case .error(let count):
      switch count {
      case 1: "1 chyba vyžaduje zásah"
      case 2...4: "\(count) chyby vyžadují zásah"
      default: "\(count) chyb vyžaduje zásah"
      }
    }
  }
}

@MainActor
func commanderScheduleAuditVisualStatus(for model: CommanderViewModel) -> CommanderScheduleAuditVisualStatus {
  guard let schedule = model.latestSchedule else { return .unavailable }
  let report = CommanderScheduleAudit.run(schedule, policy: .petrSpaOperational)
  let review = CommanderScheduleAuditReview.resolve(
    report: report,
    acknowledgements: model.scheduleAuditAcknowledgements
  )
  if !review.errors.isEmpty { return .error(review.errors.count) }
  if !review.openWarnings.isEmpty { return .warning(review.openWarnings.count) }
  return .ok
}

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
  @ObservedObject var model: CommanderViewModel
  let onClose: () -> Void

  private var report: CommanderScheduleAuditReport? {
    model.latestSchedule.map { CommanderScheduleAudit.run($0, policy: .petrSpaOperational) }
  }

  private var review: CommanderScheduleAuditReviewState? {
    guard let report else { return nil }
    return CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: model.scheduleAuditAcknowledgements
    )
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        CommanderGlassHeader(tab: "", showsTabPill: false)
        CommanderScreenHeading(
          title: "Kontrola rozpisu",
          subtitle: "Bezpečnostní kontrola aktuální verze"
        )

        if let report, let review {
          statusCard(report, review: review)
          issuesCard(report, review: review)
          summaryCard(report)
          alarmVerificationCard
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

  private func statusCard(
    _ report: CommanderScheduleAuditReport,
    review: CommanderScheduleAuditReviewState
  ) -> some View {
    let errors = review.errors.count
    let warnings = review.openWarnings.count
    let confirmed = review.acknowledgedWarnings.count
    let color = errors > 0 ? CommanderDesignTokens.Colors.criticalRed
      : warnings > 0 ? CommanderDesignTokens.Colors.urgentOrange
      : CommanderDesignTokens.Colors.mealGreen
    let title = errors > 0 ? "Rozpis obsahuje chybu"
      : warnings > 0 ? "Rozpis vyžaduje kontrolu"
      : "Strukturální kontrola dokončena"
    let detail = errors > 0 ? "\(errors) chyb · \(warnings) kontrol"
      : warnings > 0 ? "\(warnings) položek k potvrzení"
      : confirmed > 0 ? "\(confirmed) potvrzených výjimek"
      : "Bez strukturálních upozornění"

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

  private var alarmVerificationCard: some View {
    let scheduleVersion = model.latestSchedule?.scheduleVersion
    let summaryMatchesSchedule = model.summary?.scheduleVersion == scheduleVersion
    let coverage = summaryMatchesSchedule ? model.summary?.readbackCoverage : nil

    let color: Color
    let symbol: String
    let title: String
    let detail: String

    if let coverage, coverage.isComplete {
      color = CommanderDesignTokens.Colors.mealGreen
      symbol = "alarm.fill"
      if coverage.desiredAlarmCount == 0 {
        title = "Alarmy zkontrolovány"
        detail = "Aktuální rozpis už nemá žádný budoucí alarm."
      } else if let verifiedThrough = coverage.verifiedThrough {
        title = "Alarmy ověřeny do \(verifiedThrough.formatted(CommanderScheduleDateStyle.departure))"
        detail = "Systémový read-back potvrdil \(coverage.evidencedAlarmCount) / \(coverage.desiredAlarmCount) budoucích alarmů."
      } else {
        title = "Alarmy ověřeny"
        detail = "Systémový read-back potvrdil všechny budoucí alarmy."
      }
    } else if let coverage {
      color = CommanderDesignTokens.Colors.urgentOrange
      symbol = "alarm.waves.left.and.right"
      title = "Alarmy nejsou plně ověřené"
      detail = "Fyzický read-back doložil \(coverage.evidencedAlarmCount) / \(coverage.desiredAlarmCount) požadovaných budoucích alarmů."
    } else {
      color = CommanderDesignTokens.Colors.textSecondary
      symbol = "alarm"
      title = "Alarmy zatím nejsou fyzicky ověřené"
      detail = model.summary?.errorMessage ?? "Je potřeba úspěšná kontrola stejné verze rozpisu a skutečný systémový read-back."
    }

    return CommanderSectionCard(
      title: "AlarmKit",
      symbol: symbol,
      accent: color
    ) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .commanderFont(.metric)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .commanderFont(.subtitle)
          .foregroundStyle(color)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .commanderCard(accent: color, surface: .depthInset)
    }
  }

  @ViewBuilder
  private func issuesCard(
    _ report: CommanderScheduleAuditReport,
    review: CommanderScheduleAuditReviewState
  ) -> some View {
    if review.errors.isEmpty && review.openWarnings.isEmpty && review.acknowledgedWarnings.isEmpty {
      CommanderSectionCard(
        title: "Kontroly",
        symbol: "checkmark.seal.fill",
        accent: CommanderDesignTokens.Colors.mealGreen
      ) {
        Text("Žádná strukturální anomálie. Přesná shoda se zdrojovým papírem je samostatný acceptance krok.")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
    }

    if !review.errors.isEmpty || !review.openWarnings.isEmpty {
      CommanderSectionCard(
        title: "Vyžaduje pozornost",
        symbol: "exclamationmark.triangle.fill",
        accent: review.errors.isEmpty ? CommanderDesignTokens.Colors.urgentOrange : CommanderDesignTokens.Colors.criticalRed
      ) {
        VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
          ForEach(Array((review.errors + review.openWarnings).enumerated()), id: \.offset) { _, issue in
            auditIssueRow(issue, acknowledged: false)
          }
        }
      }
    }

    if !review.acknowledgedWarnings.isEmpty {
      CommanderSectionCard(
        title: "Potvrzené výjimky",
        symbol: "checkmark.circle.fill",
        accent: CommanderDesignTokens.Colors.mealGreen
      ) {
        VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
          ForEach(Array(review.acknowledgedWarnings.enumerated()), id: \.offset) { _, issue in
            auditIssueRow(issue, acknowledged: true)
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

  private func auditIssueRow(
    _ issue: CommanderScheduleAuditIssue,
    acknowledged: Bool
  ) -> some View {
    let color = issue.severity == .error
      ? CommanderDesignTokens.Colors.criticalRed
      : acknowledged ? CommanderDesignTokens.Colors.mealGreen : CommanderDesignTokens.Colors.urgentOrange

    return VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .top, spacing: 9) {
        Image(systemName: issue.severity == .error
          ? "xmark.octagon.fill"
          : acknowledged ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
          if acknowledged {
            Text("Potvrzeno jako očekávaná výjimka")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.mealGreen)
          } else if issue.severity == .warning {
            Text("Čeká na vaše potvrzení")
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          }
        }
        Spacer(minLength: 0)
      }

      if issue.severity == .warning {
        Button {
          if acknowledged {
            model.revokeScheduleAuditAcknowledgement(for: issue)
          } else {
            model.acknowledgeScheduleAuditIssue(issue)
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: acknowledged ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
            Text(acknowledged ? "Zrušit potvrzení" : "Potvrdit jako správné")
          }
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .frame(maxWidth: .infinity, minHeight: 38)
          .background(color.opacity(0.16))
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(color.opacity(0.42), lineWidth: 0.8)
          }
        }
        .buttonStyle(.plain)
      }
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

  private var auditStatus: CommanderScheduleAuditVisualStatus {
    commanderScheduleAuditVisualStatus(for: model)
  }

  private var needsAlarmPermission: Bool {
    model.accessStatus.contains("not been requested") || model.accessStatus.contains("denied")
  }

  var body: some View {
    CommanderSectionCard(
      title: "Rozpis",
      symbol: "calendar",
      accent: auditStatus.sectionAccent
    ) {
      Button {
        openScheduleAudit()
      } label: {
        CommanderNavigationRow(
          title: "Kontrola rozpisu",
          subtitle: auditStatus.subtitle,
          symbol: auditStatus.symbol,
          accent: auditStatus.sectionAccent
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

  private enum LeadTimeCategory: Int, CaseIterable, Identifiable {
    case rehabilitation
    case electro
    case water
    case massage
    case heat
    case meal
    case other

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .rehabilitation: "Rehabilitace a pohyb"
      case .electro: "Elektroléčba"
      case .water: "Vodoléčba"
      case .massage: "Masáže"
      case .heat: "Teplo a zábaly"
      case .meal: "Jídlo"
      case .other: "Ostatní"
      }
    }

    var representativeTitle: String {
      switch self {
      case .rehabilitation: "Individuální rehabilitace"
      case .electro: "Magnetoterapie"
      case .water: "Bazén"
      case .massage: "Masáž"
      case .heat: "Rašelinový zábal"
      case .meal: "Snídaně"
      case .other: "Procedura"
      }
    }

    var kind: ScheduleKind {
      self == .meal ? .meal : .procedure
    }

    var coreCategory: CommanderProcedureCategory? {
      switch self {
      case .rehabilitation: .rehabilitation
      case .electro: .electro
      case .water: .water
      case .massage: .massage
      case .heat: .heatWrap
      case .other: .other
      case .meal: nil
      }
    }

    var accent: Color {
      Color(commanderPresentationHex: accentHex)
    }

    private var accentHex: String {
      switch self {
      case .rehabilitation: CommanderBrandAssets.Colors.rehabilitationBlue
      case .electro: CommanderBrandAssets.Colors.electroIndigo
      case .water: CommanderBrandAssets.Colors.waterAqua
      case .massage: CommanderBrandAssets.Colors.massageCoral
      case .heat: CommanderBrandAssets.Colors.heatOchre
      case .meal: CommanderBrandAssets.Colors.mealGreen
      case .other: CommanderBrandAssets.Colors.therapyPink
      }
    }
  }

  private var procedureCategories: [LeadTimeCategory] {
    let present = Set((model.latestSchedule?.events ?? []).compactMap { event -> LeadTimeCategory? in
      guard event.kind == .procedure else { return nil }
      return category(for: event)
    })
    return LeadTimeCategory.allCases.filter { $0 != .meal && present.contains($0) }
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
      let lhsRank = eventCategoryRank($0)
      let rhsRank = eventCategoryRank($1)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      if $0.date != $1.date { return $0.date < $1.date }
      if $0.start != $1.start { return $0.start < $1.start }
      return $0.stableId < $1.stableId
    }
  }

  private func eventCategoryRank(_ event: ScheduleEvent) -> Int {
    if event.kind == .meal { return 5 }
    switch CommanderProcedureCategory.classify(event.procedureType ?? event.title) {
    case .rehabilitation: return 0
    case .electro: return 1
    case .water: return 2
    case .massage: return 3
    case .heatWrap: return 4
    case .other: return 6
    }
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        sectionTitle("Výchozí čas")
        defaultLeadTimeCard

        if !procedureCategories.isEmpty {
          sectionTitle("Podle kategorie")
          ForEach(procedureCategories) { category in
            if let coreCategory = category.coreCategory {
              leadTimeCard(
                title: category.title,
                value: categoryLeadTime(category),
                category: category,
                subtitle: "Výchozí pro tuto kategorii",
                isOverridden: model.leadTimeOverrides.procedureCategoryOverrides[coreCategory.rawValue] != nil,
                set: { model.setProcedureCategoryLeadTimeMinutes($0, category: coreCategory) },
                resetTitle: "Použít výchozí čas",
                reset: { model.resetProcedureCategoryLeadTime(category: coreCategory) }
              )
            }
          }
        }

        if !mealTypes.isEmpty {
          sectionTitle("Podle jídla")
          ForEach(mealTypes, id: \.self) { type in
            leadTimeCard(
              title: type,
              value: mealLeadTime(type),
              category: .meal,
              subtitle: "Odchod před jídlem",
              isOverridden: model.leadTimeOverrides.mealOverrides[type] != nil,
              set: { model.setMealLeadTimeMinutes($0, mealType: type) },
              resetTitle: "Použít obecné nastavení",
              reset: { model.resetMealLeadTime(mealType: type) }
            )
          }
        }

        if !events.isEmpty {
          sectionTitle("Jednotlivé události")

          VStack(spacing: 8) {
            ForEach(events, id: \.stableId) { event in
              eventLeadTimeCard(event, category: category(for: event))
            }
          }
        }

        if model.leadTimeOverrides != LeadTimeOverrides() {
          Button(role: .destructive) {
            model.resetAllLeadTimeOverrides()
          } label: {
            Label("Vrátit všechny časy k rozpisu", systemImage: "arrow.uturn.backward.circle.fill")
              .font(.system(size: 16, weight: .bold))
              .frame(maxWidth: .infinity)
              .padding(.vertical, 13)
          }
          .buttonStyle(.plain)
          .foregroundStyle(CommanderDesignTokens.Colors.criticalRed)
          .commanderCard(
            accent: CommanderDesignTokens.Colors.criticalRed,
            surface: .depthInset
          )
          .padding(.top, 2)
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, 12)
      .padding(.bottom, CommanderDesignTokens.Spacing.tabBarClearance)
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .navigationTitle("Čas na odchod")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var defaultLeadTimeCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .fill(CommanderDesignTokens.Colors.primaryPurple.opacity(0.18))
          Image(systemName: "figure.walk.departure")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(CommanderDesignTokens.Colors.primaryPurple)
        }
        .frame(width: 38, height: 38)

        VStack(alignment: .leading, spacing: 2) {
          Text("Základní předstih")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          Text("Platí, pokud kategorie, jídlo nebo událost nemá vlastní čas")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        }

        Spacer(minLength: 8)
      }

      leadTimeControl(
        value: model.defaultLeadTimeMinutes,
        accent: CommanderDesignTokens.Colors.primaryPurple,
        set: { model.setDefaultLeadTimeMinutes($0) }
      )

      if model.leadTimeOverrides.defaultLeadTimeMinutes != nil,
         let source = model.latestSchedule?.settings.defaultLeadTimeMinutes {
        Button("Použít hodnotu z rozpisu (\(source) min)") {
          model.resetDefaultLeadTime()
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
      }

      Text("Předstih určuje skutečný čas odchodu. 30 minut je jen maximální délka systémového odpočtu před alarmem.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .commanderCard(
      accent: CommanderDesignTokens.Colors.primaryPurple,
      surface: .depthInset
    )
  }

  @ViewBuilder
  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 19, weight: .bold))
      .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 2)
  }


  @ViewBuilder
  private func leadTimeCard(
    title: String,
    value: Int,
    category: LeadTimeCategory,
    subtitle: String,
    isOverridden: Bool,
    set: @escaping (Int) -> Void,
    resetTitle: String,
    reset: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(spacing: 10) {
        CommanderProcedureArtwork(
          iconKey: nil,
          title: title,
          size: 38,
          kind: category.kind
        )

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(category.accent)
            .lineLimit(2)
          Text(subtitle)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        }

        Spacer(minLength: 6)
      }

      leadTimeControl(value: value, accent: category.accent, set: set)

      if isOverridden {
        Button(resetTitle) { reset() }
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(category.accent)
      }
    }
    .padding(11)
    .commanderCard(accent: category.accent, surface: .depthInset)
  }

  @ViewBuilder
  private func eventLeadTimeCard(
    _ event: ScheduleEvent,
    category: LeadTimeCategory
  ) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .center, spacing: 9) {
        CommanderProcedureArtwork(
          iconKey: nil,
          title: event.procedureType ?? event.mealType ?? event.title,
          size: 34,
          kind: event.kind
        )

        VStack(alignment: .leading, spacing: 2) {
          Text(event.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(category.accent)
            .lineLimit(2)

          Text(eventTimeLabel(event))
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        }

        Spacer(minLength: 6)
      }

      leadTimeControl(
        value: model.effectiveLeadTimeMinutes(for: event),
        accent: category.accent,
        set: { model.setEventLeadTimeMinutes($0, stableId: event.stableId) }
      )

      if model.leadTimeOverrides.eventOverrides[event.stableId] != nil {
        Button("Zrušit výjimku") {
          model.resetEventLeadTime(stableId: event.stableId)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(category.accent)
      }
    }
    .padding(10)
    .commanderCard(accent: category.accent, surface: .eventRow)
  }

  @ViewBuilder
  private func leadTimeControl(
    value: Int,
    accent: Color,
    set: @escaping (Int) -> Void
  ) -> some View {
    HStack(spacing: 10) {
      Button {
        set(max(0, value - 1))
      } label: {
        Image(systemName: "minus")
          .font(.system(size: 15, weight: .heavy))
          .frame(width: 34, height: 34)
          .background(accent.opacity(0.20), in: Circle())
          .overlay(Circle().strokeBorder(accent.opacity(0.75), lineWidth: 1))
      }
      .buttonStyle(.plain)
      .foregroundStyle(accent)
      .disabled(value <= 0)
      .opacity(value <= 0 ? 0.42 : 1)
      .accessibilityLabel("Snížit předstih")

      Text("\(value) min")
        .font(.system(size: 18, weight: .bold).monospacedDigit())
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .frame(minWidth: 76)
        .padding(.vertical, 7)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(accent.opacity(0.10))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(accent.opacity(0.34), lineWidth: 0.8)
        )

      Button {
        set(min(180, value + 1))
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 15, weight: .heavy))
          .frame(width: 34, height: 34)
          .background(accent.opacity(0.20), in: Circle())
          .overlay(Circle().strokeBorder(accent.opacity(0.75), lineWidth: 1))
      }
      .buttonStyle(.plain)
      .foregroundStyle(accent)
      .disabled(value >= 180)
      .opacity(value >= 180 ? 0.42 : 1)
      .accessibilityLabel("Zvýšit předstih")

      Spacer(minLength: 0)

      Text("předem")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    }
  }

  private func category(for event: ScheduleEvent) -> LeadTimeCategory {
    if event.kind == .meal { return .meal }
    return category(forCoreCategory: CommanderProcedureCategory.classify(
      event.procedureType ?? event.title
    ))
  }

  private func category(forCoreCategory category: CommanderProcedureCategory) -> LeadTimeCategory {
    switch category {
    case .rehabilitation: return .rehabilitation
    case .electro: return .electro
    case .water: return .water
    case .massage: return .massage
    case .heatWrap: return .heat
    case .other: return .other
    }
  }

  private func eventTimeLabel(_ event: ScheduleEvent) -> String {
    guard let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start) else {
      return "\(event.date) · \(event.start)"
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

    let day: String
    if calendar.isDateInToday(start) {
      day = "Dnes"
    } else if calendar.isDateInTomorrow(start) {
      day = "Zítra"
    } else {
      day = start.formatted(
        .dateTime
          .day()
          .month(.defaultDigits)
          .locale(Locale(identifier: "cs_CZ"))
      )
    }

    return "\(day) · \(event.start)"
  }

  private func categoryLeadTime(_ category: LeadTimeCategory) -> Int {
    guard let coreCategory = category.coreCategory else { return model.defaultLeadTimeMinutes }

    if let override = model.leadTimeOverrides.procedureCategoryOverrides[coreCategory.rawValue] {
      return override
    }

    guard let schedule = model.latestSchedule else { return model.defaultLeadTimeMinutes }
    let values = Set(schedule.events.compactMap { event -> Int? in
      guard event.kind == .procedure,
            CommanderProcedureCategory.classify(event.procedureType ?? event.title) == coreCategory
      else { return nil }

      let type = event.procedureType ?? event.title
      return try? NativeAlarmContract.typeLeadTime(
        kind: .procedure,
        type: type,
        schedule: schedule,
        overrides: model.leadTimeOverrides
      )
    })

    return values.count == 1 ? (values.first ?? model.defaultLeadTimeMinutes) : model.defaultLeadTimeMinutes
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

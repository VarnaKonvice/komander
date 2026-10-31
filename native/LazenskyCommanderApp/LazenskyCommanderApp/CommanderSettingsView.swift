import LazenskyCommanderCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
  let report = CommanderScheduleAudit.run(schedule, policy: model.scheduleAuditPolicy)
  let review = CommanderScheduleAuditReview.resolve(
    report: report,
    acknowledgements: model.scheduleAuditAcknowledgements,
    operationalWarningsOnOrAfter: CommanderDateText.isoDate(Date())
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

      CommanderScheduleImportSettingsCard()

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
    model.latestSchedule.map { CommanderScheduleAudit.run($0, policy: model.scheduleAuditPolicy) }
  }

  private var review: CommanderScheduleAuditReviewState? {
    guard let report else { return nil }
    return CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: model.scheduleAuditAcknowledgements,
      operationalWarningsOnOrAfter: CommanderDateText.isoDate(Date())
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
        auditMetric("Vizity", value: "\(report.visitCount)")
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
            Text(CommanderDateText.numericDateWithWeekday(isoDate: date) ?? date)
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
  @State private var showIndividualEvents = false

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

        Button {
          model.applySpaLeadTimePreset()
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
              .font(.system(size: 20, weight: .bold))
              .foregroundStyle(CommanderDesignTokens.Colors.mealGreen)
            VStack(alignment: .leading, spacing: 2) {
              Text("Nastavit lázeňský předstih")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
              Text("20 min všude · Vizita 5 min")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            }
            Spacer(minLength: 8)
          }
          .padding(11)
          .frame(maxWidth: .infinity, alignment: .leading)
          .commanderCard(accent: CommanderDesignTokens.Colors.mealGreen, surface: .depthInset)
        }
        .buttonStyle(.plain)

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

        if model.latestSchedule?.events.isEmpty == false {
          sectionTitle("Jednotlivé události")

          Button {
            withAnimation(.easeOut(duration: 0.18)) {
              showIndividualEvents.toggle()
            }
          } label: {
            HStack(spacing: 10) {
              Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
              VStack(alignment: .leading, spacing: 2) {
                Text("Výjimky pro konkrétní události")
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
                Text(showIndividualEvents
                     ? "Skrýt dlouhý seznam"
                     : "Zobrazit jen když potřebuješ změnit jednu konkrétní událost")
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: 6)
              Image(systemName: showIndividualEvents ? "chevron.up" : "chevron.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
          }
          .buttonStyle(.plain)

          if showIndividualEvents {
            LazyVStack(spacing: 8) {
              ForEach(events, id: \.stableId) { event in
                eventLeadTimeCard(event, category: category(for: event))
              }
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


private struct CommanderScheduleImportSettingsCard: View {
  var body: some View {
    CommanderSectionCard(
      title: "Vlastní rozpis",
      symbol: "doc.viewfinder.fill",
      accent: CommanderDesignTokens.Colors.locationBlue
    ) {
      NavigationLink {
        CommanderScheduleImportView()
      } label: {
        CommanderNavigationRow(
          title: "Přidat rozpis",
          subtitle: "Fotografie nebo naskenovaný dokument",
          symbol: "photo.on.rectangle.angled",
          accent: CommanderDesignTokens.Colors.locationBlue,
          value: "JPG · PDF"
        )
      }
      .buttonStyle(.plain)
    }
  }
}

@MainActor
private final class CommanderScheduleImportDraft: ObservableObject {
  struct Attachment: Identifiable, Equatable {
    let storedName: String
    let displayName: String
    let byteCount: Int

    var id: String { storedName }

    var formattedSize: String {
      ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var symbol: String {
      storedName.lowercased().hasSuffix(".pdf") ? "doc.fill" : "photo.fill"
    }
  }

  enum DraftError: LocalizedError {
    case unsupportedFile
    case unreadableImage
    case fileTooLarge
    case tooManyFiles

    var errorDescription: String? {
      switch self {
      case .unsupportedFile:
        "Soubor není v podporovaném formátu."
      case .unreadableImage:
        "Fotografii se nepodařilo načíst."
      case .fileTooLarge:
        "Jeden soubor může mít nejvýše 25 MB."
      case .tooManyFiles:
        "Do jednoho rozpisu lze přidat nejvýše 20 souborů."
      }
    }
  }

  @Published private(set) var attachments: [Attachment] = []

  private let fileManager = FileManager.default
  private let maximumFileBytes = 25 * 1024 * 1024
  private let maximumAttachmentCount = 20

  init() {
    reload()
  }

  var totalSizeText: String {
    let total = attachments.reduce(0) { $0 + $1.byteCount }
    return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
  }

  func addPhotoData(_ sourceData: Data) throws {
    guard attachments.count < maximumAttachmentCount else { throw DraftError.tooManyFiles }
    guard let image = UIImage(data: sourceData),
          let jpeg = image.jpegData(compressionQuality: 0.92)
    else {
      throw DraftError.unreadableImage
    }
    guard jpeg.count <= maximumFileBytes else { throw DraftError.fileTooLarge }

    try ensureDirectory()
    let sequence = attachments.count + 1
    let displayName = String(format: "Fotografie %02d.jpg", sequence)
    let storedName = "\(UUID().uuidString).jpg"
    try jpeg.write(to: directoryURL.appendingPathComponent(storedName), options: .atomic)
    reload(displayNames: [storedName: displayName])
  }

  func addFile(_ sourceURL: URL) throws {
    guard attachments.count < maximumAttachmentCount else { throw DraftError.tooManyFiles }

    let scoped = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if scoped { sourceURL.stopAccessingSecurityScopedResource() }
    }

    let ext = sourceURL.pathExtension.lowercased()
    let supported = ["jpg", "jpeg", "png", "heic", "heif", "pdf"]
    guard supported.contains(ext) else { throw DraftError.unsupportedFile }

    let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
    let size = values.fileSize ?? 0
    guard size <= maximumFileBytes else { throw DraftError.fileTooLarge }

    try ensureDirectory()
    let storedName = "\(UUID().uuidString).\(ext)"
    let destination = directoryURL.appendingPathComponent(storedName)
    let data = try Data(contentsOf: sourceURL)
    guard data.count <= maximumFileBytes else { throw DraftError.fileTooLarge }
    try data.write(to: destination, options: .atomic)
    reload(displayNames: [storedName: sourceURL.lastPathComponent])
  }

  func remove(_ attachment: Attachment) {
    try? fileManager.removeItem(at: directoryURL.appendingPathComponent(attachment.storedName))
    reload()
  }

  func clear() {
    try? fileManager.removeItem(at: directoryURL)
    attachments = []
  }

  private var directoryURL: URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base
      .appendingPathComponent("LazenskyCommander", isDirectory: true)
      .appendingPathComponent("ScheduleImportDraft", isDirectory: true)
  }

  private var namesURL: URL {
    directoryURL.appendingPathComponent("display-names.json")
  }

  private func ensureDirectory() throws {
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  private func reload(displayNames additions: [String: String] = [:]) {
    var names = (try? Data(contentsOf: namesURL))
      .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    additions.forEach { names[$0.key] = $0.value }

    let urls = (try? fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.fileSizeKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    let files = urls
      .filter { $0.lastPathComponent != namesURL.lastPathComponent }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    attachments = files.compactMap { url in
      let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
      return Attachment(
        storedName: url.lastPathComponent,
        displayName: names[url.lastPathComponent] ?? url.lastPathComponent,
        byteCount: size
      )
    }

    let activeNames = Dictionary(uniqueKeysWithValues: attachments.map {
      ($0.storedName, names[$0.storedName] ?? $0.displayName)
    })
    if !attachments.isEmpty {
      try? ensureDirectory()
      if let encoded = try? JSONEncoder().encode(activeNames) {
        try? encoded.write(to: namesURL, options: .atomic)
      }
    }
  }
}

private struct CommanderScheduleImportView: View {
  @StateObject private var draft = CommanderScheduleImportDraft()
  @State private var selectedPhotos: [PhotosPickerItem] = []
  @State private var showsFileImporter = false
  @State private var errorMessage: String?

  private let accent = CommanderDesignTokens.Colors.locationBlue

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        CommanderGlassHeader(tab: "", showsTabPill: false)
        CommanderScreenHeading(
          title: "Přidat vlastní rozpis",
          subtitle: "Vyfoťte rozpis nebo přidejte naskenovaný dokument."
        )

        instructionsCard
        pickerCard

        if !draft.attachments.isEmpty {
          attachmentsCard
          preparedCard
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, CommanderDesignTokens.Spacing.scrollTop)
      .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
    }
    .scrollIndicators(.hidden)
    .background(CommanderDepthBackground().ignoresSafeArea())
    .navigationTitle("Vlastní rozpis")
    .navigationBarTitleDisplayMode(.inline)
    .fileImporter(
      isPresented: $showsFileImporter,
      allowedContentTypes: [.jpeg, .png, .heic, .pdf],
      allowsMultipleSelection: true,
      onCompletion: importFiles
    )
    .onChange(of: selectedPhotos) { _, items in
      guard !items.isEmpty else { return }
      Task { await importPhotos(items) }
    }
    .alert(
      "Soubor se nepodařilo přidat",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private var instructionsCard: some View {
    CommanderSectionCard(
      title: "Co můžete přidat",
      symbol: "doc.badge.plus",
      accent: accent
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Fotografie papírového rozpisu nebo soubor vytvořený skenerem.")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 7) {
          HStack(spacing: 8) {
            formatBadge("JPG")
            formatBadge("JPEG")
            formatBadge("PNG")
          }
          HStack(spacing: 8) {
            formatBadge("HEIC")
            formatBadge("PDF")
          }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Podporované formáty JPG, JPEG, PNG, HEIC a PDF")

        Text("Přidejte všechny stránky jednoho pobytu. Fotografie z iPhonu Commander uloží jako JPG.")
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var pickerCard: some View {
    CommanderSectionCard(
      title: "Vybrat podklady",
      symbol: "square.and.arrow.down.fill",
      accent: CommanderDesignTokens.Colors.mealGreen
    ) {
      PhotosPicker(
        selection: $selectedPhotos,
        maxSelectionCount: 20,
        matching: .images
      ) {
        CommanderSettingsActionRow(
          title: "Vybrat fotografie",
          subtitle: "Z aplikace Fotky",
          symbol: "photo.stack.fill",
          accent: CommanderDesignTokens.Colors.mealGreen,
          isWorking: false
        )
      }
      .buttonStyle(.plain)

      Button {
        showsFileImporter = true
      } label: {
        CommanderSettingsActionRow(
          title: "Vybrat soubor",
          subtitle: "PDF nebo obrázek ze Souborů",
          symbol: "doc.fill.badge.plus",
          accent: accent,
          isWorking: false
        )
      }
      .buttonStyle(.plain)
    }
  }

  private var attachmentsCard: some View {
    CommanderSectionCard(
      title: "Připravené soubory",
      symbol: "tray.full.fill",
      accent: accent
    ) {
      ForEach(draft.attachments) { attachment in
        HStack(spacing: CommanderDesignTokens.Spacing.small) {
          CommanderSymbolBadge(
            symbol: attachment.symbol,
            color: accent,
            size: CommanderDesignTokens.Size.rowMetricBadge
          )
          VStack(alignment: .leading, spacing: 2) {
            Text(attachment.displayName)
              .commanderFont(.metric)
              .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
              .lineLimit(2)
            Text(attachment.formattedSize)
              .commanderFont(.label)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          }
          Spacer(minLength: 8)
          Button(role: .destructive) {
            draft.remove(attachment)
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.criticalRed)
              .frame(width: 42, height: 42)
          }
          .accessibilityLabel("Odebrat \(attachment.displayName)")
        }
        .padding(CommanderDesignTokens.Spacing.small)
        .commanderCard(accent: accent, surface: .depthInset)
      }

      Button(role: .destructive) {
        draft.clear()
      } label: {
        Text("Odebrat všechny soubory")
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.criticalRed)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.plain)
    }
  }

  private var preparedCard: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: "checkmark.circle.fill",
        color: CommanderDesignTokens.Colors.mealGreen,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(preparedTitle)
          .commanderFont(.eventTitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text("\(draft.totalSizeText) · připraveno k budoucímu odeslání")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .commanderCard(accent: CommanderDesignTokens.Colors.mealGreen, surface: .depthCard)
  }

  private var preparedTitle: String {
    switch draft.attachments.count {
    case 1: "1 soubor připraven"
    case 2...4: "\(draft.attachments.count) soubory připraveny"
    default: "\(draft.attachments.count) souborů připraveno"
    }
  }

  private func formatBadge(_ label: String) -> some View {
    Text(label)
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(accent.opacity(0.18))
      .clipShape(Capsule())
  }

  private func importFiles(_ result: Result<[URL], Error>) {
    do {
      for url in try result.get() {
        try draft.addFile(url)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func importPhotos(_ items: [PhotosPickerItem]) async {
    defer { selectedPhotos = [] }

    for item in items {
      do {
        guard let data = try await item.loadTransferable(type: Data.self) else {
          throw CommanderScheduleImportDraft.DraftError.unreadableImage
        }
        try draft.addPhotoData(data)
      } catch {
        errorMessage = error.localizedDescription
        break
      }
    }
  }
}

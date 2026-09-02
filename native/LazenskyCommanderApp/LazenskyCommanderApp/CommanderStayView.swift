import LazenskyCommanderCore
import SwiftUI

struct CommanderStayView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      CommanderTabScaffold(
        tab: "Pobyt",
        title: "Pobyt",
        subtitle: "Souhrn celého pobytu"
      ) {
        if let schedule = model.latestSchedule {
          if let stay = try? CommanderStayPresentation.make(schedule: schedule, now: context.date) {
            CommanderStayOverviewCard(stay: stay)
            CommanderProcedureOverviewCard(stay: stay)
          } else {
            CommanderStayUnavailableCard(message: "Souhrn pobytu nelze zobrazit")
          }
        } else {
          CommanderStayUnavailableCard(message: "Rozpis ještě není načten")
        }
      }
    }
  }
}

private struct CommanderStayOverviewCard: View {
  let stay: CommanderStayPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
      HStack(spacing: CommanderDesignTokens.Spacing.small) {
        CommanderSymbolBadge(
          symbol: "bed.double.fill",
          color: CommanderDesignTokens.Colors.primaryPurple,
          size: CommanderDesignTokens.Size.sectionBadge
        )
        VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
          Text(primaryTitle)
            .commanderFont(.liveTitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          Text(statusText)
            .commanderFont(.subtitle)
            .foregroundStyle(statusColor)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      if let period = stay.period {
        HStack(spacing: CommanderDesignTokens.Spacing.small) {
          dateMetric(title: "Pobyt od", date: period.dateFrom, symbol: "calendar.badge.plus")
          dateMetric(title: "Pobyt do", date: period.dateTo, symbol: "calendar.badge.checkmark")
        }
        CommanderProgressMeter(
          title: progressTitle(for: period),
          value: progressValue(for: period),
          fraction: progressFraction(for: period),
          accent: CommanderDesignTokens.Colors.procedureCyan
        )
      } else {
        Text("Termín pobytu není k dispozici")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard()
  }

  private var primaryTitle: String {
    guard let period = stay.period else { return "Termín není v rozpisu" }
    if let currentDay = period.currentDay {
      return "\(dayCount(currentDay)) z \(period.totalDays) dnů"
    }
    return "\(dayCount(period.totalDays)) pobytu"
  }

  private var statusText: String {
    guard let period = stay.period else { return "Zobrazují se dostupné údaje" }
    if let currentDay = period.currentDay {
      return "Aktuální den \(currentDay) / \(period.totalDays)"
    }
    return period.phase == .upcoming ? "Pobyt ještě nezačal" : "Pobyt skončil"
  }

  private var statusColor: Color {
    guard let phase = stay.period?.phase else { return CommanderDesignTokens.Colors.textSecondary }
    switch phase {
    case .active: return CommanderDesignTokens.Colors.mealGreen
    case .upcoming: return CommanderDesignTokens.Colors.freeBlue
    case .finished: return CommanderDesignTokens.Colors.textSecondary
    }
  }

  private func dayCount(_ count: Int) -> String {
    switch count {
    case 1: return "1 den"
    case 2...4: return "\(count) dny"
    default: return "\(count) dní"
    }
  }

  private func progressTitle(for period: CommanderStayPeriod) -> String {
    period.phase == .active ? "Průběh pobytu" : "Pobyt podle rozpisu"
  }

  private func progressValue(for period: CommanderStayPeriod) -> String {
    if let currentDay = period.currentDay { return "\(currentDay) / \(period.totalDays)" }
    return period.phase == .finished ? "\(period.totalDays) / \(period.totalDays)" : "0 / \(period.totalDays)"
  }

  private func progressFraction(for period: CommanderStayPeriod) -> Double {
    guard period.totalDays > 0 else { return 0 }
    if let currentDay = period.currentDay { return Double(currentDay) / Double(period.totalDays) }
    return period.phase == .finished ? 1 : 0
  }

  private func dateMetric(title: String, date: Date, symbol: String) -> some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: symbol,
        color: CommanderDesignTokens.Colors.locationBlue,
        size: CommanderDesignTokens.Size.rowMetricBadge
      )
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
        Text(title)
          .commanderFont(.label)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Text(CommanderDateText.numericDate(date))
          .commanderFont(.metric)
          .monospacedDigit()
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.9)
      }
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CommanderDesignTokens.Colors.panel.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(CommanderDesignTokens.Stroke.normal, lineWidth: CommanderDesignTokens.Stroke.width)
    }
  }
}

private struct CommanderProcedureOverviewCard: View {
  let stay: CommanderStayPresentation

  var body: some View {
    CommanderSectionCard(
      title: "Procedury",
      symbol: "cross.case.fill",
      accent: CommanderDesignTokens.Colors.primaryPurple
    ) {
      CommanderProgressMeter(
        title: "Ukončené podle rozpisu",
        value: "\(stay.completedProcedures) / \(stay.totalProcedures)",
        fraction: procedureFraction,
        accent: CommanderDesignTokens.Colors.primaryPurple
      )

      if stay.procedures.isEmpty {
        Text("Rozpis neobsahuje žádné procedury")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      } else {
        VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
          ForEach(stay.procedures, id: \.name) { procedure in
            CommanderProcedureProgressRow(procedure: procedure)
          }
        }
      }
    }
  }

  private var procedureFraction: Double {
    guard stay.totalProcedures > 0 else { return 0 }
    return Double(stay.completedProcedures) / Double(stay.totalProcedures)
  }
}

private struct CommanderProcedureProgressRow: View {
  let procedure: CommanderProcedureSummary

  private var accent: Color {
    Color(commanderHex: CommanderVisualAssets.accent(for: procedure.representativeEvent))
  }

  var body: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.small) {
      CommanderSymbolBadge(
        symbol: CommanderVisualAssets.symbol(for: procedure.representativeEvent),
        color: accent,
        size: CommanderDesignTokens.Size.rowMetricBadge
      )
      Text(procedure.name)
        .commanderFont(.metric)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: CommanderDesignTokens.Spacing.small)
      Text("\(procedure.completed) / \(procedure.total)")
        .commanderFont(.metric)
        .monospacedDigit()
        .foregroundStyle(accent)
    }
    .padding(CommanderDesignTokens.Spacing.small)
    .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
    .background(CommanderDesignTokens.Colors.panel.opacity(0.72))
    .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(accent.opacity(0.35), lineWidth: CommanderDesignTokens.Stroke.width)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(procedure.name), ukončené podle rozpisu \(procedure.completed) z \(procedure.total)")
  }
}

private struct CommanderStayUnavailableCard: View {
  let message: String

  var body: some View {
    HStack(spacing: CommanderDesignTokens.Spacing.medium) {
      CommanderSymbolBadge(
        symbol: "bed.double",
        color: CommanderDesignTokens.Colors.textSecondary,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      Text(message)
        .commanderFont(.eventTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    }
    .padding(CommanderDesignTokens.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard()
  }
}

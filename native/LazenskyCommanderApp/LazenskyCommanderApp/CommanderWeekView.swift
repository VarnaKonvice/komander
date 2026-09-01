import LazenskyCommanderCore
import SwiftUI

struct CommanderWeekView: View {
  @ObservedObject var model: CommanderViewModel
  @State private var expandedDays: Set<Date> = []

  private var days: [CommanderWeekDay]? {
    guard let schedule = model.latestSchedule else { return nil }
    return try? CommanderWeekPresentation.make(
      schedule: schedule, now: .now, overrides: model.leadTimeOverrides
    )
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
        CommanderGlassHeader(tab: "Týden")
        if let days, !days.isEmpty {
          ForEach(days, id: \.date) { day in
            CommanderWeekDayTile(
              day: day, isExpanded: expandedDays.contains(day.date)
            ) {
              if expandedDays.contains(day.date) {
                expandedDays.remove(day.date)
              } else {
                expandedDays.insert(day.date)
              }
            }
          }
        } else {
          Text(model.latestSchedule == nil ? "Rozpis ještě není načten"
               : days == nil ? "Rozpis nelze zobrazit" : "Rozpis neobsahuje žádné události")
            .commanderFont(.eventTitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .padding(CommanderDesignTokens.Spacing.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .commanderCard()
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, CommanderDesignTokens.Spacing.tiny)
      .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
    }
    .scrollIndicators(.hidden)
    .background(CommanderDesignTokens.Colors.background.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }
}

struct CommanderWeekDayTile: View {
  let day: CommanderWeekDay
  let isExpanded: Bool
  let toggle: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.small) {
      Button(action: toggle) {
        CommanderDaySummaryCard(overview: day.overview, isExpanded: isExpanded)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(isExpanded ? "Rozbaleno" : "Sbaleno")
      .accessibilityHint(isExpanded ? "Sbalí program dne" : "Rozbalí program dne")
      if isExpanded {
        if day.events.isEmpty {
          Text("Žádný program")
            .commanderFont(.subtitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            .padding(CommanderDesignTokens.Spacing.medium)
        } else {
          ForEach(day.events, id: \.event.stableId) { item in
            CommanderEventRow(item: item)
          }
        }
      }
    }
  }
}

struct CommanderDaySummaryCard: View {
  let overview: CommanderDayOverview
  var isExpanded: Bool? = nil
  private var isCompact: Bool { isExpanded != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.small) {
      HStack(spacing: CommanderDesignTokens.Spacing.small) {
        CommanderSymbolBadge(symbol: "calendar", color: CommanderDesignTokens.Colors.primaryPurple, size: 28)
        Text(CommanderDateText.shortDay(overview.date))
          .commanderFont(.date)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
        Spacer(minLength: 0)
        if isCompact {
          Text(proceduresText)
            .commanderFont(.subtitle)
            .foregroundStyle(CommanderDesignTokens.Colors.primaryPurple)
            .fixedSize(horizontal: false, vertical: true)
        }
        if let isExpanded {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .commanderFont(.subtitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            .accessibilityHidden(true)
        }
      }
      HStack(alignment: .top, spacing: 6) {
        if !isCompact {
          CommanderDayMetric(
            title: "Procedury", value: "\(overview.procedureCount)",
            symbol: "cross.case", accent: CommanderDesignTokens.Colors.primaryPurple
          )
        }
        CommanderDayMetric(
          title: "Konec\nprocedur", value: overview.procedureEndAt?.formatted(CommanderScheduleDateStyle.clock) ?? "—",
          symbol: isCompact ? nil : "clock", accent: CommanderDesignTokens.Colors.primaryPurple,
          accessibleValue: overview.procedureEndAt == nil ? "Bez procedur" : nil
        )
        CommanderDayMetric(
          title: "Volno do\nvečeře", value: freeTime,
          symbol: isCompact ? nil : "cup.and.saucer", accent: CommanderDesignTokens.Colors.freeBlue,
          accessibleValue: overview.freeBeforeDinnerMinutes == nil ? "Údaj není k dispozici" : nil
        )
        .frame(minWidth: 100)
        CommanderDayMetric(
          title: "Večeře", value: overview.dinnerStartAt?.formatted(CommanderScheduleDateStyle.clock) ?? "—",
          symbol: isCompact ? nil : "fork.knife", accent: CommanderDesignTokens.Colors.mealGreen,
          accessibleValue: overview.dinnerStartAt == nil ? "Není v rozpisu" : nil
        )
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, isCompact ? 8 : 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard()
    .accessibilityElement(children: .combine)
  }

  private var freeTime: String {
    guard let minutes = overview.freeBeforeDinnerMinutes else { return "—" }
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder) min" }
    return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
  }

  private var proceduresText: String {
    switch overview.procedureCount {
    case 1: return "1 procedura"
    case 2...4: return "\(overview.procedureCount) procedury"
    default: return "\(overview.procedureCount) procedur"
    }
  }
}

private struct CommanderDayMetric: View {
  let title: String
  let value: String
  let symbol: String?
  let accent: Color
  var accessibleValue: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
      if let symbol {
        CommanderSymbolBadge(symbol: symbol, color: accent, size: 24)
      }
      Text(title)
        .commanderFont(.label)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 34, alignment: .topLeading)
      Text(value)
        .commanderFont(.metric)
        .monospacedDigit()
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.94)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    .accessibilityValue(accessibleValue ?? value)
  }
}

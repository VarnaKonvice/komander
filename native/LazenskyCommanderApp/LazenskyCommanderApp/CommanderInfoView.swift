import LazenskyCommanderCore
import SwiftUI

struct CommanderInfoView: View {
  @ObservedObject var model: CommanderViewModel

  private let labels = [
    "spa": "Lázně", "dateFrom": "Pobyt od", "dateTo": "Pobyt do",
    "room": "Pokoj", "doctor": "Lékař", "mealShift": "Stravovací směna"
  ]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      CommanderTabScaffold(
        tab: "Info",
        title: "Info",
        subtitle: "Informace o vašem pobytu"
      ) {
        if let schedule = model.latestSchedule {
          let fields = CommanderInfoPresentation.fields(stay: schedule.stay)
          if fields.isEmpty {
            unavailableCard("Informace o pobytu nejsou uvedeny")
          } else {
            CommanderSectionCard(
              title: "Údaje o pobytu",
              symbol: "info.circle.fill",
              accent: CommanderDesignTokens.Colors.locationBlue
            ) {
              if let period = CommanderStayPresentation.period(stay: schedule.stay, now: context.date) {
                stayDayRow(period)
              }
              VStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
                ForEach(fields, id: \.key) { field in
                  CommanderDetailRow(
                    title: labels[field.key] ?? field.key,
                    value: field.value,
                    symbol: symbol(for: field.key),
                    accent: accent(for: field.key)
                  )
                }
              }
            }
          }
        } else {
          unavailableCard("Rozpis ještě není načten")
        }
      }
    }
  }

  @ViewBuilder
  private func stayDayRow(_ period: CommanderStayPeriod) -> some View {
    switch period.phase {
    case .active:
      if let currentDay = period.currentDay {
        CommanderDetailRow(
          title: "Aktuální den pobytu",
          value: "\(currentDay) / \(period.totalDays)",
          symbol: "calendar.circle.fill",
          accent: CommanderDesignTokens.Colors.primaryPurple
        )
      }
    case .upcoming:
      CommanderDetailRow(
        title: "Stav pobytu",
        value: "Pobyt ještě nezačal",
        symbol: "calendar.badge.clock",
        accent: CommanderDesignTokens.Colors.freeBlue
      )
    case .finished:
      CommanderDetailRow(
        title: "Stav pobytu",
        value: "Pobyt skončil",
        symbol: "calendar.badge.checkmark",
        accent: CommanderDesignTokens.Colors.textSecondary
      )
    }
  }

  private func symbol(for key: String) -> String {
    switch key {
    case "spa": return "building.2.fill"
    case "dateFrom": return "calendar.badge.plus"
    case "dateTo": return "calendar.badge.checkmark"
    case "room": return "bed.double.fill"
    case "doctor": return "stethoscope"
    case "mealShift": return "fork.knife"
    default: return "info.circle"
    }
  }

  private func accent(for key: String) -> Color {
    switch key {
    case "spa": return CommanderDesignTokens.Colors.locationBlue
    case "dateFrom", "dateTo": return CommanderDesignTokens.Colors.primaryPurple
    case "room": return CommanderDesignTokens.Colors.freeBlue
    case "doctor": return CommanderDesignTokens.Colors.procedureCyan
    case "mealShift": return CommanderDesignTokens.Colors.mealGreen
    default: return CommanderDesignTokens.Colors.textSecondary
    }
  }

  private func unavailableCard(_ message: String) -> some View {
    HStack(spacing: CommanderDesignTokens.Spacing.medium) {
      CommanderSymbolBadge(
        symbol: "info.circle",
        color: CommanderDesignTokens.Colors.textSecondary,
        size: CommanderDesignTokens.Size.sectionBadge
      )
      Text(message)
        .commanderFont(.eventTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    }
    .padding(CommanderDesignTokens.Spacing.page)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthCard)
  }
}
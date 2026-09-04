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
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
          CommanderGlassHeader(tab: "Týden")
          CommanderScreenHeading(title: "Týden", subtitle: "Přehled procedur a aktivit")
          if let days, !days.isEmpty {
            ForEach(days, id: \.date) { day in
              CommanderWeekDayTile(
                day: day, isExpanded: expandedDays.contains(day.date)
              ) {
                if expandedDays.contains(day.date) {
                  expandedDays.remove(day.date)
                } else {
                  expandedDays.insert(day.date)
                  DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.12)) {
                      proxy.scrollTo(day.date, anchor: .top)
                    }
                  }
                }
              }
              .id(day.date)
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
      .background(CommanderDepthBackground().ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
  }
}

struct CommanderWeekDayTile: View {
  let day: CommanderWeekDay
  let isExpanded: Bool
  let toggle: () -> Void

  private let expandedRadius: CGFloat = 22

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
          LazyVStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
            ForEach(day.events, id: \.event.stableId) { item in
              CommanderEventRow(item: item)
            }
          }
          .padding(.horizontal, 2)
          .padding(.bottom, 2)
        }
      }
    }
    .padding(isExpanded ? 8 : 0)
    .background {
      if isExpanded {
        let shape = RoundedRectangle(cornerRadius: expandedRadius)
        ZStack {
          shape.fill(
            LinearGradient(
              colors: [
                Color(red: 0.16, green: 0.18, blue: 0.39),
                Color(red: 0.08, green: 0.13, blue: 0.29),
                Color(red: 0.035, green: 0.06, blue: 0.17)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          shape.fill(
            LinearGradient(
              colors: [
                Color.white.opacity(0.11),
                CommanderDesignTokens.Colors.primaryPurple.opacity(0.14),
                CommanderDesignTokens.Colors.freeBlue.opacity(0.07),
                Color.clear
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          shape.fill(
            RadialGradient(
              colors: [
                CommanderDesignTokens.Colors.freeBlue.opacity(0.28),
                CommanderDesignTokens.Colors.primaryPurple.opacity(0.18),
                .clear
              ],
              center: .topTrailing,
              startRadius: 8,
              endRadius: 250
            )
          )
        }
      }
    }
    .overlay {
      if isExpanded {
        RoundedRectangle(cornerRadius: expandedRadius)
          .strokeBorder(
            LinearGradient(
              colors: [
                Color.white.opacity(0.48),
                CommanderDesignTokens.Colors.freeBlue.opacity(0.98),
                CommanderDesignTokens.Colors.primaryPurple.opacity(0.92),
                CommanderDesignTokens.Colors.freeBlue.opacity(0.50)
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1.8
          )
      }
    }
    .shadow(
      color: isExpanded ? Color.black.opacity(0.34) : .clear,
      radius: isExpanded ? 15 : 0,
      y: isExpanded ? 9 : 0
    )
    .shadow(
      color: isExpanded ? CommanderDesignTokens.Colors.freeBlue.opacity(0.31) : .clear,
      radius: isExpanded ? 18 : 0
    )
    .shadow(
      color: isExpanded ? CommanderDesignTokens.Colors.primaryPurple.opacity(0.20) : .clear,
      radius: isExpanded ? 27 : 0
    )
  }
}

struct CommanderDaySummaryCard: View {
  let overview: CommanderDayOverview
  var isExpanded: Bool? = nil

  private var isWeekTile: Bool { isExpanded != nil }
  private var summaryAccent: Color {
    isExpanded == true
      ? CommanderDesignTokens.Colors.freeBlue
      : CommanderDesignTokens.Colors.primaryPurple
  }

  private var cardRadius: CGFloat { CommanderDesignTokens.Radius.card }

  private var metricColumns: [GridItem] {
    Array(
      repeating: GridItem(.flexible(minimum: 0), spacing: 5, alignment: .top),
      count: 4
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: CommanderDesignTokens.Spacing.small) {
        CommanderSymbolBadge(
          symbol: "calendar",
          color: CommanderDesignTokens.Colors.primaryPurple,
          size: 40
        )
        .background(CommanderDesignTokens.Colors.primaryPurple.opacity(0.10), in: Circle())
        .overlay {
          Circle().strokeBorder(
            CommanderDesignTokens.Colors.primaryPurple.opacity(0.60), lineWidth: 1.2
          )
        }
        .shadow(color: CommanderDesignTokens.Colors.primaryPurple.opacity(0.52), radius: 8)

        Text(CommanderDateText.shortDay(overview.date))
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
        Spacer(minLength: 0)
        if isWeekTile {
          Text(proceduresText)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
              isExpanded == true
                ? CommanderDesignTokens.Colors.freeBlue
                : CommanderDesignTokens.Colors.primaryPurple
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        if let isExpanded {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(
              isExpanded
                ? CommanderDesignTokens.Colors.freeBlue
                : CommanderDesignTokens.Colors.textSecondary
            )
            .accessibilityHidden(true)
        }
      }

      LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 0) {
        CommanderMetricTile(
          title: "Terapie", value: "\(overview.procedureCount)",
          symbol: "cross.case", accent: CommanderDesignTokens.Colors.primaryPurple
        )
        CommanderMetricTile(
          title: "Konec\nprocedur",
          value: overview.procedureEndAt?.formatted(CommanderScheduleDateStyle.clock) ?? "—",
          symbol: "clock", accent: CommanderDesignTokens.Colors.primaryPurple,
          accessibleValue: overview.procedureEndAt == nil ? "Bez procedur" : nil
        )
        CommanderMetricTile(
          title: "Volno do\nvečeře", value: freeTime,
          symbol: "cup.and.saucer", accent: CommanderDesignTokens.Colors.freeBlue,
          accessibleValue: overview.freeBeforeDinnerMinutes == nil ? "Údaj není k dispozici" : nil
        )
        CommanderMetricTile(
          title: "Večeře",
          value: overview.dinnerStartAt?.formatted(CommanderScheduleDateStyle.clock) ?? "—",
          symbol: "fork.knife", accent: CommanderDesignTokens.Colors.mealGreen,
          accessibleValue: overview.dinnerStartAt == nil ? "Není v rozpisu" : nil
        )
      }
    }
    .padding(.horizontal, 9)
    .padding(.top, 14)
    .padding(.bottom, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      let shape = RoundedRectangle(cornerRadius: cardRadius)
      ZStack {
        shape.fill(
          LinearGradient(
            colors: [
              Color(red: 0.15, green: 0.17, blue: 0.36),
              Color(red: 0.075, green: 0.11, blue: 0.26),
              Color(red: 0.035, green: 0.055, blue: 0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        shape.fill(
          LinearGradient(
            colors: [
              Color.white.opacity(isExpanded == true ? 0.13 : 0.10),
              summaryAccent.opacity(isExpanded == true ? 0.15 : 0.10),
              Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        shape.fill(
          RadialGradient(
            colors: [
              summaryAccent.opacity(isExpanded == true ? 0.24 : 0.15),
              .clear
            ],
            center: .topLeading,
            startRadius: 8,
            endRadius: 220
          )
        )
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: cardRadius)
        .strokeBorder(
          LinearGradient(
            colors: [
              Color.white.opacity(isExpanded == true ? 0.34 : 0.24),
              summaryAccent.opacity(isExpanded == true ? 0.88 : 0.64),
              CommanderDesignTokens.Colors.panelStroke.opacity(0.34)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: isExpanded == true ? 1.5 : 1.15
        )
    }
    .shadow(color: Color.black.opacity(0.28), radius: 9, y: 6)
    .shadow(
      color: summaryAccent.opacity(isExpanded == true ? 0.19 : 0.09),
      radius: isExpanded == true ? 12 : 7
    )
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

private struct CommanderMetricTile: View {
  let title: String
  let value: String
  let symbol: String?
  let accent: Color
  var accessibleValue: String? = nil

  private var isClockValue: Bool {
    value.contains(":") && !value.contains(" ")
  }

  var body: some View {
    VStack(alignment: .center, spacing: 3) {
      if let symbol {
        CommanderSymbolBadge(symbol: symbol, color: accent, size: 40)
          .background(accent.opacity(0.10), in: Circle())
          .overlay { Circle().strokeBorder(accent.opacity(0.60), lineWidth: 1.2) }
          .shadow(color: accent.opacity(0.50), radius: 8)
      }
      Text(title)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .top)
      Text(value)
        .font(.system(size: 21, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .multilineTextAlignment(.center)
        .lineLimit(isClockValue ? 1 : 2)
        .minimumScaleFactor(isClockValue ? 0.90 : 1)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .top)
    }
    .padding(.horizontal, 5)
    .padding(.top, 12)
    .padding(.bottom, 9)
    .frame(maxWidth: .infinity, minHeight: 142, alignment: .top)
    .background {
      let shape = RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
      ZStack {
        shape.fill(
          LinearGradient(
            colors: [
              Color(red: 0.17, green: 0.18, blue: 0.38),
              accent.opacity(0.12),
              Color(red: 0.055, green: 0.075, blue: 0.19)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        shape.fill(
          LinearGradient(
            colors: [
              Color.white.opacity(0.12),
              accent.opacity(0.13),
              Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        shape.fill(
          RadialGradient(
            colors: [accent.opacity(0.15), .clear],
            center: .topLeading,
            startRadius: 4,
            endRadius: 105
          )
        )
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
        .strokeBorder(
          LinearGradient(
            colors: [
              Color.white.opacity(0.24),
              accent.opacity(0.50),
              Color.black.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1
        )
    }
    .shadow(color: Color.black.opacity(0.33), radius: 5, y: 4)
    .shadow(color: accent.opacity(0.12), radius: 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    .accessibilityValue(accessibleValue ?? value)
  }
}

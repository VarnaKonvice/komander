import LazenskyCommanderCore
import SwiftUI

struct CommanderWeekView: View {
  @ObservedObject var model: CommanderViewModel
  @State private var expandedDays: Set<Date> = []
  @State private var hasFocusedToday = false

  private func days(at now: Date) -> [CommanderWeekDay]? {
    guard let schedule = model.latestSchedule else { return nil }
    return try? CommanderWeekPresentation.make(
      schedule: schedule, now: now, overrides: model.leadTimeOverrides
    )
  }

  var body: some View {
    TimelineView(.everyMinute) { context in
      weekContent(
        days: days(at: context.date),
        today: Self.calendar.startOfDay(for: context.date)
      )
    }
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }

  private func focusToday(_ today: Date, in days: [CommanderWeekDay]?, using proxy: ScrollViewProxy) {
    guard !hasFocusedToday, days?.contains(where: { $0.date == today }) == true else { return }
    hasFocusedToday = true
    DispatchQueue.main.async {
      proxy.scrollTo(today, anchor: .top)
    }
  }

  private func weekContent(days: [CommanderWeekDay]?, today: Date) -> some View {
    ScrollViewReader { proxy in
      VStack(spacing: 0) {
        CommanderPinnedTabHeader(
          title: "Týden",
          subtitle: "Přehled procedur a aktivit",
          schedule: model.latestSchedule
        )
        ScrollView {
          LazyVStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
          if let days, !days.isEmpty {
            ForEach(days, id: \.date) { day in
              let previewExpanded = ProcessInfo.processInfo.arguments.contains("-CommanderPreviewExpandWeek")
                && day.date == days[min(1, days.count - 1)].date
              CommanderWeekDayTile(
                day: day, isExpanded: expandedDays.contains(day.date) || previewExpanded,
                isPast: day.date < today, isToday: day.date == today
              ) {
                if expandedDays.contains(day.date) {
                  expandedDays.remove(day.date)
                } else {
                  expandedDays = [day.date]
                  DispatchQueue.main.async {
                    proxy.scrollTo(day.date, anchor: .top)
                  }
                }
              }
              .id(day.date)
            }
            .onAppear {
#if DEBUG
              if ProcessInfo.processInfo.arguments.contains("-CommanderPreviewExpandFirstDay"),
                 expandedDays.isEmpty,
                 let first = days.first?.date {
                expandedDays = [first]
              }
#endif
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
          .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
        }
        .scrollIndicators(.hidden)
        .clipped()
      }
      .background(CommanderDepthBackground().ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .onAppear { focusToday(today, in: days, using: proxy) }
      .onChange(of: days?.map(\.date)) { _, _ in
        // The first appearance can precede schedule loading.
        focusToday(today, in: days, using: proxy)
      }
      .onDisappear { hasFocusedToday = false }
    }
  }
}

struct CommanderWeekDayTile: View {
  let day: CommanderWeekDay
  let isExpanded: Bool
  var isPast = false
  var isToday = false
  let toggle: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(action: toggle) {
        CommanderDaySummaryCard(
          overview: day.overview, isExpanded: isExpanded, embedded: true
        )
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
            .padding(12)
        } else {
          LazyVStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
            ForEach(day.events, id: \.event.stableId) { item in
              CommanderEventRow(item: item)
            }
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
      }
    }
    // Expansion adds rows, never shrinks or replaces the full summary.
    .commanderCard(
      accent: isToday ? CommanderDesignTokens.Colors.procedureCyan : CommanderDesignTokens.Colors.locationBlue,
      surface: .depthCard
    )
    .overlay {
      if isToday {
        RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.card)
          .strokeBorder(CommanderDesignTokens.Colors.procedureCyan.opacity(0.28), lineWidth: 1.1)
          .allowsHitTesting(false)
      }
    }
    .saturation(isPast ? 0.7 : 1)
    .opacity(isPast ? 0.92 : 1)
  }
}

struct CommanderDaySummaryCard: View {
  let overview: CommanderDayOverview
  var isExpanded: Bool? = nil
  var stayPeriod: CommanderStayPeriod? = nil
  var embedded = false

  var body: some View {
    if embedded {
      content
    } else {
      content
        .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthCard)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 8) {
        CommanderSymbolBadge(
          symbol: "calendar", color: CommanderDesignTokens.Colors.locationBlue, size: CommanderDesignTokens.Size.primaryBadge
        )
        Text(CommanderDateText.shortDay(overview.date))
          .commanderFont(.date)
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .layoutPriority(1)
        Spacer(minLength: 4)
        if let isExpanded {
          Text(proceduresText)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.therapyPink)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .accessibilityHidden(true)
        } else if let period = stayPeriod, let day = period.currentDay {
          VStack(alignment: .trailing, spacing: 3) {
            Text("Den pobytu")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
              .lineLimit(1)
            Text("\(day) / \(period.totalDays)")
              .font(.system(size: 17, weight: .bold))
              .monospacedDigit()
              .foregroundStyle(.white)
              .lineLimit(1)
            GeometryReader { proxy in
              ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                  .fill(LinearGradient(
                    colors: [CommanderDesignTokens.Colors.locationBlue,
                             CommanderDesignTokens.Colors.procedureCyan],
                    startPoint: .leading, endPoint: .trailing
                  ))
                  .frame(width: proxy.size.width * min(1, Double(day) / Double(max(1, period.totalDays))))
              }
            }
            .frame(height: 5)
            .accessibilityHidden(true)
          }
          .frame(width: 108, alignment: .trailing)
          .accessibilityElement(children: .combine)
          .accessibilityLabel("Den pobytu \(day) z \(period.totalDays)")
        }
      }
      CommanderDayMetrics(overview: overview)
    }
    .padding(.horizontal, 12)
    .padding(.top, 14)
    .padding(.bottom, 14)
    .accessibilityElement(children: .combine)
  }

  private var proceduresText: String {
    switch overview.procedureCount {
    case 1: "1 procedura"
    case 2...4: "\(overview.procedureCount) procedury"
    default: "\(overview.procedureCount) procedur"
    }
  }
}

/// Identical geometry in Today and in every collapsed / expanded week summary.
struct CommanderDayMetrics: View {
  let overview: CommanderDayOverview
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.flexible(minimum: 0), spacing: 8),
        count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
      ), spacing: 8
    ) {
      CommanderMetricTile(
        title: "Terapie", value: "\(overview.procedureCount)",
        symbol: "cross.case.fill", accent: CommanderDesignTokens.Colors.therapyPink,
        referenceValue: freeTime
      )
      CommanderMetricTile(
        title: "Konec\nprocedur",
        value: overview.procedureEndAt?.formatted(CommanderScheduleDateStyle.clock) ?? "—",
        symbol: "clock.fill", accent: CommanderDesignTokens.Colors.procedureEndNeutral,
        referenceValue: freeTime,
        accessibleValue: overview.procedureEndAt == nil ? "Bez procedur" : nil
      )
      CommanderMetricTile(
        title: "Volno do\nvečeře", value: freeTime,
        symbol: "cup.and.saucer", accent: CommanderDesignTokens.Colors.freeBlue,
        referenceValue: freeTime,
        accessibleValue: overview.freeBeforeDinnerMinutes == nil ? "Údaj není k dispozici" : nil
      )
    }
  }

  private var freeTime: String {
    guard let minutes = overview.freeBeforeDinnerMinutes else { return "—" }
    let hours = minutes / 60
    let remainder = minutes % 60
    // Keep number + unit together; mixed durations have one deliberate line break.
    if hours == 0 { return "\(remainder)\u{00A0}min" }
    if remainder == 0 { return "\(hours)\u{00A0}h" }
    return "\(hours)\u{00A0}h \(remainder)\u{00A0}min"
  }
}

private struct CommanderMetricTile: View {
  let title: String
  let value: String
  let symbol: String
  let accent: Color
  let referenceValue: String
  var accessibleValue: String? = nil
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    VStack(spacing: 4) {
      CommanderSymbolBadge(symbol: symbol, color: accent, size: CommanderDesignTokens.Size.primaryBadge)
      Text(title)
        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 19 : 16, weight: .semibold))
        .foregroundStyle(Color.white.opacity(0.96))
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.78)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 46 : 38, maxHeight: dynamicTypeSize.isAccessibilitySize ? 46 : 38)
      // "Volno do večeře" determines the value slot for every tile in this day.
      // Measure its actual typography, including mixed hour/minute durations.
      metricValue(referenceValue)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 48)
        .hidden()
        .accessibilityHidden(true)
        .overlay {
          metricValue(value)
            .frame(maxWidth: .infinity)
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .commanderCard(accent: accent, surface: .depthInset)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    .accessibilityValue((accessibleValue ?? value).replacingOccurrences(of: "\n", with: " "))
  }

  private func metricValue(_ text: String) -> some View {
    Text(text)
      .font(.system(size: text.contains("\n") ? 23 : 22, weight: .bold))
      .monospacedDigit()
      .foregroundStyle(.white)
      .multilineTextAlignment(.center)
      .lineLimit(text.contains("\n") ? 2 : 1)
      .minimumScaleFactor(0.65)
      .allowsTightening(true)
  }
}

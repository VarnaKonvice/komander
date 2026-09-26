import LazenskyCommanderCore
import SwiftUI

struct CommanderDepthBackground: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [Color(commanderHex: "#20266F"), Color(commanderHex: "#0F326F"),
                   Color(commanderHex: "#132553"), Color(commanderHex: "#161B49")],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        RadialGradient(
          colors: [Color(commanderHex: "#4588FF").opacity(0.22), .clear],
          center: UnitPoint(x: 0.95, y: 0.22), startRadius: 0, endRadius: proxy.size.height * 0.65
        )
        RadialGradient(
          colors: [Color(commanderHex: "#8B46FF").opacity(0.16), .clear],
          center: UnitPoint(x: 0.02, y: 0.88), startRadius: 0, endRadius: proxy.size.height * 0.46
        )
        RadialGradient(
          colors: [Color(commanderHex: "#5A39FF").opacity(0.08), .clear],
          center: UnitPoint(x: 0.08, y: 0.05), startRadius: 0, endRadius: proxy.size.height * 0.34
        )
        // Directional ribbons create light and depth without blurring the entire page.
        ForEach(0..<3) { index in
          Path { path in
            let y = proxy.size.height * (0.30 + Double(index) * 0.34)
            path.move(to: CGPoint(x: -40, y: y + 130))
            path.addCurve(
              to: CGPoint(x: proxy.size.width + 70, y: y - 170),
              control1: CGPoint(x: proxy.size.width * 0.35, y: y + 30),
              control2: CGPoint(x: proxy.size.width * 0.7, y: y - 145)
            )
          }
          .stroke(
            LinearGradient(
              colors: [.clear, Color(commanderHex: "#3DACFF").opacity(0.12), .clear],
              startPoint: .bottomLeading, endPoint: .topTrailing
            ), lineWidth: 26
          )
          .shadow(color: Color(commanderHex: "#37BFFF").opacity(0.05), radius: 1.0)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct CommanderDashboardView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      CommanderDashboardContent(
        schedule: model.latestSchedule,
        overrides: model.leadTimeOverrides,
        now: context.date,
        isSynchronizing: model.isSynchronizing,
        synchronize: model.synchronize
      )
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }
}

struct CommanderDashboardContent: View {
  let schedule: Schedule?
  let overrides: LeadTimeOverrides
  let now: Date
  let isSynchronizing: Bool
  let synchronize: () -> Void

  private var presentation: CommanderDashboardPresentation {
    CommanderDashboardPresentation.make(schedule: schedule, now: now, overrides: overrides)
  }

  var body: some View {
    let presentation = presentation
    VStack(spacing: 0) {
      CommanderPinnedTabHeader(
        title: "Dnes",
        subtitle: "Přehled dne a aktuální stav",
        schedule: schedule
      )

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
          if presentation.mode == .unsynchronized {
            CommanderUnsynchronizedView(
              isSynchronizing: isSynchronizing,
              synchronize: synchronize
            )
          } else {
            CommanderTodayOverviewCard(presentation: presentation)
            CommanderNowDeck(presentation: presentation)
            if !presentation.timeline.isEmpty {
              CommanderDayTimelineView(
                items: presentation.timeline,
                excludedStableIDs: Set(
                  [presentation.currentEvent, presentation.nextEvent]
                    .compactMap { $0?.event.stableId }
                )
              )
            }
          }
        }
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
      }
      .scrollIndicators(.hidden)
      .clipped()
    }
  }
}

private struct CommanderTodayOverviewCard: View {
  let presentation: CommanderDashboardPresentation

  var body: some View {
    CommanderDaySummaryCard(
      overview: presentation.dayOverview,
      stayPeriod: presentation.stayPeriod,
      now: presentation.now
    )
  }
}

private struct CommanderNowDeck: View {
  let presentation: CommanderDashboardPresentation

  private var item: CommanderDashboardEvent? { presentation.currentEvent }

  private var accent: Color {
    item.map { CommanderEventAppearance.accent(for: $0.event) }
      ?? CommanderDesignTokens.Colors.primaryPurple
  }

  private var stateTitle: String {
    switch presentation.mode {
    case .upcoming: return "Následuje"
    case .leaveNow: return "Čas vyrazit"
    case .inProgress: return "Právě probíhá"
    case .dayDone: return "Dnes hotovo"
    case .noSchedule: return "Dnes bez programu"
    case .unsynchronized: return "Rozpis není načten"
    }
  }

  private func isSingleWordTitle(_ title: String) -> Bool {
    !title.contains { $0.isWhitespace }
  }

  private var deckTitle: String {
    if item == nil, presentation.nextProcedure != nil,
       presentation.mode == .dayDone || presentation.mode == .noSchedule {
      return "Volno do další procedury"
    }
    return "Co mě teď čeká"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(deckTitle)
        .font(.system(size: 23, weight: .bold))
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)

      if let item {
        primaryTile(item)

        if let next = presentation.nextEvent {
          followingTile(next, label: presentation.mode == .upcoming ? "Potom" : "Následuje")
        } else {
          endOfDayTile
        }
      } else if let procedure = presentation.nextProcedure {
        futurePrimaryTile(procedure, label: nextProcedureLabel(for: procedure))
      } else {
        emptyTile
      }
    }
    .padding(10)
    .commanderCard(accent: CommanderDesignTokens.Colors.procedureCyan, surface: .depthCard)
  }

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  @ViewBuilder
  private func primaryTile(_ item: CommanderDashboardEvent) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 12) {
        primaryIdentity(item)
        countdownRing(item)
          .frame(width: 108, height: 108)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(10)
      .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
      .commanderCard(accent: accent, surface: .depthInset)
      .accessibilityValue("\(stateTitle). \(primaryTimeLine(item))")
    } else {
      ZStack(alignment: .trailing) {
        countdownRing(item)
          .frame(width: 132, height: 132)
          .fixedSize()
          .offset(x: 12)
          .zIndex(0)

        layeredPrimaryIdentity(item)
          .zIndex(1)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
      .commanderCard(accent: accent, surface: .depthInset)
      .accessibilityValue("\(stateTitle). \(primaryTimeLine(item))")
    }
  }

  private func layeredPrimaryIdentity(_ item: CommanderDashboardEvent) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .center, spacing: 11) {
        CommanderSymbolBadge(
          symbol: CommanderEventAppearance.symbol(for: item.event),
          color: accent,
          size: 68
        )

        VStack(alignment: .leading, spacing: 5) {
          Text(stateTitle)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.82)

          layeredPrimaryTime(
            "\(item.startAt.formatted(CommanderScheduleDateStyle.clock)) – \(item.endAt.formatted(CommanderScheduleDateStyle.clock))"
          )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.trailing, 108)

      layeredPrimaryTitle(item.event.title, color: accent)
        .layoutPriority(3)
        .zIndex(3)

      if !item.event.location.isEmpty {
        Label(item.event.location, systemImage: "mappin.circle.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
          .padding(.trailing, 104)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func layeredPrimaryTitle(_ title: String, color: Color) -> some View {
    ZStack(alignment: .leading) {
      Text(title)
        .font(.system(size: 31, weight: .heavy))
        .foregroundStyle(color)
        .allowsTightening(true)
        .lineLimit(2)
        .minimumScaleFactor(0.70)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(title)
        .font(.system(size: 31, weight: .heavy))
        .foregroundStyle(color)
        .allowsTightening(true)
        .lineLimit(2)
        .minimumScaleFactor(0.70)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: Color.black.opacity(0.92), radius: 5.5, x: 2, y: 2)
        .shadow(color: CommanderDesignTokens.Colors.backgroundDeep.opacity(0.84), radius: 2.5, x: 0, y: 1)
        .mask(alignment: .trailing) {
          LinearGradient(
            colors: [.clear, .white.opacity(0.72), .white],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 128)
        }
    }
    .padding(.trailing, 18)
  }

  private func layeredPrimaryTime(_ text: String) -> some View {
    ZStack(alignment: .leading) {
      Text(text)
        .font(.system(size: 19, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.76)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(text)
        .font(.system(size: 19, weight: .bold))
        .monospacedDigit()
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.76)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadow(color: Color.black.opacity(0.78), radius: 3.5, x: 1.5, y: 1.5)
        .mask(alignment: .trailing) {
          LinearGradient(
            colors: [.clear, .white.opacity(0.65), .white],
            startPoint: .leading,
            endPoint: .trailing
          )
          .frame(width: 76)
        }
    }
  }

  private func primaryIdentity(_ item: CommanderDashboardEvent) -> some View {
    HStack(alignment: .center, spacing: 8) {
      CommanderSymbolBadge(
        symbol: CommanderEventAppearance.symbol(for: item.event), color: accent, size: CommanderDesignTokens.Size.featuredBadge
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(stateTitle)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .lineLimit(1)
        Text("\(item.startAt.formatted(CommanderScheduleDateStyle.clock)) – \(item.endAt.formatted(CommanderScheduleDateStyle.clock))")
          .font(.system(size: 17, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Text(item.event.title)
          .commanderFont(.liveTitle)
          .foregroundStyle(accent)
          .allowsTightening(true)
          .lineLimit(isSingleWordTitle(item.event.title) ? 1 : 2)
          .minimumScaleFactor(isSingleWordTitle(item.event.title) ? 0.78 : 1)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
        if !item.event.location.isEmpty {
          Label(item.event.location, systemImage: "mappin.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func countdownRing(_ item: CommanderDashboardEvent) -> some View {
    CommanderCountdownRing(
      topLabel: ringTopLabel,
      valueText: ringValueText(item),
      bottomLabel: ringBottomLabel,
      progress: ringProgress(item),
      accent: accent,
      plainTopLabel: true
    )
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func futurePrimaryTile(_ item: CommanderDashboardEvent, label: String) -> some View {
    let nextAccent = CommanderEventAppearance.accent(for: item.event)
    let target = item.leaveAt > presentation.now ? item.leaveAt : item.startAt
    let minutes = max(0, Int(ceil(target.timeIntervalSince(presentation.now) / 60)))
    let value = futureDurationText(minutes: minutes)
    let totalWindow: TimeInterval = 12 * 60 * 60
    let remaining = max(0, min(totalWindow, target.timeIntervalSince(presentation.now)))

    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          CommanderSymbolBadge(
            symbol: CommanderEventAppearance.symbol(for: item.event),
            color: nextAccent,
            size: CommanderDesignTokens.Size.featuredBadge
          )
          VStack(alignment: .leading, spacing: 4) {
            Text(label)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(Color.white.opacity(0.95))
            Text(item.event.title)
              .font(.system(size: 24, weight: .bold))
              .foregroundStyle(nextAccent)
              .lineLimit(2)
            Label(
              "Začátek \(item.startAt.formatted(CommanderScheduleDateStyle.clock))",
              systemImage: "clock.fill"
            )
            .font(.system(size: 16, weight: .bold))
            .monospacedDigit()
          }
        }

        CommanderCountdownRing(
          topLabel: item.leaveAt > presentation.now ? "Odchod" : "Začátek za",
          valueText: value,
          bottomLabel: nil,
          progress: remaining / totalWindow,
          accent: nextAccent,
          plainTopLabel: true
        )
        .frame(width: 108, height: 108)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(12)
      .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
      .commanderCard(accent: nextAccent, surface: .depthInset)
    } else {
      ZStack(alignment: .trailing) {
        CommanderCountdownRing(
          topLabel: item.leaveAt > presentation.now ? "Odchod" : "Začátek za",
          valueText: value,
          bottomLabel: nil,
          progress: remaining / totalWindow,
          accent: nextAccent,
          plainTopLabel: true
        )
        .frame(width: 126, height: 126)
        .fixedSize()
        .padding(.trailing, 4)
        .zIndex(0)

        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .center, spacing: 11) {
            CommanderSymbolBadge(
              symbol: CommanderEventAppearance.symbol(for: item.event),
              color: nextAccent,
              size: 68
            )

            VStack(alignment: .leading, spacing: 5) {
              Text(label)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

              layeredPrimaryTime(
                "Začátek \(item.startAt.formatted(CommanderScheduleDateStyle.clock))"
              )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .padding(.trailing, 108)

          layeredPrimaryTitle(item.event.title, color: nextAccent)
            .layoutPriority(3)
            .zIndex(3)

          if !item.event.location.isEmpty {
            Label(item.event.location, systemImage: "mappin.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
              .padding(.trailing, 112)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(1)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
      .commanderCard(accent: nextAccent, surface: .depthInset)
    }
  }

  private func followingTile(_ item: CommanderDashboardEvent, label: String) -> some View {
    let nextAccent = CommanderEventAppearance.accent(for: item.event)
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
    return layout {
      HStack(spacing: 12) {
        CommanderSymbolBadge(
          symbol: CommanderEventAppearance.symbol(for: item.event),
          color: nextAccent,
          size: dynamicTypeSize.isAccessibilitySize ? 59 : 66
        )
        VStack(alignment: .leading, spacing: 5) {
          Text(label)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text(item.event.title)
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 23 : 26, weight: .bold))
            .foregroundStyle(nextAccent)
            .allowsTightening(true)
            .lineLimit(2)
            .minimumScaleFactor(0.76)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
          if !item.event.location.isEmpty {
            Label(item.event.location, systemImage: "mappin.circle.fill")
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
              .lineLimit(1)
              .minimumScaleFactor(0.84)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      VStack(alignment: .leading, spacing: 12) {
        followingTimeRow(
          title: "Začátek", date: item.startAt, symbol: "clock.fill"
        )
        followingTimeRow(
          title: "Odchod", date: item.leaveAt, symbol: "figure.walk"
        )
      }
      .frame(width: 96, alignment: .leading)
      .layoutPriority(2)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 120 : 126)
    .commanderCard(accent: nextAccent, surface: .depthInset)
  }

  private func followingTimeRow(title: String, date: Date, symbol: String) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .medium))
        .frame(width: 18)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 14, weight: .semibold))
        Text(date.formatted(CommanderScheduleDateStyle.clock))
          .font(.system(size: 19, weight: .bold))
          .monospacedDigit()
      }
    }
    .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
    .accessibilityElement(children: .combine)
  }

  private var endOfDayTile: some View {
    HStack(spacing: 10) {
      CommanderSymbolBadge(
        symbol: "moon.stars.fill",
        color: CommanderDesignTokens.Colors.primaryPurple,
        size: CommanderDesignTokens.Size.standardBadge
      )

      VStack(alignment: .leading, spacing: 2) {
        Text("Potom")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text("Dnes už nic")
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text("Zbytek dne je volný.")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, minHeight: 78)
    .commanderCard(accent: CommanderDesignTokens.Colors.primaryPurple, surface: .depthInset)
  }

  private func nextProcedureLabel(for item: CommanderDashboardEvent) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!

    if calendar.isDate(item.startAt, inSameDayAs: presentation.now) {
      return "Další procedura"
    }
    if let tomorrow = calendar.date(byAdding: .day, value: 1, to: presentation.now),
       calendar.isDate(item.startAt, inSameDayAs: tomorrow) {
      return "Zítra · první procedura"
    }
    return "\(CommanderDateText.shortDay(item.startAt)) · první procedura"
  }

  private func futureDurationText(minutes: Int) -> String {
    if minutes < 60 {
      return "\(minutes) min"
    }

    let hours = minutes / 60
    let remainder = minutes % 60
    if hours < 24 {
      return remainder == 0 ? "\(hours) h" : "\(hours) h\n\(remainder) min"
    }

    let days = hours / 24
    let remainingHours = hours % 24
    if remainingHours == 0, remainder == 0 {
      return days == 1 ? "1 den" : "\(days) dny"
    }
    if remainder == 0 {
      return "\(days) d\n\(remainingHours) h"
    }
    return "\(days) d\n\(remainingHours) h \(remainder) min"
  }

  private var emptyTile: some View {
    HStack(spacing: 10) {
      CommanderSymbolBadge(
        symbol: presentation.mode == .dayDone ? "checkmark.circle.fill" : "calendar",
        color: CommanderDesignTokens.Colors.primaryPurple,
        size: CommanderDesignTokens.Size.standardBadge
      )
      VStack(alignment: .leading, spacing: 3) {
        Text(stateTitle)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text(
          presentation.mode == .dayDone || presentation.mode == .noSchedule
            ? "Další procedura není naplánovaná."
            : "Na dnešek nejsou naplánované události."
        )
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func primaryTimeLine(_ item: CommanderDashboardEvent) -> String {
    switch presentation.mode {
    case .upcoming:
      return "Odchod \(item.leaveAt.formatted(CommanderScheduleDateStyle.clock)) · začátek \(item.startAt.formatted(CommanderScheduleDateStyle.clock))"
    case .leaveNow:
      return "Začátek \(item.startAt.formatted(CommanderScheduleDateStyle.clock))"
    case .inProgress:
      return "Do \(item.endAt.formatted(CommanderScheduleDateStyle.clock))"
    default:
      return item.startAt.formatted(CommanderScheduleDateStyle.clock)
    }
  }

  private var ringTopLabel: String {
    switch presentation.mode {
    case .upcoming: return "Odchod"
    case .leaveNow: return "Do začátku"
    case .inProgress: return "Do konce"
    default: return ""
    }
  }

  private var ringBottomLabel: String? {
    nil
  }

  private func ringValueText(_ item: CommanderDashboardEvent) -> String {
    let target: Date
    switch presentation.mode {
    case .upcoming: target = item.leaveAt
    case .leaveNow: target = item.startAt
    case .inProgress: target = item.endAt
    default: return "—"
    }
    let minutes = max(0, Int(ceil(target.timeIntervalSince(presentation.now) / 60)))
    if minutes == 0 { return "teď" }
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder) min" }
    if remainder == 0 { return "\(hours) h" }
    return "\(hours) h \(remainder) min"
  }

  private func ringProgress(_ item: CommanderDashboardEvent) -> Double {
    let target: Date
    let windowStart: Date

    switch presentation.mode {
    case .upcoming:
      target = item.leaveAt
      if let previous = presentation.timeline.last(where: {
        $0.endAt <= item.startAt && $0.event.stableId != item.event.stableId
      }), previous.endAt < target {
        windowStart = previous.endAt
      } else {
        windowStart = target.addingTimeInterval(-2 * 60 * 60)
      }
    case .leaveNow:
      target = item.startAt
      windowStart = item.leaveAt
    case .inProgress:
      target = item.endAt
      windowStart = item.startAt
    default:
      return 0
    }

    let total = max(1, target.timeIntervalSince(windowStart))
    let remaining = max(0, min(total, target.timeIntervalSince(presentation.now)))
    return remaining / total
  }
}

private struct CommanderCountdownRing: View {
  let topLabel: String
  let valueText: String
  let bottomLabel: String?
  let progress: Double
  let accent: Color
  var plainTopLabel = false

  private var departureContentOverflows: Bool {
    topLabel == "Odchod" && (valueText.contains("\n") || valueText.count > 9)
  }

  var body: some View {
    ZStack {
      Circle()
        .stroke(accent.opacity(0.18), lineWidth: 8)
      Circle()
        .trim(from: 0, to: max(0.03, min(1, progress)))
        .stroke(
          AngularGradient(
            colors: [accent.opacity(0.45), accent, Color.white],
            center: .center
          ),
          style: StrokeStyle(lineWidth: 8, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .shadow(color: accent.opacity(0.72), radius: 2.4)

      if plainTopLabel {
        VStack(spacing: valueText.count > 9 ? 3 : 6) {
          if !topLabel.isEmpty {
            if topLabel == "Odchod" {
              VStack(spacing: 1) {
                Image(systemName: "figure.walk")
                  .font(.system(size: 25, weight: .heavy))
                  .accessibilityHidden(true)

                Text("Odchod")
                  .font(.system(size: 14, weight: .heavy))
                  .lineLimit(1)
                  .minimumScaleFactor(0.82)
              }
              .foregroundStyle(.white)
              .shadow(
                color: departureContentOverflows ? Color.black.opacity(0.88) : .clear,
                radius: departureContentOverflows ? 4.5 : 0,
                x: 1.5,
                y: 1.5
              )
            } else {
              Text(topLabel)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            }
          }

          Text(valueText)
            .font(.system(size: valueText.count > 7 ? 21 : 25, weight: .heavy))
            .minimumScaleFactor(0.70)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)

          if let bottomLabel {
            Text(bottomLabel)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
              .lineLimit(2)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      } else {
        VStack(spacing: 0) {
          Text(valueText)
            .font(.system(size: valueText.count > 7 ? 21 : 25, weight: .heavy))
            .minimumScaleFactor(0.70)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
          if let bottomLabel {
            Text(bottomLabel)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
              .lineLimit(2)
              .multilineTextAlignment(.center)
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .padding(.horizontal, 8)
        .padding(.top, topLabel.isEmpty ? 8 : 15)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

        if !topLabel.isEmpty {
          Text(topLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
              Capsule()
                .fill(
                  LinearGradient(
                    colors: [Color(commanderHex: "#234E8E"), Color(commanderHex: "#172952")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                  )
                )
                .overlay {
                  Capsule()
                    .strokeBorder(accent.opacity(0.38), lineWidth: 0.75)
                }
                .shadow(color: Color(commanderHex: "#08162F").opacity(0.34), radius: 2.2, y: 1.2)
            }
            .offset(y: -3)
            .frame(maxHeight: .infinity, alignment: .top)
        }
      }
    }
  }
}

private struct CommanderUnsynchronizedView: View {
  let isSynchronizing: Bool
  let synchronize: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.page) {
      Text("Rozpis ještě není načten")
        .commanderFont(.liveTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      Button(action: synchronize) {
        HStack(spacing: CommanderDesignTokens.Spacing.small) {
          Label(
            isSynchronizing ? "Synchronizuji…" : "Synchronizovat rozpis",
            systemImage: "arrow.triangle.2.circlepath"
          )
          Spacer(minLength: 0)
          if isSynchronizing {
            ProgressView().tint(CommanderDesignTokens.Colors.textPrimary)
          }
        }
        .commanderFont(.section)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .padding(CommanderDesignTokens.Spacing.medium)
        .frame(minHeight: 44)
        .background(CommanderDesignTokens.Colors.primaryPurple.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
      }
      .buttonStyle(.plain)
      .disabled(isSynchronizing)
    }
    .padding(CommanderDesignTokens.Spacing.page)
    .commanderCard()
  }
}

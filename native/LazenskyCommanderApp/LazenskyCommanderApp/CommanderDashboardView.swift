import LazenskyCommanderCore
import SwiftUI

struct CommanderDepthBackground: View {
  var body: some View {
    ZStack {
      CommanderDashboardPalette.backgroundGradient
      LinearGradient(
        colors: [
          Color.white.opacity(0.035),
          Color.clear,
          CommanderDesignTokens.Colors.primaryPurple.opacity(0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      RadialGradient(
        colors: [CommanderDesignTokens.Colors.primaryPurple.opacity(0.32), .clear],
        center: UnitPoint(x: 0.16, y: 0.08),
        startRadius: 0,
        endRadius: 260
      )
      RadialGradient(
        colors: [CommanderDesignTokens.Colors.freeBlue.opacity(0.24), .clear],
        center: UnitPoint(x: 0.92, y: 0.24),
        startRadius: 0,
        endRadius: 300
      )
      RadialGradient(
        colors: [CommanderDesignTokens.Colors.panelStroke.opacity(0.14), .clear],
        center: .bottom,
        startRadius: 20,
        endRadius: 330
      )
    }
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
    ScrollView {
      LazyVStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
        CommanderGlassHeader(tab: "Dnes")
        CommanderScreenHeading(title: "Dnes", subtitle: "Přehled dne a aktuální stav")
        if presentation.mode == .unsynchronized {
          CommanderUnsynchronizedView(isSynchronizing: isSynchronizing, synchronize: synchronize)
        } else {
          CommanderDaySummaryCard(overview: presentation.dayOverview)
          CommanderTodayLiveCard(presentation: presentation)
          if !presentation.timeline.isEmpty {
            CommanderDayTimelineView(items: presentation.timeline)
          }
        }
      }
      .padding(.horizontal, CommanderDesignTokens.Spacing.page)
      .padding(.top, CommanderDesignTokens.Spacing.tiny)
      .padding(.bottom, CommanderDesignTokens.Spacing.bottom)
    }
    .scrollIndicators(.hidden)
  }
}

struct CommanderTodayLiveCard: View {
  let presentation: CommanderDashboardPresentation
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var item: CommanderDashboardEvent? { presentation.currentEvent }

  private var eventAccent: Color {
    guard let item else { return CommanderDesignTokens.Colors.primaryPurple }
    return Color(commanderHex: CommanderVisualAssets.accent(for: item.event))
  }

  private var statusColor: Color {
    switch presentation.mode {
    case .leaveNow: return CommanderDesignTokens.Colors.criticalRed
    case .inProgress: return CommanderDesignTokens.Colors.mealGreen
    default: return CommanderDesignTokens.Colors.freeBlue
    }
  }

  private var statusTitle: String {
    switch presentation.mode {
    case .upcoming: return "Právě volno"
    case .leaveNow: return "Čas vyrazit"
    case .inProgress: return item?.event.kind == .meal ? "Právě jídlo" : "Právě probíhá"
    case .dayDone: return "Pro dnešek hotovo"
    case .noSchedule:
      return presentation.stayPeriod?.phase == .finished ? "Pobyt skončil" : "Dnes bez programu"
    case .unsynchronized: return "Rozpis ještě není načten"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
      HStack(alignment: .top, spacing: CommanderDesignTokens.Spacing.medium) {
        if !dynamicTypeSize.isAccessibilitySize {
          CommanderSymbolBadge(
            symbol: item.map { CommanderVisualAssets.symbol(for: $0.event) } ?? "clock.fill",
            color: presentation.mode == .inProgress ? eventAccent : statusColor,
            size: CommanderDesignTokens.Size.sectionBadge
          )
        }
        VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
          Text(statusTitle)
            .commanderFont(.liveTitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
          if let item {
            Text(presentation.mode == .inProgress ? "Nyní" : "Další událost")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            Text("\(item.event.title) · \(item.startAt.formatted(CommanderScheduleDateStyle.clock))")
              .commanderFont(.eventTitle)
              .foregroundStyle(eventAccent)
              .fixedSize(horizontal: false, vertical: true)
          } else if presentation.mode != .noSchedule {
            Text(presentation.mode == .dayDone ? "Dnešní program je dokončený." : "Na dnešek nejsou naplánované události.")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if presentation.mode == .noSchedule {
        noScheduleDetails
      } else if let item {
        countdown(item)
        locationPanel(for: item)
        if presentation.mode == .inProgress, let next = presentation.nextEvent {
          VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
            Text("Dále \(next.startAt.formatted(CommanderScheduleDateStyle.clock)) · \(next.event.title)")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            if !next.event.location.isEmpty {
              Text(next.event.location)
                .commanderFont(.location)
                .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(CommanderDesignTokens.Spacing.medium)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: statusColor)
    .overlay {
      let shape = RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.card)
      ZStack {
        shape.fill(
          LinearGradient(
            colors: [
              Color.white.opacity(0.055),
              statusColor.opacity(0.16),
              Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        shape.fill(
          RadialGradient(
            colors: [statusColor.opacity(0.17), .clear],
            center: .topLeading,
            startRadius: 8,
            endRadius: 220
          )
        )
        shape.strokeBorder(
          LinearGradient(
            colors: [
              Color.white.opacity(0.22),
              statusColor.opacity(0.42),
              Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1.15
        )
      }
      .allowsHitTesting(false)
    }
    .shadow(color: statusColor.opacity(0.22), radius: 13, y: 3)
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var noScheduleDetails: some View {
    if let stay = presentation.stayPeriod, stay.phase == .finished {
      Text("Poslední den pobytu \(CommanderDateText.numericDate(stay.dateTo))")
        .commanderFont(.subtitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    } else if let procedure = presentation.nextProcedure {
      let accent = Color(commanderHex: CommanderVisualAssets.accent(for: procedure.event))
      VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.small) {
        VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.tiny) {
          Text(freeHeadline(for: procedure))
            .commanderFont(.countdown)
            .monospacedDigit()
            .foregroundStyle(CommanderDesignTokens.Colors.freeBlue)
            .fixedSize(horizontal: false, vertical: true)
          Text("První procedura \(procedure.startAt.formatted(CommanderScheduleDateStyle.clock)) · \(procedure.event.title)")
            .commanderFont(.eventTitle)
            .foregroundStyle(accent)
            .fixedSize(horizontal: false, vertical: true)
        }
        locationPanel(for: procedure)
        departureLine(for: procedure)
      }
    } else {
      Text("Další procedura není v rozpisu")
        .commanderFont(.subtitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func freeHeadline(for procedure: CommanderDashboardEvent) -> String {
    let departure = departureDescription(for: procedure)
    return procedure.leaveAt > presentation.now
      ? "Volno do \(departure)"
      : "Je čas vyrazit · \(departure)"
  }

  private func departureDescription(for procedure: CommanderDashboardEvent) -> String {
    let time = procedure.leaveAt.formatted(CommanderScheduleDateStyle.clock)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    guard !calendar.isDate(procedure.startAt, inSameDayAs: presentation.now) else { return time }
    return "\(CommanderDateText.shortDay(procedure.leaveAt)) \(time)"
  }

  @ViewBuilder
  private func locationPanel(for item: CommanderDashboardEvent) -> some View {
    if !item.event.location.isEmpty {
      Label(item.event.location, systemImage: "mappin.circle.fill")
        .commanderFont(.location)
        .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CommanderDesignTokens.Spacing.small)
        .background(CommanderDesignTokens.Colors.locationBlue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
        .overlay {
          RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
            .strokeBorder(CommanderDesignTokens.Colors.locationBlue.opacity(0.45), lineWidth: 1)
        }
    }
  }

  private func departureLine(for procedure: CommanderDashboardEvent) -> some View {
    let time = procedure.leaveAt.formatted(CommanderScheduleDateStyle.clock)
    let relative = presentation.minutesUntilNextProcedureLeave.map {
      " · za \(relativeDuration(minutes: $0))"
    } ?? ""
    return (
      Text("Odchod \(time)").foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        + Text(relative).foregroundStyle(CommanderDesignTokens.Colors.amber)
    )
    .commanderFont(.subtitle)
    .monospacedDigit()
    .fixedSize(horizontal: false, vertical: true)
  }

  private func relativeDuration(minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder) min" }
    return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
  }

  @ViewBuilder
  private func countdown(_ item: CommanderDashboardEvent) -> some View {
    switch presentation.mode {
    case .upcoming:
      if let minutes = presentation.liveState.minutesUntilLeave {
        Label("Odchod za \(minutes) min", systemImage: "clock")
          .commanderFont(.countdown)
          .monospacedDigit()
          .foregroundStyle(CommanderDesignTokens.Colors.amber)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .leaveNow:
      Label("Vyrazit právě teď", systemImage: "clock.badge.exclamationmark")
        .commanderFont(.countdown)
        .foregroundStyle(CommanderDesignTokens.Colors.criticalRed)
        .fixedSize(horizontal: false, vertical: true)
    case .inProgress:
      let minutes = max(0, Int(ceil(item.endAt.timeIntervalSince(presentation.now) / 60)))
      Label("Do konce \(minutes) min", systemImage: "clock")
        .commanderFont(.countdown)
        .monospacedDigit()
        .foregroundStyle(statusColor)
        .fixedSize(horizontal: false, vertical: true)
    default:
      EmptyView()
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

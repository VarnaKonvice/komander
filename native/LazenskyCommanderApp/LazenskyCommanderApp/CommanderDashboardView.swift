import LazenskyCommanderCore
import SwiftUI

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
    .background(CommanderDesignTokens.Colors.background.ignoresSafeArea())
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
              .padding(.top, CommanderDesignTokens.Spacing.tiny)
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

  private var statusColor: Color {
    switch presentation.mode {
    case .leaveNow: return CommanderDesignTokens.Colors.criticalRed
    case .inProgress:
      return item.map { CommanderEventAppearance.accent(for: $0.event) }
        ?? CommanderDesignTokens.Colors.primaryPurple
    default: return CommanderDesignTokens.Colors.freeBlue
    }
  }

  private var statusTitle: String {
    switch presentation.mode {
    case .upcoming: return "Právě volno"
    case .leaveNow: return "Čas vyrazit"
    case .inProgress: return item?.event.kind == .meal ? "Právě jídlo" : "Právě probíhá"
    case .dayDone: return "Pro dnešek hotovo"
    case .noSchedule: return "Dnes bez programu"
    case .unsynchronized: return "Rozpis ještě není načten"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.medium) {
      HStack(alignment: .top, spacing: CommanderDesignTokens.Spacing.medium) {
        if !dynamicTypeSize.isAccessibilitySize {
          if presentation.mode == .inProgress, let item {
            CommanderSymbolBadge(
              symbol: CommanderEventAppearance.symbol(for: item.event), color: statusColor, size: 52
            )
          } else {
            CommanderBrandAssets.smallGlyph
              .resizable()
              .scaledToFit()
              .frame(width: 60, height: 60)
              .accessibilityHidden(true)
          }
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
              .foregroundStyle(CommanderEventAppearance.accent(for: item.event))
              .fixedSize(horizontal: false, vertical: true)
          } else {
            Text(presentation.mode == .dayDone ? "Dnešní program je dokončený." : "Na dnešek nejsou naplánované události.")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }

      if let item {
        countdown(item)
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
    .accessibilityElement(children: .combine)
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
      // This only formats the existing event end, without selecting or changing a live state.
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

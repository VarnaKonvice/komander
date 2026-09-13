import ActivityKit
import AlarmKit
import Foundation
import LazenskyCommanderCore
import SwiftUI
import WidgetKit

private enum CommanderActivityTokens {
  static let background = Color(commanderActivityHex: CommanderBrandAssets.Colors.background)
  static let panel = Color(commanderActivityHex: CommanderBrandAssets.Colors.panel)
  static let panelStroke = Color(commanderActivityHex: CommanderBrandAssets.Colors.panelStroke)
  static let primaryPurple = Color(commanderActivityHex: CommanderBrandAssets.Colors.primaryPurple)
  static let locationBlue = Color(commanderActivityHex: CommanderBrandAssets.Colors.locationBlue)
  static let mealGreen = Color(commanderActivityHex: CommanderBrandAssets.Colors.mealGreen)
  static let amber = Color(commanderActivityHex: CommanderBrandAssets.Colors.amber)
  static let freeBlue = Color(commanderActivityHex: CommanderBrandAssets.Colors.freeBlue)
  static let procedureCyan = Color(commanderActivityHex: CommanderBrandAssets.Colors.procedureCyan)
  static let urgentOrange = Color(commanderActivityHex: CommanderBrandAssets.Colors.urgentOrange)
  static let criticalRed = Color(commanderActivityHex: CommanderBrandAssets.Colors.criticalRed)
  static let textPrimary = Color.white
  static let textSecondary = Color(commanderActivityHex: CommanderBrandAssets.Colors.textSecondary)
  static let runningGreen = mealGreen

  static let insetRadius: CGFloat = 12
  static let cardRadius: CGFloat = 24
  static let lockScreenMinHeight: CGFloat = 164
  static let heroTimeSize: CGFloat = 58
  static let heroWidth: CGFloat = 196
  static let heroMinHeight: CGFloat = 80

  static var backgroundGradient: LinearGradient {
    LinearGradient(colors: [panel, background], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  static func eventAccent(kind: ScheduleKind?, iconKey: String?, title: String) -> Color {
    Color(commanderActivityHex: CommanderBrandAssets.procedureAccentHex(
      iconKey: iconKey,
      title: title,
      isMeal: kind == .meal
    ))
  }

  static func departureAccent(for mode: AlarmPresentationState.Mode) -> Color {
    switch mode {
    case .alert: return criticalRed
    case .countdown, .paused: return amber
    @unknown default: return urgentOrange
    }
  }

  static func eventSymbol(kind: ScheduleKind?, iconKey: String?, title: String) -> String {
    CommanderBrandAssets.procedureSymbol(
      iconKey: iconKey,
      title: title,
      isMeal: kind == .meal
    )
  }
}

@main
struct LazenskyCommanderLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LazenskyCommanderAlarmLiveActivity()
    LazenskyCommanderProcedureLiveActivity()
  }
}

struct LazenskyCommanderAlarmLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self) { context in
      CommanderAlarmActivityContent(context: context)
    } dynamicIsland: { context in
      let metadata = context.attributes.metadata
      let title = metadata?.title ?? "Lázeňský Commander"
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: metadata?.kind,
        iconKey: metadata?.iconKey,
        title: title
      )
      let departureAccent = CommanderActivityTokens.departureAccent(for: context.state.mode)
      let eventSymbol = CommanderActivityTokens.eventSymbol(
        kind: metadata?.kind,
        iconKey: metadata?.iconKey,
        title: title
      )

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderActivityBrandMark(size: 34)
        }
        DynamicIslandExpandedRegion(.center) {
          CommanderIslandEventTitle(
            title: title,
            symbol: eventSymbol,
            accent: eventAccent
          )
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderAlarmExpandedTiming(mode: context.state.mode)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CommanderIslandDetails(
            location: metadata?.location,
            status: context.state.mode.isAlert ? "VYRAZIT TEĎ" : "Odchod za",
            statusAccent: departureAccent,
            timeLabel: "Začátek",
            timeValue: CommanderAlarmTime.startTime(from: metadata?.startAt),
            timeAccent: eventAccent
          )
        }
      } compactLeading: {
        CommanderIslandStateGlyph(symbol: "figure.walk", accent: departureAccent)
      } compactTrailing: {
        CommanderAlarmCountdownContext(
          mode: context.state.mode,
          showsLabel: false,
          size: .compact
        )
      } minimal: {
        CommanderIslandStateGlyph(symbol: "figure.walk", accent: departureAccent)
      }
      .keylineTint(departureAccent)
    }
    .supplementalActivityFamilies([.small])
  }
}

struct LazenskyCommanderProcedureLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CommanderProcedureLiveActivityAttributes.self) { context in
      CommanderProcedureActivityContent(context: context)
    } dynamicIsland: { context in
      let isStandby = context.state.isDepartureStandby
      let isDepartureBridge = context.state.isDepartureBridge
      let isDepartureHolder = context.attributes.departureHolder == true && context.state.isDepartureHolder
      let currentAccent = CommanderActivityTokens.eventAccent(
        kind: context.attributes.kind,
        iconKey: context.attributes.iconKey,
        title: context.attributes.title
      )
      let currentSymbol = CommanderActivityTokens.eventSymbol(
        kind: context.attributes.kind,
        iconKey: context.attributes.iconKey,
        title: context.attributes.title
      )
      let hasHandoff = !isStandby && !isDepartureHolder
        && !isDepartureBridge
        && context.isStale
        && context.state.nextTitle != nil
        && context.state.nextStartAt != nil
        && context.state.nextLeaveAt != nil
      let nextTitle = context.state.nextTitle ?? context.attributes.title
      let nextAccent = CommanderActivityTokens.eventAccent(
        kind: context.state.nextKind,
        iconKey: context.state.nextIconKey,
        title: nextTitle
      )
      let nextSymbol = CommanderActivityTokens.eventSymbol(
        kind: context.state.nextKind,
        iconKey: context.state.nextIconKey,
        title: nextTitle
      )
      let bridgeTitle = context.state.nextTitle ?? context.attributes.title
      let bridgeLocation = context.state.nextLocation ?? context.attributes.location
      let bridgeKind = context.state.nextKind ?? context.attributes.kind
      let bridgeIconKey = context.state.nextIconKey ?? context.attributes.iconKey
      let bridgeStartAt = context.state.nextStartAt ?? context.attributes.startAt
      let bridgeAccent = CommanderActivityTokens.eventAccent(
        kind: bridgeKind,
        iconKey: bridgeIconKey,
        title: bridgeTitle
      )
      let bridgeSymbol = CommanderActivityTokens.eventSymbol(
        kind: bridgeKind,
        iconKey: bridgeIconKey,
        title: bridgeTitle
      )
      let displayTitle = isDepartureBridge ? bridgeTitle : (hasHandoff ? nextTitle : context.attributes.title)
      let displaySymbol = isDepartureBridge ? bridgeSymbol : (hasHandoff ? nextSymbol : currentSymbol)
      let displayAccent = isDepartureBridge ? bridgeAccent : (hasHandoff ? nextAccent : currentAccent)
      let stateAccent: Color = isStandby
        ? .clear
        : (isDepartureBridge
          ? CommanderActivityTokens.criticalRed
          : (isDepartureHolder ? (context.isStale ? CommanderActivityTokens.amber : currentAccent) : (context.isStale
            ? (hasHandoff ? CommanderActivityTokens.freeBlue : CommanderActivityTokens.textSecondary)
            : CommanderActivityTokens.runningGreen)))

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if !isStandby { CommanderActivityBrandMark(size: 34) }
        }
        DynamicIslandExpandedRegion(.center) {
          if !isStandby {
            CommanderIslandEventTitle(
              title: displayTitle,
              symbol: displaySymbol,
              accent: displayAccent
            )
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          if !isStandby {
            if isDepartureBridge {
              CommanderDepartureBridgeTiming(startAt: bridgeStartAt, size: .regular)
            } else if isDepartureHolder, let leaveAt = context.state.nextLeaveAt {
              if context.isStale {
                CommanderDepartureBridgeTiming(startAt: leaveAt, size: .regular, isDepartureCountdown: true)
              } else {
                CommanderUpcomingTiming(startAt: bridgeStartAt, accent: currentAccent, size: .regular)
              }
            } else if hasHandoff, let leaveAt = context.state.nextLeaveAt {
              CommanderNextDepartureTiming(leaveAt: leaveAt, size: .regular)
            } else {
              CommanderProcedureTiming(
                endAt: context.attributes.endAt,
                isStale: context.isStale,
                accent: stateAccent,
                size: .regular
              )
            }
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          if !isStandby {
            if isDepartureBridge {
              CommanderIslandDetails(
                location: bridgeLocation,
                status: "VYRAZIT TEĎ",
                statusAccent: CommanderActivityTokens.criticalRed,
                timeLabel: "Začátek",
                timeValue: bridgeStartAt.formatted(date: .omitted, time: .shortened),
                timeAccent: bridgeAccent
              )
            } else if isDepartureHolder {
              if context.isStale, let leaveAt = context.state.nextLeaveAt {
                CommanderIslandDetails(
                  location: context.attributes.location,
                  status: "Odchod za",
                  statusAccent: CommanderActivityTokens.amber,
                  timeLabel: "Začátek",
                  timeValue: bridgeStartAt.formatted(date: .omitted, time: .shortened),
                  timeAccent: currentAccent
                )
              } else {
                CommanderIslandUpcomingDetails(
                  location: context.attributes.location,
                  startAt: bridgeStartAt,
                  accent: currentAccent
                )
              }
            } else if hasHandoff {
              CommanderIslandDetails(
                location: context.state.nextLocation,
                status: "Právě volno",
                statusAccent: CommanderActivityTokens.freeBlue,
                timeLabel: "Odchod",
                timeValue: context.state.nextLeaveAt?.formatted(date: .omitted, time: .shortened) ?? "--:--",
                timeAccent: CommanderActivityTokens.amber
              )
            } else {
              CommanderIslandDetails(
                location: context.attributes.location,
                status: CommanderProcedureText.status(
                  kind: context.attributes.kind,
                  isStale: context.isStale
                ),
                statusAccent: stateAccent,
                timeLabel: "Konec",
                timeValue: context.attributes.endAt.formatted(date: .omitted, time: .shortened),
                timeAccent: currentAccent
              )
            }
          }
        }
      } compactLeading: {
        if !isStandby {
          CommanderIslandStateGlyph(
            symbol: isDepartureBridge || hasHandoff || (isDepartureHolder && context.isStale)
              ? "figure.walk" : (context.isStale && !isDepartureHolder ? "checkmark" : displaySymbol),
            accent: stateAccent
          )
        }
      } compactTrailing: {
        if !isStandby {
          if isDepartureBridge {
            CommanderDepartureBridgeTiming(startAt: bridgeStartAt, size: .compact)
          } else if isDepartureHolder, let leaveAt = context.state.nextLeaveAt {
            if context.isStale {
              CommanderDepartureBridgeTiming(startAt: leaveAt, size: .compact, isDepartureCountdown: true)
            } else {
              CommanderUpcomingTiming(startAt: bridgeStartAt, accent: currentAccent, size: .compact)
            }
          } else if hasHandoff, let leaveAt = context.state.nextLeaveAt {
            CommanderNextDepartureTiming(leaveAt: leaveAt, size: .compact)
          } else {
            CommanderProcedureTiming(
              endAt: context.attributes.endAt,
              isStale: context.isStale,
              accent: stateAccent,
              size: .compact
            )
          }
        }
      } minimal: {
        if !isStandby {
          if isDepartureHolder, !context.isStale {
            Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<bridgeStartAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
              .font(.caption2.bold().monospacedDigit())
              .foregroundStyle(currentAccent)
              .lineLimit(1)
              .minimumScaleFactor(0.65)
          } else {
            CommanderIslandStateGlyph(
              symbol: isDepartureBridge || hasHandoff || (isDepartureHolder && context.isStale)
                ? "figure.walk" : (context.isStale && !isDepartureHolder ? "checkmark" : displaySymbol),
              accent: stateAccent
            )
          }
        }
      }
      .keylineTint(isStandby ? .clear : stateAccent)
    }
    .supplementalActivityFamilies([.small])
  }
}

private struct CommanderAlarmActivityContent: View {
  @Environment(\.activityFamily) private var activityFamily
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  @ViewBuilder
  var body: some View {
    if activityFamily == .small {
      CommanderAlarmWatchLiveActivityView(context: context)
    } else {
      CommanderAlarmLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    }
  }
}

private struct CommanderProcedureActivityContent: View {
  @Environment(\.activityFamily) private var activityFamily
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  @ViewBuilder
  var body: some View {
    if context.state.isDepartureStandby {
      EmptyView()
    } else if activityFamily == .small {
      CommanderProcedureWatchLiveActivityView(context: context)
    } else {
      CommanderProcedureLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    }
  }
}

private struct CommanderAlarmWatchLiveActivityView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  private var metadata: CommanderAlarmMetadata? { context.attributes.metadata }
  private var title: String { metadata?.title ?? "Lázeňský Commander" }
  private var accent: Color { CommanderActivityTokens.departureAccent(for: context.state.mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        CommanderActivityBrandMark(size: 16)
        Text(context.state.mode.isAlert ? "VYRAZIT TEĎ" : "Odchod za")
          .font(.caption2.bold())
          .foregroundStyle(accent)
          .lineLimit(1)
        Spacer(minLength: 4)
        if context.state.mode.isAlert {
          Text(CommanderAlarmTime.startTime(from: metadata?.startAt))
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(accent)
        } else {
          CommanderAlarmCountdown(mode: context.state.mode)
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(accent)
        }
      }
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CommanderActivityTokens.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
      if let location = metadata?.location, !location.isEmpty {
        Label(location, systemImage: "location.fill")
          .font(.caption2)
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .containerBackground(CommanderActivityTokens.backgroundGradient, for: .widget)
  }
}

private struct CommanderProcedureWatchLiveActivityView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  private var isBridge: Bool { context.state.isDepartureBridge }
  private var isHolder: Bool { context.attributes.departureHolder == true && context.state.isDepartureHolder }
  private var hasHandoff: Bool {
    !isHolder && !isBridge && context.isStale
      && context.state.nextTitle != nil && context.state.nextLeaveAt != nil
  }
  private var title: String {
    isBridge || hasHandoff ? (context.state.nextTitle ?? context.attributes.title) : context.attributes.title
  }
  private var location: String {
    isBridge || hasHandoff ? (context.state.nextLocation ?? context.attributes.location) : context.attributes.location
  }
  private var eventAccent: Color {
    CommanderActivityTokens.eventAccent(
      kind: isBridge || hasHandoff ? context.state.nextKind : context.attributes.kind,
      iconKey: isBridge || hasHandoff ? context.state.nextIconKey : context.attributes.iconKey,
      title: title
    )
  }
  private var eventSymbol: String {
    CommanderActivityTokens.eventSymbol(
      kind: isBridge || hasHandoff ? context.state.nextKind : context.attributes.kind,
      iconKey: isBridge || hasHandoff ? context.state.nextIconKey : context.attributes.iconKey,
      title: title
    )
  }
  private var accent: Color {
    if isBridge { return CommanderActivityTokens.criticalRed }
    if isHolder { return context.isStale ? CommanderActivityTokens.amber : eventAccent }
    if hasHandoff { return CommanderActivityTokens.freeBlue }
    if context.isStale { return CommanderActivityTokens.textSecondary }
    return CommanderActivityTokens.runningGreen
  }
  private var status: String {
    if isBridge { return "VYRAZIT TEĎ" }
    if isHolder { return context.isStale ? "Odchod za" : "Následuje" }
    if hasHandoff { return "Právě volno" }
    if context.isStale { return "Skončilo" }
    return context.attributes.kind == .meal ? "Právě jídlo" : "Právě probíhá"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        CommanderActivityBrandMark(size: 16)
        Text(status)
          .font(.caption2.bold())
          .foregroundStyle(accent)
          .lineLimit(1)
        Spacer(minLength: 4)
        timing
      }
      HStack(spacing: 5) {
        Image(systemName: eventSymbol)
          .font(.caption2.bold())
          .foregroundStyle(eventAccent)
          .frame(width: 16, height: 16)
          .background(eventAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CommanderActivityTokens.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      if !location.isEmpty {
        Label(location, systemImage: "location.fill")
          .font(.caption2)
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .containerBackground(CommanderActivityTokens.backgroundGradient, for: .widget)
  }

  @ViewBuilder
  private var timing: some View {
    if isBridge, let startAt = context.state.nextStartAt {
      Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
        .font(.subheadline.bold().monospacedDigit())
        .foregroundStyle(accent)
    } else if isHolder {
      if context.isStale, let leaveAt = context.state.nextLeaveAt {
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<leaveAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.subheadline.bold().monospacedDigit())
          .foregroundStyle(accent)
      } else if let startAt = context.state.nextStartAt {
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.subheadline.bold().monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
      }
    } else if hasHandoff, let leaveAt = context.state.nextLeaveAt {
      Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<leaveAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
        .font(.subheadline.bold().monospacedDigit())
        .foregroundStyle(accent)
    } else if context.isStale {
      Text(context.attributes.endAt, style: .time)
        .font(.subheadline.bold().monospacedDigit())
        .foregroundStyle(accent)
    } else {
      Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<context.attributes.endAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
        .font(.subheadline.bold().monospacedDigit())
        .foregroundStyle(accent)
    }
  }
}

private struct CommanderAlarmLockScreenView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  private var metadata: CommanderAlarmMetadata? { context.attributes.metadata }
  private var title: String { metadata?.title ?? "Lázeňský Commander" }
  private var eventAccent: Color {
    CommanderActivityTokens.eventAccent(kind: metadata?.kind, iconKey: metadata?.iconKey, title: title)
  }
  private var departureAccent: Color {
    CommanderActivityTokens.departureAccent(for: context.state.mode)
  }
  private var eventSymbol: String {
    CommanderActivityTokens.eventSymbol(kind: metadata?.kind, iconKey: metadata?.iconKey, title: title)
  }

  var body: some View {
    VStack(spacing: 9) {
      CommanderAlarmHero(
        mode: context.state.mode,
        startAt: metadata?.startAt
      )
      CommanderActivityDivider(accent: departureAccent)
      CommanderActivityEventFooter(
        title: title,
        location: metadata?.location,
        symbol: eventSymbol,
        eventAccent: eventAccent,
        timeLabel: "Začátek",
        timeValue: CommanderAlarmTime.startTime(from: metadata?.startAt),
        timeAccent: departureAccent
      )
    }
    .commanderActivityCard(accent: departureAccent)
  }
}

private struct CommanderProcedureLockScreenView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  private var currentAccent: Color {
    CommanderActivityTokens.eventAccent(
      kind: context.attributes.kind,
      iconKey: context.attributes.iconKey,
      title: context.attributes.title
    )
  }
  private var currentSymbol: String {
    CommanderActivityTokens.eventSymbol(
      kind: context.attributes.kind,
      iconKey: context.attributes.iconKey,
      title: context.attributes.title
    )
  }
  private var isDepartureBridge: Bool { context.state.isDepartureBridge }
  private var isDepartureHolder: Bool { context.attributes.departureHolder == true && context.state.isDepartureHolder }
  private var hasHandoff: Bool {
    !context.state.isDepartureStandby && !isDepartureHolder
      && !isDepartureBridge
      && context.isStale
      && context.state.nextTitle != nil
      && context.state.nextStartAt != nil
      && context.state.nextLeaveAt != nil
  }
  private var nextTitle: String { context.state.nextTitle ?? context.attributes.title }
  private var nextAccent: Color {
    CommanderActivityTokens.eventAccent(
      kind: context.state.nextKind,
      iconKey: context.state.nextIconKey,
      title: nextTitle
    )
  }
  private var nextSymbol: String {
    CommanderActivityTokens.eventSymbol(
      kind: context.state.nextKind,
      iconKey: context.state.nextIconKey,
      title: nextTitle
    )
  }
  private var bridgeTitle: String { context.state.nextTitle ?? context.attributes.title }
  private var bridgeLocation: String { context.state.nextLocation ?? context.attributes.location }
  private var bridgeKind: ScheduleKind { context.state.nextKind ?? context.attributes.kind }
  private var bridgeIconKey: String { context.state.nextIconKey ?? context.attributes.iconKey }
  private var bridgeStartAt: Date { context.state.nextStartAt ?? context.attributes.startAt }
  private var bridgeAccent: Color {
    CommanderActivityTokens.eventAccent(
      kind: bridgeKind,
      iconKey: bridgeIconKey,
      title: bridgeTitle
    )
  }
  private var bridgeSymbol: String {
    CommanderActivityTokens.eventSymbol(
      kind: bridgeKind,
      iconKey: bridgeIconKey,
      title: bridgeTitle
    )
  }
  private var stateAccent: Color {
    if isDepartureBridge { return CommanderActivityTokens.criticalRed }
    if isDepartureHolder { return context.isStale ? CommanderActivityTokens.amber : currentAccent }
    return context.isStale
      ? (hasHandoff ? CommanderActivityTokens.freeBlue : CommanderActivityTokens.textSecondary)
      : CommanderActivityTokens.runningGreen
  }

  var body: some View {
    VStack(spacing: 9) {
      if isDepartureBridge {
        CommanderDepartureBridgeHero(startAt: bridgeStartAt)
        CommanderActivityDivider(accent: CommanderActivityTokens.criticalRed)
        CommanderActivityEventFooter(
          title: bridgeTitle,
          location: bridgeLocation,
          symbol: bridgeSymbol,
          eventAccent: bridgeAccent,
          timeLabel: "Začátek",
          timeValue: bridgeStartAt.formatted(date: .omitted, time: .shortened),
          timeAccent: CommanderActivityTokens.criticalRed
        )
      } else if isDepartureHolder, let leaveAt = context.state.nextLeaveAt {
        if context.isStale {
          CommanderDepartureBridgeHero(startAt: leaveAt, isDepartureCountdown: true)
          CommanderActivityDivider(accent: CommanderActivityTokens.amber)
          CommanderActivityEventFooter(title: context.attributes.title, location: context.attributes.location,
            symbol: currentSymbol, eventAccent: currentAccent, timeLabel: "Začátek",
            timeValue: bridgeStartAt.formatted(date: .omitted, time: .shortened),
            timeAccent: CommanderActivityTokens.amber)
        } else {
          CommanderUpcomingHero(startAt: bridgeStartAt, accent: currentAccent)
          CommanderActivityDivider(accent: currentAccent)
          CommanderActivityEventFooter(title: context.attributes.title, location: context.attributes.location,
            symbol: currentSymbol, eventAccent: currentAccent, timeLabel: "Začátek",
            timeValue: bridgeStartAt.formatted(date: .omitted, time: .shortened),
            timeAccent: currentAccent)
        }
      } else if hasHandoff, let leaveAt = context.state.nextLeaveAt {
        CommanderTransitionHero(leaveAt: leaveAt)
        CommanderActivityDivider(accent: CommanderActivityTokens.freeBlue)
        CommanderActivityEventFooter(
          title: nextTitle,
          location: context.state.nextLocation,
          symbol: nextSymbol,
          eventAccent: nextAccent,
          timeLabel: "Odchod",
          timeValue: leaveAt.formatted(date: .omitted, time: .shortened),
          timeAccent: CommanderActivityTokens.amber
        )
      } else {
        CommanderProcedureHero(
          kind: context.attributes.kind,
          endAt: context.attributes.endAt,
          isStale: context.isStale,
          accent: stateAccent
        )
        CommanderActivityDivider(accent: stateAccent)
        CommanderActivityEventFooter(
          title: context.attributes.title,
          location: context.attributes.location,
          symbol: currentSymbol,
          eventAccent: currentAccent,
          timeLabel: "Konec",
          timeValue: context.attributes.endAt.formatted(date: .omitted, time: .shortened),
          timeAccent: stateAccent
        )
      }
    }
    .commanderActivityCard(accent: stateAccent)
  }
}

private struct CommanderAlarmHero: View {
  let mode: AlarmPresentationState.Mode
  let startAt: String?

  private var accent: Color {
    CommanderActivityTokens.departureAccent(for: mode)
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Text(mode.isAlert ? "VYRAZIT TEĎ" : "Odchod za")
          .font(.system(size: mode.isAlert ? 19 : 16, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)

        if mode.isAlert {
          if let startDate = CommanderAlarmTime.startDate(from: startAt) {
            Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startDate, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
              .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
              .foregroundStyle(accent)
              .lineLimit(1)
              .minimumScaleFactor(0.74)
          } else {
            Text("TEĎ")
              .font(.system(size: 42, weight: .heavy, design: .rounded))
              .foregroundStyle(accent)
          }
        } else {
          CommanderAlarmCountdown(mode: mode)
            .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        }
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)

        Spacer(minLength: 0)

        CommanderAlarmSideStatus(mode: mode, accent: accent)
          .frame(width: 72, alignment: .trailing)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderAlarmSideStatus: View {
  let mode: AlarmPresentationState.Mode
  let accent: Color

  var body: some View {
    VStack(spacing: 2) {
      Image(systemName: "figure.walk")
        .font(.system(size: 27, weight: .semibold))
        .foregroundStyle(accent)
        .frame(height: 31)

      Text(mode.isAlert ? "Je čas\nvyrazit" : "Odchod\nza")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(CommanderActivityTokens.textSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
  }
}

private struct CommanderDepartureBridgeHero: View {
  let startAt: Date
  var isDepartureCountdown = false
  private var accent: Color { isDepartureCountdown ? CommanderActivityTokens.amber : CommanderActivityTokens.criticalRed }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Text(isDepartureCountdown ? "Odchod za" : "VYRAZIT TEĎ")
          .font(.system(size: isDepartureCountdown ? 16 : 19, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.74)
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)
        Spacer(minLength: 0)
        VStack(spacing: 2) {
          Image(systemName: "figure.walk")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(accent)
            .frame(height: 31)
          Text(isDepartureCountdown ? "Odchod\nza" : "Je čas\nvyrazit")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.textSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(width: 72, alignment: .trailing)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderUpcomingHero: View {
  let startAt: Date
  let accent: Color

  var body: some View {
    ZStack {
      VStack(spacing: 1) {
        Text("Následuje za")
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.system(size: 42, weight: .heavy, design: .rounded).monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)
        Spacer(minLength: 0)
        VStack(spacing: 2) {
          Image(systemName: "clock")
            .font(.system(size: 27, weight: .semibold))
            .foregroundStyle(accent)
            .frame(height: 31)
          Text("Začátek")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.textSecondary)
            .lineLimit(1)
        }
        .frame(width: 72, alignment: .trailing)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderProcedureHero: View {
  let kind: ScheduleKind
  let endAt: Date
  let isStale: Bool
  let accent: Color

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Text(CommanderProcedureText.status(kind: kind, isStale: isStale))
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)

        if isStale {
          Text("Skončilo")
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundStyle(CommanderActivityTokens.textPrimary)
            .lineLimit(1)
        } else {
          Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<endAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
            .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        }
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)

        Spacer(minLength: 0)

        CommanderProcedureSideStatus(
          endAt: endAt,
          isStale: isStale,
          accent: accent
        )
        .frame(width: 72, alignment: .center)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderTransitionHero: View {
  let leaveAt: Date

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Text("Právě volno")
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(CommanderActivityTokens.freeBlue)
          .lineLimit(1)
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<leaveAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
          .foregroundStyle(CommanderActivityTokens.freeBlue)
          .lineLimit(1)
          .minimumScaleFactor(0.74)
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)
        Spacer(minLength: 0)
        VStack(spacing: 2) {
          Image(systemName: "figure.walk")
            .font(.system(size: 25, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.amber)
          Text("Odchod\nza")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.textSecondary)
            .multilineTextAlignment(.center)
        }
        .frame(width: 72, alignment: .center)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderProcedureSideStatus: View {
  let endAt: Date
  let isStale: Bool
  let accent: Color

  var body: some View {
    if isStale {
      VStack(spacing: 2) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(accent)
        Text("Skončilo")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
      }
      .frame(width: 72, alignment: .center)
    } else {
      VStack(alignment: .center, spacing: 0) {
        Text("Do konce")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<endAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.system(size: 18, weight: .bold).monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(width: 72, alignment: .center)
      .multilineTextAlignment(.center)
    }
  }
}

private struct CommanderActivityDivider: View {
  let accent: Color

  var body: some View {
    Rectangle()
      .fill(
        LinearGradient(
          colors: [accent.opacity(0.86), accent.opacity(0.18), CommanderActivityTokens.panelStroke.opacity(0.14)],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(height: 1.4)
  }
}

private struct CommanderActivityEventFooter: View {
  let title: String
  let location: String?
  let symbol: String
  let eventAccent: Color
  let timeLabel: String
  let timeValue: String
  let timeAccent: Color

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      CommanderActivityEventBadge(symbol: symbol, accent: eventAccent, size: 36)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 21, weight: .bold))
          .foregroundStyle(CommanderActivityTokens.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.84)
        if let location, !location.isEmpty {
          Label(location, systemImage: "mappin.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      CommanderActivityTimeBlock(
        label: timeLabel,
        value: timeValue,
        accent: timeAccent
      )
    }
    .frame(minHeight: 48)
  }
}

private struct CommanderActivityTimeBlock: View {
  let label: String
  let value: String
  let accent: Color

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "clock.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(accent)
      Text(label)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(CommanderActivityTokens.textSecondary)
      Text(value)
        .font(.system(size: 15, weight: .bold).monospacedDigit())
        .foregroundStyle(CommanderActivityTokens.textPrimary)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.78)
    .fixedSize(horizontal: true, vertical: false)
  }
}

private struct CommanderIslandStateGlyph: View {
  let symbol: String
  let accent: Color

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(accent)
      .frame(width: 20, height: 20)
      .accessibilityHidden(true)
  }
}

private struct CommanderIslandEventTitle: View {
  let title: String
  let symbol: String
  let accent: Color

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(accent)
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(CommanderActivityTokens.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct CommanderIslandUpcomingDetails: View {
  let location: String?
  let startAt: Date
  let accent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Text("Následuje za")
          .font(.caption.bold())
          .foregroundStyle(accent)
        Spacer(minLength: 8)
        Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
          .font(.subheadline.bold().monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
      }
      HStack(spacing: 6) {
        if let location, !location.isEmpty {
          Label(location, systemImage: "mappin.circle.fill")
            .foregroundStyle(CommanderActivityTokens.textSecondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "clock.fill")
          .foregroundStyle(accent)
        Text("Začátek")
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(startAt, style: .time)
          .fontWeight(.bold)
          .monospacedDigit()
          .foregroundStyle(CommanderActivityTokens.textPrimary)
      }
      .font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(CommanderActivityTokens.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(accent.opacity(0.42), lineWidth: 1)
    }
  }
}

private struct CommanderIslandDetails: View {
  let location: String?
  let status: String?
  let statusAccent: Color
  let timeLabel: String
  let timeValue: String
  let timeAccent: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let location, !location.isEmpty {
        Label(location, systemImage: "mappin.circle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
      }
      HStack(spacing: 7) {
        if let status {
          Text(status)
            .fontWeight(.bold)
            .foregroundStyle(statusAccent)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "clock.fill")
          .foregroundStyle(timeAccent)
        Text(timeLabel)
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(timeValue)
          .fontWeight(.bold)
          .monospacedDigit()
          .foregroundStyle(CommanderActivityTokens.textPrimary)
      }
      .font(.caption)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(CommanderActivityTokens.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(CommanderActivityTokens.panelStroke.opacity(0.45), lineWidth: 1)
    }
  }
}

private struct CommanderActivityCardStyle: ViewModifier {
  let accent: Color

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 15)
      .padding(.vertical, 13)
      .frame(
        maxWidth: .infinity,
        minHeight: CommanderActivityTokens.lockScreenMinHeight,
        alignment: .leading
      )
      .background {
        ZStack {
          CommanderActivityTokens.backgroundGradient
          LinearGradient(
            colors: [accent.opacity(0.31), accent.opacity(0.13), accent.opacity(0.22)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          RadialGradient(
            colors: [accent.opacity(0.18), .clear],
            center: .topLeading,
            startRadius: 12,
            endRadius: 220
          )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: CommanderActivityTokens.cardRadius)
          .strokeBorder(accent.opacity(0.88), lineWidth: 1.6)
      }
  }
}

private extension View {
  func commanderActivityCard(accent: Color) -> some View {
    modifier(CommanderActivityCardStyle(accent: accent))
  }
}

private struct CommanderAlarmExpandedTiming: View {
  let mode: AlarmPresentationState.Mode

  @ViewBuilder
  var body: some View {
    if !mode.isAlert {
      CommanderAlarmCountdownContext(mode: mode, showsLabel: false, size: .regular)
    }
  }
}

private struct CommanderAlarmCountdownContext: View {
  let mode: AlarmPresentationState.Mode
  let showsLabel: Bool
  let size: CommanderTimingSize

  private var accent: Color { CommanderActivityTokens.departureAccent(for: mode) }

  var body: some View {
    VStack(alignment: size == .large ? .leading : .trailing, spacing: 2) {
      if showsLabel {
        Text(label)
          .font(size == .large ? .system(size: 20, weight: .bold) : .caption.weight(.bold))
          .foregroundStyle(accent)
          .lineLimit(1)
      }
      CommanderAlarmCountdown(mode: mode)
        .font(countdownFont)
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.74)
    }
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(1)
  }

  private var countdownFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .system(size: 38, weight: .heavy, design: .rounded).monospacedDigit()
    }
  }

  private var label: String {
    switch mode {
    case .alert: return "Vyrazit teď"
    case .countdown, .paused: return "Odchod za"
    @unknown default: return "Odchod za"
    }
  }
}

private struct CommanderProcedureTiming: View {
  let endAt: Date
  let isStale: Bool
  let accent: Color
  let size: CommanderTimingSize

  var body: some View {
    Group {
      if isStale {
        Image(systemName: "checkmark.circle.fill")
          .font(size == .large ? .title2 : .headline)
          .foregroundStyle(accent)
      } else {
        VStack(alignment: .trailing, spacing: 1) {
          if size == .large {
            Text("Do konce")
              .font(.caption.weight(.semibold))
              .foregroundStyle(CommanderActivityTokens.textSecondary)
          }
          Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<endAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
            .font(timingFont)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
      }
    }
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(1)
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
    }
  }
}

private struct CommanderDepartureBridgeTiming: View {
  let startAt: Date
  let size: CommanderTimingSize
  var isDepartureCountdown = false

  var body: some View {
    Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
      .font(timingFont)
      .foregroundStyle(isDepartureCountdown ? CommanderActivityTokens.amber : CommanderActivityTokens.criticalRed)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .fixedSize(horizontal: true, vertical: false)
      .layoutPriority(1)
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
    }
  }
}

private struct CommanderUpcomingTiming: View {
  let startAt: Date
  let accent: Color
  let size: CommanderTimingSize

  var body: some View {
    Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<startAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
      .font(timingFont)
      .foregroundStyle(accent)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .fixedSize(horizontal: true, vertical: false)
      .layoutPriority(1)
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
    }
  }
}

private struct CommanderNextDepartureTiming: View {
  let leaveAt: Date
  let size: CommanderTimingSize

  var body: some View {
    Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<leaveAt, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
      .font(timingFont)
      .foregroundStyle(CommanderActivityTokens.freeBlue)
      .lineLimit(1)
      .minimumScaleFactor(0.72)
      .fixedSize(horizontal: true, vertical: false)
      .layoutPriority(1)
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
    }
  }
}

private enum CommanderTimingSize {
  case compact, regular, large
}

private enum CommanderProcedureText {
  static func status(kind: ScheduleKind, isStale: Bool) -> String {
    if isStale { return kind == .meal ? "Jídlo skončilo" : "Procedura skončila" }
    return kind == .meal ? "Právě jídlo" : "Právě probíhá"
  }
}

private struct CommanderAlarmCountdown: View {
  let mode: AlarmPresentationState.Mode

  @ViewBuilder
  var body: some View {
    switch mode {
    case .countdown(let countdown):
      Text(.currentDate, format: .timer(countingDownIn: Date.distantPast..<countdown.fireDate, showsHours: true, maxFieldCount: 2, maxPrecision: .seconds(1)))
    case .paused(let paused):
      Text(CommanderAlarmTime.duration(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
    case .alert:
      Text("Teď")
    @unknown default:
      Text("--:--")
    }
  }
}

private struct CommanderActivityBrandMark: View {
  let size: CGFloat

  var body: some View {
    CommanderBrandAssets.circularMark
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

private struct CommanderActivityEventBadge: View {
  let symbol: String
  let accent: Color
  let size: CGFloat

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(accent)
      .frame(width: size, height: size)
      .background(accent.opacity(0.14), in: Circle())
      .overlay { Circle().strokeBorder(accent.opacity(0.42), lineWidth: 1) }
      .accessibilityHidden(true)
  }
}

private extension AlarmPresentationState.Mode {
  var isAlert: Bool {
    if case .alert = self { return true }
    return false
  }
}

private enum CommanderAlarmTime {
  static func startTime(from localISO: String?) -> String {
    guard let localISO, localISO.count >= 16 else { return "--:--" }
    let start = localISO.index(localISO.startIndex, offsetBy: 11)
    let end = localISO.index(start, offsetBy: 5)
    return String(localISO[start..<end])
  }

  static func startDate(from localISO: String?) -> Date? {
    guard let localISO else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.date(from: localISO)
  }

  static func duration(_ seconds: TimeInterval) -> String {
    let remaining = max(0, Int(seconds.rounded(.up)))
    return String(format: "%02d:%02d", remaining / 60, remaining % 60)
  }
}

private extension Color {
  init(commanderActivityHex: String) {
    let value = commanderActivityHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255,
      green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255
    )
  }
}

#if DEBUG
private enum CommanderActivityPreviewFixtures {
  private static let previewTimeZone = TimeZone(identifier: "Europe/Prague")!

  private static func localISO(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = previewTimeZone
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }

  static var departureAlarmAttributes: AlarmAttributes<CommanderAlarmMetadata> {
    let now = Date()
    let leaveAt = now.addingTimeInterval(10 * 60)
    let startAt = leaveAt.addingTimeInterval(10 * 60)
    return AlarmAttributes(
      presentation: AlarmPresentation(
        alert: AlarmPresentation.Alert(title: "Vyrazit na Masáž"),
        countdown: AlarmPresentation.Countdown(title: "Odchod za Masáž")
      ),
      metadata: CommanderAlarmMetadata(
        stableId: "preview-massage-departure",
        scheduleVersion: 1,
        iconKey: "massage",
        title: "Masáž",
        location: "Rehabilitace, box 3",
        kind: .procedure,
        startAt: localISO(startAt),
        leaveAt: localISO(leaveAt),
        endAt: localISO(startAt.addingTimeInterval(30 * 60))
      ),
      tintColor: .orange
    )
  }

  static var leaveNowAlarmAttributes: AlarmAttributes<CommanderAlarmMetadata> {
    let now = Date()
    let startAt = now.addingTimeInterval(10 * 60)
    return AlarmAttributes(
      presentation: AlarmPresentation(
        alert: AlarmPresentation.Alert(title: "Vyrazit na Masáž"),
        countdown: AlarmPresentation.Countdown(title: "Odchod za Masáž")
      ),
      metadata: CommanderAlarmMetadata(
        stableId: "preview-massage-leave-now",
        scheduleVersion: 1,
        iconKey: "massage",
        title: "Masáž",
        location: "Rehabilitace, box 3",
        kind: .procedure,
        startAt: localISO(startAt),
        leaveAt: localISO(now),
        endAt: localISO(startAt.addingTimeInterval(30 * 60))
      ),
      tintColor: .orange
    )
  }

  static var departureInTenMinutes: AlarmPresentationState {
    let now = Date()
    return AlarmPresentationState(
      alarmID: UUID(uuidString: "A1100000-0000-0000-0000-000000000010")!,
      mode: .countdown(
        AlarmPresentationState.Mode.Countdown(
          totalCountdownDuration: 600,
          previouslyElapsedDuration: 0,
          startDate: now,
          fireDate: now.addingTimeInterval(600)
        )
      )
    )
  }

  static let leaveNow = AlarmPresentationState(
    alarmID: UUID(uuidString: "A1100000-0000-0000-0000-000000000000")!,
    mode: .alert(
      AlarmPresentationState.Mode.Alert(
        time: Alarm.Schedule.Relative.Time(hour: 13, minute: 50)
      )
    )
  )

  static var procedureAttributes: CommanderProcedureLiveActivityAttributes {
    let now = Date()
    return CommanderProcedureLiveActivityAttributes(
      stableId: "preview-current-massage",
      scheduleVersion: 1,
      iconKey: "massage",
      title: "Masáž",
      location: "Rehabilitace, box 3",
      kind: .procedure,
      startAt: now.addingTimeInterval(-11 * 60),
      endAt: now.addingTimeInterval(19 * 60)
    )
  }

  static var mealAttributes: CommanderProcedureLiveActivityAttributes {
    let now = Date()
    return CommanderProcedureLiveActivityAttributes(
      stableId: "preview-current-lunch",
      scheduleVersion: 1,
      iconKey: "meal",
      title: "Oběd",
      location: "Jídelna",
      kind: .meal,
      startAt: now.addingTimeInterval(-10 * 60),
      endAt: now.addingTimeInterval(35 * 60)
    )
  }

  static var departureBridgeAttributes: CommanderProcedureLiveActivityAttributes {
    let now = Date()
    return CommanderProcedureLiveActivityAttributes(
      stableId: "preview-departure-bridge",
      scheduleVersion: 1,
      iconKey: "massage",
      title: "Masáž",
      location: "Rehabilitace, box 3",
      kind: .procedure,
      startAt: now.addingTimeInterval(7 * 60),
      endAt: now.addingTimeInterval(37 * 60)
    )
  }

  static let current = CommanderProcedureLiveActivityAttributes.ContentState(
    projectionRevision: 1
  )

  static let departureBridge = CommanderProcedureLiveActivityAttributes.ContentState(
    projectionRevision: -1,
    phase: .departureBridge
  )
}

#Preview("Lock Screen - Odchod za 10 min", as: .content, using: CommanderActivityPreviewFixtures.departureAlarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}

#Preview("Lock Screen - Vyrazit ted", as: .content, using: CommanderActivityPreviewFixtures.leaveNowAlarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.leaveNow
}

#Preview("Lock Screen - Prave probiha procedura", as: .content, using: CommanderActivityPreviewFixtures.procedureAttributes) {
  LazenskyCommanderProcedureLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.current
}

#Preview("Lock Screen - Prave probiha jidlo", as: .content, using: CommanderActivityPreviewFixtures.mealAttributes) {
  LazenskyCommanderProcedureLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.current
}

#Preview("Lock Screen - Vyrazit po zastaveni", as: .content, using: CommanderActivityPreviewFixtures.departureBridgeAttributes) {
  LazenskyCommanderProcedureLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureBridge
}

#Preview("Dynamic Island - Compact odchod", as: .dynamicIsland(.compact), using: CommanderActivityPreviewFixtures.departureAlarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}

#Preview("Dynamic Island - Expanded Masaz", as: .dynamicIsland(.expanded), using: CommanderActivityPreviewFixtures.departureAlarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}
#endif
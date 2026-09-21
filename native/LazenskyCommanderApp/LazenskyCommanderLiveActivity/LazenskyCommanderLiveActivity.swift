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
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
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
          CommanderActivityBrandMark(size: 22)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.state.mode.isAlert ? "VYRAZIT TEĎ" : "ODCHOD ZA")
              .font(.caption2.weight(.heavy))
              .foregroundStyle(departureAccent)
              .lineLimit(1)
            CommanderIslandEventTitle(title: title, symbol: eventSymbol, accent: eventAccent)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderAlarmIslandCountdown(mode: context.state.mode, size: .expanded)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CommanderIslandDetails(
            location: metadata?.location,
            status: nil,
            statusAccent: departureAccent,
            timeLabel: "Začátek",
            timeValue: CommanderAlarmTime.startTime(from: metadata?.startAt),
            timeAccent: eventAccent
          )
        }
      } compactLeading: {
        CommanderCompactBrandEventMark(symbol: eventSymbol, accent: eventAccent)
      } compactTrailing: {
        CommanderAlarmIslandCountdown(mode: context.state.mode, size: .compact)
      } minimal: {
        CommanderAlarmIslandCountdown(mode: context.state.mode, size: .minimal)
      }
      .keylineTint(departureAccent)
      .contentMargins(.horizontal, 4, for: .expanded)
      .contentMargins(.horizontal, 2, for: .compactLeading)
      .contentMargins(.horizontal, 2, for: .compactTrailing)
    }
    .supplementalActivityFamilies([.small])
  }
}

struct LazenskyCommanderProcedureLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CommanderProcedureLiveActivityAttributes.self) { context in
      CommanderProcedureActivityContent(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    } dynamicIsland: { context in
      let fallback = context.isStale ? context.attributes.nextEvent : nil
      let keylineTitle = fallback?.title ?? context.attributes.title
      let keylineAccent = CommanderActivityTokens.eventAccent(
        kind: fallback?.kind ?? context.attributes.kind,
        iconKey: fallback?.iconKey ?? context.attributes.iconKey,
        title: keylineTitle
      )

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderActivityBrandMark(size: 22)
        }
        DynamicIslandExpandedRegion(.center) {
          CommanderProcedureIslandCenter(context: context)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderProcedureIslandTiming(context: context, size: .regular)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CommanderProcedureIslandBottom(context: context)
        }
      } compactLeading: {
        CommanderProcedureIslandMark(context: context)
      } compactTrailing: {
        CommanderProcedureIslandTiming(context: context, size: .compact)
      } minimal: {
        CommanderProcedureIslandTiming(context: context, size: .compact)
      }
      .keylineTint(keylineAccent)
      .contentMargins(.horizontal, 4, for: .expanded)
      .contentMargins(.horizontal, 2, for: .compactLeading)
      .contentMargins(.horizontal, 2, for: .compactTrailing)
    }
    .supplementalActivityFamilies([.small])
  }
}

private struct CommanderProcedureIslandCenter: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let eventSymbol = CommanderActivityTokens.eventSymbol(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let stateAccent = display.phase == .ended
        ? CommanderActivityTokens.textSecondary
        : eventAccent

      VStack(alignment: .leading, spacing: 2) {
        Text(display.status.uppercased())
          .font(.caption2.weight(.heavy))
          .foregroundStyle(stateAccent)
          .lineLimit(1)
        CommanderIslandEventTitle(
          title: display.title,
          symbol: eventSymbol,
          accent: eventAccent
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

private struct CommanderProcedureIslandTiming: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>
  let size: CommanderTimingSize

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let stateAccent = display.phase == .ended
        ? CommanderActivityTokens.textSecondary
        : eventAccent
      CommanderProcedurePhaseTiming(
        display: display,
        accent: stateAccent,
        size: size
      )
    }
  }
}

private struct CommanderProcedureIslandBottom: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let stateAccent = display.phase == .ended
        ? CommanderActivityTokens.textSecondary
        : eventAccent
      CommanderIslandDetails(
        location: display.location,
        status: nil,
        statusAccent: stateAccent,
        timeLabel: display.timeLabel,
        timeValue: display.timeValue,
        timeAccent: eventAccent
      )
    }
  }
}

private struct CommanderProcedureIslandMark: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let accent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let symbol = CommanderActivityTokens.eventSymbol(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      CommanderCompactBrandEventMark(symbol: symbol, accent: accent)
    }
  }
}

private struct CommanderAlarmActivityContent: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>
  @Environment(\.activityFamily) private var activityFamily

  @ViewBuilder
  var body: some View {
    if activityFamily == .small {
      CommanderAlarmWatchLiveActivityView(context: context)
    } else {
      CommanderAlarmLockScreenView(context: context)
    }
  }
}

private struct CommanderProcedureActivityContent: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>
  @Environment(\.activityFamily) private var activityFamily

  @ViewBuilder
  var body: some View {
    if activityFamily == .small {
      CommanderProcedureWatchLiveActivityView(context: context)
    } else {
      CommanderProcedureLockScreenView(context: context)
    }
  }
}

private struct CommanderAlarmWatchLiveActivityView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  private var metadata: CommanderAlarmMetadata? { context.attributes.metadata }
  private var title: String { metadata?.title ?? "Lázeňský Commander" }
  private var eventAccent: Color {
    CommanderActivityTokens.eventAccent(kind: metadata?.kind, iconKey: metadata?.iconKey, title: title)
  }
  private var departureAccent: Color { CommanderActivityTokens.departureAccent(for: context.state.mode) }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        CommanderActivityBrandMark(size: 18)
        Text(context.state.mode.isAlert ? "VYRAZIT TEĎ" : "Odchod za")
          .font(.caption.weight(.bold))
          .foregroundStyle(departureAccent)
        Spacer(minLength: 4)
        CommanderAlarmIslandCountdown(mode: context.state.mode, size: .compact)
      }
      Text(title)
        .font(.headline)
        .foregroundStyle(eventAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if let location = metadata?.location, !location.isEmpty {
        Text(location)
          .font(.caption2)
          .foregroundStyle(CommanderActivityTokens.locationBlue)
          .lineLimit(1)
      }
    }
    .padding(8)
  }
}

private struct CommanderProcedureWatchLiveActivityView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let stateAccent = display.phase == .ended
        ? CommanderActivityTokens.textSecondary
        : eventAccent

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          CommanderActivityBrandMark(size: 18)
          Text(display.status)
            .font(.caption.weight(.bold))
            .foregroundStyle(stateAccent)
          Spacer(minLength: 4)
          CommanderProcedurePhaseTiming(
            display: display,
            accent: stateAccent,
            size: .compact
          )
        }
        Text(display.title)
          .font(.headline)
          .foregroundStyle(eventAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        if !display.location.isEmpty {
          Text(display.location)
            .font(.caption2)
            .foregroundStyle(CommanderActivityTokens.locationBlue)
            .lineLimit(1)
        }
        Text("\(display.timeLabel) \(display.timeValue)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
      }
      .padding(8)
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

  var body: some View {
    TimelineView(.explicit(CommanderProcedureDisplay.timelineDates(attributes: context.attributes))) { timeline in
      let display = CommanderProcedureDisplay.resolve(attributes: context.attributes, at: timeline.date)
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let eventSymbol = CommanderActivityTokens.eventSymbol(
        kind: display.kind,
        iconKey: display.iconKey,
        title: display.title
      )
      let stateAccent = display.phase == .ended
        ? CommanderActivityTokens.textSecondary
        : eventAccent

      VStack(spacing: 9) {
        CommanderProcedureDisplayHero(display: display, accent: stateAccent)
        CommanderActivityDivider(accent: stateAccent)
        CommanderActivityEventFooter(
          title: display.title,
          location: display.location,
          symbol: eventSymbol,
          eventAccent: eventAccent,
          timeLabel: display.timeLabel,
          timeValue: display.timeValue,
          timeAccent: stateAccent
        )
      }
      .commanderActivityCard(accent: stateAccent)
    }
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
            Text(startDate, style: .timer)
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

private struct CommanderProcedureDisplayHero: View {
  let display: CommanderProcedureDisplay
  let accent: Color

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Text(display.status)
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)

        switch display.phase {
        case .upcoming:
          Text(display.startAt, style: .timer)
            .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        case .active:
          Text(display.endAt, style: .timer)
            .font(.system(size: CommanderActivityTokens.heroTimeSize, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        case .ended:
          Text("Skončilo")
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundStyle(CommanderActivityTokens.textPrimary)
            .lineLimit(1)
        }
      }
      .frame(width: CommanderActivityTokens.heroWidth, alignment: .center)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        CommanderActivityBrandMark(size: 74)
          .frame(width: 82, alignment: .leading)

        Spacer(minLength: 0)

        CommanderProcedureDisplaySideStatus(display: display, accent: accent)
          .frame(width: 72, alignment: .center)
      }
    }
    .frame(minHeight: CommanderActivityTokens.heroMinHeight)
  }
}

private struct CommanderProcedureDisplaySideStatus: View {
  let display: CommanderProcedureDisplay
  let accent: Color

  var body: some View {
    switch display.phase {
    case .upcoming:
      VStack(spacing: 2) {
        Image(systemName: "clock.badge")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(accent)
        Text("Začátek")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(display.startAt.formatted(date: .omitted, time: .shortened))
          .font(.system(size: 12, weight: .bold).monospacedDigit())
          .foregroundStyle(accent)
      }
    case .active:
      VStack(alignment: .center, spacing: 0) {
        Text("Do konce")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
        Text(display.endAt, style: .timer)
          .font(.system(size: 18, weight: .bold).monospacedDigit())
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .multilineTextAlignment(.center)
    case .ended:
      VStack(spacing: 2) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(accent)
        Text("Skončilo")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
      }
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
          .foregroundStyle(eventAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.84)
        if let location, !location.isEmpty {
          Label(location, systemImage: "mappin.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.locationBlue)
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
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
          .foregroundStyle(CommanderActivityTokens.locationBlue)
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

private enum CommanderAlarmIslandCountdownSize {
  case compact, minimal, expanded
}

private struct CommanderAlarmIslandCountdown: View {
  let mode: AlarmPresentationState.Mode
  let size: CommanderAlarmIslandCountdownSize

  private var accent: Color { CommanderActivityTokens.departureAccent(for: mode) }

  var body: some View {
    CommanderAlarmCountdown(mode: mode)
      .font(font)
      .foregroundStyle(accent)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.68)
      .frame(width: timerWidth, alignment: .trailing)
      .fixedSize(horizontal: true, vertical: false)
      .layoutPriority(2)
  }

  private var timerWidth: CGFloat? {
    guard !mode.isAlert else { return nil }
    switch size {
    case .compact: return 54
    case .minimal: return 42
    case .expanded: return nil
    }
  }

  private var font: Font {
    switch size {
    case .compact: return .system(size: 14, weight: .heavy, design: .rounded)
    case .minimal: return .system(size: 12, weight: .heavy, design: .rounded)
    case .expanded: return .system(size: 24, weight: .heavy, design: .rounded)
    }
  }
}

private struct CommanderCompactBrandEventMark: View {
  let symbol: String
  let accent: Color

  var body: some View {
    HStack(spacing: 2) {
      CommanderActivityBrandMark(size: 18)
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(accent)
        .frame(width: 10, height: 10)
    }
    .fixedSize(horizontal: true, vertical: false)
    .accessibilityHidden(true)
  }
}

private enum CommanderTimingSize {
  case compact, regular, large
}

private enum CommanderProcedureVisualPhase {
  case upcoming
  case active
  case ended
}

private struct CommanderProcedureDisplay {
  let title: String
  let location: String
  let kind: ScheduleKind
  let iconKey: String
  let startAt: Date
  let endAt: Date
  let phase: CommanderProcedureVisualPhase

  static func resolve(
    attributes: CommanderProcedureLiveActivityAttributes,
    at date: Date
  ) -> CommanderProcedureDisplay {
    let current = CommanderProcedureDisplay(
      title: attributes.title,
      location: attributes.location,
      kind: attributes.kind,
      iconKey: attributes.iconKey,
      startAt: attributes.startAt,
      endAt: attributes.endAt,
      phase: phase(at: date, startAt: attributes.startAt, endAt: attributes.endAt)
    )
    guard date >= attributes.endAt,
          let next = attributes.nextEvent,
          let nextStart = CommanderAlarmTime.startDate(from: next.startAt),
          let nextEnd = CommanderAlarmTime.startDate(from: next.endAt)
    else { return current }

    return CommanderProcedureDisplay(
      title: next.title,
      location: next.location,
      kind: next.kind,
      iconKey: next.iconKey,
      startAt: nextStart,
      endAt: nextEnd,
      phase: phase(at: date, startAt: nextStart, endAt: nextEnd)
    )
  }

  static func timelineDates(
    attributes: CommanderProcedureLiveActivityAttributes
  ) -> [Date] {
    var dates = [attributes.startAt, attributes.endAt]
    if let next = attributes.nextEvent {
      if let start = CommanderAlarmTime.startDate(from: next.startAt) { dates.append(start) }
      if let end = CommanderAlarmTime.startDate(from: next.endAt) { dates.append(end) }
    }
    return Array(Set(dates)).sorted()
  }

  var status: String {
    switch phase {
    case .upcoming:
      return "Začíná za"
    case .active:
      return kind == .meal ? "Právě jídlo" : "Právě probíhá"
    case .ended:
      return kind == .meal ? "Jídlo skončilo" : "Procedura skončila"
    }
  }

  var timeLabel: String {
    switch phase {
    case .upcoming: return "Začátek"
    case .active, .ended: return "Konec"
    }
  }

  var timeValue: String {
    switch phase {
    case .upcoming:
      return startAt.formatted(date: .omitted, time: .shortened)
    case .active, .ended:
      return endAt.formatted(date: .omitted, time: .shortened)
    }
  }

  private static func phase(at date: Date, startAt: Date, endAt: Date) -> CommanderProcedureVisualPhase {
    if date < startAt { return .upcoming }
    if date < endAt { return .active }
    return .ended
  }
}

private struct CommanderProcedurePhaseTiming: View {
  let display: CommanderProcedureDisplay
  let accent: Color
  let size: CommanderTimingSize

  var body: some View {
    Group {
      switch display.phase {
      case .upcoming:
        countdown(to: display.startAt, label: "Začíná za")
      case .active:
        countdown(to: display.endAt, label: "Do konce")
      case .ended:
        Image(systemName: "checkmark.circle.fill")
          .font(size == .large ? .title2 : .headline)
          .foregroundStyle(accent)
      }
    }
    .frame(width: timingWidth, alignment: .trailing)
    .fixedSize(horizontal: true, vertical: false)
    .layoutPriority(1)
  }

  @ViewBuilder
  private func countdown(to date: Date, label: String) -> some View {
    VStack(alignment: .trailing, spacing: 1) {
      if size == .large || size == .regular {
        Text(label)
          .font(size == .large ? .caption.weight(.semibold) : .caption2.weight(.semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
          .lineLimit(1)
      }
      Text(date, style: .timer)
        .font(timingFont)
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
  }

  private var timingWidth: CGFloat? {
    guard display.phase != .ended, size == .compact else { return nil }
    return 54
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
    }
  }
}

private struct CommanderAlarmCountdown: View {
  let mode: AlarmPresentationState.Mode

  @ViewBuilder
  var body: some View {
    switch mode {
    case .countdown(let countdown):
      Text(countdown.fireDate, style: .timer)
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
      leaveAt: now.addingTimeInterval(-13 * 60),
      startAt: now.addingTimeInterval(-11 * 60),
      endAt: now.addingTimeInterval(19 * 60),
      nextEvent: nil
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
      leaveAt: now.addingTimeInterval(-12 * 60),
      startAt: now.addingTimeInterval(-10 * 60),
      endAt: now.addingTimeInterval(35 * 60),
      nextEvent: nil
    )
  }


  static let current = CommanderProcedureLiveActivityAttributes.ContentState(
    projectionRevision: 1
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
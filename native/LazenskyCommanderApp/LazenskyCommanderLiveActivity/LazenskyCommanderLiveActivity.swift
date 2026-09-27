import ActivityKit
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
  static let amber = CommanderBrandAssets.Presentation.countdown
  static let freeBlue = Color(commanderActivityHex: CommanderBrandAssets.Colors.freeBlue)
  static let procedureCyan = Color(commanderActivityHex: CommanderBrandAssets.Colors.procedureCyan)
  static let urgentOrange = Color(commanderActivityHex: CommanderBrandAssets.Colors.urgentOrange)
  static let criticalRed = CommanderBrandAssets.Presentation.alert
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

  static func eventIconKey(kind: ScheduleKind?, iconKey: String?, title: String) -> String {
    CommanderBrandAssets.approvedIcon(iconKey: iconKey, title: title)?.key ?? ""
  }

  static func procedureStateAccent(
    mode: CommanderLiveActivityPresentationMode,
    isStale: Bool,
    eventAccent: Color
  ) -> Color {
    isStale ? CommanderBrandAssets.Presentation.neutral : eventAccent
  }
}

@main
struct LazenskyCommanderLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LazenskyCommanderProcedureLiveActivity()
    LazenskyCommanderHomeWidget()
    LazenskyCommanderDayOverviewWidget()
    LazenskyCommanderProcedureCountWidget()
  }
}

struct LazenskyCommanderProcedureLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CommanderProcedureLiveActivityAttributes.self) { context in
      CommanderProcedureActivityContent(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    } dynamicIsland: { context in
      let preview = CommanderProcedureDisplay.resolve(
        attributes: context.attributes,
        state: context.state,
        isStale: context.isStale
      )
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: preview.kind,
        iconKey: preview.iconKey,
        title: preview.title
      )
      let keylineAccent = CommanderActivityTokens.procedureStateAccent(
        mode: preview.presentationMode,
        isStale: preview.isStale,
        eventAccent: eventAccent
      )
      let isVisualProbe = context.attributes.stableId == "physicalAcceptance.visualProbe"

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if isVisualProbe {
            Text("LC").font(.headline).foregroundStyle(.yellow)
          } else {
            CommanderActivityBrandMark(size: 32)
          }
        }
        DynamicIslandExpandedRegion(.center) {
          if isVisualProbe {
            Text("TEST").font(.headline).foregroundStyle(.yellow)
          } else {
            CommanderProcedureIslandCenter(context: context)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          if isVisualProbe {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
          } else {
            CommanderProcedureIslandArtwork(context: context)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          if isVisualProbe {
            Text("Dynamic Island").font(.caption).foregroundStyle(.white)
          } else {
            CommanderProcedureIslandBottom(context: context)
          }
        }
      } compactLeading: {
        if isVisualProbe {
          Text("LC").font(.caption2.bold()).foregroundStyle(.yellow)
        } else {
          CommanderCompactBrandEventMark()
        }
      } compactTrailing: {
        if isVisualProbe {
          Text("OK").font(.caption2.bold()).foregroundStyle(.yellow)
        } else {
          CommanderProcedureIslandTiming(context: context, size: .compact)
        }
      } minimal: {
        if isVisualProbe {
          Text("LC").font(.caption2.bold()).foregroundStyle(.yellow)
        } else {
          CommanderProcedureIslandTiming(context: context, size: .minimal)
        }
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
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    let eventAccent = CommanderActivityTokens.eventAccent(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    Text(display.status)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(CommanderActivityTokens.procedureStateAccent(
        mode: display.presentationMode,
        isStale: display.isStale,
        eventAccent: eventAccent
      ))
      .lineLimit(1)
      .minimumScaleFactor(0.85)
  }
}

private struct CommanderProcedureIslandTiming: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>
  let size: CommanderTimingSize

  var body: some View {
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    let eventAccent = CommanderActivityTokens.eventAccent(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    let stateAccent = CommanderActivityTokens.procedureStateAccent(
      mode: display.presentationMode,
      isStale: display.isStale,
      eventAccent: eventAccent
    )
    CommanderProcedurePhaseTiming(
      display: display,
      accent: stateAccent,
      size: size
    )
  }
}

private struct CommanderProcedureIslandBottom: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    let eventAccent = CommanderActivityTokens.eventAccent(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    CommanderExpandedEventBody(
      title: display.title,
      iconKey: display.iconKey,
      kind: display.kind,
      location: display.location,
      nextEvent: display.nextEvent,
      nextEventLabel: display.nextEventLabel,
      stateAccent: CommanderActivityTokens.procedureStateAccent(
        mode: display.presentationMode,
        isStale: display.isStale,
        eventAccent: eventAccent
      )
    ) {
      CommanderPresentationClock(display: display)
    }
  }
}

private struct CommanderProcedureIslandArtwork: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    CommanderProcedureArtwork(iconKey: display.iconKey, title: display.title, size: 32)
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

private struct CommanderProcedureWatchLiveActivityView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    let eventAccent = CommanderActivityTokens.eventAccent(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    CommanderSmartStackCard(
      status: display.status,
      title: display.title,
      iconKey: display.iconKey,
      kind: display.kind,
      timeLabel: display.timeLabel,
      timeValue: display.timeValue,
      stateAccent: CommanderActivityTokens.procedureStateAccent(
        mode: display.presentationMode,
        isStale: display.isStale,
        eventAccent: eventAccent
      )
    ) {
      CommanderPresentationClock(display: display)
    }
  }
}

/// Compact 49 mm Smart Stack content is about 191 x 81.5 pt. The timer and title
/// occupy different rows, so a long title can never squeeze or cover the clock.
private struct CommanderSmartStackCard<Clock: View>: View {
  let status: String
  let title: String
  let iconKey: String?
  let kind: ScheduleKind?
  let timeLabel: String
  let timeValue: String
  let stateAccent: Color
  @ViewBuilder var clock: () -> Clock

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 2) {
        HStack(spacing: 6) {
          CommanderActivityBrandMark(size: 30)
          VStack(spacing: 0) {
            Text(status)
              .font(.system(size: 11, weight: .bold))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            clock()
              .font(.system(size: 29, weight: .heavy, design: .rounded).monospacedDigit())
              .lineLimit(1)
              .minimumScaleFactor(0.72)
              .frame(maxWidth: .infinity)
              .frame(height: 32)
              .layoutPriority(1)
          }
          .foregroundStyle(stateAccent)
        }
        Rectangle().fill(stateAccent.opacity(0.55)).frame(height: 0.5)
        HStack(spacing: 5) {
          CommanderProcedureArtwork(iconKey: iconKey, title: title, size: 22)
          VStack(alignment: .leading, spacing: 0) {
            Text(title)
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Color(commanderPresentationHex: CommanderBrandAssets.procedureAccentHex(
                iconKey: iconKey,
                title: title,
                isMeal: kind == .meal
              )))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .truncationMode(.tail)
              .frame(maxWidth: .infinity, alignment: .leading)
            if geometry.size.height >= 78 && geometry.size.width >= 170 {
              Text(timeLabel + " " + timeValue)
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            }
          }
        }
      }
      .padding(5)
      .frame(width: geometry.size.width, height: geometry.size.height)
      .background(LinearGradient(colors: [stateAccent.opacity(0.18), .black], startPoint: .topLeading, endPoint: .bottomTrailing))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(stateAccent.opacity(0.8), lineWidth: 1))
    }
    .accessibilityElement(children: .combine)
  }
}

private struct CommanderExpandedEventBody<Clock: View>: View {
  let title: String
  let iconKey: String?
  let kind: ScheduleKind?
  let location: String
  let nextEvent: CommanderAlarmEventSnapshot?
  let nextEventLabel: String
  let stateAccent: Color
  @ViewBuilder var clock: () -> Clock

  var body: some View {
    VStack(spacing: 3) {
      clock()
        .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
        .foregroundStyle(stateAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .layoutPriority(2)
      Text(title)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Color(commanderPresentationHex: CommanderBrandAssets.procedureAccentHex(
          iconKey: iconKey,
          title: title,
          isMeal: kind == .meal
        )))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity)
      if !location.isEmpty {
        Label(location, systemImage: "mappin.circle.fill")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(stateAccent.opacity(0.15), in: Capsule())
      }
      if let nextEvent {
        CommanderNextEventLine(
          event: nextEvent,
          compact: true,
          label: nextEventLabel
        )
      }
    }
    .padding(.bottom, 4)
  }
}

private struct CommanderClampedCountdown: View {
  let target: Date

  private var interval: Range<Date> {
    target.addingTimeInterval(-24 * 60 * 60)..<target
  }

  var body: some View {
    Text(
      .currentDate,
      format: .timer(
        countingDownIn: interval,
        showsHours: true,
        maxFieldCount: 3,
        maxPrecision: .seconds(1)
      )
    )
  }
}

private struct CommanderPresentationClock: View {
  let display: CommanderProcedureDisplay

  @ViewBuilder var body: some View {
    if display.isStale {
      Text("Skončilo")
    } else {
      CommanderClampedCountdown(target: display.countdownTarget)
    }
  }
}

private struct CommanderProcedureLockScreenView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    let display = CommanderProcedureDisplay.resolve(
      attributes: context.attributes,
      state: context.state,
      isStale: context.isStale
    )
    let eventAccent = CommanderActivityTokens.eventAccent(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    let eventIconKey = CommanderActivityTokens.eventIconKey(
      kind: display.kind,
      iconKey: display.iconKey,
      title: display.title
    )
    let stateAccent = CommanderActivityTokens.procedureStateAccent(
      mode: display.presentationMode,
      isStale: display.isStale,
      eventAccent: eventAccent
    )

    VStack(spacing: 9) {
      CommanderProcedureDisplayHero(display: display, accent: stateAccent)
      CommanderActivityDivider(accent: stateAccent)
      CommanderActivityEventFooter(
        title: display.title,
        location: display.location,
        iconKey: eventIconKey,
        eventAccent: eventAccent,
        timeLabel: display.timeLabel,
        timeValue: display.timeValue,
        timeAccent: stateAccent,
        nextEvent: display.nextEvent,
        nextEventLabel: display.nextEventLabel
      )
    }
    .commanderActivityCard(accent: stateAccent)
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

        if display.isStale {
          Text("Skončilo")
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundStyle(CommanderActivityTokens.textPrimary)
            .lineLimit(1)
        } else {
          CommanderClampedCountdown(target: display.countdownTarget)
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
    if display.isStale {
      VStack(spacing: 2) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(accent)
        Text("Skončilo")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
      }
    } else {
      VStack(spacing: 2) {
        Image(systemName: display.presentationMode == .departureCountdown ? "figure.walk" : "clock.badge")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(accent)
        Text(display.timeLabel)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(display.timeValue)
          .font(.system(size: 12, weight: .bold).monospacedDigit())
          .foregroundStyle(accent)
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
  let iconKey: String
  let eventAccent: Color
  let timeLabel: String
  let timeValue: String
  let timeAccent: Color
  let nextEvent: CommanderAlarmEventSnapshot?
  let nextEventLabel: String

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      CommanderProcedureArtwork(iconKey: iconKey, title: title, size: 36)

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
        if let nextEvent {
          CommanderNextEventLine(
            event: nextEvent,
            compact: false,
            label: nextEventLabel
          )
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

private struct CommanderNextEventLine: View {
  let event: CommanderAlarmEventSnapshot
  let compact: Bool
  let label: String

  init(
    event: CommanderAlarmEventSnapshot,
    compact: Bool,
    label: String = "Další:"
  ) {
    self.event = event
    self.compact = compact
    self.label = label
  }

  private var accent: Color {
    CommanderActivityTokens.eventAccent(
      kind: event.kind,
      iconKey: event.iconKey,
      title: event.title
    )
  }

  private var iconKey: String {
    CommanderActivityTokens.eventIconKey(
      kind: event.kind,
      iconKey: event.iconKey,
      title: event.title
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 0 : 2) {
      HStack(spacing: 5) {
        Text(label)
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        CommanderProcedureArtwork(iconKey: iconKey, title: event.title, size: 18)
        Text(event.title)
          .fontWeight(.semibold)
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Spacer(minLength: 4)
        Text(CommanderAlarmTime.startTime(from: event.startAt))
          .fontWeight(.bold)
          .monospacedDigit()
          .foregroundStyle(CommanderActivityTokens.textPrimary)
      }

      if !event.location.isEmpty {
        Label(event.location, systemImage: "mappin.circle.fill")
          .font(compact ? .system(size: 8, weight: .medium) : .caption2.weight(.medium))
          .foregroundStyle(CommanderActivityTokens.locationBlue)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .padding(.leading, compact ? 18 : 23)
      }
    }
    .font(compact ? .caption2 : .system(size: 13, weight: .medium))
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

private struct CommanderCompactBrandEventMark: View {
  var body: some View {
    CommanderActivityBrandMark(size: 22)
      .accessibilityHidden(true)
  }
}

private enum CommanderTimingSize {
  case compact, minimal, regular, large
}

private struct CommanderProcedureDisplay {
  let title: String
  let location: String
  let kind: ScheduleKind
  let iconKey: String
  let leaveAt: Date
  let startAt: Date
  let endAt: Date
  let presentationMode: CommanderLiveActivityPresentationMode
  let isStale: Bool
  let nextEvent: CommanderAlarmEventSnapshot?
  let nextEventLabel: String

  private struct ResolvedEvent {
    let snapshot: CommanderAlarmEventSnapshot
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
  }

  static func resolve(
    attributes: CommanderProcedureLiveActivityAttributes,
    state: CommanderProcedureLiveActivityAttributes.ContentState,
    isStale: Bool = false
  ) -> CommanderProcedureDisplay {
    let events = resolvedEvents(attributes: attributes, state: state)
    let focusStableID = state.focusStableId ?? attributes.stableId
    let focusIndex = events.firstIndex(where: { $0.snapshot.stableId == focusStableID }) ?? 0

    if !events.isEmpty {
      let primary = events[focusIndex]
      let following = events.dropFirst(focusIndex + 1).first
      let followingIsConcurrent = following.map { $0.startAt < primary.endAt } ?? false
      return CommanderProcedureDisplay(
        title: primary.snapshot.title,
        location: primary.snapshot.location,
        kind: primary.snapshot.kind,
        iconKey: primary.snapshot.iconKey,
        leaveAt: primary.leaveAt,
        startAt: primary.startAt,
        endAt: primary.endAt,
        presentationMode: state.presentationMode,
        isStale: isStale,
        nextEvent: following?.snapshot,
        nextEventLabel: followingIsConcurrent ? "Současně:" : "Potom:"
      )
    }

    return CommanderProcedureDisplay(
      title: attributes.title,
      location: attributes.location,
      kind: attributes.kind,
      iconKey: attributes.iconKey,
      leaveAt: attributes.leaveAt,
      startAt: attributes.startAt,
      endAt: attributes.endAt,
      presentationMode: state.presentationMode,
      isStale: isStale,
      nextEvent: attributes.nextEvent,
      nextEventLabel: "Potom:"
    )
  }

  private static func resolvedEvents(
    attributes: CommanderProcedureLiveActivityAttributes,
    state: CommanderProcedureLiveActivityAttributes.ContentState
  ) -> [ResolvedEvent] {
    let snapshots: [CommanderAlarmEventSnapshot]
    if state.events.isEmpty {
      let seed = CommanderAlarmEventSnapshot(
        stableId: attributes.stableId,
        iconKey: attributes.iconKey,
        title: attributes.title,
        location: attributes.location,
        kind: attributes.kind,
        startAt: localISO(attributes.startAt),
        endAt: localISO(attributes.endAt),
        leaveAt: localISO(attributes.leaveAt)
      )
      snapshots = [seed, attributes.nextEvent].compactMap { $0 }
    } else {
      snapshots = state.events
    }

    return snapshots.compactMap { snapshot in
      guard let leaveAt = CommanderAlarmTime.startDate(from: snapshot.leaveAt),
            let startAt = CommanderAlarmTime.startDate(from: snapshot.startAt),
            let endAt = CommanderAlarmTime.startDate(from: snapshot.endAt)
      else { return nil }
      return ResolvedEvent(
        snapshot: snapshot,
        leaveAt: leaveAt,
        startAt: startAt,
        endAt: endAt
      )
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.snapshot.stableId < $1.snapshot.stableId
    }
  }

  private static func localISO(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }

  var status: String {
    if isStale { return "Skončilo" }
    switch presentationMode {
    case .departureCountdown:
      return "Vyrazit za"
    case .eventContext:
      return "Začátek " + startAt.formatted(date: .omitted, time: .shortened)
    }
  }

  var countdownTarget: Date {
    switch presentationMode {
    case .departureCountdown: return leaveAt
    case .eventContext: return endAt
    }
  }

  var countdownLabel: String {
    if isStale { return "" }
    switch presentationMode {
    case .departureCountdown: return "Do odchodu"
    case .eventContext: return "Do konce"
    }
  }

  var timeLabel: String {
    if isStale { return "Konec" }
    switch presentationMode {
    case .departureCountdown: return "Odchod"
    case .eventContext: return "Konec"
    }
  }

  var timeValue: String {
    switch presentationMode {
    case .departureCountdown:
      return leaveAt.formatted(date: .omitted, time: .shortened)
    case .eventContext:
      return endAt.formatted(date: .omitted, time: .shortened)
    }
  }
}

private struct CommanderProcedurePhaseTiming: View {
  let display: CommanderProcedureDisplay
  let accent: Color
  let size: CommanderTimingSize

  var body: some View {
    Group {
      if display.isStale {
        Image(systemName: "checkmark.circle.fill")
          .font(size == .large ? .title2 : .headline)
          .foregroundStyle(accent)
      } else {
        countdown(to: display.countdownTarget, label: display.countdownLabel)
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
      CommanderClampedCountdown(target: date)
        .font(timingFont)
        .foregroundStyle(accent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
  }

  private var timingWidth: CGFloat? {
    guard !display.isStale else { return nil }
    return size == .compact ? 54 : (size == .minimal ? 36 : nil)
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .system(size: 14, weight: .bold, design: .rounded).monospacedDigit()
    case .minimal: return .system(size: 11, weight: .bold, design: .rounded).monospacedDigit()
    case .regular: return .subheadline.weight(.heavy).monospacedDigit()
    case .large: return .title2.weight(.heavy).monospacedDigit()
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


#endif
import ActivityKit
import Foundation
import LazenskyCommanderCore
import SwiftUI
import WidgetKit

private enum CommanderActivityTokens {
  static let background = Color(commanderActivityHex: CommanderBrandAssets.Colors.background)
  static let panel = Color(commanderActivityHex: CommanderBrandAssets.Colors.panel)
  static let panelStroke = Color(commanderActivityHex: CommanderBrandAssets.Colors.panelStroke)
  static let locationBlue = Color(commanderActivityHex: CommanderBrandAssets.Colors.locationBlue)
  static let textPrimary = Color.white
  static let textSecondary = Color(commanderActivityHex: CommanderBrandAssets.Colors.textSecondary)

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
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderBrandAssets.circularMark
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .padding(.leading, 8)
            .accessibilityLabel("Lázeňský Commander")
        }
        DynamicIslandExpandedRegion(.center) {
          CommanderProcedureIslandCenter(context: context)
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderProcedureIslandReference(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
          CommanderProcedureIslandBottom(context: context)
        }
      } compactLeading: {
        CommanderBrandAssets.circularMark
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .padding(.leading, 5)
          .accessibilityLabel("Lázeňský Commander")
      } compactTrailing: {
        CommanderProcedureIslandTiming(context: context, size: .compact)
      } minimal: {
        CommanderProcedureIslandTiming(context: context, size: .minimal)
      }
      .keylineTint(keylineAccent)
      .contentMargins(.horizontal, 8, for: .expanded)
      .contentMargins(.horizontal, 4, for: .compactLeading)
      .contentMargins(.horizontal, 3, for: .compactTrailing)
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
    CommanderProcedureStatusText(display: display)
      .font(.system(size: 13, weight: .bold))
      .foregroundStyle(CommanderActivityTokens.procedureStateAccent(
        mode: display.presentationMode,
        isStale: display.isFinished || display.isScheduleFallback,
        eventAccent: eventAccent
      ))
      .lineLimit(1)
      .minimumScaleFactor(0.76)
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
      isStale: display.isFinished || display.isScheduleFallback,
      eventAccent: eventAccent
    )
    CommanderProcedurePhaseTiming(
      display: display,
      accent: stateAccent,
      size: size
    )
  }
}

private struct CommanderProcedureIslandReference: View {
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
    let accent = CommanderActivityTokens.procedureStateAccent(
      mode: display.presentationMode,
      isStale: display.isFinished || display.isScheduleFallback,
      eventAccent: eventAccent
    )

    VStack(spacing: 1) {
      Image(systemName: display.timing.symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(accent)

      if !display.isFinished {
        Text(display.timeLabel)
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(display.timeValue)
          .font(.system(size: 10, weight: .bold).monospacedDigit())
          .foregroundStyle(accent)
      }
    }
    .frame(width: 48)
    .accessibilityElement(children: .combine)
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
    let stateAccent = CommanderActivityTokens.procedureStateAccent(
      mode: display.presentationMode,
      isStale: display.isFinished || display.isScheduleFallback,
      eventAccent: eventAccent
    )

    VStack(spacing: 2) {
      CommanderPresentationClock(display: display)
        .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
        .foregroundStyle(stateAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .layoutPriority(2)

      HStack(spacing: 7) {
        CommanderProcedureArtwork(
          iconKey: display.iconKey,
          title: display.title,
          size: 19,
          kind: display.kind
        )
        Text(display.title)
          .font(.system(size: 12.5, weight: .bold))
          .foregroundStyle(eventAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.80)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.bottom, 1)
    .accessibilityElement(children: .combine)
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
      display: display,
      title: display.title,
      iconKey: display.iconKey,
      kind: display.kind,
      location: display.location,
      stateAccent: CommanderActivityTokens.procedureStateAccent(
        mode: display.presentationMode,
        isStale: display.isFinished || display.isScheduleFallback,
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
  let display: CommanderProcedureDisplay
  let title: String
  let iconKey: String?
  let kind: ScheduleKind?
  let location: String
  let stateAccent: Color
  @ViewBuilder var clock: () -> Clock

  var body: some View {
    GeometryReader { geometry in
      let roomy = geometry.size.height >= 100 || geometry.size.width >= 220
      VStack(spacing: roomy ? 4 : 1.5) {
        ZStack {
          HStack(spacing: 0) {
            CommanderBrandAssets.circularMark
              .resizable()
              .scaledToFit()
              .frame(width: roomy ? 28 : 19, height: roomy ? 28 : 19)
              .accessibilityLabel("Lázeňský Commander")
            Spacer(minLength: 0)
          }

          VStack(spacing: 0) {
            Image(systemName: display.timing.symbol)
              .font(.system(size: roomy ? 18 : 12.5, weight: .semibold))
              .foregroundStyle(stateAccent)

            Text(display.status)
              .font(.system(size: roomy ? 10 : 7.5, weight: .bold))
              .foregroundStyle(stateAccent)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
          }
          .frame(maxWidth: roomy ? 92 : 72)
        }
        .frame(height: roomy ? 31 : 20)

        clock()
          .font(.system(size: roomy ? 46 : 31, weight: .heavy, design: .rounded).monospacedDigit())
          .foregroundStyle(stateAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.68)
          .frame(maxWidth: .infinity)
          .frame(height: roomy ? 49 : 31)
          .multilineTextAlignment(.center)
          .layoutPriority(2)

        Rectangle()
          .fill(stateAccent.opacity(0.48))
          .frame(height: 0.5)

        HStack(spacing: roomy ? 7 : 5) {
          CommanderProcedureArtwork(
            iconKey: iconKey,
            title: title,
            size: roomy ? 28 : 18,
            kind: kind
          )

          Text(title)
            .font(.system(size: roomy ? 14 : 10.5, weight: .bold))
            .foregroundStyle(Color(commanderPresentationHex: CommanderBrandAssets.procedureAccentHex(
              iconKey: iconKey,
              title: title,
              isMeal: kind == .meal
            )))
            .lineLimit(roomy ? 2 : 1)
            .minimumScaleFactor(0.80)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: roomy ? 30 : 18)

        if roomy, !location.isEmpty {
          Label(location, systemImage: "mappin.circle.fill")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.locationBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(.horizontal, roomy ? 8 : 6)
      .padding(.vertical, roomy ? 5 : 3)
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
      .background(
        LinearGradient(
          colors: [
            Color(commanderActivityHex: CommanderBrandAssets.Colors.panel),
            Color.black.opacity(0.92)
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    .accessibilityElement(children: .combine)
  }
}

private struct CommanderClampedCountdown: View {
  let target: Date

  var body: some View {
    CommanderSystemCountdown(target: target)
  }
}

private struct CommanderPresentationClock: View {
  let display: CommanderProcedureDisplay

  @ViewBuilder var body: some View {
    if display.isFinished {
      Text("Skončilo")
    } else if let target = display.countdownTarget {
      CommanderClampedCountdown(target: target)
    } else {
      Text(display.timeValue)
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
      isStale: display.isFinished || display.isScheduleFallback,
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
        CommanderProcedureStatusText(display: display)
          .font(.system(size: 16, weight: .bold, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.76)

        if display.isFinished {
          Text("Skončilo")
            .font(.system(size: 38, weight: .heavy, design: .rounded))
            .foregroundStyle(CommanderActivityTokens.textPrimary)
            .lineLimit(1)
        } else {
          CommanderPresentationClock(display: display)
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
        CommanderBrandAssets.circularMark
          .resizable()
          .scaledToFit()
          .frame(width: 74, height: 74)
          .accessibilityLabel("Lázeňský Commander")
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
    if display.isFinished {
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
        Image(systemName: display.timing.symbol)
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
  let nextEvent: CommanderAlarmEventSnapshot?
  let nextEventLabel: String

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      CommanderProcedureArtwork(
        iconKey: iconKey,
        title: title,
        size: 36,
        kind: nil
      )

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
        CommanderProcedureArtwork(
          iconKey: iconKey,
          title: event.title,
          size: 18,
          kind: event.kind
        )
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
            colors: [accent.opacity(0.11), accent.opacity(0.035), accent.opacity(0.07)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          RadialGradient(
            colors: [accent.opacity(0.10), .clear],
            center: .topLeading,
            startRadius: 10,
            endRadius: 210
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

private enum CommanderTimingSize {
  case compact, minimal, regular, large
}

private typealias CommanderProcedureDisplay = CommanderActivityPresentation

private extension CommanderActivityPresentation {
  static func resolve(
    attributes: CommanderProcedureLiveActivityAttributes,
    state: CommanderProcedureLiveActivityAttributes.ContentState,
    isStale: Bool = false
  ) -> CommanderActivityPresentation {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    let seed = CommanderAlarmEventSnapshot(
      stableId: attributes.stableId, iconKey: attributes.iconKey,
      title: attributes.title, location: attributes.location, kind: attributes.kind,
      startAt: formatter.string(from: attributes.startAt),
      endAt: formatter.string(from: attributes.endAt),
      leaveAt: formatter.string(from: attributes.leaveAt)
    )
    let events = state.events.isEmpty
      ? [seed, attributes.nextEvent].compactMap { $0 }
      : state.events
    // PLATFORM LIMIT: a stale signal does not supply a second future boundary.
    // Evaluate terminal safety now, but never archive "Právě probíhá" from an
    // already-stale start snapshot: it could survive endAt without another update.
    return resolve(
      seed: seed,
      events: events,
      focusStableId: state.focusStableId ?? attributes.stableId,
      presentationMode: state.presentationMode,
      isStale: isStale,
      at: Date(),
      renderingPolicy: .suspendedActivity
    )
  }
}

private struct CommanderProcedureStatusText: View {
  let display: CommanderProcedureDisplay

  var body: some View {
    Text(display.status)
  }
}

private struct CommanderProcedurePhaseTiming: View {
  let display: CommanderProcedureDisplay
  let accent: Color
  let size: CommanderTimingSize

  var body: some View {
    Group {
      if display.isFinished {
        Image(systemName: "checkmark.circle.fill")
          .font(size == .large ? .title2 : .headline)
          .foregroundStyle(accent)
      } else if let target = display.countdownTarget {
        countdown(to: target, label: display.countdownLabel)
      } else {
        Image(systemName: "clock")
          .foregroundStyle(accent)
          .accessibilityLabel("Časový plán " + display.timeValue)
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
    guard display.countdownTarget != nil else { return nil }
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

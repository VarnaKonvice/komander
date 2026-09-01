import ActivityKit
import AlarmKit
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
  static let procedureCyan = Color(commanderActivityHex: CommanderBrandAssets.Colors.procedureCyan)
  static let urgentOrange = Color(commanderActivityHex: CommanderBrandAssets.Colors.urgentOrange)
  static let criticalRed = Color(commanderActivityHex: CommanderBrandAssets.Colors.criticalRed)
  static let textPrimary = Color.white
  static let textSecondary = Color(commanderActivityHex: CommanderBrandAssets.Colors.textSecondary)
  static let runningGreen = mealGreen

  static let insetRadius: CGFloat = 12
  static let cardRadius: CGFloat = 22
  static let lockScreenMinHeight: CGFloat = 138

  static var backgroundGradient: LinearGradient {
    LinearGradient(colors: [panel, background], startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  static func eventAccent(kind: ScheduleKind?, iconKey: String?) -> Color {
    if kind == .meal { return mealGreen }
    switch iconKey {
    case "iodobrom", "peat_wrap": return amber
    case "electro_therapy", "hydrojet", "whirlpool", "pool": return procedureCyan
    default: return primaryPurple
    }
  }

  static func departureAccent(for mode: AlarmPresentationState.Mode) -> Color {
    switch mode {
    case .alert: return criticalRed
    case .countdown, .paused: return amber
    @unknown default: return urgentOrange
    }
  }

  static func eventSymbol(kind: ScheduleKind?, iconKey: String?) -> String {
    if kind == .meal || iconKey == "meal" { return "fork.knife" }
    switch iconKey {
    case "electro_therapy": return "atom"
    case "iodobrom", "whirlpool": return "bathtub.fill"
    case "massage", "peat_wrap": return "figure.mind.and.body"
    case "pool", "hydrojet": return "water.waves"
    case "individual_rehab", "imoove": return "figure.walk"
    default: return "calendar"
    }
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
      CommanderAlarmLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    } dynamicIsland: { context in
      let metadata = context.attributes.metadata
      let eventAccent = CommanderActivityTokens.eventAccent(
        kind: metadata?.kind,
        iconKey: metadata?.iconKey
      )
      let departureAccent = CommanderActivityTokens.departureAccent(for: context.state.mode)
      let eventSymbol = CommanderActivityTokens.eventSymbol(
        kind: metadata?.kind,
        iconKey: metadata?.iconKey
      )

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderActivityBrandMark(size: 34)
        }
        DynamicIslandExpandedRegion(.center) {
          CommanderIslandEventTitle(
            title: metadata?.title ?? "Lázeňský Commander",
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
        CommanderActivityBrandMark(size: 22)
      } compactTrailing: {
        CommanderAlarmCountdownContext(
          mode: context.state.mode,
          showsLabel: false,
          size: .compact
        )
      } minimal: {
        CommanderActivityBrandMark(size: 20)
      }
      .keylineTint(departureAccent)
    }
  }
}

struct LazenskyCommanderProcedureLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CommanderProcedureLiveActivityAttributes.self) { context in
      CommanderProcedureLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityTokens.background)
        .activitySystemActionForegroundColor(CommanderActivityTokens.textPrimary)
    } dynamicIsland: { context in
      let accent = CommanderActivityTokens.eventAccent(
        kind: context.attributes.kind,
        iconKey: context.attributes.iconKey
      )
      let eventSymbol = CommanderActivityTokens.eventSymbol(
        kind: context.attributes.kind,
        iconKey: context.attributes.iconKey
      )
      let stateAccent = context.isStale
        ? CommanderActivityTokens.textSecondary
        : CommanderActivityTokens.runningGreen

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderActivityBrandMark(size: 34)
        }
        DynamicIslandExpandedRegion(.center) {
          CommanderIslandEventTitle(
            title: context.attributes.title,
            symbol: eventSymbol,
            accent: accent
          )
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderProcedureTiming(
            endAt: context.attributes.endAt,
            isStale: context.isStale,
            accent: stateAccent,
            size: .regular
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          CommanderIslandDetails(
            location: context.attributes.location,
            status: CommanderProcedureText.status(
              kind: context.attributes.kind,
              isStale: context.isStale
            ),
            statusAccent: stateAccent,
            timeLabel: "Konec",
            timeValue: context.attributes.endAt.formatted(date: .omitted, time: .shortened),
            timeAccent: accent
          )
        }
      } compactLeading: {
        CommanderActivityBrandMark(size: 22)
      } compactTrailing: {
        CommanderProcedureTiming(
          endAt: context.attributes.endAt,
          isStale: context.isStale,
          accent: stateAccent,
          size: .compact
        )
      } minimal: {
        CommanderActivityBrandMark(size: 20)
      }
      .keylineTint(stateAccent)
    }
  }
}

private struct CommanderAlarmLockScreenView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  private var metadata: CommanderAlarmMetadata? { context.attributes.metadata }
  private var eventAccent: Color {
    CommanderActivityTokens.eventAccent(kind: metadata?.kind, iconKey: metadata?.iconKey)
  }
  private var departureAccent: Color {
    CommanderActivityTokens.departureAccent(for: context.state.mode)
  }
  private var eventSymbol: String {
    CommanderActivityTokens.eventSymbol(kind: metadata?.kind, iconKey: metadata?.iconKey)
  }

  var body: some View {
    VStack(spacing: 8) {
      CommanderAlarmHero(mode: context.state.mode)
      CommanderActivityDivider(accent: departureAccent)
      CommanderActivityEventFooter(
        title: metadata?.title ?? "Lázeňský Commander",
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

  private var accent: Color {
    CommanderActivityTokens.eventAccent(
      kind: context.attributes.kind,
      iconKey: context.attributes.iconKey
    )
  }
  private var eventSymbol: String {
    CommanderActivityTokens.eventSymbol(
      kind: context.attributes.kind,
      iconKey: context.attributes.iconKey
    )
  }
  private var stateAccent: Color {
    context.isStale ? CommanderActivityTokens.textSecondary : CommanderActivityTokens.runningGreen
  }

  var body: some View {
    VStack(spacing: 8) {
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
        symbol: eventSymbol,
        eventAccent: accent,
        timeLabel: "Konec",
        timeValue: context.attributes.endAt.formatted(date: .omitted, time: .shortened),
        timeAccent: stateAccent
      )
    }
    .commanderActivityCard(accent: stateAccent)
  }
}

private struct CommanderAlarmHero: View {
  let mode: AlarmPresentationState.Mode

  private var accent: Color {
    CommanderActivityTokens.departureAccent(for: mode)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      CommanderActivityBrandMark(size: 54)

      VStack(alignment: .leading, spacing: 1) {
        if mode.isAlert {
          Text("VYRAZIT TEĎ")
            .font(.system(size: 27, weight: .heavy, design: .rounded))
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
          Text("Je čas vyrazit")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.textSecondary)
        } else {
          Text("Odchod za")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(accent)
          CommanderAlarmCountdown(mode: mode)
            .font(.system(size: 42, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      CommanderActivityStateBadge(
        symbol: "figure.walk",
        label: mode.isAlert ? "Je čas\nvyrazit" : "Odchod",
        accent: accent
      )
    }
    .frame(minHeight: 58)
  }
}

private struct CommanderProcedureHero: View {
  let kind: ScheduleKind
  let endAt: Date
  let isStale: Bool
  let accent: Color

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      CommanderActivityBrandMark(size: 54)

      VStack(alignment: .leading, spacing: 1) {
        Text(CommanderProcedureText.status(kind: kind, isStale: isStale))
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(accent)
          .lineLimit(1)

        if isStale {
          Text("Skončilo")
            .font(.system(size: 27, weight: .heavy, design: .rounded))
            .foregroundStyle(CommanderActivityTokens.textPrimary)
            .lineLimit(1)
        } else {
          Text(endAt, style: .timer)
            .font(.system(size: 42, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      CommanderActivityStateBadge(
        symbol: isStale ? "checkmark" : "play.fill",
        label: isStale ? "Skončilo" : "Do konce",
        accent: accent
      )
    }
    .frame(minHeight: 58)
  }
}

private struct CommanderActivityStateBadge: View {
  let symbol: String
  let label: String
  let accent: Color

  var body: some View {
    VStack(spacing: 3) {
      Image(systemName: symbol)
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 34, height: 30)
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(CommanderActivityTokens.textSecondary)
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
    .frame(width: 50)
  }
}

private struct CommanderActivityDivider: View {
  let accent: Color

  var body: some View {
    Rectangle()
      .fill(
        LinearGradient(
          colors: [accent.opacity(0.55), CommanderActivityTokens.panelStroke.opacity(0.18)],
          startPoint: .leading,
          endPoint: .trailing
        )
      )
      .frame(height: 1)
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
    HStack(alignment: .center, spacing: 9) {
      CommanderActivityEventBadge(symbol: symbol, accent: eventAccent, size: 32)

      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.system(size: 19, weight: .bold))
          .foregroundStyle(CommanderActivityTokens.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.84)
        if let location, !location.isEmpty {
          Label(location, systemImage: "mappin.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(CommanderActivityTokens.locationBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
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
    .frame(minHeight: 42)
  }
}

private struct CommanderActivityTimeBlock: View {
  let label: String
  let value: String
  let accent: Color

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: "clock.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accent)
      VStack(alignment: .trailing, spacing: 0) {
        Text(label)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(CommanderActivityTokens.textSecondary)
        Text(value)
          .font(.system(size: 15, weight: .bold).monospacedDigit())
          .foregroundStyle(CommanderActivityTokens.textPrimary)
      }
    }
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
        .foregroundStyle(CommanderActivityTokens.textPrimary)
        .lineLimit(1)
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
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .frame(
        maxWidth: .infinity,
        minHeight: CommanderActivityTokens.lockScreenMinHeight,
        alignment: .leading
      )
      .background {
        ZStack {
          CommanderActivityTokens.backgroundGradient
          LinearGradient(
            colors: [accent.opacity(0.11), .clear, accent.opacity(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: CommanderActivityTokens.cardRadius)
          .strokeBorder(accent.opacity(0.62), lineWidth: 1)
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
        .minimumScaleFactor(0.8)
    }
  }

  private var countdownFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .headline.weight(.heavy).monospacedDigit()
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
          Text(endAt, style: .timer)
            .font(timingFont)
            .foregroundStyle(accent)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }
      }
    }
  }

  private var timingFont: Font {
    switch size {
    case .compact: return .caption2.weight(.bold).monospacedDigit()
    case .regular: return .headline.weight(.heavy).monospacedDigit()
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
    return "Právě probíhá"
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
  static let alarmAttributes = AlarmAttributes(
    presentation: AlarmPresentation(
      alert: AlarmPresentation.Alert(title: "Vyrazit na Masáž"),
      countdown: AlarmPresentation.Countdown(title: "Odchod za Masáž")
    ),
    metadata: CommanderAlarmMetadata(
      stableId: "preview-massage",
      scheduleVersion: 1,
      iconKey: "massage",
      title: "Masáž",
      location: "Rehabilitace, box 3",
      kind: .procedure,
      startAt: "2026-09-01T14:00:00",
      leaveAt: "2026-09-01T13:50:00"
    ),
    tintColor: .orange
  )

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

  static let current = CommanderProcedureLiveActivityAttributes.ContentState(
    projectionRevision: 1
  )
}

#Preview("Lock Screen - Odchod za 10 min", as: .content, using: CommanderActivityPreviewFixtures.alarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}

#Preview("Lock Screen - Vyrazit ted", as: .content, using: CommanderActivityPreviewFixtures.alarmAttributes) {
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

#Preview("Dynamic Island - Compact odchod", as: .dynamicIsland(.compact), using: CommanderActivityPreviewFixtures.alarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}

#Preview("Dynamic Island - Expanded Masaz", as: .dynamicIsland(.expanded), using: CommanderActivityPreviewFixtures.alarmAttributes) {
  LazenskyCommanderAlarmLiveActivity()
} contentStates: {
  CommanderActivityPreviewFixtures.departureInTenMinutes
}
#endif

import Foundation
import LazenskyCommanderCore
import SwiftUI
import WidgetKit

struct CommanderHomeWidgetEntry: TimelineEntry {
  let date: Date
  let snapshot: WatchScheduleSnapshot?
}

struct CommanderHomeWidgetProvider: TimelineProvider {
  private static let snapshotLoader = CommanderWidgetSnapshotLoader(
    service: URLSessionScheduleService(configuration: AppConfiguration()),
    cache: FileWatchScheduleCache(
      directoryURL: URL.applicationSupportDirectory.appendingPathComponent("CommanderWidgetCache"),
      dataset: .production
    )
  )
  func placeholder(in context: Context) -> CommanderHomeWidgetEntry {
    CommanderHomeWidgetEntry(date: Date(), snapshot: nil)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping @Sendable (CommanderHomeWidgetEntry) -> Void
  ) {
    Task {
      completion(CommanderHomeWidgetEntry(date: Date(), snapshot: await cachedSnapshot()))
    }
  }

  func getTimeline(
    in context: Context,
    completion: @escaping @Sendable (Timeline<CommanderHomeWidgetEntry>) -> Void
  ) {
    Task {
      let now = Date()
      guard let snapshot = await cachedSnapshot(),
            let activeSchedule = WatchScheduleExpiryPolicy.activeSchedule(snapshot.schedule, at: now)
      else {
        completion(Timeline(
          entries: [CommanderHomeWidgetEntry(date: now, snapshot: nil)],
          policy: .after(now.addingTimeInterval(15 * 60))
        ))
        return
      }

      do {
        let points = try WatchTimelinePlanner.points(
          schedule: activeSchedule,
          now: now,
          overrides: snapshot.leadTimeOverrides
        )
        let horizon = now.addingTimeInterval(6 * 60 * 60)
        var dates = Set(points.map(\.date).filter { $0 <= horizon })
        dates.insert(now)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        if var tick = calendar.nextDate(
          after: now,
          matching: DateComponents(second: 0),
          matchingPolicy: .nextTime
        ) {
          while tick <= horizon {
            dates.insert(tick)
            tick = tick.addingTimeInterval(60)
          }
        }

        let entries = dates.sorted().map {
          CommanderHomeWidgetEntry(date: $0, snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(horizon)))
      } catch {
        completion(Timeline(
          entries: [CommanderHomeWidgetEntry(date: now, snapshot: snapshot)],
          policy: .after(now.addingTimeInterval(15 * 60))
        ))
      }
    }
  }

  private func cachedSnapshot() async -> WatchScheduleSnapshot? {
#if COMMANDER_VISUAL_REVIEW
    return WatchScheduleSnapshot(schedule: CommanderVisualReviewSchedule.make(now: Date()))
#else
#if DEBUG
    if UserDefaults(
      suiteName: CommanderWatchWidgetContract.appGroupIdentifier
    )?.bool(forKey: "commander.visualReview.enabled") == true {
      return WatchScheduleSnapshot(schedule: CommanderVisualReviewSchedule.make(now: Date()))
    }
#endif
    return await Self.snapshotLoader.load()
#endif
  }


}

private enum CommanderWidgetCountdownText {
  static func value(now: Date, target: Date?) -> String {
    guard let target else { return "–" }
    let interval = target.timeIntervalSince(now)
    if interval <= 0 { return "teď" }

    let totalMinutes = Int(interval / 60)
    if totalMinutes <= 0 { return "< 1 min" }

    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
      return minutes > 0 ? "\(hours) h \(minutes) min" : "\(hours) h"
    }
    return "\(minutes) min"
  }
}

private enum CommanderWidgetTokens {
  static let background = Color(commanderPresentationHex: CommanderBrandAssets.Colors.background)
  static let panel = Color(commanderPresentationHex: CommanderBrandAssets.Colors.panel)
  static let panelStroke = Color(commanderPresentationHex: CommanderBrandAssets.Colors.panelStroke)
  static let primaryPurple = Color(commanderPresentationHex: CommanderBrandAssets.Colors.primaryPurple)
  static let textPrimary = Color.white
  static let textSecondary = Color(commanderPresentationHex: CommanderBrandAssets.Colors.textSecondary)

  static var backgroundGradient: LinearGradient {
    LinearGradient(
      colors: [Color(commanderPresentationHex: "#173A78"), panel, background],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  static func accent(for event: ScheduleEvent) -> Color {
    Color(commanderPresentationHex: CommanderBrandAssets.procedureAccentHex(
      iconKey: nil,
      title: event.title,
      isMeal: event.kind == .meal
    ))
  }
}

struct LazenskyCommanderHomeWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: CommanderWatchWidgetContract.iPhoneKind,
      provider: CommanderHomeWidgetProvider()
    ) { entry in
      CommanderHomeWidgetView(entry: entry)
    }
    .configurationDisplayName("Commander – teď")
    .description("Aktuální nebo následující událost, odchod a odpočet.")
    .supportedFamilies([
      .systemSmall,
      .systemMedium,
      .accessoryInline,
      .accessoryCircular,
      .accessoryRectangular
    ])
    .contentMarginsDisabled()
  }
}

struct LazenskyCommanderDayOverviewWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: CommanderWatchWidgetContract.iPhoneDayOverviewKind,
      provider: CommanderHomeWidgetProvider()
    ) { entry in
      CommanderDayOverviewWidgetView(entry: entry)
    }
    .configurationDisplayName("Commander – přehled dne")
    .description("Počet procedur, konec procedur a večeře.")
    .supportedFamilies([.systemSmall])
    .contentMarginsDisabled()
  }
}

struct LazenskyCommanderProcedureCountWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: CommanderWatchWidgetContract.iPhoneProcedureCountKind,
      provider: CommanderHomeWidgetProvider()
    ) { entry in
      CommanderProcedureCountWidgetView(entry: entry)
    }
    .configurationDisplayName("Commander – odpočet")
    .description("Kruhový odpočet do odchodu, začátku nebo konce aktuální události.")
    .supportedFamilies([.accessoryCircular])
  }
}

private struct CommanderWidgetState {
  let entry: CommanderHomeWidgetEntry

  var schedule: Schedule? {
    guard let snapshot = entry.snapshot else { return nil }
    return WatchScheduleExpiryPolicy.activeSchedule(snapshot.schedule, at: entry.date)
  }

  var live: CommanderLiveStateResult {
    CommanderLiveStateCalculator.compute(
      schedule: schedule,
      now: entry.date,
      overrides: entry.snapshot?.leadTimeOverrides
    )
  }

  var event: ScheduleEvent? { live.event }

  var nextAfterCurrent: ScheduleEvent? {
    let events = todayEvents.sorted(by: Self.eventOrder)
    if let event, let index = events.firstIndex(where: { $0.stableId == event.stableId }) {
      return events.dropFirst(index + 1).first
    }
    return events.first(where: {
      ((try? NativeAlarmContract.dateTime(date: $0.date, time: $0.start)) ?? .distantPast) > entry.date
    })
  }

  var nextRelevantTodayEvent: ScheduleEvent? {
    switch live.state {
    case .upcoming, .leaveNow:
      return event
    case .inProgress:
      return nextAfterCurrent
    case .dayDone, .noSchedule:
      return nil
    }
  }

  var nextRelevantTodayStart: Date? {
    guard let event = nextRelevantTodayEvent else { return nil }
    return try? NativeAlarmContract.dateTime(date: event.date, time: event.start)
  }

  var remainingProcedureCount: Int {
    guard schedule != nil else { return 0 }
    return todayEvents.filter { event in
      guard event.kind == .procedure,
            let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end)
      else { return false }
      return end > entry.date
    }.count
  }

  var finalProcedureEnd: Date? {
    todayEvents
      .filter { $0.kind == .procedure }
      .compactMap { try? NativeAlarmContract.dateTime(date: $0.date, time: $0.end) }
      .max()
  }

  var dinnerStart: Date? {
    todayEvents
      .filter { $0.kind == .meal && Self.normalized($0.title).contains("vecer") }
      .compactMap { try? NativeAlarmContract.dateTime(date: $0.date, time: $0.start) }
      .min()
  }

  private var todayEvents: [ScheduleEvent] {
    guard let schedule else { return [] }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return schedule.events.filter { event in
      guard let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start) else { return false }
      return calendar.isDate(start, inSameDayAs: entry.date)
    }
  }

  static func eventOrder(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
    [lhs.date, lhs.start, lhs.end, lhs.stableId].joined(separator: "|")
      < [rhs.date, rhs.start, rhs.end, rhs.stableId].joined(separator: "|")
  }

  static func normalized(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
      .lowercased(with: Locale(identifier: "cs_CZ"))
  }
}

private struct CommanderHomeWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: CommanderHomeWidgetEntry

  var body: some View {
    let state = CommanderWidgetState(entry: entry)
    Group {
      switch family {
      case .systemSmall:
        CommanderSmallHomeWidget(state: state)
      case .systemMedium:
        CommanderMediumHomeWidget(state: state)
      case .accessoryInline:
        CommanderInlineLockWidget(state: state)
      case .accessoryCircular:
        CommanderCircularLockWidget(state: state)
      case .accessoryRectangular:
        CommanderRectangularLockWidget(state: state)
          .containerBackground(.clear, for: .widget)
      default:
        CommanderSmallHomeWidget(state: state)
      }
    }
  }
}

private struct CommanderWidgetBrandRow: View {
  let title: String
  var iconSize: CGFloat = 26
  var fontSize: CGFloat = 17

  var body: some View {
    HStack(spacing: 7) {
      Image(CommanderBrandAssets.circularMarkName, bundle: .main)
        .renderingMode(.original)
        .resizable()
        .scaledToFit()
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: max(6, iconSize * 0.24)))
      Text(title)
        .font(.system(size: fontSize, weight: .bold))
        .foregroundStyle(CommanderWidgetTokens.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.76)
    }
  }
}

private struct CommanderSmallHomeWidget: View {
  let state: CommanderWidgetState

  var body: some View {
    VStack(spacing: 6) {
      HStack {
        CommanderWidgetBrandRow(title: "Commander")
        Spacer(minLength: 0)
      }

      if let event = state.event {
        CommanderWidgetCountdown(state: state, compact: false)
          .frame(maxWidth: .infinity, alignment: .center)

        Rectangle()
          .fill(CommanderWidgetTokens.accent(for: event).opacity(0.32))
          .frame(height: 0.5)

        HStack(spacing: 8) {
          CommanderProcedureArtwork(iconKey: nil, title: event.title, size: 32)
          VStack(alignment: .leading, spacing: 1) {
            Text(event.title)
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(CommanderWidgetTokens.accent(for: event))
              .lineLimit(1)
              .minimumScaleFactor(0.68)
            if !event.location.isEmpty {
              Label(event.location, systemImage: "mappin.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CommanderWidgetTokens.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        CommanderWidgetEmptyState(state: state, compact: true)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
    }
    .padding(11)
    .containerBackground(CommanderWidgetTokens.backgroundGradient, for: .widget)
  }
}

private struct CommanderMediumHomeWidget: View {
  let state: CommanderWidgetState

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .center, spacing: 8) {
        CommanderWidgetBrandRow(title: "Lázeňský Commander", iconSize: 30, fontSize: 17)
        Spacer(minLength: 8)
        Text(entryDayLabel)
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(CommanderWidgetTokens.textPrimary.opacity(0.82))
          .offset(y: 1)
      }

      if let event = state.event {
        let accent = CommanderWidgetTokens.accent(for: event)

        HStack(alignment: .center, spacing: 12) {
          CommanderProcedureArtwork(iconKey: nil, title: event.title, size: 62)

          VStack(alignment: .leading, spacing: 2) {
            Text(event.title)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(accent)
              .lineLimit(1)
              .minimumScaleFactor(0.72)

            if !event.location.isEmpty {
              Label(event.location, systemImage: "mappin.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommanderWidgetTokens.textPrimary)
                .lineLimit(1)
            }

            if let start = state.live.startAt, let end = state.live.endAt {
              Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(CommanderWidgetTokens.textSecondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          CommanderWidgetCountdown(state: state, compact: false)
            .frame(width: 126, alignment: .center)
        }

        if let next = state.nextAfterCurrent {
          Rectangle()
            .fill(accent.opacity(0.30))
            .frame(height: 0.6)

          VStack(alignment: .leading, spacing: 2) {
            Text("Potom")
              .font(.system(size: 9, weight: .bold))
              .foregroundStyle(CommanderWidgetTokens.textSecondary)

            HStack(spacing: 6) {
              compactNextIcon(next)
                .fixedSize()
                .layoutPriority(1)

              Text(next.title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(CommanderWidgetTokens.accent(for: next))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

              Spacer(minLength: 4)

              if let start = try? NativeAlarmContract.dateTime(date: next.date, time: next.start) {
                Text("Začátek \(start.formatted(date: .omitted, time: .shortened))")
                  .font(.system(size: 11, weight: .bold).monospacedDigit())
                  .foregroundStyle(CommanderWidgetTokens.textPrimary)
                  .lineLimit(1)
                  .minimumScaleFactor(0.78)
              }
            }
          }
        }
      } else {
        CommanderWidgetEmptyState(state: state)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      }
    }
    .padding(.horizontal, 10)
    .padding(.top, 6)
    .padding(.bottom, 8)
    .containerBackground(CommanderWidgetTokens.backgroundGradient, for: .widget)
  }

  @ViewBuilder
  private func compactNextIcon(_ event: ScheduleEvent) -> some View {
    let symbol = CommanderBrandAssets.procedureSymbol(
      iconKey: nil,
      title: event.procedureType ?? event.mealType ?? event.title,
      isMeal: event.kind == .meal
    )
    let accent = CommanderWidgetTokens.accent(for: event)

    if symbol == "commander.heat.waves" {
      CommanderProcedureArtwork(
        iconKey: nil,
        title: event.title,
        size: 18,
        kind: event.kind
      )
    } else {
      ZStack {
        Circle()
          .fill(accent.opacity(0.16))
        Circle()
          .strokeBorder(accent.opacity(0.90), lineWidth: 1)
        Image(systemName: symbol)
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(accent)
      }
      .frame(width: 18, height: 18)
    }
  }

  private var entryDayLabel: String {
    state.entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.defaultDigits))
  }
}

private struct CommanderWidgetCountdown: View {
  let state: CommanderWidgetState
  let compact: Bool

  var body: some View {
    switch state.live.state {
    case .upcoming:
      countdown(label: "Odchod za", target: state.live.leaveAt, accent: CommanderBrandAssets.Presentation.countdown, symbol: "figure.walk")
    case .leaveNow:
      countdown(label: "Čas vyrazit", target: state.live.startAt, accent: CommanderBrandAssets.Presentation.alert, symbol: "figure.walk")
    case .inProgress:
      countdown(label: "Do konce", target: state.live.endAt, accent: CommanderBrandAssets.Presentation.active, symbol: nil)
    case .dayDone:
      status("Dnes hotovo", color: CommanderWidgetTokens.textPrimary)
    case .noSchedule:
      status("Bez programu", color: CommanderWidgetTokens.textSecondary)
    }
  }

  private func countdown(label: String, target: Date?, accent: Color, symbol: String?) -> some View {
    VStack(alignment: .center, spacing: 1) {
      HStack(spacing: 5) {
        if let symbol {
          ZStack {
            Circle()
              .fill(accent.opacity(0.16))
              .frame(width: compact ? 18 : 23, height: compact ? 18 : 23)
            Image(systemName: symbol)
              .font(.system(size: compact ? 10 : 14, weight: .bold))
          }
        }
        Text(label)
      }
      .font(.system(size: compact ? 10 : 13, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .lineLimit(1)

      if target != nil {
        Text(CommanderWidgetCountdownText.value(now: state.entry.date, target: target))
          .font(.system(size: compact ? 22 : 29, weight: .heavy, design: .rounded))
          .foregroundStyle(accent)
          .lineLimit(1)
          .minimumScaleFactor(0.56)
      }
    }
    .multilineTextAlignment(.center)
  }

  private func status(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: compact ? 14 : 18, weight: .bold))
      .foregroundStyle(color)
      .lineLimit(2)
  }
}

private struct CommanderWidgetEmptyState: View {
  let state: CommanderWidgetState
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 6 : 8) {
      Image(systemName: state.live.state == .dayDone ? "checkmark.circle.fill" : "calendar")
        .font(.system(size: compact ? 18 : 20, weight: .bold))
        .foregroundStyle(state.live.state == .dayDone ? Color(commanderPresentationHex: CommanderBrandAssets.Colors.mealGreen) : CommanderWidgetTokens.textSecondary)
      Text(emptyText)
        .font(.system(size: compact ? 15 : 16, weight: .bold))
        .foregroundStyle(CommanderWidgetTokens.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var emptyText: String {
    if state.live.state == .dayDone {
      return compact ? "Dnes hotovo" : "Dnešní program dokončen"
    }
    return compact ? "Bez programu" : "Dnes bez programu"
  }
}

private struct CommanderInlineLockWidget: View {
  let state: CommanderWidgetState

  var body: some View {
    Group {
      if let event = state.event {
        HStack(spacing: 3) {
          Text(inlinePrefix)
          inlineTimer
          Text("· \(event.title)")
        }
        .lineLimit(1)
      } else {
        Label(state.live.state == .dayDone ? "Commander · dnes hotovo" : "Commander · bez programu", systemImage: "calendar")
      }
    }
    .containerBackground(.clear, for: .widget)
  }

  private var inlinePrefix: String {
    switch state.live.state {
    case .upcoming: return "Odchod za"
    case .leaveNow: return "Začátek za"
    case .inProgress: return "Do konce"
    case .dayDone, .noSchedule: return ""
    }
  }

  @ViewBuilder
  private var inlineTimer: some View {
    let target: Date? = switch state.live.state {
    case .upcoming: state.live.leaveAt
    case .leaveNow: state.live.startAt
    case .inProgress: state.live.endAt
    case .dayDone, .noSchedule: nil
    }
    if let target {
      Text(CommanderWidgetCountdownText.value(now: state.entry.date, target: target))
    }
  }
}

private struct CommanderCircularLockWidget: View {
  let state: CommanderWidgetState

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()

      if let target = targetDate {
        Circle()
          .stroke(.secondary.opacity(0.25), lineWidth: 4)

        Circle()
          .trim(from: 0, to: remainingFraction)
          .stroke(
            accent,
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))

        VStack(spacing: -1) {
          Image(systemName: phaseSymbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accent)
          Text(compactCountdown(target))
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.62)
            .lineLimit(1)
        }
      } else if state.live.state == .dayDone {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 25, weight: .bold))
      } else {
        Image(CommanderBrandAssets.circularMarkName, bundle: .main)
          .renderingMode(.template)
          .resizable()
          .scaledToFit()
          .frame(width: 28, height: 28)
      }
    }
    .widgetLabel(circularLabel)
    .containerBackground(.clear, for: .widget)
  }

  private var accent: Color {
    if let event = state.event {
      return CommanderWidgetTokens.accent(for: event)
    }
    return CommanderWidgetTokens.primaryPurple
  }

  private var targetDate: Date? {
    switch state.live.state {
    case .upcoming: return state.live.leaveAt
    case .leaveNow: return state.live.startAt
    case .inProgress: return state.live.endAt
    case .dayDone, .noSchedule: return nil
    }
  }

  private var phaseStartDate: Date? {
    switch state.live.state {
    case .upcoming:
      return state.live.leaveAt?.addingTimeInterval(-30 * 60)
    case .leaveNow:
      return state.live.leaveAt
    case .inProgress:
      return state.live.startAt
    case .dayDone, .noSchedule:
      return nil
    }
  }

  private var remainingFraction: Double {
    guard let start = phaseStartDate, let target = targetDate, target > start else { return 1 }
    let total = target.timeIntervalSince(start)
    let remaining = target.timeIntervalSince(state.entry.date)
    return min(1, max(0, remaining / total))
  }

  private var phaseSymbol: String {
    switch state.live.state {
    case .upcoming, .leaveNow: return "figure.walk"
    case .inProgress: return "clock.fill"
    case .dayDone: return "checkmark"
    case .noSchedule: return "calendar"
    }
  }

  private func compactCountdown(_ target: Date) -> String {
    let seconds = max(0, target.timeIntervalSince(state.entry.date))
    if seconds <= 0 { return "teď" }
    let minutes = Int(ceil(seconds / 60))
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours)h" : "\(hours)h\(rest)"
  }

  private var circularLabel: String {
    switch state.live.state {
    case .upcoming: return "Do odchodu"
    case .leaveNow: return "Do začátku"
    case .inProgress: return "Do konce"
    case .dayDone: return "Dnes hotovo"
    case .noSchedule: return "Lázeňský Commander"
    }
  }
}

private struct CommanderRectangularLockWidget: View {
  let state: CommanderWidgetState

  var body: some View {
    if let event = state.event {
      HStack(alignment: .center, spacing: 6) {
        VStack(alignment: .leading, spacing: 0) {
          Text(rectangularStatus)
            .font(.system(size: 10, weight: .bold))
          Text(event.title)
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
          if !event.location.isEmpty {
            Text(event.location)
              .font(.system(size: 10, weight: .semibold))
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if let target = rectangularTarget {
          Text(CommanderWidgetCountdownText.value(now: state.entry.date, target: target))
            .font(.system(size: 17, weight: .heavy, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
      }
    } else {
      Label(state.live.state == .dayDone ? "Dnes hotovo" : "Bez programu", systemImage: "calendar")
        .font(.system(size: 13, weight: .bold))
    }
  }

  private var rectangularStatus: String {
    switch state.live.state {
    case .upcoming: return "Odchod za"
    case .leaveNow: return "Čas vyrazit"
    case .inProgress: return "Právě probíhá"
    case .dayDone: return "Dnes hotovo"
    case .noSchedule: return "Commander"
    }
  }

  private var rectangularTarget: Date? {
    switch state.live.state {
    case .upcoming: return state.live.leaveAt
    case .leaveNow: return state.live.startAt
    case .inProgress: return state.live.endAt
    case .dayDone, .noSchedule: return nil
    }
  }
}

private struct CommanderDayOverviewWidgetView: View {
  let entry: CommanderHomeWidgetEntry

  var body: some View {
    let state = CommanderWidgetState(entry: entry)
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        CommanderWidgetBrandRow(title: "Dnes")
        Spacer(minLength: 0)
      }

      Rectangle()
        .fill(CommanderWidgetTokens.primaryPurple.opacity(0.35))
        .frame(height: 0.6)

      if state.remainingProcedureCount == 0 {
        summaryRow(
          symbol: "checkmark.circle.fill",
          label: "Procedury",
          value: "Hotovo",
          color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.mealGreen)
        )

        if let next = state.nextRelevantTodayEvent,
           let start = state.nextRelevantTodayStart {
          summaryRow(
            symbol: next.kind == .meal ? "fork.knife" : "calendar",
            label: "Další",
            value: "\(next.title) \(start.formatted(date: .omitted, time: .shortened))",
            color: CommanderWidgetTokens.accent(for: next)
          )

          summaryRow(
            symbol: "hourglass",
            label: next.kind == .meal ? "Volno do \(next.title.lowercased())" : "Do začátku",
            value: CommanderWidgetCountdownText.value(now: state.entry.date, target: start),
            color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.procedureCyan)
          )
        } else {
          summaryRow(
            symbol: "checkmark.seal.fill",
            label: "Dnešní program",
            value: "Hotovo",
            color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.mealGreen)
          )
        }
      } else {
        summaryRow(
          symbol: "cross.case.fill",
          label: "Procedury",
          value: "\(state.remainingProcedureCount)",
          color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.therapyPink)
        )
        summaryRow(
          symbol: "clock.fill",
          label: "Konec procedur",
          value: time(state.finalProcedureEnd),
          color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.timeGold)
        )
        summaryRow(
          symbol: "fork.knife",
          label: "Večeře",
          value: time(state.dinnerStart),
          color: Color(commanderPresentationHex: CommanderBrandAssets.Colors.mealGreen)
        )
      }
    }
    .padding(.horizontal, 10)
    .padding(.top, 5)
    .padding(.bottom, 10)
    .containerBackground(CommanderWidgetTokens.backgroundGradient, for: .widget)
  }

  private func summaryRow(symbol: String, label: String, value: String, color: Color) -> some View {
    HStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(color)
        .frame(width: 20)
      VStack(alignment: .leading, spacing: -1) {
        Text(label)
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(CommanderWidgetTokens.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
        Text(value)
          .font(.system(size: 16, weight: .heavy, design: .rounded))
          .foregroundStyle(CommanderWidgetTokens.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func time(_ date: Date?) -> String {
    date?.formatted(date: .omitted, time: .shortened) ?? "–"
  }
}

private struct CommanderProcedureCountWidgetView: View {
  let entry: CommanderHomeWidgetEntry

  var body: some View {
    CommanderCircularLockWidget(state: CommanderWidgetState(entry: entry))
  }
}

import Foundation
import LazenskyCommanderCore
import RelevanceKit
import SwiftUI
import WidgetKit

@main
struct LazenskyCommanderWatchWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: CommanderWatchWidgetContract.kind,
      provider: CommanderWatchTimelineProvider()
    ) { entry in
      CommanderWatchWidgetView(entry: entry)
    }
    .configurationDisplayName("Lázeňský Commander")
    .description("Aktuální procedura a čas odchodu.")
    .supportedFamilies([.accessoryRectangular])
  }
}

struct CommanderWatchWidgetEntry: TimelineEntry {
  let date: Date
  let liveState: CommanderLiveStateResult

  var relevance: TimelineEntryRelevance? {
    guard liveState.state != .dayDone,
          let end = liveState.endAt, end > date else { return nil }
    return TimelineEntryRelevance(score: liveState.state == .upcoming ? 50 : 100,
                                  duration: end.timeIntervalSince(date))
  }
}

struct CommanderWatchTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> CommanderWatchWidgetEntry {
    noScheduleEntry(at: Date())
  }

  func getSnapshot(in context: Context, completion: @escaping @Sendable (CommanderWatchWidgetEntry) -> Void) {
    Task {
      completion(await currentEntry(at: Date()))
    }
  }

  func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<CommanderWatchWidgetEntry>) -> Void) {
    Task {
      let now = Date()
      guard let snapshot = await cachedSnapshot() else {
        completion(Timeline(entries: [noScheduleEntry(at: now)], policy: .after(now.addingTimeInterval(30))))
        return
      }
      let schedule = snapshot.schedule
      let overrides = snapshot.leadTimeOverrides

      do {
        let horizon = now.addingTimeInterval(CommanderWatchWidgetContract.timelineHorizon)
        let entries = try WatchPreparedTimelinePlanner.entries(
          schedule: schedule,
          now: now,
          horizon: horizon,
          overrides: overrides
        ).map {
          CommanderWatchWidgetEntry(date: $0.date, liveState: $0.liveState)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
      } catch {
        completion(Timeline(entries: [noScheduleEntry(at: now)], policy: .after(now.addingTimeInterval(60))))
      }
    }
  }

  func relevance() async -> WidgetRelevance<Void> {
    guard let snapshot = await cachedSnapshot() else { return WidgetRelevance([]) }
    let now = Date()
    let horizon = now.addingTimeInterval(CommanderWatchWidgetContract.timelineHorizon)
    guard let windows = try? WatchPreparedTimelinePlanner.relevanceWindows(
      schedule: snapshot.schedule,
      now: now,
      horizon: horizon,
      overrides: snapshot.leadTimeOverrides
    ) else {
      return WidgetRelevance([])
    }
    let attributes = windows.map {
        WidgetRelevanceAttribute<Void>(
          context: .date(interval: $0.interval, kind: .scheduled)
        )
      }
    return WidgetRelevance(attributes)
  }

  private func currentEntry(at date: Date) async -> CommanderWatchWidgetEntry {
    guard let snapshot = await cachedSnapshot(),
          let liveState = try? WatchPreparedTimelinePlanner.currentState(
            schedule: snapshot.schedule,
            now: date,
            overrides: snapshot.leadTimeOverrides
          ) else {
      return noScheduleEntry(at: date)
    }
    return CommanderWatchWidgetEntry(date: date, liveState: liveState)
  }

  private func cachedSnapshot() async -> WatchScheduleSnapshot? {
    // The complication has a tight execution budget. Migration and network
    // recovery belong to the foreground Watch app; the widget only consumes
    // the already-prepared canonical App Group cache.
    let cache = WatchCacheLocation.makeCache()
    guard let cached = try? await cache.loadPrepared(),
          !WatchPreparedTimelinePlanner.isExpired(
            cached.schedule,
            at: Date(),
            overrides: cached.leadTimeOverrides
          ) else {
      return nil
    }
    return cached
  }

  private func noScheduleEntry(at date: Date) -> CommanderWatchWidgetEntry {
    CommanderWatchWidgetEntry(
      date: date,
      liveState: CommanderLiveStateCalculator.compute(schedule: nil, now: date)
    )
  }
}

private struct CommanderWatchWidgetView: View {
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced

  let entry: CommanderWatchWidgetEntry

  private var displayEvent: ScheduleEvent? {
    if let event = entry.liveState.event { return event }
    return entry.liveState.nextEvent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      switch entry.liveState.state {
      case .dayDone:
        dayDoneLines

      case .noSchedule:
        noScheduleLines

      case .upcoming, .leaveNow, .inProgress:
        if let event = displayEvent {
          eventHeader(event)
          firstLine
          referenceLine
        } else {
          noScheduleLines
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .privacySensitive(false)
    .containerBackground(.clear, for: .widget)
  }

  private func eventHeader(_ event: ScheduleEvent) -> some View {
    HStack(spacing: 6) {
      eventSymbol(event)

      ViewThatFits(in: .horizontal) {
        Text(event.title)
        Text(compactTitle(for: event))
      }
      .font(.headline.weight(.semibold))
      .lineLimit(1)
    }
    .foregroundStyle(.primary)
  }

  @ViewBuilder
  private func eventSymbol(_ event: ScheduleEvent) -> some View {
    let iconKey = WatchVisualAssets.icon(for: event)?.key
    let symbol = CommanderBrandAssets.procedureSymbol(
      iconKey: iconKey,
      title: event.title,
      isMeal: event.kind == .meal
    )

    if symbol == "commander.heat.waves" {
      CommanderProcedureArtwork(
        iconKey: iconKey,
        title: event.title,
        size: 18,
        kind: event.kind
      )
      .contrast(1.35)
    } else {
      Image(systemName: symbol)
        .symbolRenderingMode(.monochrome)
        .font(.system(size: 16, weight: .bold))
        .frame(width: 18, height: 18)
        .widgetAccentable()
    }
  }

  private func compactTitle(for event: ScheduleEvent) -> String {
    let normalized = event.title.folding(
      options: [.diacriticInsensitive, .caseInsensitive],
      locale: Locale(identifier: "cs_CZ")
    )
    if normalized.contains("ctyrkomor") { return "4komorová lázeň" }
    if let procedureType = event.procedureType,
       procedureType.count < event.title.count,
       procedureType.count <= 20 {
      return procedureType
    }
    return event.title
  }

  private var brandMark: some View {
    Image(CommanderBrandAssets.circularMarkName, bundle: .main)
      .renderingMode(.original)
      .resizable()
      .scaledToFit()
      .frame(width: 15, height: 15)
  }

  @ViewBuilder
  private var firstLine: some View {
    switch entry.liveState.state {
    case .upcoming:
      if let leaveAt = entry.liveState.leaveAt {
        countdownLine(
          label: "Vyrazit za",
          symbol: "figure.walk",
          target: leaveAt
        )
      }

    case .leaveNow:
      if let startAt = entry.liveState.startAt {
        countdownLine(
          label: "Začíná za",
          symbol: "figure.walk.motion",
          target: startAt
        )
      }

    case .inProgress:
      if let endAt = entry.liveState.endAt {
        countdownLine(
          label: "Končí za",
          symbol: "timer",
          target: endAt
        )
      }

    case .dayDone, .noSchedule:
      EmptyView()
    }
  }

  private func countdownLine(
    label: String,
    symbol: String,
    target: Date
  ) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .frame(width: 14, alignment: .leading)

      if isLuminanceReduced {
        Text(reducedCountdownText(to: target))
          .monospacedDigit()
      } else {
        Text(target, style: .timer)
          .monospacedDigit()
      }
    }
    .font(.headline.weight(.bold))
    .widgetAccentable()
    .lineLimit(1)
    .accessibilityLabel(label)
  }

  private func reducedCountdownText(to target: Date) -> String {
    let remainingSeconds = max(0, target.timeIntervalSince(entry.date))
    let totalMinutes = Int(ceil(remainingSeconds / 60))
    return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
  }

  private var referenceLine: some View {
    Group {
      switch entry.liveState.state {
      case .upcoming:
        if let startAt = entry.liveState.startAt {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Začátek")
            Text(startAt, style: .time).monospacedDigit()
          }
        }
      case .leaveNow:
        if let startAt = entry.liveState.startAt {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Začátek")
            Text(startAt, style: .time).monospacedDigit()
          }
        }
      case .inProgress:
        if let endAt = entry.liveState.endAt {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Konec")
            Text(endAt, style: .time).monospacedDigit()
          }
        }
      case .dayDone:
        if entry.liveState.nextEvent != nil, let leaveAt = entry.liveState.leaveAt {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Odchod")
            Text(leaveAt, style: .time).monospacedDigit()
          }
        }
      case .noSchedule:
        EmptyView()
      }
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private var nextEventDayLabel: String {
    guard let startAt = entry.liveState.startAt else { return "DALŠÍ" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    if calendar.isDateInTomorrow(startAt) { return "ZÍTRA" }
    return startAt.formatted(
      .dateTime.day().month(.abbreviated).locale(Locale(identifier: "cs_CZ"))
    ).uppercased(with: Locale(identifier: "cs_CZ"))
  }

  @ViewBuilder
  private var dayDoneLines: some View {
    if let nextEvent = entry.liveState.nextEvent {
      eventHeader(nextEvent)

      HStack(spacing: 4) {
        Image(systemName: "calendar")
        Text(nextEventDayLabel)
        if let startAt = entry.liveState.startAt {
          Text(startAt, style: .time).monospacedDigit()
        }
      }
      .font(.body.weight(.bold))
      .widgetAccentable()
      .lineLimit(1)

      if let leaveAt = entry.liveState.leaveAt {
        HStack(spacing: 4) {
          Image(systemName: "figure.walk")
          Text("Odchod")
          Text(leaveAt, style: .time).monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    } else {
      HStack(spacing: 5) {
        Image(systemName: "checkmark.circle.fill")
        Text("Dnes hotovo")
      }
      .font(.headline.weight(.semibold))
      .foregroundStyle(.primary)
      .lineLimit(1)

      Text("Další program není")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private var noScheduleLines: some View {
    HStack(spacing: 5) {
      brandMark
      Text("Bez rozpisu")
        .font(.headline.weight(.semibold))
    }
    .foregroundStyle(.primary)
    .lineLimit(1)

    Text("Otevři Commander")
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .lineLimit(1)
  }
}

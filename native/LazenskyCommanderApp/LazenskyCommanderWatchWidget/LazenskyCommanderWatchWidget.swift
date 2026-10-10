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
        let entries = try WatchTimelinePlanner.points(
          schedule: schedule,
          now: now,
          overrides: overrides
        )
        .filter { $0.date <= horizon }
        .map { point in
          let activeSchedule = point.transition == .expired ? nil : schedule
          return CommanderWatchWidgetEntry(
            date: point.date,
            liveState: CommanderLiveStateCalculator.compute(
              schedule: activeSchedule,
              now: point.date,
              overrides: overrides
            )
          )
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
    guard let windows = try? WatchTimelinePlanner.relevanceWindows(
      schedule: snapshot.schedule,
      now: now,
      overrides: snapshot.leadTimeOverrides
    ) else {
      return WidgetRelevance([])
    }
    let horizon = now.addingTimeInterval(CommanderWatchWidgetContract.timelineHorizon)
    let attributes = windows
      .filter { $0.interval.start <= horizon }
      .map {
        WidgetRelevanceAttribute<Void>(
          context: .date(interval: $0.interval, kind: .scheduled)
        )
      }
    return WidgetRelevance(attributes)
  }

  private func currentEntry(at date: Date) async -> CommanderWatchWidgetEntry {
    guard let snapshot = await cachedSnapshot() else { return noScheduleEntry(at: date) }
    let activeSchedule = WatchScheduleExpiryPolicy.activeSchedule(snapshot.schedule, at: date)
    return CommanderWatchWidgetEntry(
      date: date,
      liveState: CommanderLiveStateCalculator.compute(
        schedule: activeSchedule,
        now: date,
        overrides: snapshot.leadTimeOverrides
      )
    )
  }

  private func cachedSnapshot() async -> WatchScheduleSnapshot? {
    try? await WatchCacheLocation.migrateLegacyCacheIfNeeded()
    let cache = WatchCacheLocation.makeCache()

    if let cached = try? await cache.load(),
       !WatchScheduleExpiryPolicy.isExpired(cached.schedule, at: Date()) {
      return cached
    }

    // WidgetKit can occasionally wake before the Watch app has populated the
    // shared App Group cache. Recover independently from the canonical
    // production schedule instead of staying on "Čekám na rozpis".
    do {
      let schedule = try await URLSessionScheduleService(
        configuration: AppConfiguration()
      ).fetchSchedule()
      let overrides = LeadTimeOverrides(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: ["Vizita": 5]
      )
      let snapshot = WatchScheduleSnapshot(
        schedule: schedule,
        leadTimeOverrides: overrides
      )
      _ = try? await cache.accept(snapshot)
      return snapshot
    } catch {
      return nil
    }
  }

  private func noScheduleEntry(at date: Date) -> CommanderWatchWidgetEntry {
    CommanderWatchWidgetEntry(
      date: date,
      liveState: CommanderLiveStateCalculator.compute(schedule: nil, now: date)
    )
  }
}

private struct CommanderWatchWidgetView: View {
  let entry: CommanderWatchWidgetEntry

  private var displayEvent: ScheduleEvent? {
    if let event = entry.liveState.event { return event }
    return entry.liveState.nextEvent
  }

  private var commanderPurple: Color {
    Color(hex: WatchVisualAssets.colors?.brand.commanderPurple ?? "#6E56CF")
  }

  private var accent: Color {
    guard let event = displayEvent else { return commanderPurple }
    return Color(hex: WatchVisualAssets.accent(for: WatchVisualAssets.icon(for: event)))
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
    HStack(spacing: 5) {
      CommanderProcedureArtwork(
        iconKey: WatchVisualAssets.icon(for: event)?.key,
        title: event.title,
        size: 18,
        kind: event.kind
      )
      .widgetAccentable()

      Text(compactTitle(for: event))
        .font(.system(size: 13.5, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
        .minimumScaleFactor(0.62)
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
      HStack(spacing: 4) {
        Image(systemName: "figure.walk")
        Text("Vyrazit")
        if let leaveAt = entry.liveState.leaveAt {
          Text(leaveAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .widgetAccentable()
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .leaveNow:
      HStack(spacing: 4) {
        Image(systemName: "figure.walk")
        Text("Začíná")
        if let startAt = entry.liveState.startAt {
          Text(startAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .widgetAccentable()
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .inProgress:
      HStack(spacing: 4) {
        Image(systemName: "clock.fill")
        Text("Konec")
        if let endAt = entry.liveState.endAt {
          Text(endAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .widgetAccentable()
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .dayDone:
      HStack(spacing: 4) {
        Image(systemName: entry.liveState.nextEvent == nil ? "checkmark.circle.fill" : "arrow.right.circle.fill")
        Text(entry.liveState.nextEvent == nil ? "Dnes hotovo" : nextEventDayLabel)
      }
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .widgetAccentable()
      .lineLimit(1)

    case .noSchedule:
      EmptyView()
    }
  }

  private var referenceLine: some View {
    Group {
      switch entry.liveState.state {
      case .upcoming:
        if let leaveAt = entry.liveState.leaveAt {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text("Odchod")
            Text(leaveAt, style: .time).monospacedDigit()
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
    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
    .foregroundStyle(.white.opacity(0.88))
    .lineLimit(1)
    .minimumScaleFactor(0.78)
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
      .font(.system(size: 12.5, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .widgetAccentable()
      .lineLimit(1)

      if let leaveAt = entry.liveState.leaveAt {
        HStack(spacing: 4) {
          Image(systemName: "figure.walk")
          Text("Odchod")
          Text(leaveAt, style: .time).monospacedDigit()
        }
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.88))
        .lineLimit(1)
      }
    } else {
      HStack(spacing: 5) {
        Image(systemName: "checkmark.circle.fill")
        Text("Dnes hotovo")
      }
      .font(.system(size: 13.5, weight: .bold, design: .rounded))
      .foregroundStyle(.white)
      .lineLimit(1)

      Text("Další program není")
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
    }
  }

  @ViewBuilder
  private var noScheduleLines: some View {
    HStack(spacing: 5) {
      brandMark
      Text("Bez rozpisu")
        .font(.system(size: 13.5, weight: .bold, design: .rounded))
    }
    .foregroundStyle(.white)
    .lineLimit(1)

    Text("Otevři Commander")
      .font(.system(size: 11.5, weight: .semibold, design: .rounded))
      .foregroundStyle(.white.opacity(0.82))
      .lineLimit(1)
  }
}

private extension Color {
  init(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255,
      green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255
    )
  }
}

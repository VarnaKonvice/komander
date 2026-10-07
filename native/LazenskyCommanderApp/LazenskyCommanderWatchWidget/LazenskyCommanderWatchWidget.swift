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
        let entries = try WatchTimelinePlanner.points(
          schedule: schedule,
          now: now,
          overrides: overrides
        ).map { point in
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
        completion(Timeline(entries: [noScheduleEntry(at: now)], policy: .after(now.addingTimeInterval(30))))
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
    let attributes = windows.map {
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
      firstLine

      if let event = displayEvent {
        Text(event.title)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Text(event.location.isEmpty ? " " : event.location)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white.opacity(0.88))
          .lineLimit(1)
          .minimumScaleFactor(0.74)
      } else {
        noScheduleLines
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .privacySensitive(false)
    .containerBackground(.clear, for: .widget)
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
      HStack(spacing: 3) {
        brandMark
        Text("VYRAZIT ZA")
        if let leaveAt = entry.liveState.leaveAt {
          Text(leaveAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .leaveNow:
      HStack(spacing: 3) {
        brandMark
        Text("VYRAZIT")
        if let startAt = entry.liveState.startAt {
          Text("·")
          Text(startAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .inProgress:
      HStack(spacing: 3) {
        brandMark
        Text("PROBÍHÁ")
        if let endAt = entry.liveState.endAt {
          Text("·")
          Text(endAt, style: .relative)
            .monospacedDigit()
        }
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .lineLimit(1)
      .minimumScaleFactor(0.72)

    case .dayDone:
      HStack(spacing: 3) {
        brandMark
        if entry.liveState.nextEvent != nil {
          Text(nextEventDayLabel)
          if let leaveAt = entry.liveState.leaveAt {
            Text("· ODCHOD")
            Text(leaveAt, style: .time)
              .monospacedDigit()
          }
        } else {
          Text("DNES HOTOVO")
        }
      }
      .font(.system(size: 12, weight: .bold, design: .rounded))
      .foregroundStyle(accent)
      .lineLimit(1)
      .minimumScaleFactor(0.70)

    case .noSchedule:
      HStack(spacing: 4) {
        brandMark
        Text("ČEKÁM NA ROZPIS")
      }
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(.white)
      .lineLimit(1)
    }
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
  private var noScheduleLines: some View {
    switch entry.liveState.state {
    case .noSchedule:
      Text("Otevři Commander")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
      Text("Rozpis se obnoví automaticky")
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.82))
        .lineLimit(1)
    case .dayDone:
      if entry.liveState.nextEvent == nil {
        Text("Zbytek dne je volný")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text("Další program není")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
      }
    case .upcoming, .leaveNow, .inProgress:
      EmptyView()
    }
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

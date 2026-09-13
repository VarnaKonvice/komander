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
        completion(Timeline(entries: [noScheduleEntry(at: now)], policy: .never))
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
        completion(Timeline(entries: entries, policy: .never))
      } catch {
        completion(Timeline(entries: [noScheduleEntry(at: now)], policy: .never))
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
    try? await WatchCacheLocation.makeCache().load()
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

  private var icon: CommanderIconMap.Icon? {
    WatchVisualAssets.icon(for: entry.liveState.event)
  }

  private var commanderPurple: Color {
    Color(hex: WatchVisualAssets.colors?.brand.commanderPurple ?? "#6E56CF")
  }

  private var accent: Color {
    Color(hex: WatchVisualAssets.accent(for: icon))
  }

  var body: some View {
    HStack(spacing: 7) {
      if let event = entry.liveState.event {
        Image(systemName: CommanderBrandAssets.procedureSymbol(
          iconKey: icon?.key,
          title: event.title,
          isMeal: event.kind == .meal
        ))
        .font(.system(size: 21, weight: .semibold))
        .foregroundStyle(accent)
        .frame(width: 36, height: 36)
        .background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.72), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
      }

      VStack(alignment: .leading, spacing: 1) {
        stateHeader
        if let event = entry.liveState.event {
          Text(event.title)
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          if !event.location.isEmpty {
            Text(event.location)
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.78))
              .lineLimit(1)
          }
          timing
        } else {
          emptyState
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(.white)
    .containerBackground(commanderPurple, for: .widget)
  }

  @ViewBuilder
  private var stateHeader: some View {
    switch entry.liveState.state {
    case .upcoming:
      status("NADCHÁZÍ")
    case .leaveNow:
      status("VYRAZIT")
    case .inProgress:
      status("Právě probíhá")
    case .dayDone:
      status("PROGRAM DOKONČEN")
    case .noSchedule:
      status("LÁZEŇSKÝ COMMANDER")
    }
  }

  private func status(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 9, weight: .bold))
      .foregroundStyle(entry.liveState.state == .leaveNow ? accent : .white.opacity(0.86))
      .lineLimit(1)
  }

  @ViewBuilder
  private var timing: some View {
    switch entry.liveState.state {
    case .upcoming:
      if let leaveAt = entry.liveState.leaveAt, leaveAt.timeIntervalSince(entry.date) <= 30 * 60 {
        timer(label: "Odchod za", target: leaveAt, clock: entry.liveState.startAt)
      } else {
        timer(label: "Následuje za", target: entry.liveState.startAt, clock: entry.liveState.startAt)
      }
    case .leaveNow:
      timer(label: "Začátek za", target: entry.liveState.startAt, clock: nil)
    case .inProgress:
      if let endAt = entry.liveState.endAt {
        HStack(spacing: 2) {
          Text("do")
          Text(endAt, style: .time)
        }
        .font(.caption2.bold())
      }
    case .dayDone, .noSchedule:
      EmptyView()
    }
  }

  private func timer(label: String, target: Date?, clock: Date?) -> some View {
    HStack(spacing: 3) {
      Text(label)
      if let target {
        Text(.currentDate, format: .timer(
          countingDownIn: Date.distantPast..<target,
          showsHours: true,
          maxFieldCount: 2,
          maxPrecision: .seconds(1)
        ))
        .monospacedDigit()
      }
      if let clock {
        Text(clock, style: .time)
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .font(.caption2.bold())
    .lineLimit(1)
    .minimumScaleFactor(0.65)
  }

  @ViewBuilder
  private var emptyState: some View {
    switch entry.liveState.state {
    case .dayDone:
      Text("Dnešní program dokončen")
        .font(.caption.bold())
        .lineLimit(2)
    case .noSchedule:
      Text("Žádný dostupný program")
        .font(.caption.bold())
        .lineLimit(2)
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

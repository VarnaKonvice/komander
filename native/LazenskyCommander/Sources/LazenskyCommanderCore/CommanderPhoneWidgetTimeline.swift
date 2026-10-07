import Foundation

/// Materialize presentation once, outside SwiftUI's repeatedly evaluated body.
/// All entries share one validated projection; no entry reparses the month.
public struct CommanderPhoneWidgetPresentation: Sendable {
  public let hasSchedule: Bool
  public let live: CommanderLiveStateResult
  public let nextRelevantTodayStart: Date?
  public let remainingProcedureCount: Int
  public let finalProcedureEnd: Date?
  public let dinnerStart: Date?

  public init(projection: CommanderScheduleProjection?, at date: Date) {
    guard let projection,
          let finalEnd = projection.events.map(\.endAt).max(),
          date < finalEnd.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod) else {
      hasSchedule = false
      live = .init(state: .noSchedule, now: date)
      nextRelevantTodayStart = nil
      remainingProcedureCount = 0
      finalProcedureEnd = nil
      dinnerStart = nil
      return
    }
    hasSchedule = true
    let state = projection.liveState(at: date)
    live = .init(state: state.state == .leaveNow ? .upcoming : state.state,
      event: state.event, nextEvent: state.nextEvent, startAt: state.startAt, endAt: state.endAt, now: date)
    switch state.state {
    case .upcoming, .leaveNow: nextRelevantTodayStart = state.startAt
    case .inProgress:
      nextRelevantTodayStart = projection.events.first { $0.event.stableId == state.nextEvent?.stableId }?.startAt
    case .dayDone, .noSchedule: nextRelevantTodayStart = nil
    }
    let today = projection.events(on: date)
    let procedures = today.filter { $0.event.kind == .procedure }
    remainingProcedureCount = procedures.filter { $0.endAt > date }.count
    finalProcedureEnd = procedures.map(\.endAt).max()
    dinnerStart = today.filter {
      $0.event.kind == .meal && $0.event.title.folding(options: [.diacriticInsensitive, .caseInsensitive],
        locale: Locale(identifier: "cs_CZ")).lowercased().contains("vecer")
    }.map(\.startAt).min()
  }
}

public struct CommanderPhoneWidgetTimelinePoint: Sendable {
  public let date: Date
  public let presentation: CommanderPhoneWidgetPresentation
}

public enum CommanderPhoneWidgetTimeline {
  public static let horizon: TimeInterval = 24 * 60 * 60
  public static let refreshInterval: TimeInterval = 6 * 60 * 60

  public static func points(snapshot: WatchScheduleSnapshot, now: Date) throws -> [CommanderPhoneWidgetTimelinePoint] {
    let projection = try CommanderScheduleProjection(schedule: snapshot.schedule, overrides: snapshot.leadTimeOverrides)
    let end = now.addingTimeInterval(horizon)
    var dates: Set<Date> = [now]
    func include(_ date: Date) {
      if date >= now && date <= end { dates.insert(date) }
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    for event in projection.events {
      include(calendar.startOfDay(for: event.startAt))
      include(event.leaveAt)
      include(event.startAt)
      include(event.endAt)
      let countdown = try AlarmCountdown.countdownWindow(for: event.alarm, in: snapshot.schedule)
      include(event.leaveAt.addingTimeInterval(-countdown))
    }
    if let finalEnd = projection.events.map(\.endAt).max() {
      include(finalEnd.addingTimeInterval(CommanderWatchWidgetContract.expiryGracePeriod))
    }
    return dates.sorted().map {
      .init(date: $0, presentation: .init(projection: projection, at: $0))
    }
  }
}

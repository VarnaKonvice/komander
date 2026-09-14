import Foundation

public enum CommanderDinnerContext: Equatable, Sendable {
  case proceduresEnded
  case noProcedures
}

public struct CommanderDaySummary: Equatable, Sendable {
  public let procedureCount: Int
  public let firstEventStartAt: Date?
  public let lastEventStartAt: Date?
  public let lastEventEndAt: Date?
  public let lastProcedureEndAt: Date?
  public let dinnerStartAt: Date?
  public let freeBeforeDinner: DateInterval?
  public let dinnerContext: CommanderDinnerContext?
  public let minutesUntilDinner: Int?

  public var freeBeforeDinnerMinutes: Int? {
    freeBeforeDinner.map { Int(ceil($0.duration / 60)) }
  }

  static func make(timeline: [CommanderDashboardEvent], now: Date) -> Self {
    let procedures = timeline.filter { $0.event.kind == .procedure }
    let lastProcedureEnd = procedures.map(\.endAt).max()
    let dinner = timeline.first { isDinner($0.event) }
    let dinnerIsAhead = dinner.map { now < $0.startAt } ?? false
    let context: CommanderDinnerContext?
    if dinnerIsAhead, procedures.isEmpty {
      context = .noProcedures
    } else if dinnerIsAhead, let lastProcedureEnd, now >= lastProcedureEnd {
      context = .proceduresEnded
    } else {
      context = nil
    }

    return Self(
      procedureCount: procedures.count,
      firstEventStartAt: timeline.first?.startAt,
      lastEventStartAt: timeline.last?.startAt,
      lastEventEndAt: timeline.last?.endAt,
      lastProcedureEndAt: lastProcedureEnd,
      dinnerStartAt: dinner?.startAt,
      freeBeforeDinner: dinnerIsAhead ? dinner.flatMap {
        freeInterval(before: $0, notBefore: lastProcedureEnd ?? now, timeline: timeline)
      } : nil,
      dinnerContext: context,
      minutesUntilDinner: context == nil ? nil : dinner.map {
        Int(ceil($0.startAt.timeIntervalSince(now) / 60))
      }
    )
  }

  fileprivate static func isDinner(_ event: ScheduleEvent) -> Bool {
    guard event.kind == .meal else { return false }
    let type = event.mealType?.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = type.flatMap { $0.isEmpty ? nil : $0 } ?? event.title
    return name.trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ")) == "vecere"
  }

  fileprivate static func freeInterval(
    before dinner: CommanderDashboardEvent,
    notBefore start: Date,
    timeline: [CommanderDashboardEvent]
  ) -> DateInterval? {
    guard start < dinner.startAt else { return nil }
    // Only the uninterrupted gap immediately before dinner is free, not intervening meals.
    let occupiedUntil = timeline.filter {
      $0.event.stableId != dinner.event.stableId && $0.startAt < dinner.startAt && $0.endAt > start
    }.map(\.endAt).max() ?? start
    let freeStart = max(start, occupiedUntil)
    guard freeStart < dinner.startAt else { return nil }
    return DateInterval(start: freeStart, end: dinner.startAt)
  }
}

public struct CommanderDayOverview: Equatable, Sendable {
  public let date: Date
  public let procedureCount: Int
  public let procedureEndAt: Date?
  public let dinnerStartAt: Date?
  public let freeBeforeDinner: DateInterval?
  public let firstRelevantStartAt: Date?
  public let firstRelevantTitle: String?

  public var freeBeforeDinnerMinutes: Int? {
    freeBeforeDinner.map { Int(ceil($0.duration / 60)) }
  }

  public static func make(date: Date, timeline: [CommanderDashboardEvent], now: Date) -> Self {
    let summary = CommanderDaySummary.make(timeline: timeline, now: now)
    let dinner = timeline.first { CommanderDaySummary.isDinner($0.event) }
    let freeBeforeDinner = summary.lastProcedureEndAt.flatMap { procedureEnd in
      dinner.flatMap { CommanderDaySummary.freeInterval(before: $0, notBefore: procedureEnd, timeline: timeline) }
    }
    let firstRelevant = timeline.first { $0.phase != .past } ?? timeline.first

    return Self(
      date: date,
      procedureCount: summary.procedureCount,
      procedureEndAt: summary.lastProcedureEndAt,
      dinnerStartAt: summary.dinnerStartAt,
      freeBeforeDinner: freeBeforeDinner,
      firstRelevantStartAt: firstRelevant?.startAt,
      firstRelevantTitle: firstRelevant?.event.title
    )
  }
}

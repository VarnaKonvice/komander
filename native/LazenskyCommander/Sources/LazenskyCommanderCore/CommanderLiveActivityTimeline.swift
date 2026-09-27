import Foundation

public enum CommanderLiveActivityTimelinePhase: Equatable, Sendable {
  case upcoming
  case active
  case ended
}

public enum CommanderLiveActivityNextRelation: Equatable, Sendable {
  case following
  case concurrent
}

public struct CommanderLiveActivityTimelineEvent: Equatable, Sendable {
  public let stableId: String
  public let leaveAt: Date
  public let startAt: Date
  public let endAt: Date

  public init(stableId: String, leaveAt: Date, startAt: Date, endAt: Date) {
    self.stableId = stableId
    self.leaveAt = leaveAt
    self.startAt = startAt
    self.endAt = endAt
  }
}

public struct CommanderLiveActivityTimelineResolution: Equatable, Sendable {
  public let primaryStableId: String
  public let phase: CommanderLiveActivityTimelinePhase
  public let departureDue: Bool
  public let countdownTarget: Date
  public let nextStableId: String?
  public let nextRelation: CommanderLiveActivityNextRelation?

  public init(
    primaryStableId: String,
    phase: CommanderLiveActivityTimelinePhase,
    departureDue: Bool,
    countdownTarget: Date,
    nextStableId: String?,
    nextRelation: CommanderLiveActivityNextRelation?
  ) {
    self.primaryStableId = primaryStableId
    self.phase = phase
    self.departureDue = departureDue
    self.countdownTarget = countdownTarget
    self.nextStableId = nextStableId
    self.nextRelation = nextRelation
  }
}

public enum CommanderLiveActivityTimeline {
  public static func resolve(
    events: [CommanderLiveActivityTimelineEvent],
    at date: Date,
    isStale: Bool = false
  ) -> CommanderLiveActivityTimelineResolution? {
    let ordered = events.sorted(by: eventOrder)
    guard !ordered.isEmpty else { return nil }

    let primaryIndex: Int
    if let departureIndex = ordered.firstIndex(where: {
      $0.leaveAt <= date && date < $0.startAt
    }) {
      // The next required departure is more actionable than an earlier event that
      // may still be running (for example breakfast while it is time to leave).
      primaryIndex = departureIndex
    } else {
      let activeIndices = ordered.indices.filter {
        ordered[$0].startAt <= date && date < ordered[$0].endAt
      }
      if let latestActiveStart = activeIndices.map({ ordered[$0].startAt }).max(),
         let activeIndex = activeIndices.first(where: { ordered[$0].startAt == latestActiveStart }) {
        // Once a later event has actually started it must not hand the UI back to an
        // earlier overlapping event. This keeps a departure handoff stable at startAt.
        primaryIndex = activeIndex
      } else if let upcomingIndex = ordered.firstIndex(where: { $0.startAt > date }) {
        primaryIndex = upcomingIndex
      } else {
        primaryIndex = ordered.indices.last!
      }
    }

    let primary = ordered[primaryIndex]
    let phase: CommanderLiveActivityTimelinePhase
    if isStale {
      phase = .ended
    } else if date < primary.startAt {
      phase = .upcoming
    } else if date < primary.endAt {
      phase = .active
    } else {
      phase = .ended
    }

    let departureDue = phase == .upcoming && date >= primary.leaveAt
    let countdownTarget: Date
    switch phase {
    case .upcoming:
      countdownTarget = departureDue ? primary.startAt : primary.leaveAt
    case .active, .ended:
      countdownTarget = primary.endAt
    }

    let following = ordered.dropFirst(primaryIndex + 1).first(where: { $0.endAt > date })
    let relation: CommanderLiveActivityNextRelation?
    if let following {
      relation = (following.startAt <= date && date < following.endAt) ? .concurrent : .following
    } else {
      relation = nil
    }

    return CommanderLiveActivityTimelineResolution(
      primaryStableId: primary.stableId,
      phase: phase,
      departureDue: departureDue,
      countdownTarget: countdownTarget,
      nextStableId: following?.stableId,
      nextRelation: relation
    )
  }

  public static func boundaryDates(
    events: [CommanderLiveActivityTimelineEvent]
  ) -> [Date] {
    Array(Set(events.flatMap { [$0.leaveAt, $0.startAt, $0.endAt] })).sorted()
  }

  private static func eventOrder(
    _ lhs: CommanderLiveActivityTimelineEvent,
    _ rhs: CommanderLiveActivityTimelineEvent
  ) -> Bool {
    if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
    return lhs.stableId < rhs.stableId
  }
}

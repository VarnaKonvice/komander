import Foundation

/// Pure planning layer for Commander Live Activity windows.
///
/// AlarmKit remains responsible for every departure alarm. Live Activities provide
/// continuous context around nearby events, but long free gaps intentionally create
/// separate windows. Pending successor windows may be scheduled in advance.
public struct CommanderLiveActivityPlan: Equatable, Sendable {
  public static let defaultContextLeadTime: TimeInterval = 60 * 60
  public static let defaultMaximumIdleGap: TimeInterval = 2 * 60 * 60
  public static let defaultMaximumScheduledWindows = 3

  public let anchorStableID: String
  public let activationStart: Date
  public let windowEnd: Date
  public let includedStableIDs: [String]

  public init(
    anchorStableID: String,
    activationStart: Date,
    windowEnd: Date,
    includedStableIDs: [String]
  ) {
    self.anchorStableID = anchorStableID
    self.activationStart = activationStart
    self.windowEnd = windowEnd
    self.includedStableIDs = includedStableIDs
  }

  public static func make(
    schedule: Schedule,
    payload: NativeAlarmPayload,
    now: Date,
    contextLeadTime: TimeInterval = defaultContextLeadTime,
    maximumIdleGap: TimeInterval = defaultMaximumIdleGap,
    maximumActiveLifetime: TimeInterval = 7 * 60 * 60 + 50 * 60,
    maximumEvents: Int = 6
  ) -> CommanderLiveActivityPlan? {
    makeWindows(
      schedule: schedule,
      payload: payload,
      now: now,
      contextLeadTime: contextLeadTime,
      maximumIdleGap: maximumIdleGap,
      maximumActiveLifetime: maximumActiveLifetime,
      maximumEvents: maximumEvents,
      maximumWindows: 1
    ).first
  }

  public static func makeWindows(
    schedule: Schedule,
    payload: NativeAlarmPayload,
    now: Date,
    contextLeadTime: TimeInterval = defaultContextLeadTime,
    maximumIdleGap: TimeInterval = defaultMaximumIdleGap,
    maximumActiveLifetime: TimeInterval = 7 * 60 * 60 + 50 * 60,
    maximumEvents: Int = 6,
    maximumWindows: Int = defaultMaximumScheduledWindows
  ) -> [CommanderLiveActivityPlan] {
    guard maximumEvents > 0, maximumWindows > 0 else { return [] }

    let alarmByID = Dictionary(uniqueKeysWithValues: payload.alarms.map { ($0.stableId, $0) })
    let candidates = schedule.events.compactMap { event -> Candidate? in
      guard let alarm = alarmByID[event.stableId],
            let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
            let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
            let endAt = try? NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      else { return nil }

      let contextStart = min(leaveAt, startAt.addingTimeInterval(-max(0, contextLeadTime)))
      return Candidate(
        event: event,
        leaveAt: leaveAt,
        startAt: startAt,
        endAt: endAt,
        contextStart: contextStart
      )
    }.sorted(by: candidateOrder)

    guard !candidates.isEmpty else { return [] }

    var plans: [CommanderLiveActivityPlan] = []
    var cursor = 0
    var previousWindowEnd: Date?

    while cursor < candidates.count {
      let anchor = candidates[cursor]
      let baseActivation = anchor.contextStart
      let activationStart = max(baseActivation, previousWindowEnd ?? baseActivation)
      let hardWindowEnd = activationStart.addingTimeInterval(maximumActiveLifetime)

      var included: [Candidate] = []
      var coverageEnd = activationStart
      var index = cursor

      while index < candidates.count && included.count < maximumEvents {
        let candidate = candidates[index]
        let idleGap = candidate.startAt.timeIntervalSince(coverageEnd)

        if !included.isEmpty && idleGap > max(0, maximumIdleGap) {
          break
        }
        if candidate.endAt > hardWindowEnd {
          break
        }

        included.append(candidate)
        coverageEnd = max(coverageEnd, candidate.endAt)
        index += 1
      }

      if included.isEmpty {
        // Spa events are short in practice. If a single event exceeds the ActivityKit
        // lifetime budget, keep it as the anchor rather than dropping all context.
        included = [anchor]
        coverageEnd = min(anchor.endAt, hardWindowEnd)
        index = cursor + 1
      }

      plans.append(CommanderLiveActivityPlan(
        anchorStableID: anchor.event.stableId,
        activationStart: activationStart,
        windowEnd: coverageEnd,
        includedStableIDs: included.map(\.event.stableId)
      ))
      previousWindowEnd = coverageEnd
      cursor = index
    }

    return Array(plans.lazy.filter { $0.windowEnd > now }.prefix(maximumWindows))
  }

  private struct Candidate {
    let event: ScheduleEvent
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
    let contextStart: Date
  }

  private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
    return lhs.event.stableId < rhs.event.stableId
  }
}

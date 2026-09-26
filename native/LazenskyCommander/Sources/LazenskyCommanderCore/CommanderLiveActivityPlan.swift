import Foundation

/// Pure planning layer for the single Commander Live Activity.
///
/// AlarmKit remains responsible for every departure alarm. This planner only chooses the
/// one mandatory-procedure window that Commander may represent without exceeding the
/// ActivityKit active-lifetime budget.
public struct CommanderLiveActivityPlan: Equatable, Sendable {
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
    maximumActiveLifetime: TimeInterval = 7 * 60 * 60 + 50 * 60,
    maximumEvents: Int = 6
  ) -> CommanderLiveActivityPlan? {
    let alarmByID = Dictionary(uniqueKeysWithValues: payload.alarms.map { ($0.stableId, $0) })
    let candidates = schedule.events.compactMap { event -> Candidate? in
      guard let alarm = alarmByID[event.stableId],
            let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
            let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
            let endAt = try? NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      else { return nil }
      return Candidate(event: event, leaveAt: leaveAt, startAt: startAt, endAt: endAt)
    }.sorted(by: candidateOrder)

    guard let anchor = candidates.first(where: {
      $0.event.kind == .procedure && $0.endAt > now
    }) else { return nil }

    let activationStart = anchor.leaveAt
    let windowEnd = activationStart.addingTimeInterval(maximumActiveLifetime)
    let included = candidates.filter {
      $0.endAt > now &&
      $0.endAt > activationStart &&
      $0.endAt <= windowEnd
    }.prefix(max(1, maximumEvents))

    let stableIDs = included.map(\.event.stableId)
    guard stableIDs.contains(anchor.event.stableId) else { return nil }

    return CommanderLiveActivityPlan(
      anchorStableID: anchor.event.stableId,
      activationStart: activationStart,
      windowEnd: windowEnd,
      includedStableIDs: stableIDs
    )
  }

  private struct Candidate {
    let event: ScheduleEvent
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
  }

  private static func candidateOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
    if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
    return lhs.event.stableId < rhs.event.stableId
  }
}

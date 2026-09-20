import ActivityKit
import Foundation
import LazenskyCommanderCore

/// Reconciles exactly one Commander Live Activity.
///
/// AlarmKit owns departure/countdown/alert and the Stop intent is the only creator of
/// Commander. Foreground reconciliation may update that same activity and remove legacy
/// duplicates, but it never creates another Commander instance. The dynamic state carries
/// a short ordered queue of events, so overlaps and handoffs happen inside one Live Activity.
actor CommanderProcedureLiveActivityCoordinator {
  static let maximumConcurrentActivities = 1

  private let enabled: Bool
  private(set) var issue: String?
  private var reconciliationTail: Task<Void, Never>?
  private var reconciliationGeneration = 0

  private struct RawCandidate {
    let event: ScheduleEvent
    let alarm: NativeAlarm
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
  }

  init(enabled: Bool = true) {
    self.enabled = enabled
  }

  func reconcile(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int,
    now: Date = Date()
  ) async {
    reconciliationGeneration += 1
    let generation = reconciliationGeneration
    let previous = reconciliationTail
    let task = Task { [weak self] in
      if let previous { await previous.value }
      guard let self else { return }
      await self.performReconcile(
        schedule: schedule,
        overrides: overrides,
        projectionRevision: projectionRevision,
        now: now
      )
    }
    reconciliationTail = task
    await task.value
    if generation == reconciliationGeneration {
      reconciliationTail = nil
    }
  }

  private func performReconcile(
    schedule: Schedule,
    overrides: LeadTimeOverrides?,
    projectionRevision: Int,
    now: Date
  ) async {
    issue = nil
    guard enabled else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      issue = "Živé aktivity nejsou povolené."
      return
    }
    guard let payload = try? NativeAlarmContract.payload(schedule: schedule, overrides: overrides) else {
      issue = "Rozpis nelze převést na canonical alarm payload."
      return
    }

    let raw = Self.rawCandidates(schedule: schedule, payload: payload)
    let queue = Self.queue(from: raw, now: now)
    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities
      .filter { Self.isOngoing($0.activityState) }
      .sorted { Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState) }

    if queue.isEmpty {
      for activity in existing {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      return
    }

    let snapshots = queue.map(Self.snapshot)

    if let keeper = existing.first {
      let state = CommanderProcedureLiveActivityPolicy.contentState(
        scheduleVersion: schedule.scheduleVersion,
        projectionRevision: projectionRevision,
        events: snapshots,
        attributes: keeper.attributes
      )
      await keeper.update(ActivityContent(
        state: state,
        staleDate: Self.staleDate(for: state.events),
        relevanceScore: 1_000
      ))
      for duplicate in existing.dropFirst() {
        await duplicate.end(nil, dismissalPolicy: .immediate)
      }
      return
    }

    // Stop intent is the only creator. If no Commander exists yet, reconciliation
    // deliberately waits for the next explicit Stop handoff instead of racing another request.
    return
  }

  func preparedStableIDs(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int,
    now: Date = Date()
  ) -> Set<String> {
    guard let payload = try? NativeAlarmContract.payload(schedule: schedule, overrides: overrides) else {
      return []
    }
    let expectedQueue = Self.queue(from: Self.rawCandidates(schedule: schedule, payload: payload), now: now)
      .map(Self.snapshot)
    guard let activity = Activity<CommanderProcedureLiveActivityAttributes>.activities.first(where: {
      Self.isOngoing($0.activityState)
    }) else { return [] }

    guard activity.content.state.scheduleVersion == schedule.scheduleVersion,
          activity.content.state.projectionRevision == max(0, projectionRevision)
    else { return [] }

    let actualIDs = activity.content.state.events.map(\.stableId)
    let expectedIDs = expectedQueue.map(\.stableId)
    guard actualIDs == Array(expectedIDs.prefix(actualIDs.count)) else { return [] }
    return [activity.attributes.stableId]
  }

  private static func rawCandidates(
    schedule: Schedule,
    payload: NativeAlarmPayload
  ) -> [RawCandidate] {
    let alarmByID = Dictionary(uniqueKeysWithValues: payload.alarms.map { ($0.stableId, $0) })
    return schedule.events.compactMap { event -> RawCandidate? in
      guard let alarm = alarmByID[event.stableId],
            let leaveAt = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
            let startAt = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
            let endAt = try? NativeAlarmContract.date(fromLocalISO: alarm.endAt)
      else { return nil }
      return RawCandidate(
        event: event,
        alarm: alarm,
        leaveAt: leaveAt,
        startAt: startAt,
        endAt: endAt
      )
    }.sorted(by: rawCandidateOrder)
  }

  private static func queue(from raw: [RawCandidate], now: Date) -> [RawCandidate] {
    let remaining = raw.filter { $0.endAt > now }
    guard !remaining.isEmpty else { return [] }

    // Once Commander exists, keep the currently running event(s) first and then future ones.
    // If nothing is running yet, keep the nearest upcoming events. This naturally preserves
    // an older active procedure above a newer overlapping meal until the older one ends.
    return Array(remaining.prefix(CommanderProcedureLiveActivityPolicy.maximumQueuedEvents))
  }

  private static func staleDate(for events: [CommanderAlarmEventSnapshot]) -> Date? {
    events.compactMap { try? NativeAlarmContract.date(fromLocalISO: $0.endAt) }.max()
  }

  private static func snapshot(_ candidate: RawCandidate) -> CommanderAlarmEventSnapshot {
    CommanderAlarmEventSnapshot(
      stableId: candidate.event.stableId,
      iconKey: CommanderVisualAssets.icon(for: candidate.event)?.key ?? "",
      title: candidate.event.title,
      location: candidate.event.location,
      kind: candidate.event.kind,
      startAt: candidate.alarm.startAt,
      endAt: candidate.alarm.endAt,
      leaveAt: candidate.alarm.leaveAt
    )
  }

  private static func isOngoing(_ state: ActivityState) -> Bool {
    state == .pending || state == .active || state == .stale
  }

  private static func retentionRank(_ state: ActivityState) -> Int {
    switch state {
    case .active: 0
    case .pending: 1
    case .stale: 2
    case .ended: 3
    case .dismissed: 4
    @unknown default: 5
    }
  }

  private static func rawCandidateOrder(_ lhs: RawCandidate, _ rhs: RawCandidate) -> Bool {
    if lhs.startAt != rhs.startAt { return lhs.startAt < rhs.startAt }
    return lhs.event.stableId < rhs.event.stableId
  }
}

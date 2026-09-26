import ActivityKit
import Foundation
import LazenskyCommanderCore

/// Owns one Commander Live Activity for the mandatory-procedure part of the day.
///
/// AlarmKit remains the audible departure layer. Commander is requested while the app
/// legitimately has foreground execution time. If the next mandatory procedure is still
/// in the future, ActivityKit receives a scheduled start at its canonical `leaveAt`.
/// The Stop intent never creates a Live Activity from the background.
actor CommanderProcedureLiveActivityCoordinator {
  static let maximumConcurrentActivities = 1
  static let maximumActiveLifetime: TimeInterval = 7 * 60 * 60 + 50 * 60
  static let silentAlertSoundName = "CommanderSilentAlert.wav"

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
    let plan = CommanderLiveActivityPlan.make(
      schedule: schedule,
      payload: payload,
      now: now,
      maximumActiveLifetime: Self.maximumActiveLifetime,
      maximumEvents: CommanderProcedureLiveActivityPolicy.maximumQueuedEvents
    )
    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities
      .filter { Self.isOngoing($0.activityState) }
      .sorted { Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState) }

    guard let plan else {
      for activity in existing {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      return
    }

    let candidateByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.event.stableId, $0) })
    let plannedQueue = plan.includedStableIDs.compactMap { candidateByID[$0] }
    let plannedSnapshots = plannedQueue.map(Self.snapshot)

    if let keeper = existing.first {
      if keeper.attributes.rendererRevision != CommanderProcedureLiveActivityAttributes.currentRendererRevision {
        for activity in existing {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        await requestPlannedActivity(
          plan: plan,
          raw: raw,
          scheduleVersion: schedule.scheduleVersion,
          projectionRevision: projectionRevision,
          now: now
        )
        return
      }

      if keeper.activityState == .pending {
        let pendingIsFresh =
          keeper.attributes.stableId == plan.anchorStableID &&
          keeper.attributes.scheduleVersion == schedule.scheduleVersion &&
          abs(keeper.attributes.leaveAt.timeIntervalSince(plan.activationStart)) <= 1 &&
          keeper.content.state.scheduleVersion == schedule.scheduleVersion &&
          keeper.content.state.projectionRevision == max(0, projectionRevision) &&
          keeper.content.state.events == plannedSnapshots

        if pendingIsFresh {
          for duplicate in existing.dropFirst() {
            await duplicate.end(nil, dismissalPolicy: .immediate)
          }
          return
        }

        for activity in existing {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      } else {
        let activationStart = keeper.attributes.leaveAt
        let queue = Self.queue(from: raw, activationStart: activationStart, now: now)
        if !queue.isEmpty {
          let snapshots = queue.map(Self.snapshot)
          let state = CommanderProcedureLiveActivityPolicy.contentState(
            scheduleVersion: schedule.scheduleVersion,
            projectionRevision: projectionRevision,
            events: snapshots,
            attributes: keeper.attributes
          )
          await keeper.update(ActivityContent(
            state: state,
            staleDate: Self.staleDate(for: state.events, activationStart: activationStart),
            relevanceScore: 1_000
          ))
          for duplicate in existing.dropFirst() {
            await duplicate.end(nil, dismissalPolicy: .immediate)
          }
          return
        }

        for activity in existing {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
      }
    }

    await requestPlannedActivity(
      plan: plan,
      raw: raw,
      scheduleVersion: schedule.scheduleVersion,
      projectionRevision: projectionRevision,
      now: now
    )
  }

  private func requestPlannedActivity(
    plan: CommanderLiveActivityPlan,
    raw: [RawCandidate],
    scheduleVersion: Int,
    projectionRevision: Int,
    now: Date
  ) async {
    guard let anchor = raw.first(where: { $0.event.stableId == plan.anchorStableID }) else {
      issue = "Commander Live Activity nemá platnou kotevní proceduru."
      return
    }

    let candidateByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.event.stableId, $0) })
    let queue = plan.includedStableIDs.compactMap { candidateByID[$0] }
    guard !queue.isEmpty else { return }

    let snapshots = queue.map(Self.snapshot)
    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: anchor.event.stableId,
      scheduleVersion: scheduleVersion,
      iconKey: CommanderVisualAssets.icon(for: anchor.event)?.key ?? "",
      title: anchor.event.title,
      location: anchor.event.location,
      kind: anchor.event.kind,
      leaveAt: plan.activationStart,
      startAt: anchor.startAt,
      endAt: anchor.endAt,
      nextEvent: snapshots.dropFirst().first
    )
    let state = CommanderProcedureLiveActivityPolicy.contentState(
      scheduleVersion: scheduleVersion,
      projectionRevision: projectionRevision,
      events: snapshots,
      attributes: attributes
    )
    let content = ActivityContent(
      state: state,
      staleDate: Self.staleDate(for: state.events, activationStart: plan.activationStart),
      relevanceScore: 1_000
    )

    do {
      if plan.activationStart <= now {
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard
        )
      } else {
        guard Bundle.main.url(forResource: "CommanderSilentAlert", withExtension: "wav") != nil else {
          issue = "Chybí tichý zvuk pro plánovaný start Commander Live Activity."
          return
        }
        let alert = ActivityKit.AlertConfiguration(
          title: LocalizedStringResource(stringLiteral: "Lázeňský Commander"),
          body: LocalizedStringResource(stringLiteral: "Následuje · \(anchor.event.title)"),
          sound: .named(Self.silentAlertSoundName)
        )
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard,
          alertConfiguration: alert,
          start: plan.activationStart
        )
      }
    } catch {
      issue = "Commander Live Activity se nepodařilo připravit: \(error.localizedDescription)"
    }
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
    guard let activity = Activity<CommanderProcedureLiveActivityAttributes>.activities.first(where: {
      Self.isOngoing($0.activityState)
    }) else { return [] }

    let raw = Self.rawCandidates(schedule: schedule, payload: payload)
    let expectedQueue = Self.queue(
      from: raw,
      activationStart: activity.attributes.leaveAt,
      now: now
    ).map(Self.snapshot)

    guard activity.attributes.rendererRevision == CommanderProcedureLiveActivityAttributes.currentRendererRevision,
          activity.content.state.scheduleVersion == schedule.scheduleVersion,
          activity.content.state.projectionRevision == max(0, projectionRevision)
    else { return [] }

    let actualIDs = activity.content.state.events.map(\.stableId)
    let expectedIDs = expectedQueue.map(\.stableId)
    guard !actualIDs.isEmpty,
          actualIDs == Array(expectedIDs.prefix(actualIDs.count))
    else { return [] }
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

  private static func queue(
    from raw: [RawCandidate],
    activationStart: Date,
    now: Date
  ) -> [RawCandidate] {
    let windowEnd = activationStart.addingTimeInterval(maximumActiveLifetime)
    let remaining = raw.filter {
      $0.endAt > now &&
      $0.endAt > activationStart &&
      $0.endAt <= windowEnd
    }
    return Array(remaining.prefix(CommanderProcedureLiveActivityPolicy.maximumQueuedEvents))
  }

  private static func staleDate(
    for events: [CommanderAlarmEventSnapshot],
    activationStart: Date
  ) -> Date? {
    let windowEnd = activationStart.addingTimeInterval(maximumActiveLifetime)
    let lastEventEnd = events.compactMap { try? NativeAlarmContract.date(fromLocalISO: $0.endAt) }.max()
    return lastEventEnd.map { min($0, windowEnd) }
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

import ActivityKit
import Foundation
import LazenskyCommanderCore
import OSLog

/// Owns the local Commander procedure/meal Live Activity lifecycle.
///
/// AlarmKit owns departure/countdown/alert. Commander activities are prepared locally
/// in a small rolling window. Each activity starts at the event's canonical leaveAt,
/// so stopping the AlarmKit alert never leaves the person without the next event context.
/// When an activity becomes stale, its UI can fall forward to the embedded next-event
/// snapshot even if the system keeps the older activity visible for a while.
actor CommanderProcedureLiveActivityCoordinator {
  static let maximumPreparedActivities = 2

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

  private struct Candidate {
    let event: ScheduleEvent
    let alarm: NativeAlarm
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
    let nextEvent: CommanderAlarmEventSnapshot?
    let contentState: CommanderProcedureLiveActivityAttributes.ContentState
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

    guard let payload = try? NativeAlarmContract.payload(
      schedule: schedule,
      overrides: overrides
    ) else {
      issue = "Rozpis nelze převést na canonical alarm payload."
      return
    }

    let candidates = Self.candidates(
      schedule: schedule,
      payload: payload,
      projectionRevision: projectionRevision,
      now: now
    )
    let desired = Array(candidates.prefix(Self.maximumPreparedActivities))
    let relevanceScores = Dictionary(uniqueKeysWithValues: desired.enumerated().map {
      ($0.element.event.stableId, Double(($0.offset + 1) * 100))
    })
    let existing = Activity<CommanderProcedureLiveActivityAttributes>.activities.sorted {
      Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState)
    }
    var retainedStableIDs = Set<String>()

    for activity in existing {
      if activity.attributes.endAt <= now {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }

      guard Self.isOngoing(activity.activityState),
            let match = desired.first(where: {
              Self.matches(activity, $0, scheduleVersion: schedule.scheduleVersion)
            })
      else {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }

      guard retainedStableIDs.insert(activity.attributes.stableId).inserted else {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }

      await activity.update(ActivityContent(
        state: match.contentState,
        staleDate: match.endAt,
        relevanceScore: relevanceScores[match.event.stableId] ?? 0
      ))
    }

    for candidate in desired {
      guard !retainedStableIDs.contains(candidate.event.stableId) else { continue }
      if let failure = await prepare(
        candidate,
        scheduleVersion: schedule.scheduleVersion,
        relevanceScore: relevanceScores[candidate.event.stableId] ?? 0,
        now: now
      ) {
        issue = failure
        break
      }
      retainedStableIDs.insert(candidate.event.stableId)
    }
  }

  func preparedStableIDs(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int,
    now: Date = Date()
  ) -> Set<String> {
    guard let payload = try? NativeAlarmContract.payload(
      schedule: schedule,
      overrides: overrides
    ) else { return [] }
    let desired = Array(Self.candidates(
      schedule: schedule,
      payload: payload,
      projectionRevision: projectionRevision,
      now: now
    ).prefix(Self.maximumPreparedActivities))
    let expected = Dictionary(uniqueKeysWithValues: desired.map { ($0.event.stableId, $0) })

    return Set(Activity<CommanderProcedureLiveActivityAttributes>.activities.compactMap { activity in
      guard Self.isOngoing(activity.activityState),
            activity.attributes.scheduleVersion == schedule.scheduleVersion,
            activity.content.state.projectionRevision == max(0, projectionRevision),
            let expectedItem = expected[activity.attributes.stableId],
            abs(activity.attributes.leaveAt.timeIntervalSince(expectedItem.leaveAt)) <= 1,
            abs(activity.attributes.startAt.timeIntervalSince(expectedItem.startAt)) <= 1,
            abs(activity.attributes.endAt.timeIntervalSince(expectedItem.endAt)) <= 1,
            activity.attributes.nextEvent == expectedItem.nextEvent
      else { return nil }
      return activity.attributes.stableId
    })
  }

  private func prepare(
    _ candidate: Candidate,
    scheduleVersion: Int,
    relevanceScore: Double,
    now: Date
  ) async -> String? {
    let iconKey = CommanderVisualAssets.icon(for: candidate.event)?.key ?? ""
    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: candidate.event.stableId,
      scheduleVersion: scheduleVersion,
      iconKey: iconKey,
      title: candidate.event.title,
      location: candidate.event.location,
      kind: candidate.event.kind,
      leaveAt: candidate.leaveAt,
      startAt: candidate.startAt,
      endAt: candidate.endAt,
      nextEvent: candidate.nextEvent
    )
    let content = ActivityContent(
      state: candidate.contentState,
      staleDate: candidate.endAt,
      relevanceScore: relevanceScore
    )

    do {
      if candidate.leaveAt <= now {
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard
        )
      } else {
        // Scheduled starts require an alert by ActivityKit contract. The start is
        // canonical leaveAt, not event start, so the Commander card is already
        // available as soon as the departure alarm is dismissed.
        let alert = ActivityKit.AlertConfiguration(
          title: LocalizedStringResource(
            stringLiteral: candidate.event.kind == .meal ? "Další jídlo" : "Další procedura"
          ),
          body: LocalizedStringResource(stringLiteral: candidate.event.title),
          sound: .named("CommanderSilentAlert.wav")
        )
        _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
          attributes: attributes,
          content: content,
          pushType: nil,
          style: .standard,
          alertConfiguration: alert,
          start: candidate.leaveAt
        )
      }
      return nil
    } catch {
      let message = "Živou aktivitu se nepodařilo připravit: " + error.localizedDescription
      Logger(subsystem: Bundle.main.bundleIdentifier ?? "LazenskyCommander", category: "LiveActivity")
        .error("\(message, privacy: .public)")
      return message
    }
  }

  private static func candidates(
    schedule: Schedule,
    payload: NativeAlarmPayload,
    projectionRevision: Int,
    now: Date
  ) -> [Candidate] {
    let alarmByID = Dictionary(uniqueKeysWithValues: payload.alarms.map { ($0.stableId, $0) })
    let raw = schedule.events.compactMap { event -> RawCandidate? in
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
    }.sorted(by: Self.rawCandidateOrder)

    return raw.enumerated().compactMap { index, item in
      guard item.endAt > now else { return nil }
      let next = index + 1 < raw.count ? Self.snapshot(raw[index + 1]) : nil
      return Candidate(
        event: item.event,
        alarm: item.alarm,
        leaveAt: item.leaveAt,
        startAt: item.startAt,
        endAt: item.endAt,
        nextEvent: next,
        contentState: CommanderProcedureLiveActivityAttributes.ContentState(
          projectionRevision: max(0, projectionRevision)
        )
      )
    }
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

  private static func matches(
    _ activity: Activity<CommanderProcedureLiveActivityAttributes>,
    _ candidate: Candidate,
    scheduleVersion: Int
  ) -> Bool {
    activity.attributes.stableId == candidate.event.stableId
      && activity.attributes.scheduleVersion == scheduleVersion
      && activity.attributes.title == candidate.event.title
      && activity.attributes.location == candidate.event.location
      && activity.attributes.kind == candidate.event.kind
      && abs(activity.attributes.leaveAt.timeIntervalSince(candidate.leaveAt)) <= 1
      && abs(activity.attributes.startAt.timeIntervalSince(candidate.startAt)) <= 1
      && abs(activity.attributes.endAt.timeIntervalSince(candidate.endAt)) <= 1
      && activity.attributes.nextEvent == candidate.nextEvent
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

import ActivityKit
import Foundation
import LazenskyCommanderCore

/// Coordinates a small chain of non-overlapping Commander Live Activity windows.
///
/// AlarmKit remains the audible safety layer for every canonical `leaveAt`. Commander
/// supplies context before departure, through the event itself, and across nearby events.
/// Long free gaps end the visible activity; successor windows are scheduled in advance.
actor CommanderProcedureLiveActivityCoordinator {
  static let maximumActiveActivities = 1
  static let maximumScheduledActivities = CommanderLiveActivityPlan.defaultMaximumScheduledWindows
  static let maximumActiveLifetime: TimeInterval = 7 * 60 * 60 + 50 * 60
  static let contextLeadTime = CommanderLiveActivityPlan.defaultContextLeadTime
  static let maximumIdleGap = CommanderLiveActivityPlan.defaultMaximumIdleGap
  static let silentAlertSoundName = "CommanderSilentAlert.wav"

  private let enabled: Bool
  private let planningContextLeadTime: TimeInterval
  private let planningMaximumIdleGap: TimeInterval
  private let planningMaximumScheduledActivities: Int
  private let planningMaximumActiveLifetime: TimeInterval
  private(set) var issue: String?
  private var latestProjection: WatchScheduleProjectionIdentity?

  private struct RawCandidate {
    let event: ScheduleEvent
    let alarm: NativeAlarm
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
  }

  init(
    enabled: Bool = CommanderMVPPolicy.createsLiveActivities,
    contextLeadTime: TimeInterval = CommanderProcedureLiveActivityCoordinator.contextLeadTime,
    maximumIdleGap: TimeInterval = CommanderProcedureLiveActivityCoordinator.maximumIdleGap,
    maximumScheduledActivities: Int = CommanderProcedureLiveActivityCoordinator.maximumScheduledActivities,
    maximumActiveLifetime: TimeInterval = CommanderProcedureLiveActivityCoordinator.maximumActiveLifetime
  ) {
    self.enabled = enabled
    planningContextLeadTime = contextLeadTime
    planningMaximumIdleGap = maximumIdleGap
    planningMaximumScheduledActivities = maximumScheduledActivities
    planningMaximumActiveLifetime = maximumActiveLifetime
  }

  func activityState(schedule: Schedule, projectionRevision: Int) -> String {
    let ids = Set(schedule.events.map(\.stableId))
    let matches = Self.managedActivities.filter {
      ids.contains($0.attributes.stableId) &&
      $0.attributes.rendererRevision == CommanderProcedureLiveActivityAttributes.currentRendererRevision &&
      $0.content.state.scheduleVersion == schedule.scheduleVersion &&
      $0.content.state.projectionRevision == projectionRevision
    }
    if matches.contains(where: { $0.activityState == .active }) { return "active" }
    if matches.contains(where: { $0.activityState == .pending }) { return "pending" }
    return matches.isEmpty ? "missing" : "inactive"
  }

  func hasOngoingActivities() -> Bool {
    Self.managedActivities.contains {
      Self.isOngoing($0.activityState)
    }
  }

  /// Retire earlier Commander activities even when no schedule/network is available.
  func retireActivitiesForMVP() async {
    guard !CommanderMVPPolicy.createsLiveActivities else { return }
    _ = try? await CommanderProcedureLiveActivityPolicy.operations.run {
      for activity in Self.managedActivities where Self.isOngoing(activity.activityState) {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  func reconcile(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int,
    now: Date = Date()
  ) async {
    _ = try? await CommanderProcedureLiveActivityPolicy.operations.run {
      await self.performReconcile(schedule: schedule, overrides: overrides,
        projectionRevision: projectionRevision, now: now)
    }
  }

  private func performReconcile(
    schedule: Schedule,
    overrides: LeadTimeOverrides?,
    projectionRevision: Int,
    now: Date
  ) async {
    issue = nil
    guard enabled && CommanderMVPPolicy.createsLiveActivities else {
      for activity in Self.managedActivities
        where Self.isOngoing(activity.activityState) {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      return
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      issue = "Živé aktivity nejsou povolené."
      return
    }
    guard let payload = try? NativeAlarmContract.payload(schedule: schedule, overrides: overrides) else {
      issue = "Rozpis nelze převést na canonical alarm payload."
      return
    }

    let incoming = WatchScheduleProjectionIdentity(scheduleVersion: schedule.scheduleVersion,
      projectionRevision: projectionRevision)
    if let latestProjection, incoming.isOlder(than: latestProjection) { return }
    // In-memory ordering is lost on relaunch; ActivityKit content survives it.
    guard !Self.managedActivities.contains(where: {
      Self.isOngoing($0.activityState) && incoming.isOlder(than: .init(
        scheduleVersion: $0.content.state.scheduleVersion,
        projectionRevision: $0.content.state.projectionRevision))
    }) else { return }
    latestProjection = incoming

    let raw = Self.rawCandidates(schedule: schedule, payload: payload)
    let candidateByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.event.stableId, $0) })
    let plans = CommanderLiveActivityPlan.makeWindows(
      schedule: schedule,
      payload: payload,
      now: now,
      contextLeadTime: planningContextLeadTime,
      maximumIdleGap: planningMaximumIdleGap,
      maximumActiveLifetime: planningMaximumActiveLifetime,
      maximumEvents: CommanderProcedureLiveActivityPolicy.maximumQueuedEvents,
      maximumWindows: planningMaximumScheduledActivities
    )

    for activity in Self.managedActivities
      where activity.activityState == .ended {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    let existing = Self.managedActivities
      .filter { Self.isOngoing($0.activityState) }
      .sorted { Self.retentionRank($0.activityState) < Self.retentionRank($1.activityState) }

    guard !plans.isEmpty else {
      for activity in existing {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      return
    }

    let desiredIDs = Set(plans.map(\.anchorStableID))
    var keepers: [String: Activity<CommanderProcedureLiveActivityAttributes>] = [:]

    for activity in existing {
      let stableID = activity.attributes.stableId
      guard desiredIDs.contains(stableID),
            activity.attributes.rendererRevision == CommanderProcedureLiveActivityAttributes.currentRendererRevision
      else {
        await activity.end(nil, dismissalPolicy: .immediate)
        continue
      }

      if keepers[stableID] == nil {
        keepers[stableID] = activity
      } else {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }

    for plan in plans {
      guard let anchor = candidateByID[plan.anchorStableID] else { continue }
      let queue = plan.includedStableIDs.compactMap { candidateByID[$0] }
      guard !queue.isEmpty else { continue }
      let snapshots = queue.map(Self.snapshot)

      if let keeper = keepers[plan.anchorStableID] {
        let staticIsFresh = Self.staticIdentityMatches(
          keeper,
          plan: plan,
          anchor: anchor,
          scheduleVersion: schedule.scheduleVersion
        )

        if !staticIsFresh {
          await keeper.end(nil, dismissalPolicy: .immediate)
          await requestPlannedActivity(
            plan: plan,
            anchor: anchor,
            snapshots: snapshots,
            scheduleVersion: schedule.scheduleVersion,
            projectionRevision: projectionRevision,
            now: now
          )
          continue
        }

        let presentation = keeper.activityState == .pending
          ? (plan.anchorStableID, CommanderLiveActivityPresentationMode.departureCountdown)
          : Self.presentationState(
              snapshots: snapshots,
              now: now,
              fallbackStableID: plan.anchorStableID
            )
        let expectedState = CommanderProcedureLiveActivityPolicy.contentState(
          scheduleVersion: schedule.scheduleVersion,
          projectionRevision: projectionRevision,
          events: snapshots,
          attributes: keeper.attributes,
          focusStableId: presentation.0,
          presentationMode: presentation.1
        )

        if keeper.activityState == .pending {
          let pendingIsFresh =
            keeper.content.state.scheduleVersion == expectedState.scheduleVersion &&
            keeper.content.state.projectionRevision == expectedState.projectionRevision &&
            keeper.content.state.events == expectedState.events

          if !pendingIsFresh {
            await keeper.end(nil, dismissalPolicy: .immediate)
            await requestPlannedActivity(
              plan: plan,
              anchor: anchor,
              snapshots: snapshots,
              scheduleVersion: schedule.scheduleVersion,
              projectionRevision: projectionRevision,
              now: now
            )
          }
          continue
        }

        let nextBoundary = CommanderProcedureLiveActivityPolicy.nextStaleDate(
          for: expectedState,
          attributes: keeper.attributes
        ) ?? plan.windowEnd
        await keeper.update(ActivityContent(
          state: expectedState,
          staleDate: min(nextBoundary, plan.windowEnd),
          relevanceScore: 1_000
        ))
        continue
      }

      await requestPlannedActivity(
        plan: plan,
        anchor: anchor,
        snapshots: snapshots,
        scheduleVersion: schedule.scheduleVersion,
        projectionRevision: projectionRevision,
        now: now
      )
    }
  }

  private func requestPlannedActivity(
    plan: CommanderLiveActivityPlan,
    anchor: RawCandidate,
    snapshots: [CommanderAlarmEventSnapshot],
    scheduleVersion: Int,
    projectionRevision: Int,
    now: Date
  ) async {
    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: anchor.event.stableId,
      scheduleVersion: scheduleVersion,
      iconKey: CommanderVisualAssets.icon(for: anchor.event)?.key ?? "",
      title: anchor.event.title,
      location: anchor.event.location,
      kind: anchor.event.kind,
      activationStart: plan.activationStart,
      leaveAt: anchor.leaveAt,
      startAt: anchor.startAt,
      endAt: anchor.endAt,
      nextEvent: snapshots.dropFirst().first
    )
    let presentation = plan.activationStart > now
      ? (plan.anchorStableID, CommanderLiveActivityPresentationMode.departureCountdown)
      : Self.presentationState(snapshots: snapshots, now: now, fallbackStableID: plan.anchorStableID)
    let state = CommanderProcedureLiveActivityPolicy.contentState(
      scheduleVersion: scheduleVersion,
      projectionRevision: projectionRevision,
      events: snapshots,
      attributes: attributes,
      focusStableId: presentation.0,
      presentationMode: presentation.1
    )
    let nextBoundary = CommanderProcedureLiveActivityPolicy.nextStaleDate(
      for: state,
      attributes: attributes
    ) ?? plan.windowEnd
    let content = ActivityContent(
      state: state,
      staleDate: min(nextBoundary, plan.windowEnd),
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
          recordIssue("Chybí tichý zvuk pro naplánovaný Commander blok.")
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
      recordIssue("Commander blok \(anchor.event.title) se nepodařilo připravit: \(error.localizedDescription)")
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

    let raw = Self.rawCandidates(schedule: schedule, payload: payload)
    let candidateByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.event.stableId, $0) })
    let plans = CommanderLiveActivityPlan.makeWindows(
      schedule: schedule,
      payload: payload,
      now: now,
      contextLeadTime: planningContextLeadTime,
      maximumIdleGap: planningMaximumIdleGap,
      maximumActiveLifetime: planningMaximumActiveLifetime,
      maximumEvents: CommanderProcedureLiveActivityPolicy.maximumQueuedEvents,
      maximumWindows: planningMaximumScheduledActivities
    )
    let activities = Self.managedActivities
      .filter { Self.isOngoing($0.activityState) }

    var prepared: Set<String> = []
    for plan in plans {
      guard let anchor = candidateByID[plan.anchorStableID],
            let activity = activities.first(where: { $0.attributes.stableId == plan.anchorStableID }),
            Self.staticIdentityMatches(
              activity,
              plan: plan,
              anchor: anchor,
              scheduleVersion: schedule.scheduleVersion
            )
      else { continue }

      let snapshots = plan.includedStableIDs.compactMap { candidateByID[$0] }.map(Self.snapshot)
      let presentation = activity.activityState == .pending
        ? (plan.anchorStableID, CommanderLiveActivityPresentationMode.departureCountdown)
        : Self.presentationState(
            snapshots: snapshots,
            now: now,
            fallbackStableID: plan.anchorStableID
          )
      let expectedState = CommanderProcedureLiveActivityPolicy.contentState(
        scheduleVersion: schedule.scheduleVersion,
        projectionRevision: projectionRevision,
        events: snapshots,
        attributes: activity.attributes,
        focusStableId: presentation.0,
        presentationMode: presentation.1
      )
      guard activity.content.state.scheduleVersion == expectedState.scheduleVersion,
            activity.content.state.projectionRevision == expectedState.projectionRevision,
            activity.content.state.events == expectedState.events
      else { continue }

      prepared.insert(plan.anchorStableID)
    }
    return prepared
  }

  private static func presentationState(
    snapshots: [CommanderAlarmEventSnapshot],
    now: Date,
    fallbackStableID: String
  ) -> (String, CommanderLiveActivityPresentationMode) {
    let timelineEvents = snapshots.compactMap { snapshot -> CommanderLiveActivityTimelineEvent? in
      guard let leaveAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.leaveAt),
            let startAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.startAt),
            let endAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.endAt)
      else { return nil }
      return CommanderLiveActivityTimelineEvent(
        stableId: snapshot.stableId,
        leaveAt: leaveAt,
        startAt: startAt,
        endAt: endAt
      )
    }
    guard let resolution = CommanderLiveActivityTimeline.resolve(events: timelineEvents, at: now) else {
      return (fallbackStableID, .departureCountdown)
    }
    let mode: CommanderLiveActivityPresentationMode
    switch resolution.phase {
    case .upcoming:
      mode = resolution.departureDue ? .startCountdown : .departureCountdown
    case .active, .ended:
      mode = .eventContext
    }
    return (resolution.primaryStableId, mode)
  }

  private static func staticIdentityMatches(
    _ activity: Activity<CommanderProcedureLiveActivityAttributes>,
    plan: CommanderLiveActivityPlan,
    anchor: RawCandidate,
    scheduleVersion: Int
  ) -> Bool {
    let activationStart = activity.attributes.activationStart ?? activity.attributes.leaveAt
    return activity.attributes.rendererRevision == CommanderProcedureLiveActivityAttributes.currentRendererRevision &&
      activity.attributes.stableId == plan.anchorStableID &&
      activity.attributes.scheduleVersion == scheduleVersion &&
      abs(activationStart.timeIntervalSince(plan.activationStart)) <= 1 &&
      abs(activity.attributes.leaveAt.timeIntervalSince(anchor.leaveAt)) <= 1 &&
      abs(activity.attributes.startAt.timeIntervalSince(anchor.startAt)) <= 1 &&
      abs(activity.attributes.endAt.timeIntervalSince(anchor.endAt)) <= 1
  }

  private func recordIssue(_ message: String) {
    if let issue, !issue.isEmpty {
      self.issue = issue + " | " + message
    } else {
      issue = message
    }
  }

  private static func rawCandidates(
    schedule: Schedule,
    payload: NativeAlarmPayload
  ) -> [RawCandidate] {
    guard let projected = try? CommanderScheduleProjection.events(schedule: schedule, payload: payload) else { return [] }
    return projected.map {
      RawCandidate(event: $0.event, alarm: $0.alarm, leaveAt: $0.leaveAt, startAt: $0.startAt, endAt: $0.endAt)
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

  private static var managedActivities: [Activity<CommanderProcedureLiveActivityAttributes>] {
    Activity<CommanderProcedureLiveActivityAttributes>.activities.filter {
      CommanderRuntimeDataset.current.accepts(stableID: $0.attributes.stableId)
    }
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

import Foundation

public struct CommanderAlarmEventSnapshot: Codable, Hashable, Sendable {
  public let stableId: String
  public let iconKey: String
  public let title: String
  public let location: String
  public let kind: ScheduleKind
  public let startAt: String
  public let endAt: String
  public let leaveAt: String
  public init(stableId: String, iconKey: String, title: String, location: String,
              kind: ScheduleKind, startAt: String, endAt: String, leaveAt: String) {
    self.stableId = stableId; self.iconKey = iconKey; self.title = title
    self.location = location; self.kind = kind
    self.startAt = startAt; self.endAt = endAt; self.leaveAt = leaveAt
  }
}

public enum CommanderLiveActivityPresentationMode: String, Codable, Hashable, Sendable {
  case departureCountdown
  case startCountdown
  case eventContext
}

/// Reject delayed stop callbacks whose payload no longer describes the current event.
public enum CommanderAlarmStopPolicy {
  public static func canApply(
    stopped: CommanderAlarmEventSnapshot, current: CommanderAlarmEventSnapshot?,
    focused: CommanderAlarmEventSnapshot? = nil,
    stoppedIdentity: WatchScheduleProjectionIdentity? = nil,
    currentIdentity: WatchScheduleProjectionIdentity? = nil, now: Date
  ) -> Bool {
    if let currentIdentity, stoppedIdentity != currentIdentity { return false }
    guard let current,
          stopped.stableId == current.stableId,
          stopped.startAt == current.startAt,
          stopped.leaveAt == current.leaveAt,
          stopped.endAt == current.endAt,
          let leave = try? NativeAlarmContract.date(fromLocalISO: current.leaveAt),
          let start = try? NativeAlarmContract.date(fromLocalISO: current.startAt),
          let end = try? NativeAlarmContract.date(fromLocalISO: current.endAt),
          leave <= now, start < end, now < end else { return false }
    if let focused, focused.stableId != current.stableId,
       let focusedStart = try? NativeAlarmContract.date(fromLocalISO: focused.startAt),
       let focusedLeave = try? NativeAlarmContract.date(fromLocalISO: focused.leaveAt),
       focusedStart > start, focusedLeave <= now { return false }
    return true
  }
}

public enum CommanderActivityRenderingPolicy: Sendable {
  /// Exact state whenever the caller can evaluate a supplied clock instant.
  case deterministic
  /// ActivityKit archives a view until another system/content update occurs.
  case suspendedActivity
}

public struct CommanderActivityPresentation: Equatable, Sendable {
  public let title: String
  public let location: String
  public let kind: ScheduleKind
  public let iconKey: String
  public let leaveAt: Date
  public let startAt: Date
  public let endAt: Date
  public let presentationMode: CommanderLiveActivityPresentationMode
  public let isStale: Bool
  public let nextEvent: CommanderAlarmEventSnapshot?
  public let nextEventLabel: String
  public let timing: CommanderCountdownPresentation

  private struct ResolvedEvent {
    let snapshot: CommanderAlarmEventSnapshot
    let leaveAt: Date
    let startAt: Date
    let endAt: Date
  }

  public static func resolve(
    seed: CommanderAlarmEventSnapshot,
    events snapshots: [CommanderAlarmEventSnapshot],
    focusStableId: String?,
    presentationMode: CommanderLiveActivityPresentationMode,
    isStale: Bool = false,
    at now: Date,
    renderingPolicy: CommanderActivityRenderingPolicy = .deterministic
  ) -> CommanderActivityPresentation {
    let events = resolvedEvents(snapshots.isEmpty ? [seed] : snapshots)
    let focusStableID = focusStableId ?? seed.stableId
    let focusIndex = events.firstIndex(where: { $0.snapshot.stableId == focusStableID }) ?? 0

    if !events.isEmpty {
      let primary = events[focusIndex]
      let following = events.dropFirst(focusIndex + 1).first
      let boundary: Date
      switch presentationMode {
      case .departureCountdown: boundary = primary.leaveAt
      case .startCountdown: boundary = primary.startAt
      case .eventContext: boundary = primary.endAt
      }
      let expiredPhase = isStale || now >= boundary
      let timing: CommanderCountdownPresentation
      if renderingPolicy == .suspendedActivity && expiredPhase && now < primary.endAt {
        timing = .suspendedScheduleFallback
      } else {
        timing = .init(presentationMode: presentationMode, leaveAt: primary.leaveAt,
                       startAt: primary.startAt, endAt: primary.endAt, at: now)
      }
      return CommanderActivityPresentation(
        title: primary.snapshot.title,
        location: primary.snapshot.location,
        kind: primary.snapshot.kind,
        iconKey: primary.snapshot.iconKey,
        leaveAt: primary.leaveAt,
        startAt: primary.startAt,
        endAt: primary.endAt,
        presentationMode: presentationMode,
        isStale: isStale,
        nextEvent: following?.snapshot,
        nextEventLabel: "Potom:",
        timing: timing
      )
    }

    // Invalid transport dates are rejected before reaching the renderer.
    // Keep a neutral value for malformed legacy seeds instead of inventing current time.
    return CommanderActivityPresentation(
      title: seed.title, location: seed.location, kind: seed.kind, iconKey: seed.iconKey,
      leaveAt: (try? NativeAlarmContract.date(fromLocalISO: seed.leaveAt)) ?? .distantPast,
      startAt: (try? NativeAlarmContract.date(fromLocalISO: seed.startAt)) ?? .distantPast,
      endAt: (try? NativeAlarmContract.date(fromLocalISO: seed.endAt)) ?? .distantPast,
      presentationMode: presentationMode, isStale: true, nextEvent: nil, nextEventLabel: "Potom:",
      timing: .suspendedScheduleFallback
    )
  }

  private static func resolvedEvents(_ snapshots: [CommanderAlarmEventSnapshot]) -> [ResolvedEvent] {
    snapshots.compactMap { snapshot in
      guard let leaveAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.leaveAt),
            let startAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.startAt),
            let endAt = try? NativeAlarmContract.date(fromLocalISO: snapshot.endAt)
      else { return nil }
      return ResolvedEvent(snapshot: snapshot, leaveAt: leaveAt, startAt: startAt, endAt: endAt)
    }.sorted {
      if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
      return $0.snapshot.stableId < $1.snapshot.stableId
    }
  }

  public var status: String { timing.status }
  public var countdownTarget: Date? { timing.target }
  public var countdownLabel: String { timing.countdownLabel }
  public var isScheduleFallback: Bool { timing.isScheduleFallback }
  public var isFinished: Bool { timing.target == nil && !isScheduleFallback }
  public var timeLabel: String { timing.referenceLabel ?? "" }
  public var timeValue: String {
    if isScheduleFallback {
      return startAt.formatted(date: .omitted, time: .shortened) + "–" +
        endAt.formatted(date: .omitted, time: .shortened)
    }
    return (timing.referenceDate ?? endAt).formatted(date: .omitted, time: .shortened)
  }
}

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
    isStale: Bool = false
  ) -> CommanderActivityPresentation {
    let events = resolvedEvents(snapshots.isEmpty ? [seed] : snapshots)
    let focusStableID = focusStableId ?? seed.stableId
    let focusIndex = events.firstIndex(where: { $0.snapshot.stableId == focusStableID }) ?? 0

    if !events.isEmpty {
      let primary = events[focusIndex]
      let following = events.dropFirst(focusIndex + 1).first
      let followingIsConcurrent = following.map { $0.startAt < primary.endAt } ?? false
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
        nextEventLabel: followingIsConcurrent ? "Současně:" : "Potom:"
      )
    }

    // Invalid transport dates are rejected before reaching the renderer.
    // Keep a neutral value for malformed legacy seeds instead of inventing current time.
    return CommanderActivityPresentation(
      title: seed.title, location: seed.location, kind: seed.kind, iconKey: seed.iconKey,
      leaveAt: (try? NativeAlarmContract.date(fromLocalISO: seed.leaveAt)) ?? .distantPast,
      startAt: (try? NativeAlarmContract.date(fromLocalISO: seed.startAt)) ?? .distantPast,
      endAt: (try? NativeAlarmContract.date(fromLocalISO: seed.endAt)) ?? .distantPast,
      presentationMode: presentationMode, isStale: true, nextEvent: nil, nextEventLabel: "Potom:"
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

  public var timing: CommanderCountdownPresentation {
    .init(presentationMode: presentationMode, isStale: isStale,
          leaveAt: leaveAt, startAt: startAt, endAt: endAt)
  }
  public var status: String { timing.status }
  public var countdownTarget: Date { timing.target ?? endAt }
  public var countdownLabel: String { timing.countdownLabel }
  public var timeLabel: String { timing.referenceLabel ?? "" }
  public var timeValue: String {
    (timing.referenceDate ?? endAt).formatted(date: .omitted, time: .shortened)
  }
}

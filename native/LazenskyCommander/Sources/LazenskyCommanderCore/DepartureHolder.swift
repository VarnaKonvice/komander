import Foundation

/// A visible first-departure card. It is not a predecessor event or a hidden standby.
public enum CommanderDepartureHolder {
  public struct Identity: Codable, Equatable, Sendable {
    public let scheduleVersion: Int
    public let target: NativeAlarm
    public let iconKey: String
    public init(scheduleVersion: Int, target: NativeAlarm, iconKey: String) {
      self.scheduleVersion = scheduleVersion; self.target = target; self.iconKey = iconKey
    }
  }

  public enum State: Equatable, Sendable { case pending, active, stale, ended, dismissed }
  public struct Observation: Sendable {
    public let id: String
    public let identity: Identity?
    public let state: State
    public let isRed: Bool
    public init(id: String, identity: Identity?, state: State, isRed: Bool = false) {
      self.id = id; self.identity = identity; self.state = state; self.isRed = isRed
    }
  }
  public struct Plan: Equatable, Sendable {
    public let retainedID: String?
    public let removeIDs: [String]
    public let create: Bool
  }

  /// Only the nearest event without a canonical handoff is eligible. The existing
  /// second-event/free-time path is deliberately not part of this policy.
  public static func identity(for alarm: NativeAlarm, in schedule: Schedule,
                              iconKey: String, now: Date) -> Identity? {
    guard CommanderLiveActivityHandoff.runningEvents(in: schedule, now: now).first?.stableId == alarm.stableId,
          !CommanderLiveActivityHandoff.hasFreeTimeSource(for: alarm, in: schedule),
          let leave = try? NativeAlarmContract.date(fromLocalISO: alarm.leaveAt),
          let start = try? NativeAlarmContract.date(fromLocalISO: alarm.startAt),
          leave < start, now < start else { return nil }
    return Identity(scheduleVersion: schedule.scheduleVersion, target: alarm, iconKey: iconKey)
  }

  public static func reconcile(expected: Identity?, observed: [Observation], now: Date,
                               foreground: Bool, runningPrepared: Bool) -> Plan {
    let start = expected.flatMap { try? NativeAlarmContract.date(fromLocalISO: $0.target.startAt) }
    let leave = expected.flatMap { try? NativeAlarmContract.date(fromLocalISO: $0.target.leaveAt) }
    let valid = matching(expected: expected, observed: observed, now: now)
      .filter { $0.isRed || runningPrepared }
    let retained = valid.first?.id
    return Plan(retainedID: retained,
      removeIDs: observed.filter { $0.id != retained }.map(\.id).sorted(),
      create: retained == nil && expected != nil && foreground && runningPrepared
        && leave.map { now < $0 } == true && start.map { now < $0 } == true)
  }

  private static func matching(expected: Identity?, observed: [Observation], now: Date) -> [Observation] {
    let start = expected.flatMap { try? NativeAlarmContract.date(fromLocalISO: $0.target.startAt) }
    return observed.filter {
      expected != nil && $0.identity == expected && start.map { now < $0 } == true
        && ($0.state == .active || $0.state == .stale || ($0.state == .ended && $0.isRed))
    }.sorted {
      if $0.isRed != $1.isRed { return $0.isRed }
      return $0.id < $1.id
    }
  }

  /// Presence of a requested/pending card is insufficient: it must actually be
  /// active, unique, canonical, and backed by the already scheduled event activity.
  public static func verified(expected: Identity?, observed: [Observation], now: Date,
                              runningPrepared: Bool) -> Bool {
    guard runningPrepared, observed.count == 1, let item = observed.first, !item.isRed,
          item.state == .active || item.state == .stale else { return false }
    return reconcile(expected: expected, observed: observed, now: now,
      foreground: false, runningPrepared: runningPrepared).retainedID == item.id
  }

  /// Stop can only select an existing holder; the result never requests creation.
  public static func stopHolderID(expected: Identity?, observed: [Observation], now: Date) -> String? {
    guard let expected, let leave = try? NativeAlarmContract.date(fromLocalISO: expected.target.leaveAt),
          now >= leave else { return nil }
    return matching(expected: expected, observed: observed, now: now).first?.id
  }
}

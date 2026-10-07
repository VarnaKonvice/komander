import Foundation

/// An input boundary, not a separate transport or rendering mode. In particular,
/// WCSession can replay its last context after installing a different build.
public enum CommanderScheduleDataset: String, Sendable {
  case production, acceptance

  public func accepts(stableID: String) -> Bool {
    if stableID.hasPrefix("widgetDemo.") { return false }
    return stableID.hasPrefix(PhysicalAcceptanceRun.stableIDPrefix) == (self == .acceptance)
  }

  public func accepts(_ schedule: Schedule) -> Bool {
    (schedule.stay["commanderDataset"] ?? "production") == rawValue &&
      schedule.events.allSatisfy {
        // Old physical builds mislabeled this fixture as production. Reject it
        // at every schedule/cache boundary, while retaining stable-ID ownership
        // so ordinary reconciliation can still cancel its old platform alarms.
        accepts(stableID: $0.stableId) &&
          !$0.stableId.hasPrefix("mvpPhysical.") && !$0.stableId.hasPrefix("visual-review.")
      }
  }
}

/// Fixture input for the ordinary Commander bootstrap. No alternate synchronizer,
/// alarm adapter, activity renderer or Watch transport is involved.
public struct CommanderAcceptanceSchedule: ScheduleServing {
  public let schedule: Schedule

  public init(
    now: Date,
    previousVersion: Int = 0,
    cleanup: Bool = false,
    scenario: PhysicalAcceptanceScenario = .fullSpaDay
  ) throws {
    let version = max(previousVersion + 1, Int(now.timeIntervalSince1970 * 1_000))
    // Cleanup must also work near midnight, when a timed fixture cannot be made.
    if cleanup {
      schedule = Schedule(
        schemaVersion: 1, scheduleVersion: version,
        updatedAt: ISO8601DateFormatter().string(from: now),
        stay: ["commanderDataset": "acceptance"], events: [],
        settings: ScheduleSettings(defaultLeadTimeMinutes: 2, procedureTypeOverrides: [:], mealOverrides: [:])
      )
    } else {
      let fixture = try PhysicalAcceptanceRun(now: now, scenario: scenario).schedule
      schedule = Schedule(
        schemaVersion: fixture.schemaVersion, scheduleVersion: version,
        updatedAt: fixture.updatedAt,
        stay: fixture.stay.merging(["commanderDataset": "acceptance"]) { _, new in new },
        events: fixture.events, settings: fixture.settings
      )
    }
    try NativeAlarmContract.validateCanonical(schedule)
  }

  public func fetchSchedule() async throws -> Schedule { schedule }
}

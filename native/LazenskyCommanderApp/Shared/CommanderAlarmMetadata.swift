import ActivityKit
import AlarmKit
import Foundation
import LazenskyCommanderCore

struct CommanderAlarmEventSnapshot: Codable, Hashable, Sendable {
  let stableId: String
  let iconKey: String
  let title: String
  let location: String
  let kind: ScheduleKind
  let startAt: String
  let endAt: String
  let leaveAt: String
}

struct CommanderAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
  let stableId: String
  let scheduleVersion: Int
  let iconKey: String
  let title: String
  let location: String
  let kind: ScheduleKind
  let startAt: String
  let leaveAt: String
  let endAt: String?
  let nextEvent: CommanderAlarmEventSnapshot?

  init(
    stableId: String,
    scheduleVersion: Int,
    iconKey: String,
    title: String,
    location: String,
    kind: ScheduleKind,
    startAt: String,
    leaveAt: String,
    endAt: String? = nil,
    nextEvent: CommanderAlarmEventSnapshot? = nil
  ) {
    self.stableId = stableId
    self.scheduleVersion = scheduleVersion
    self.iconKey = iconKey
    self.title = title
    self.location = location
    self.kind = kind
    self.startAt = startAt
    self.leaveAt = leaveAt
    self.endAt = endAt
    self.nextEvent = nextEvent
  }
}

enum CommanderPhysicalAcceptanceDiagnostics {
  private static let legacyKey = "lazensky.commander.physicalAcceptance.stopIntent.v1"
  private static let timelineKey = "lazensky.commander.physicalAcceptance.timeline.v2"
  private static let maximumEntries = 64

  static func record(_ text: String, at date: Date = Date()) {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else { return }
    let defaults = UserDefaults.standard
    let stamp = ISO8601DateFormatter().string(from: date)
    var entries = defaults.stringArray(forKey: timelineKey) ?? []
    entries.append("\(stamp) · \(text)")
    if entries.count > maximumEntries {
      entries.removeFirst(entries.count - maximumEntries)
    }
    defaults.set(entries, forKey: timelineKey)
    defaults.set(text, forKey: legacyKey)
  }

  static func read() -> String? {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else { return nil }
    let defaults = UserDefaults.standard
    if let entries = defaults.stringArray(forKey: timelineKey), !entries.isEmpty {
      return entries.joined(separator: "\n")
    }
    return defaults.string(forKey: legacyKey)
  }

  static func clear() {
    guard Bundle.main.bundleIdentifier == PhysicalAcceptanceRun.bundleID else { return }
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: timelineKey)
    defaults.removeObject(forKey: legacyKey)
  }
}

struct CommanderProcedureLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let projectionRevision: Int

    init(projectionRevision: Int = 0) {
      self.projectionRevision = projectionRevision
    }
  }

  let stableId: String
  let scheduleVersion: Int
  let iconKey: String
  let title: String
  let location: String
  let kind: ScheduleKind
  let leaveAt: Date
  let startAt: Date
  let endAt: Date
  let nextEvent: CommanderAlarmEventSnapshot?
}

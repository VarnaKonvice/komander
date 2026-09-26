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
  let projectionRevision: Int?
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
    projectionRevision: Int? = nil,
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
    self.projectionRevision = projectionRevision
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
  static let currentRendererRevision = 4

  struct ContentState: Codable, Hashable {
    let scheduleVersion: Int
    let projectionRevision: Int
    let events: [CommanderAlarmEventSnapshot]

    private enum CodingKeys: String, CodingKey {
      case scheduleVersion
      case projectionRevision
      case events
    }

    init(
      scheduleVersion: Int = 0,
      projectionRevision: Int = 0,
      events: [CommanderAlarmEventSnapshot] = []
    ) {
      self.scheduleVersion = scheduleVersion
      self.projectionRevision = projectionRevision
      self.events = events
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      scheduleVersion = try container.decodeIfPresent(Int.self, forKey: .scheduleVersion) ?? 0
      projectionRevision = try container.decodeIfPresent(Int.self, forKey: .projectionRevision) ?? 0
      events = try container.decodeIfPresent([CommanderAlarmEventSnapshot].self, forKey: .events) ?? []
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(scheduleVersion, forKey: .scheduleVersion)
      try container.encode(projectionRevision, forKey: .projectionRevision)
      try container.encode(events, forKey: .events)
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
  let rendererRevision: Int?

  init(
    stableId: String,
    scheduleVersion: Int,
    iconKey: String,
    title: String,
    location: String,
    kind: ScheduleKind,
    leaveAt: Date,
    startAt: Date,
    endAt: Date,
    nextEvent: CommanderAlarmEventSnapshot?,
    rendererRevision: Int? = Self.currentRendererRevision
  ) {
    self.stableId = stableId
    self.scheduleVersion = scheduleVersion
    self.iconKey = iconKey
    self.title = title
    self.location = location
    self.kind = kind
    self.leaveAt = leaveAt
    self.startAt = startAt
    self.endAt = endAt
    self.nextEvent = nextEvent
    self.rendererRevision = rendererRevision
  }
}

enum CommanderProcedureLiveActivityPolicy {
  static let maximumQueuedEvents = 6
  // ActivityKit caps static + dynamic payload at 4 KB. Keep deliberate headroom.
  static let targetCombinedEncodedBytes = 3_600

  static func contentState(
    scheduleVersion: Int,
    projectionRevision: Int,
    events: [CommanderAlarmEventSnapshot],
    attributes: CommanderProcedureLiveActivityAttributes
  ) -> CommanderProcedureLiveActivityAttributes.ContentState {
    var bounded = Array(events.prefix(maximumQueuedEvents))
    while true {
      let state = CommanderProcedureLiveActivityAttributes.ContentState(
        scheduleVersion: scheduleVersion,
        projectionRevision: max(0, projectionRevision),
        events: bounded
      )
      guard bounded.count > 1 else { return state }
      let encoder = JSONEncoder()
      let attributesSize = (try? encoder.encode(attributes).count) ?? 0
      let stateSize = (try? encoder.encode(state).count) ?? 0
      if attributesSize + stateSize <= targetCombinedEncodedBytes {
        return state
      }
      bounded.removeLast()
    }
  }
}

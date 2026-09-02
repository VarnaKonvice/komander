import ActivityKit
import AlarmKit
import Foundation
import LazenskyCommanderCore

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

  init(
    stableId: String,
    scheduleVersion: Int,
    iconKey: String,
    title: String,
    location: String,
    kind: ScheduleKind,
    startAt: String,
    leaveAt: String,
    endAt: String? = nil
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
  }
}

enum CommanderProcedureLiveActivityPhase: String, Codable, Hashable, Sendable {
  case departureBridge
}

struct CommanderProcedureLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let projectionRevision: Int
    let phase: CommanderProcedureLiveActivityPhase?
    let nextTitle: String?
    let nextLocation: String?
    let nextKind: ScheduleKind?
    let nextIconKey: String?
    let nextStartAt: Date?
    let nextEndAt: Date?
    let nextLeaveAt: Date?

    init(
      projectionRevision: Int,
      phase: CommanderProcedureLiveActivityPhase? = nil,
      nextTitle: String? = nil,
      nextLocation: String? = nil,
      nextKind: ScheduleKind? = nil,
      nextIconKey: String? = nil,
      nextStartAt: Date? = nil,
      nextEndAt: Date? = nil,
      nextLeaveAt: Date? = nil
    ) {
      self.projectionRevision = projectionRevision
      self.phase = phase
      self.nextTitle = nextTitle
      self.nextLocation = nextLocation
      self.nextKind = nextKind
      self.nextIconKey = nextIconKey
      self.nextStartAt = nextStartAt
      self.nextEndAt = nextEndAt
      self.nextLeaveAt = nextLeaveAt
    }

    var isDepartureBridge: Bool { phase == .departureBridge }
  }

  let stableId: String
  let scheduleVersion: Int
  let iconKey: String
  let title: String
  let location: String
  let kind: ScheduleKind
  let startAt: Date
  let endAt: Date
}

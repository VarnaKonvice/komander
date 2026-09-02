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
}

struct CommanderProcedureLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let projectionRevision: Int
    let nextTitle: String?
    let nextLocation: String?
    let nextKind: ScheduleKind?
    let nextIconKey: String?
    let nextStartAt: Date?
    let nextEndAt: Date?
    let nextLeaveAt: Date?

    init(
      projectionRevision: Int,
      nextTitle: String? = nil,
      nextLocation: String? = nil,
      nextKind: ScheduleKind? = nil,
      nextIconKey: String? = nil,
      nextStartAt: Date? = nil,
      nextEndAt: Date? = nil,
      nextLeaveAt: Date? = nil
    ) {
      self.projectionRevision = projectionRevision
      self.nextTitle = nextTitle
      self.nextLocation = nextLocation
      self.nextKind = nextKind
      self.nextIconKey = nextIconKey
      self.nextStartAt = nextStartAt
      self.nextEndAt = nextEndAt
      self.nextLeaveAt = nextLeaveAt
    }
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

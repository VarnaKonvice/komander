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

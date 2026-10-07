import Foundation

public enum CommanderMVPPolicy {
  public static let createsLiveActivities = false
  public static let createsStandaloneWatchAlerts = false
}

public enum CommanderNavigation {
  public static let todayURL = URL(string: "lazenskycommander://today")!
  public static func opensToday(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "lazenskycommander" && url.host?.lowercased() == "today"
  }
}

public struct CommanderScheduledNotification: Equatable, Sendable {
  public let identifier: String
  public let title: String
  public let body: String
  public let fireAt: Date
  public let payload: [String: String]

  public init(identifier: String, title: String, body: String, fireAt: Date, payload: [String: String]) {
    self.identifier = identifier
    self.title = title
    self.body = body
    self.fireAt = fireAt
    self.payload = payload
  }
}

public struct CommanderNotificationChanges: Sendable {
  public let upsert: [CommanderScheduledNotification]
  public let remove: [String]
}

/// One bounded projection for start alerts and optional departure fallback. AlarmKit
/// success removes only departure fallback; start alerts remain independently useful.
public enum CommanderNotificationContract {
  public static let category = "COMMANDER_EVENT_V1"

  public static func prefix(dataset: CommanderScheduleDataset, channel: String) -> String {
    "lazensky.commander.iphone.events.v1.\(channel).\(dataset.rawValue)."
  }

  public static func identifier(stableID: String, dataset: CommanderScheduleDataset,
                                channel: String, departure: Bool = false) -> String {
    // Lossless encoding, independent of Swift's randomized Hasher and schedule version.
    prefix(dataset: dataset, channel: channel) + (departure ? "leave." : "start.") +
      Data(stableID.utf8).base64EncodedString()
  }

  public static func desired(snapshot: WatchScheduleSnapshot, dataset: CommanderScheduleDataset,
                             channel: String, includeDeparture: Bool, now: Date,
                             limit: Int = 60, departureExclusions: Set<String> = []) throws -> [CommanderScheduledNotification] {
    guard dataset.accepts(snapshot.schedule),
          snapshot.schedule.events.allSatisfy({ dataset.accepts(stableID: $0.stableId) }) else {
      throw CocoaError(.coderReadCorrupt)
    }
    let projection = try CommanderScheduleProjection(schedule: snapshot.schedule, overrides: snapshot.leadTimeOverrides)
    var result: [CommanderScheduledNotification] = []
    for item in projection.events {
      for departure in includeDeparture ? [false, true] : [false] {
        if departure && departureExclusions.contains(item.event.stableId) { continue }
        let date = departure ? item.leaveAt : item.startAt
        guard date > now else { continue }
        let payload = ["stableId": item.event.stableId, "dataset": dataset.rawValue,
          "channel": channel, "scheduleVersion": String(snapshot.schedule.scheduleVersion),
          "projectionRevision": String(snapshot.projectionRevision), "startAt": item.alarm.startAt,
          "location": item.event.location, "title": item.event.title, "route": "today",
          "kind": departure ? "leave" : "start"]
        result.append(.init(identifier: identifier(stableID: item.event.stableId, dataset: dataset,
          channel: channel, departure: departure), title: departure ? "Čas vyrazit" : item.event.title,
          body: [departure ? item.event.title : nil, item.event.location, item.event.start]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), fireAt: date, payload: payload))
      }
    }
    return Array(result.sorted {
      $0.fireAt == $1.fireAt ? $0.identifier < $1.identifier : $0.fireAt < $1.fireAt
    }.prefix(max(0, limit)))
  }

  public static func reconcile(current: [CommanderScheduledNotification], desired: [CommanderScheduledNotification],
                               dataset: CommanderScheduleDataset, channel: String) -> CommanderNotificationChanges {
    let owned = current.filter { $0.identifier.hasPrefix(prefix(dataset: dataset, channel: channel)) }
    let desiredIDs = Set(desired.map(\.identifier))
    return .init(upsert: desired.filter { !owned.contains($0) },
                 remove: owned.map(\.identifier).filter { !desiredIDs.contains($0) })
  }

  /// Notification content is a routing hint, never a replacement schedule. An old
  /// notification still opens the current canonical event (including after deletion).
  public static func routesToCurrent(actionIdentifier: String, defaultActionIdentifier: String,
                                    category: String, payload: [String: String],
                                    dataset: CommanderScheduleDataset) -> Bool {
    actionIdentifier == defaultActionIdentifier && category == Self.category &&
      payload["dataset"] == dataset.rawValue && payload["channel"] == "production" &&
      payload["route"] == "today" && payload["stableId"].map { dataset.accepts(stableID: $0) && !$0.isEmpty } == true
  }

  public static func currentState(snapshot: WatchScheduleSnapshot?, now: Date) -> CommanderLiveStateResult {
    CommanderLiveStateCalculator.compute(
      schedule: WatchScheduleExpiryPolicy.activeSchedule(snapshot?.schedule, at: now),
      now: now, overrides: snapshot?.leadTimeOverrides)
  }
}

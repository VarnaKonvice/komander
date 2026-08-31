import Foundation

public enum WatchLeaveNotificationContract {
  public static let identifierNamespace = "lazensky.commander.watch.leave."
  public static let maximumPending = 60
  public static let notificationTitle = "Čas vyrazit"

  public static func identifier(for stableId: String) -> String {
    identifierNamespace + stableId
  }

  public static func manages(identifier: String) -> Bool {
    identifier.hasPrefix(identifierNamespace)
  }

  public static func stableId(from identifier: String) -> String? {
    guard manages(identifier: identifier) else { return nil }
    return String(identifier.dropFirst(identifierNamespace.count))
  }
}

public struct WatchLocalNotification: Codable, Equatable, Sendable {
  public let stableId: String
  public let scheduleVersion: Int
  public let leaveAt: String
  public let title: String
  public let location: String

  public init(
    stableId: String,
    scheduleVersion: Int = 0,
    leaveAt: String,
    title: String,
    location: String
  ) {
    self.stableId = stableId
    self.scheduleVersion = scheduleVersion
    self.leaveAt = leaveAt
    self.title = title
    self.location = location
  }

  public var identifier: String {
    WatchLeaveNotificationContract.identifier(for: stableId)
  }

  public var notificationTitle: String {
    WatchLeaveNotificationContract.notificationTitle
  }

  public var notificationBody: String {
    let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedLocation.isEmpty ? title : "\(title) · \(trimmedLocation)"
  }

  fileprivate func hasSameNotificationContent(as other: WatchLocalNotification) -> Bool {
    stableId == other.stableId
      && leaveAt == other.leaveAt
      && title == other.title
      && location == other.location
  }
}

public struct WatchNotificationPlan: Equatable, Sendable {
  public var create: [WatchLocalNotification] = []
  public var update: [WatchLocalNotification] = []
  public var cancel: [String] = []
  public var unchanged: [WatchLocalNotification] = []
  public var ignoredStaleSchedule = false

  public var hasChanges: Bool {
    !create.isEmpty || !update.isEmpty || !cancel.isEmpty
  }
}

public enum WatchLocalNotificationPlanner {
  public static func notifications(
    schedule: Schedule,
    now: Date = Date(),
    overrides: LeadTimeOverrides? = nil,
    limit: Int = WatchLeaveNotificationContract.maximumPending
  ) throws -> [WatchLocalNotification] {
    let budget = max(0, min(limit, WatchLeaveNotificationContract.maximumPending))
    guard budget > 0 else { return [] }

    let alarms = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides).alarms
    let future = try alarms.compactMap { alarm -> (Date, WatchLocalNotification)? in
      let leaveAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
      guard leaveAt > now else { return nil }
      return (
        leaveAt,
        WatchLocalNotification(
          stableId: alarm.stableId,
          scheduleVersion: schedule.scheduleVersion,
          leaveAt: alarm.leaveAt,
          title: alarm.title,
          location: alarm.location
        )
      )
    }

    return future
      .sorted {
        if $0.0 != $1.0 { return $0.0 < $1.0 }
        return $0.1.stableId < $1.1.stableId
      }
      .prefix(budget)
      .map(\.1)
  }
}

public enum WatchNotificationReconciler {
  public static func reconcile(
    current: [WatchLocalNotification],
    next: [WatchLocalNotification]
  ) -> WatchNotificationPlan {
    var byID = Dictionary(uniqueKeysWithValues: current.map { ($0.stableId, $0) })
    var plan = WatchNotificationPlan()

    for item in next {
      guard let prior = byID.removeValue(forKey: item.stableId) else {
        plan.create.append(item)
        continue
      }
      if prior.hasSameNotificationContent(as: item) {
        plan.unchanged.append(prior)
      } else {
        plan.update.append(item)
      }
    }

    plan.cancel = byID.values.map(\.identifier).sorted()
    return plan
  }

  public static func reconcile(
    current: [WatchLocalNotification],
    schedule: Schedule?,
    enabled: Bool,
    now: Date = Date(),
    overrides: LeadTimeOverrides? = nil,
    lastReconciledScheduleVersion: Int? = nil
  ) throws -> WatchNotificationPlan {
    guard enabled, let schedule else {
      var plan = WatchNotificationPlan()
      plan.cancel = current.map(\.identifier).sorted()
      return plan
    }

    if let lastReconciledScheduleVersion,
       schedule.scheduleVersion < lastReconciledScheduleVersion {
      var plan = WatchNotificationPlan()
      plan.unchanged = current
      plan.ignoredStaleSchedule = true
      return plan
    }

    let next = try WatchLocalNotificationPlanner.notifications(
      schedule: schedule,
      now: now,
      overrides: overrides
    )
    return reconcile(current: current, next: next)
  }
}

public enum WatchNotificationAuthorizationState: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
}

public struct WatchStandaloneAlarmState: Equatable, Sendable {
  public let isEnabled: Bool
  public let authorization: WatchNotificationAuthorizationState

  public init(isEnabled: Bool, authorization: WatchNotificationAuthorizationState) {
    self.isEnabled = isEnabled
    self.authorization = authorization
  }

  public var isOperational: Bool {
    isEnabled && authorization == .authorized
  }
}

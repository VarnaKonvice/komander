import Foundation
import LazenskyCommanderCore
import UserNotifications

actor WatchLocalNotificationService {
  private enum VerificationError: LocalizedError {
    case pendingRequestsDiffer
    var errorDescription: String? { "Notifikace Watch se nepodařilo ověřit. Obnovte aplikaci pro další pokus." }
  }

  private struct PendingNotifications {
    var items: [WatchLocalNotification] = []
    var invalidIdentifiers: Set<String> = []
  }

  private enum UserInfoKey {
    static let stableId = "stableId"
    static let scheduleVersion = "scheduleVersion"
    static let leaveAt = "leaveAt"
    static let eventTitle = "eventTitle"
    static let location = "location"
  }

  private static let prague = TimeZone(identifier: "Europe/Prague")!

  private let operations = CommanderSerialOperationQueue()
  private var latestProjection: WatchScheduleProjectionIdentity?
  private let center: UNUserNotificationCenter
  private let preferences: WatchStandaloneAlarmPreferences

  init(
    center: UNUserNotificationCenter = .current(),
    preferences: WatchStandaloneAlarmPreferences
  ) {
    self.center = center
    self.preferences = preferences
  }

  func authorizationStatus() async -> WatchNotificationAuthorizationState {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional:
      return .authorized
    case .denied:
      return .denied
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .denied
    }
  }

  func requestAuthorization() async throws -> WatchNotificationAuthorizationState {
    _ = try await center.requestAuthorization(options: [.alert, .sound])
    return await authorizationStatus()
  }

  @discardableResult
  func reconcile(
    schedule: Schedule?,
    enabled: Bool,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date = Date()
  ) async throws -> WatchNotificationPlan {
    try await operations.run {
      try await self.apply(schedule: schedule, enabled: enabled, overrides: overrides,
                           projectionRevision: projectionRevision, now: now)
    }
  }

  private func apply(schedule: Schedule?, enabled: Bool, overrides: LeadTimeOverrides?,
                     projectionRevision: Int, now: Date) async throws -> WatchNotificationPlan {
    // A queued reconciliation must not re-enable notifications after the user disabled them.
    let enabled = enabled && preferences.isEnabled
    let current = await managedPendingNotifications()
    if enabled, let schedule, let latestProjection,
       schedule.scheduleVersion == latestProjection.scheduleVersion,
       projectionRevision < latestProjection.projectionRevision {
      var stale = WatchNotificationPlan()
      stale.unchanged = current.items
      stale.ignoredStaleSchedule = true
      return stale
    }
    let plan = try WatchNotificationReconciler.reconcile(
      current: current.items,
      schedule: schedule,
      enabled: enabled,
      now: now,
      overrides: overrides,
      lastReconciledScheduleVersion: preferences.lastReconciledScheduleVersion,
      invalidIdentifiers: current.invalidIdentifiers
    )

    guard !plan.ignoredStaleSchedule else { return plan }

    if !plan.cancel.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: plan.cancel)
    }
    for notification in plan.create + plan.update {
      try await center.add(request(for: notification))
    }

    // Verify actual OS requests before recording success. A notification that became
    // due while awaiting the OS must not be recreated as a past notification.
    let observed = await managedPendingNotifications()
    let remaining = try WatchNotificationReconciler.reconcile(
      current: observed.items, schedule: schedule, enabled: enabled,
      now: max(now, Date()), overrides: overrides,
      invalidIdentifiers: observed.invalidIdentifiers
    )
    guard !remaining.hasChanges else { throw VerificationError.pendingRequestsDiffer }

    if enabled, let schedule {
      let previous = preferences.lastReconciledScheduleVersion ?? schedule.scheduleVersion
      preferences.lastReconciledScheduleVersion = max(previous, schedule.scheduleVersion)
      latestProjection = WatchScheduleProjectionIdentity(scheduleVersion: schedule.scheduleVersion,
                                                         projectionRevision: projectionRevision)
    }
    return plan
  }

  private func managedPendingNotifications() async -> PendingNotifications {
    var pending = PendingNotifications()
    for request in await center.pendingNotificationRequests() {
      guard let stableId = WatchLeaveNotificationContract.stableId(from: request.identifier) else { continue }
      let info = request.content.userInfo
      let item = WatchLocalNotification(
        stableId: stableId,
        scheduleVersion: info[UserInfoKey.scheduleVersion] as? Int ?? 0,
        leaveAt: info[UserInfoKey.leaveAt] as? String ?? "",
        title: info[UserInfoKey.eventTitle] as? String ?? "",
        location: info[UserInfoKey.location] as? String ?? ""
      )
      pending.items.append(item)
      let trigger = request.trigger as? UNCalendarNotificationTrigger
      if !item.matchesObservedRequest(
        title: request.content.title, body: request.content.body,
        fireDate: trigger?.nextTriggerDate(), repeats: trigger?.repeats ?? true,
        hasSound: request.content.sound != nil
      ) {
        pending.invalidIdentifiers.insert(request.identifier)
      }
    }
    return pending
  }

  private func request(for notification: WatchLocalNotification) throws -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = notification.notificationTitle
    content.body = notification.notificationBody
    content.sound = .default
    content.interruptionLevel = .active
    content.userInfo = [
      UserInfoKey.stableId: notification.stableId,
      UserInfoKey.scheduleVersion: notification.scheduleVersion,
      UserInfoKey.leaveAt: notification.leaveAt,
      UserInfoKey.eventTitle: notification.title,
      UserInfoKey.location: notification.location
    ]

    let leaveAt = try NativeAlarmContract.date(fromLocalISO: notification.leaveAt)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Self.prague
    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: leaveAt
    )
    components.timeZone = Self.prague
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    return UNNotificationRequest(
      identifier: notification.identifier,
      content: content,
      trigger: trigger
    )
  }
}

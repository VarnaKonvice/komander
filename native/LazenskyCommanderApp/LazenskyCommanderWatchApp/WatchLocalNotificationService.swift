import Foundation
import LazenskyCommanderCore
import UserNotifications

actor WatchLocalNotificationService {
  private enum UserInfoKey {
    static let stableId = "stableId"
    static let scheduleVersion = "scheduleVersion"
    static let leaveAt = "leaveAt"
    static let eventTitle = "eventTitle"
    static let location = "location"
  }

  private static let prague = TimeZone(identifier: "Europe/Prague")!

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
    now: Date = Date()
  ) async throws -> WatchNotificationPlan {
    let current = await managedPendingNotifications()
    let plan = try WatchNotificationReconciler.reconcile(
      current: current,
      schedule: schedule,
      enabled: enabled,
      now: now,
      lastReconciledScheduleVersion: preferences.lastReconciledScheduleVersion
    )

    guard !plan.ignoredStaleSchedule else { return plan }

    if !plan.cancel.isEmpty {
      center.removePendingNotificationRequests(withIdentifiers: plan.cancel)
    }
    for notification in plan.create + plan.update {
      try await center.add(request(for: notification))
    }

    if enabled, let schedule {
      let previous = preferences.lastReconciledScheduleVersion ?? schedule.scheduleVersion
      preferences.lastReconciledScheduleVersion = max(previous, schedule.scheduleVersion)
    }
    return plan
  }

  private func managedPendingNotifications() async -> [WatchLocalNotification] {
    await center.pendingNotificationRequests().compactMap { request in
      guard let stableId = WatchLeaveNotificationContract.stableId(from: request.identifier) else {
        return nil
      }
      let info = request.content.userInfo
      return WatchLocalNotification(
        stableId: stableId,
        scheduleVersion: info[UserInfoKey.scheduleVersion] as? Int ?? 0,
        leaveAt: info[UserInfoKey.leaveAt] as? String ?? "",
        title: info[UserInfoKey.eventTitle] as? String ?? "",
        location: info[UserInfoKey.location] as? String ?? ""
      )
    }
  }

  private func request(for notification: WatchLocalNotification) throws -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = notification.notificationTitle
    content.body = notification.notificationBody
    content.sound = .default
    content.interruptionLevel = .timeSensitive
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

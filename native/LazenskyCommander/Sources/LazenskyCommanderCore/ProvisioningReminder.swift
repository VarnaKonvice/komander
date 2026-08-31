import Foundation

public struct ProvisioningReminderRequest: Equatable, Sendable {
  public static let identifier = "lazensky.commander.provisioning.renewal.v1"
  public static let title = "Obnov Lázeňský Commander"
  public static let body = "Připoj iPhone k MacBooku Air a spusť jedno-klikové obnovení."
  public let fireAt: Date
  public let profileCreatedAt: Date
  public let profileExpiresAt: Date

  public init(fireAt: Date, profileCreatedAt: Date, profileExpiresAt: Date) {
    self.fireAt = fireAt
    self.profileCreatedAt = profileCreatedAt
    self.profileExpiresAt = profileExpiresAt
  }
}

public enum ProvisioningNotificationPermission: Sendable {
  case allowed, notRequested, denied
}

public enum ProvisioningReminderStatus: Equatable, Sendable {
  case unavailable, permissionRequired, denied, due, expired, failed
  case scheduled(Date)
}

@MainActor public protocol ProvisioningReminderNotifications: AnyObject {
  func permission() async -> ProvisioningNotificationPermission
  func requestPermission() async throws -> Bool
  func pendingReminder() async -> ProvisioningReminderRequest?
  func replaceReminder(_ request: ProvisioningReminderRequest) async throws
  func clearPendingReminder() async
  func clearDeliveredReminder() async
}

@available(macOS 10.15, *)
@MainActor public final class ProvisioningReminderCoordinator {
  private let notifications: any ProvisioningReminderNotifications
  private var operation: Task<ProvisioningReminderStatus, Never>?

  public init(notifications: any ProvisioningReminderNotifications) {
    self.notifications = notifications
  }

  public func refresh(
    profile: ProvisioningProfileMetadata?, now: Date, requestPermission: Bool = false
  ) async -> ProvisioningReminderStatus {
    // Foreground refresh and the permission button share one serial operation stream.
    let previous = operation
    let task = Task { @MainActor in
      _ = await previous?.value
      return await self.reconcile(profile: profile, now: now, requestPermission: requestPermission)
    }
    operation = task
    return await task.value
  }

  private func reconcile(
    profile: ProvisioningProfileMetadata?, now: Date, requestPermission: Bool
  ) async -> ProvisioningReminderStatus {
    guard let profile, profile.creationDate <= now else {
      await notifications.clearPendingReminder()
      return .unavailable
    }
    guard profile.expirationDate > now else {
      await notifications.clearPendingReminder()
      return .expired
    }
    guard profile.recommendedRefreshAt > now else {
      await notifications.clearPendingReminder()
      return .due
    }

    await notifications.clearDeliveredReminder()

    var permission = await notifications.permission()
    if case .notRequested = permission, requestPermission {
      do {
        permission = try await notifications.requestPermission() ? .allowed : .denied
      } catch {
        return .failed
      }
    }
    switch permission {
    case .notRequested:
      await notifications.clearPendingReminder()
      return .permissionRequired
    case .denied:
      await notifications.clearPendingReminder()
      return .denied
    case .allowed:
      break
    }

    let desired = ProvisioningReminderRequest(
      fireAt: profile.recommendedRefreshAt,
      profileCreatedAt: profile.creationDate, profileExpiresAt: profile.expirationDate
    )
    if await notifications.pendingReminder() != desired {
      do {
        try await notifications.replaceReminder(desired)
      } catch {
        return .failed
      }
    }
    guard await notifications.pendingReminder() == desired else { return .failed }
    return .scheduled(desired.fireAt)
  }
}

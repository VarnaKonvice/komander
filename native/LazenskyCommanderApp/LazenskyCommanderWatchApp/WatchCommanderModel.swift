import Foundation
import LazenskyCommanderCore
import Observation
import WidgetKit

@MainActor
@Observable
final class WatchCommanderModel {
  private let cache: FileWatchScheduleCache
  private let alarmPreferences: WatchStandaloneAlarmPreferences
  private let notificationService: WatchLocalNotificationService

  private(set) var snapshot: WatchScheduleSnapshot?
  private(set) var schedule: Schedule?
  private(set) var cacheError: String?
  private(set) var transportError: String?
  private(set) var standaloneAlarmsEnabled: Bool
  private(set) var notificationAuthorization: WatchNotificationAuthorizationState = .notDetermined
  private(set) var notificationError: String?
  private(set) var isUpdatingStandaloneAlarms = false

  var leadTimeOverrides: LeadTimeOverrides {
    snapshot?.leadTimeOverrides ?? LeadTimeOverrides()
  }

  var projectionIdentity: WatchScheduleProjectionIdentity? {
    snapshot?.projectionIdentity
  }

  init(
    cache: FileWatchScheduleCache? = nil,
    alarmPreferences: WatchStandaloneAlarmPreferences? = nil,
    notificationService: WatchLocalNotificationService? = nil
  ) {
    let preferences = alarmPreferences ?? WatchStandaloneAlarmPreferences()
    let service = notificationService ?? WatchLocalNotificationService(preferences: preferences)
    self.alarmPreferences = preferences
    self.notificationService = service
    self.standaloneAlarmsEnabled = preferences.isEnabled
    self.cache = cache ?? WatchCacheLocation.makeCache { snapshot in
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.kind)
      WidgetCenter.shared.invalidateRelevance(ofKind: CommanderWatchWidgetContract.kind)
      guard preferences.isEnabled,
            await service.authorizationStatus() == .authorized
      else { return }
      _ = try? await service.reconcile(
        schedule: snapshot.schedule,
        enabled: true,
        overrides: snapshot.leadTimeOverrides
      )
    }
  }

  func bootstrap() async {
    do {
      snapshot = try await cache.load()
      schedule = snapshot?.schedule
      cacheError = nil
      await reconcileStandaloneAlarms(requestAuthorization: false)
    } catch {
      snapshot = nil
      schedule = nil
      cacheError = error.localizedDescription
    }
  }

  @discardableResult
  func receive(_ incoming: WatchScheduleSnapshot) async throws -> WatchScheduleCacheDecision {
    let decision = try await cache.accept(incoming)
    switch decision {
    case .stored, .unchanged:
      snapshot = try await cache.load()
      schedule = snapshot?.schedule
      cacheError = nil
    case .rejectedInvalid, .rejectedVersion:
      break
    }
    return decision
  }

  func recordTransportError(_ message: String?) {
    transportError = message
  }

  func setStandaloneAlarmsEnabled(_ enabled: Bool) async {
    alarmPreferences.isEnabled = enabled
    standaloneAlarmsEnabled = enabled
    await reconcileStandaloneAlarms(requestAuthorization: enabled)
  }

  func handleForeground() async {
    await reconcileStandaloneAlarms(requestAuthorization: false)
  }

  var standaloneAlarmState: WatchStandaloneAlarmState {
    WatchStandaloneAlarmState(
      isEnabled: standaloneAlarmsEnabled,
      authorization: notificationAuthorization
    )
  }

  private func reconcileStandaloneAlarms(requestAuthorization: Bool) async {
    isUpdatingStandaloneAlarms = true
    defer { isUpdatingStandaloneAlarms = false }

    do {
      var authorization = await notificationService.authorizationStatus()
      if standaloneAlarmsEnabled,
         requestAuthorization,
         authorization == .notDetermined {
        authorization = try await notificationService.requestAuthorization()
      }
      notificationAuthorization = authorization

      if standaloneAlarmsEnabled, authorization == .authorized {
        _ = try await notificationService.reconcile(
          schedule: schedule,
          enabled: true,
          overrides: leadTimeOverrides
        )
      } else {
        _ = try await notificationService.reconcile(schedule: nil, enabled: false)
      }
      notificationError = nil
    } catch {
      notificationError = error.localizedDescription
      notificationAuthorization = await notificationService.authorizationStatus()
    }
  }
}

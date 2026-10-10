import Foundation
import LazenskyCommanderCore
import Observation
import WidgetKit

@MainActor
@Observable
final class WatchCommanderModel {
  private let cache: FileWatchScheduleCache
  private let usesSharedCache: Bool
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
    self.standaloneAlarmsEnabled = preferences.isEnabled && CommanderMVPPolicy.createsStandaloneWatchAlerts
    self.usesSharedCache = cache == nil
    self.cache = cache ?? WatchCacheLocation.makeCache { _ in
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.kind)
      WidgetCenter.shared.invalidateRelevance(ofKind: CommanderWatchWidgetContract.kind)
    }
  }

  func bootstrap() async {
    do {
      if usesSharedCache {
        try await WatchCacheLocation.migrateLegacyCacheIfNeeded()
      }
      let cached = try await cache.load()
      if let cached, !WatchScheduleExpiryPolicy.isExpired(cached.schedule, at: Date()) {
        applyCachedSnapshot(cached)
      } else if let recovered = try await recoverProductionSnapshot() {
        applyCachedSnapshot(recovered)
      }
      cacheError = nil
      refreshComplication()
    } catch {
      // The foreground Watch app has a more reliable network budget than the
      // complication extension. Recover the shared production cache here.
      do {
        if let recovered = try await recoverProductionSnapshot() {
          applyCachedSnapshot(recovered)
          cacheError = nil
          refreshComplication()
        } else {
          cacheError = error.localizedDescription
        }
      } catch {
        cacheError = error.localizedDescription
      }
    }
    // Cleanup of old standalone requests is independent of loading the root view.
    Task { @MainActor [weak self] in
      await self?.reconcileStandaloneAlarms(requestAuthorization: false)
    }
  }

  private func recoverProductionSnapshot() async throws -> WatchScheduleSnapshot? {
    guard WatchCacheLocation.dataset == .production else { return nil }
    let schedule = try await URLSessionScheduleService(
      configuration: AppConfiguration()
    ).fetchSchedule()
    let fallback = WatchScheduleSnapshot(
      schedule: schedule,
      leadTimeOverrides: LeadTimeOverrides(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: ["Vizita": 5]
      )
    )
    let receipt = try await cache.acceptAndLoad(fallback)
    switch receipt.decision {
    case .stored, .unchanged, .rejectedVersion:
      return receipt.snapshot
    case .rejectedInvalid:
      return nil
    }
  }

  @discardableResult
  func receive(_ incoming: WatchScheduleSnapshot) async throws -> WatchScheduleCacheDecision {
    let receipt = try await cache.acceptAndLoad(incoming)
    let decision = receipt.decision
    switch decision {
    case .stored, .unchanged, .rejectedVersion:
      applyCachedSnapshot(receipt.snapshot)
      cacheError = nil
      refreshComplication()
      #if !COMMANDER_ACCEPTANCE_FIXTURES
      if snapshot != nil {
        try? await WatchCacheLocation.makeAcceptanceCache().remove()
      }
      #endif
      // Transport ACK proves the exact atomic cache projection, not the optional
      // standalone-notification projection. Do not block cache acknowledgement on
      // UNUserNotificationCenter reads/writes; retry those independently.
      Task { @MainActor [weak self] in
        await self?.reconcileStandaloneAlarms(requestAuthorization: false)
      }
    case .rejectedInvalid:
      break
    }
    return decision
  }

  private func applyCachedSnapshot(_ incoming: WatchScheduleSnapshot?) {
    guard let incoming else { return }
    // MainActor methods can resume out of order after awaiting the cache actor.
    guard WatchScheduleCachePolicy.decision(incoming: incoming, existing: snapshot) == .stored ||
          incoming == snapshot else { return }
    snapshot = incoming
    schedule = incoming.schedule
  }

  private func refreshComplication() {
    // Never hold the MainActor/bootstrap on WidgetKit IPC. The Watch app must
    // publish its loaded schedule to the UI immediately even if chronod is busy.
    Task { @MainActor in
      WidgetCenter.shared.reloadTimelines(ofKind: CommanderWatchWidgetContract.kind)
      WidgetCenter.shared.invalidateRelevance(ofKind: CommanderWatchWidgetContract.kind)
    }
  }

  func recordTransportError(_ message: String?) {
    transportError = message
  }

  func setStandaloneAlarmsEnabled(_ enabled: Bool) async {
    alarmPreferences.isEnabled = enabled
    standaloneAlarmsEnabled = enabled && CommanderMVPPolicy.createsStandaloneWatchAlerts
    await reconcileStandaloneAlarms(requestAuthorization: enabled)
  }

  func currentState(at now: Date) -> CommanderLiveStateResult {
    CommanderNotificationContract.currentState(snapshot: snapshot, now: now)
  }

  func handleForeground() async {
    // A warm system launch need not redeliver a notification response. Always
    // refresh from the same canonical cache used by a cold root-view launch.
    await bootstrap()
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
          overrides: leadTimeOverrides,
          projectionRevision: snapshot?.projectionRevision ?? 0
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

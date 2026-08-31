import Foundation

public enum CommanderScheduleSource: Equatable, Sendable {
  case remote
  case cached
}

public enum CommanderScheduleSyncError: LocalizedError {
  case noValidatedSnapshot

  public var errorDescription: String? {
    "Nejdřív načti platný rozpis. Bez uloženého rozpisu nelze přepočítat alarmy."
  }
}

public struct CommanderScheduleSyncResult: Equatable, Sendable {
  public let schedule: Schedule
  public let scheduleDecision: ScheduleSnapshotDecision
  public let alarmSummary: AlarmSyncSummary
  public let watchSnapshot: WatchScheduleSnapshot
  public let watchDeliveryStatus: WatchScheduleDeliveryStatus

  public var succeeded: Bool {
    // Watch acknowledgement is diagnostic, not a prerequisite for iPhone operation.
    alarmSummary.succeeded
  }
}

public struct CommanderScheduleSyncCoordinator: Sendable {
  private let scheduleService: any ScheduleServing
  private let alarmSyncService: AlarmSyncService
  private let scheduleStore: any ScheduleSnapshotStoring
  private let watchDelivery: (any WatchScheduleSnapshotDelivering)?

  public init(
    scheduleService: any ScheduleServing,
    alarmSyncService: AlarmSyncService,
    scheduleStore: any ScheduleSnapshotStoring,
    watchDelivery: (any WatchScheduleSnapshotDelivering)? = nil
  ) {
    self.scheduleService = scheduleService
    self.alarmSyncService = alarmSyncService
    self.scheduleStore = scheduleStore
    self.watchDelivery = watchDelivery
  }

  public func loadLastSchedule() async throws -> Schedule? {
    try await scheduleStore.load()
  }

  public func synchronize(
    source: CommanderScheduleSource = .remote,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date = Date()
  ) async throws -> CommanderScheduleSyncResult {
    let decision: ScheduleSnapshotDecision
    let schedule: Schedule
    switch source {
    case .cached:
      guard let cached = try await scheduleStore.load() else {
        throw CommanderScheduleSyncError.noValidatedSnapshot
      }
      try NativeAlarmContract.validateCanonical(cached)
      schedule = cached
      decision = .unchanged
    case .remote:
      let fetchedSchedule = try await scheduleService.fetchSchedule()
      // Accept canonical data before projecting it. Local preferences never write this store.
      decision = try await scheduleStore.accept(fetchedSchedule)
      switch decision {
      case .stored, .unchanged:
        schedule = fetchedSchedule
      case .rejectedVersion:
        guard let existing = try await scheduleStore.load() else {
          throw ScheduleValidationError.invalidScheduleVersion
        }
        schedule = existing
      }
    }

    let effectiveOverrides = overrides ?? LeadTimeOverrides()
    let summary = try await alarmSyncService.synchronizeValidated(
      schedule: schedule,
      overrides: effectiveOverrides,
      projectionRevision: projectionRevision,
      now: now
    )
    let watchSnapshot = WatchScheduleSnapshot(
      schedule: schedule,
      leadTimeOverrides: effectiveOverrides,
      projectionRevision: projectionRevision
    )
    let watchDeliveryStatus: WatchScheduleDeliveryStatus
    if let watchDelivery {
      do {
        let disposition = try await watchDelivery.deliver(watchSnapshot)
        if await watchDelivery.verifiedProjectionIdentity() == watchSnapshot.projectionIdentity {
          watchDeliveryStatus = .verified
        } else {
          switch disposition {
          case .queued: watchDeliveryStatus = .queued
          case .sent: watchDeliveryStatus = .sent
          }
        }
      } catch {
        watchDeliveryStatus = .failed(error.localizedDescription)
      }
    } else {
      watchDeliveryStatus = .notConfigured
    }

    return CommanderScheduleSyncResult(
      schedule: schedule,
      scheduleDecision: decision,
      alarmSummary: summary,
      watchSnapshot: watchSnapshot,
      watchDeliveryStatus: watchDeliveryStatus
    )
  }
}

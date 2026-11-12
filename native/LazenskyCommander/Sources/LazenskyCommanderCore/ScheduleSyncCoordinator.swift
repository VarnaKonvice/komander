import Foundation

public enum CommanderScheduleSource: Equatable, Sendable {
  case remote
  case cached
  case imported(Schedule)
}

public enum CommanderScheduleSyncError: LocalizedError {
  case noValidatedSnapshot
  case importVersionConflict(current: Int, incoming: Int)

  public var errorDescription: String? {
    switch self {
    case .noValidatedSnapshot:
      "Nejdřív načti platný rozpis. Bez uloženého rozpisu nelze přepočítat alarmy."
    case let .importVersionConflict(current, incoming):
      "Soubor má verzi \(incoming), uložený rozpis verzi \(current). Změněný rozpis musí mít vyšší verzi."
    }
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
  private let operations = CommanderSerialOperationQueue()
  private let dataset: CommanderScheduleDataset?
  private let clock: @Sendable () -> Date
  private let scheduleService: any ScheduleServing
  private let alarmSyncService: AlarmSyncService
  private let scheduleStore: any ScheduleSnapshotStoring
  private let watchDelivery: (any WatchScheduleSnapshotDelivering)?

  public init(
    scheduleService: any ScheduleServing,
    alarmSyncService: AlarmSyncService,
    scheduleStore: any ScheduleSnapshotStoring,
    watchDelivery: (any WatchScheduleSnapshotDelivering)? = nil,
    dataset: CommanderScheduleDataset? = nil,
    clock: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.dataset = dataset
    self.clock = clock
    self.scheduleService = scheduleService
    self.alarmSyncService = alarmSyncService
    self.scheduleStore = scheduleStore
    self.watchDelivery = watchDelivery
  }

  public func loadLastSchedule() async throws -> Schedule? {
    guard let schedule = try await scheduleStore.load() else { return nil }
    guard dataset?.accepts(schedule) != false else { throw CocoaError(.coderReadCorrupt) }
    return schedule
  }

  /// Fetches and validates the remote schedule without accepting it into the
  /// local snapshot or touching alarms, widgets, notifications, or calendar.
  /// Used by the client-facing approval gate for a new/updated stay schedule.
  public func fetchRemoteCandidate() async throws -> Schedule {
    let incoming = try await scheduleService.fetchSchedule()
    guard dataset?.accepts(incoming) != false else { throw CocoaError(.coderReadCorrupt) }
    try NativeAlarmContract.validateCanonical(incoming)
    return incoming
  }

  public func synchronize(
    source: CommanderScheduleSource = .remote,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date? = nil
  ) async throws -> CommanderScheduleSyncResult {
    try await operations.run {
      try await self.performSynchronization(source: source, overrides: overrides,
        projectionRevision: projectionRevision, now: now)
    }
  }

  private func performSynchronization(
    source: CommanderScheduleSource, overrides: LeadTimeOverrides?,
    projectionRevision: Int, now: Date?
  ) async throws -> CommanderScheduleSyncResult {
    let decision: ScheduleSnapshotDecision
    let schedule: Schedule
    switch source {
    case .cached:
      guard let cached = try await scheduleStore.load() else {
        throw CommanderScheduleSyncError.noValidatedSnapshot
      }
      guard dataset?.accepts(cached) != false else { throw CocoaError(.coderReadCorrupt) }
      try NativeAlarmContract.validateCanonical(cached)
      schedule = cached
      decision = .unchanged
    case .remote, .imported:
      let incoming: Schedule
      if case let .imported(schedule) = source {
        incoming = schedule
      } else {
        incoming = try await scheduleService.fetchSchedule()
      }
      guard dataset?.accepts(incoming) != false else { throw CocoaError(.coderReadCorrupt) }
      try NativeAlarmContract.validateCanonical(incoming)
      // Check the current local preferences before replacing the offline snapshot.
      _ = try CommanderScheduleProjection(schedule: incoming, overrides: overrides)
      decision = try await scheduleStore.accept(incoming)
      switch decision {
      case .stored, .unchanged:
        schedule = incoming
      case let .rejectedVersion(current, version):
        if case .imported = source {
          throw CommanderScheduleSyncError.importVersionConflict(current: current, incoming: version)
        }
        guard let existing = try await loadLastSchedule() else {
          throw ScheduleValidationError.invalidScheduleVersion
        }
        schedule = existing
      }
    }

    let effectiveOverrides = overrides ?? LeadTimeOverrides()
    let projection = try CommanderScheduleProjection(schedule: schedule, overrides: effectiveOverrides)
    let acceptedAt = now ?? clock()
    let summary: AlarmSyncSummary
    do {
      summary = try await alarmSyncService.synchronizeValidated(
        schedule: schedule, overrides: effectiveOverrides, projectionRevision: projectionRevision,
        // The network may cross a departure deadline; project at acceptance time.
        now: acceptedAt
      )
    } catch {
      // A platform/persistence failure is not a failed schedule acceptance. Keep
      // widgets, Watch and start notifications on the accepted canonical snapshot,
      // while reporting AlarmKit as unverified and retaining its ownership ledger.
      summary = AlarmSyncSummary(scheduleVersion: schedule.scheduleVersion,
        desiredAlarmCount: projection.events.filter { $0.leaveAt > acceptedAt }.count,
        plan: AlarmReconciliationPlan(), appliedCreate: 0, appliedUpdate: 0, appliedCancel: 0,
        errorMessage: error.localizedDescription, completedAt: acceptedAt, verified: false, repairAttempts: 0)
    }
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

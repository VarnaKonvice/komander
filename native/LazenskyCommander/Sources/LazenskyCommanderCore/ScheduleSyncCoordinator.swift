import Foundation

public struct CommanderScheduleSyncResult: Equatable, Sendable {
  public let schedule: Schedule
  public let alarmSummary: AlarmSyncSummary
  public let watchSnapshot: WatchScheduleSnapshot
  public let watchDeliveryStatus: WatchScheduleDeliveryStatus
  public let alarmRecoveryAttempts: Int

  public var succeeded: Bool { alarmSummary.succeeded }
}

public struct CommanderScheduleSyncCoordinator: Sendable {
  private let scheduleService: any ScheduleServing
  private let alarmSyncService: AlarmSyncService
  private let scheduleStore: any ScheduleSnapshotStoring
  private let watchDelivery: (any WatchScheduleSnapshotDelivering)?
  private let alarmRecoveryAttempts: Int

  public init(
    scheduleService: any ScheduleServing,
    alarmSyncService: AlarmSyncService,
    scheduleStore: any ScheduleSnapshotStoring,
    watchDelivery: (any WatchScheduleSnapshotDelivering)? = nil,
    alarmRecoveryAttempts: Int = 3
  ) {
    self.scheduleService = scheduleService
    self.alarmSyncService = alarmSyncService
    self.scheduleStore = scheduleStore
    self.watchDelivery = watchDelivery
    self.alarmRecoveryAttempts = max(1, alarmRecoveryAttempts)
  }

  public func loadLastSchedule() async throws -> Schedule? {
    try await scheduleStore.load()
  }

  public func synchronize(overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> CommanderScheduleSyncResult {
    let schedule = try await scheduleService.fetchSchedule()
    let (summary, attempts) = try await synchronizeAlarmsWithRecovery(
      schedule: schedule,
      overrides: overrides,
      now: now
    )

    // A valid canonical schedule must not be held back by a recoverable projection failure.
    // AlarmKit and Watch are derived services; their status is reported independently.
    try await scheduleStore.save(schedule)

    let watchSnapshot = WatchScheduleSnapshot(schedule: schedule)
    let watchDeliveryStatus: WatchScheduleDeliveryStatus
    if let watchDelivery {
      do {
        switch try await watchDelivery.deliver(watchSnapshot) {
        case .queued: watchDeliveryStatus = .queued
        case .sent: watchDeliveryStatus = .sent
        }
      } catch {
        watchDeliveryStatus = .failed(error.localizedDescription)
      }
    } else {
      watchDeliveryStatus = .notConfigured
    }

    return CommanderScheduleSyncResult(
      schedule: schedule,
      alarmSummary: summary,
      watchSnapshot: watchSnapshot,
      watchDeliveryStatus: watchDeliveryStatus,
      alarmRecoveryAttempts: attempts
    )
  }

  private func synchronizeAlarmsWithRecovery(
    schedule: Schedule,
    overrides: LeadTimeOverrides?,
    now: Date
  ) async throws -> (AlarmSyncSummary, Int) {
    var lastSummary: AlarmSyncSummary?

    for attempt in 1...alarmRecoveryAttempts {
      let summary = try await alarmSyncService.synchronizeValidated(
        schedule: schedule,
        overrides: overrides,
        now: now
      )
      lastSummary = summary
      if summary.succeeded {
        return (summary, attempt)
      }
    }

    // alarmRecoveryAttempts is clamped to at least one, so this is always populated.
    return (lastSummary!, alarmRecoveryAttempts)
  }
}

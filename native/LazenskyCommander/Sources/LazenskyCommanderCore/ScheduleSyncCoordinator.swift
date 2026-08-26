import Foundation

public struct CommanderScheduleSyncResult: Equatable, Sendable {
  public let schedule: Schedule
  public let scheduleDecision: ScheduleSnapshotDecision
  public let alarmSummary: AlarmSyncSummary
  public let watchSnapshot: WatchScheduleSnapshot
  public let watchDeliveryStatus: WatchScheduleDeliveryStatus

  public var succeeded: Bool {
    guard alarmSummary.succeeded else { return false }
    switch watchDeliveryStatus {
    case .notConfigured, .verified:
      return true
    case .notAttempted, .queued, .sent, .failed:
      return false
    }
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

  public func synchronize(overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> CommanderScheduleSyncResult {
    let fetchedSchedule = try await scheduleService.fetchSchedule()

    // Accept the validated canonical snapshot first. AlarmKit and Watch are independent
    // projections: losing one projection must never roll the dashboard back to an older version.
    let decision = try await scheduleStore.accept(fetchedSchedule)
    let schedule: Schedule
    switch decision {
    case .stored, .unchanged:
      schedule = fetchedSchedule
    case .rejectedVersion:
      guard let existing = try await scheduleStore.load() else {
        throw ScheduleValidationError.invalidScheduleVersion
      }
      schedule = existing
    }

    let summary = try await alarmSyncService.synchronizeValidated(schedule: schedule, overrides: overrides, now: now)
    let watchSnapshot = WatchScheduleSnapshot(schedule: schedule)
    let watchDeliveryStatus: WatchScheduleDeliveryStatus
    if let watchDelivery {
      do {
        let disposition = try await watchDelivery.deliver(watchSnapshot)
        if await watchDelivery.verifiedScheduleVersion() == schedule.scheduleVersion {
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

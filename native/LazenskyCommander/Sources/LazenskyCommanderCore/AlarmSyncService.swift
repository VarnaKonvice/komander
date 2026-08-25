import Foundation

public struct AlarmSyncSummary: Equatable, Sendable {
  public let scheduleVersion: Int?
  public let desiredAlarmCount: Int
  public let plan: AlarmReconciliationPlan
  public let appliedCreate: Int
  public let appliedUpdate: Int
  public let appliedCancel: Int
  public let errorMessage: String?
  public let completedAt: Date?
  public let verified: Bool
  public let repairAttempts: Int

  public var succeeded: Bool { errorMessage == nil && verified }
}

public struct AlarmSyncService: Sendable {
  private let scheduleService: any ScheduleServing
  private let store: any AlarmStateStoring
  private let adapter: any AlarmAdapting

  public init(scheduleService: any ScheduleServing, store: any AlarmStateStoring, adapter: any AlarmAdapting) {
    self.scheduleService = scheduleService
    self.store = store
    self.adapter = adapter
  }

  public func alarmAccessDescription() async -> String {
    switch await adapter.availability() {
    case .unavailable(let reason): return reason
    case .available:
      switch await adapter.authorizationStatus() {
      case .authorized: return "Alarm access authorized."
      case .notDetermined: return "Alarm access has not been requested."
      case .denied: return "Alarm access denied."
      }
    }
  }

  public func authorizationStatus() async -> AlarmAuthorizationStatus {
    await adapter.authorizationStatus()
  }

  public func synchronize(overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> AlarmSyncSummary {
    let schedule = try await scheduleService.fetchSchedule()
    return try await synchronizeValidated(schedule: schedule, overrides: overrides, now: now)
  }

  public func synchronize(schedule: Schedule, overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> AlarmSyncSummary {
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    return try await synchronize(schedule: schedule, payload: payload, now: now)
  }

  func synchronizeValidated(schedule: Schedule, overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> AlarmSyncSummary {
    let payload = try NativeAlarmContract.payloadValidated(schedule: schedule, overrides: overrides)
    return try await synchronize(schedule: schedule, payload: payload, now: now)
  }

  private func synchronize(schedule: Schedule, payload: NativeAlarmPayload, now: Date) async throws -> AlarmSyncSummary {
    let desiredPayload = try desiredPayload(from: payload, now: now)
    await adapter.prepare(schedule: schedule)
    var state = try await store.load()

    let availability = await adapter.availability()
    guard case .available = availability else {
      let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
      let message: String
      if case .unavailable(let reason) = availability { message = reason } else { message = "AlarmKit is unavailable." }
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: message, completedAt: nil, verified: false, repairs: 0)
    }

    switch await adapter.authorizationStatus() {
    case .authorized:
      break
    case .notDetermined:
      try await adapter.requestAuthorization()
    case .denied:
      throw AlarmAdapterError.authorizationDenied
    }

    let platformIDs: Set<String>?
    do {
      platformIDs = try await adapter.existingPlatformAlarmIDs()
    } catch {
      let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0)
    }

    if let platformIDs {
      let before = state.records.count
      state.records = state.records.filter { platformIDs.contains($0.value.platformAlarmID) }
      if state.records.count != before { try await store.save(state) }
    }

    let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
    var created = 0
    var updated = 0
    var cancelled = 0
    var repairs = 0

    do {
      for change in plan.cancel {
        try await cancel(change, state: &state)
        cancelled += 1
        try await store.save(state)
      }
      for change in plan.update {
        try await cancel(change, state: &state)
        try await store.save(state)
        try await create(change, state: &state)
        updated += 1
        try await store.save(state)
      }
      for change in plan.create {
        try await create(change, state: &state)
        created += 1
        try await store.save(state)
      }

      if let actualIDs = try await adapter.existingPlatformAlarmIDs() {
        let expectedIDs = Set(state.records.values.map(\.platformAlarmID))
        if actualIDs != expectedIDs {
          repairs += 1

          let missingRecords = state.records.values.filter { !actualIDs.contains($0.platformAlarmID) }
          for record in missingRecords {
            state.records.removeValue(forKey: record.stableId)
          }
          if !missingRecords.isEmpty { try await store.save(state) }

          let remainingExpectedIDs = Set(state.records.values.map(\.platformAlarmID))
          for orphanID in actualIDs.subtracting(remainingExpectedIDs) {
            try await adapter.cancel(platformAlarmID: orphanID)
          }

          let desiredByStableID = Dictionary(uniqueKeysWithValues: desiredPayload.alarms.map { ($0.stableId, $0) })
          for record in missingRecords {
            guard let alarm = desiredByStableID[record.stableId] else { continue }
            let platformAlarmID = try await adapter.schedule(alarm, replacing: nil)
            state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: platformAlarmID, alarm: alarm)
            created += 1
            try await store.save(state)
          }

          guard let repairedIDs = try await adapter.existingPlatformAlarmIDs(), repairedIDs == Set(state.records.values.map(\.platformAlarmID)) else {
            throw AlarmAdapterError.verificationFailed
          }
        }
      }

      state.lastSuccessfulPayload = desiredPayload
      state.lastSuccessfulSync = now
      try await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: nil, completedAt: now, verified: true, repairs: repairs)
    } catch {
      try? await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: error.localizedDescription, completedAt: nil, verified: false, repairs: repairs)
    }
  }

  private func desiredPayload(from payload: NativeAlarmPayload, now: Date) throws -> NativeAlarmPayload {
    let futureAlarms = try payload.alarms.filter {
      try NativeAlarmContract.date(fromLocalISO: $0.leaveAt) > now
    }
    return NativeAlarmPayload(
      contractVersion: payload.contractVersion,
      scheduleVersion: payload.scheduleVersion,
      alarms: futureAlarms
    )
  }

  private func create(_ change: AlarmChange, state: inout ManagedAlarmState) async throws {
    guard let alarm = change.nextAlarm else { return }
    let previousID = state.records[alarm.stableId]?.platformAlarmID
    let platformAlarmID = try await adapter.schedule(alarm, replacing: previousID)
    state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: platformAlarmID, alarm: alarm)
  }

  private func cancel(_ change: AlarmChange, state: inout ManagedAlarmState) async throws {
    guard let record = state.records[change.stableId] else { return }
    try await adapter.cancel(platformAlarmID: record.platformAlarmID)
    state.records.removeValue(forKey: change.stableId)
  }

  private func summary(scheduleVersion: Int, payload: NativeAlarmPayload, plan: AlarmReconciliationPlan, created: Int, updated: Int, cancelled: Int, error: String?, completedAt: Date?, verified: Bool, repairs: Int) -> AlarmSyncSummary {
    AlarmSyncSummary(scheduleVersion: scheduleVersion, desiredAlarmCount: payload.alarms.count, plan: plan, appliedCreate: created, appliedUpdate: updated, appliedCancel: cancelled, errorMessage: error, completedAt: completedAt, verified: verified, repairAttempts: repairs)
  }
}

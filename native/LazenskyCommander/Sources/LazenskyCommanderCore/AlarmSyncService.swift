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
      do {
        try await adapter.requestAuthorization()
      } catch {
        let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
        return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0)
      }
    case .denied:
      let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: AlarmAdapterError.authorizationDenied.localizedDescription, completedAt: nil, verified: false, repairs: 0)
    }

    var repairs = 0
    let platformIDs: Set<String>
    let fixedAlertDates: [String: Date]?
    do {
      guard let ids = try await adapter.existingPlatformAlarmIDs() else {
        let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
        return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: AlarmAdapterError.verificationFailed.localizedDescription, completedAt: nil, verified: false, repairs: 0)
      }
      platformIDs = ids
      fixedAlertDates = try await adapter.existingPlatformFixedAlertDates()
    } catch {
      let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0)
    }

    // Reconcile persisted state against the real platform before computing the write plan.
    // A record with the right ID but the wrong fixed alert time is just as broken as a missing alarm.
    let invalidBeforeWrite = try invalidStableIDs(in: state, platformIDs: platformIDs, fixedAlertDates: fixedAlertDates)
    if !invalidBeforeWrite.isEmpty {
      repairs += 1
      for stableID in invalidBeforeWrite {
        guard let record = state.records[stableID] else { continue }
        if platformIDs.contains(record.platformAlarmID) {
          try? await adapter.cancel(platformAlarmID: record.platformAlarmID)
        }
        state.records.removeValue(forKey: stableID)
      }
      try await store.save(state)
    }

    let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
    var created = 0
    var updated = 0
    var cancelled = 0

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

      var verification = try await inspectPlatform(state: state)
      if !verification.invalidStableIDs.isEmpty || !verification.orphanPlatformIDs.isEmpty {
        repairs += 1

        let desiredByStableID = Dictionary(uniqueKeysWithValues: desiredPayload.alarms.map { ($0.stableId, $0) })
        for stableID in verification.invalidStableIDs {
          if let record = state.records[stableID] {
            if verification.platformIDs.contains(record.platformAlarmID) {
              try? await adapter.cancel(platformAlarmID: record.platformAlarmID)
            }
            state.records.removeValue(forKey: stableID)
          }
        }
        if !verification.invalidStableIDs.isEmpty { try await store.save(state) }

        for orphanID in verification.orphanPlatformIDs {
          try await adapter.cancel(platformAlarmID: orphanID)
        }

        for stableID in verification.invalidStableIDs.sorted() {
          guard let alarm = desiredByStableID[stableID] else { continue }
          let platformAlarmID = try await adapter.schedule(alarm, replacing: nil)
          state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: platformAlarmID, alarm: alarm)
          created += 1
          try await store.save(state)
        }

        verification = try await inspectPlatform(state: state)
        guard verification.invalidStableIDs.isEmpty, verification.orphanPlatformIDs.isEmpty else {
          throw AlarmAdapterError.verificationFailed
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

  private func invalidStableIDs(
    in state: ManagedAlarmState,
    platformIDs: Set<String>,
    fixedAlertDates: [String: Date]?
  ) throws -> Set<String> {
    var invalid = Set<String>()
    for record in state.records.values {
      guard platformIDs.contains(record.platformAlarmID) else {
        invalid.insert(record.stableId)
        continue
      }
      guard let fixedAlertDates else { continue }
      let expected = try NativeAlarmContract.date(fromLocalISO: record.alarm.leaveAt)
      guard let actual = fixedAlertDates[record.platformAlarmID], abs(actual.timeIntervalSince(expected)) <= 1 else {
        invalid.insert(record.stableId)
        continue
      }
    }
    return invalid
  }

  private func inspectPlatform(state: ManagedAlarmState) async throws -> (
    platformIDs: Set<String>,
    invalidStableIDs: Set<String>,
    orphanPlatformIDs: Set<String>
  ) {
    guard let platformIDs = try await adapter.existingPlatformAlarmIDs() else {
      throw AlarmAdapterError.verificationFailed
    }
    let fixedAlertDates = try await adapter.existingPlatformFixedAlertDates()
    let invalid = try invalidStableIDs(in: state, platformIDs: platformIDs, fixedAlertDates: fixedAlertDates)
    let expectedIDs = Set(state.records.values.map(\.platformAlarmID))
    let orphanIDs = platformIDs.subtracting(expectedIDs)
    return (platformIDs, invalid, orphanIDs)
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

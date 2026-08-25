import Foundation

public struct AlarmSyncSummary: Equatable, Sendable {
  public let scheduleVersion: Int?
  public let desiredAlarmCount: Int
  public let plan: AlarmReconciliationPlan
  public let appliedCreate: Int
  public let appliedUpdate: Int
  public let appliedCancel: Int
  public let uncoveredStableIds: [String]
  public let errorMessage: String?
  public let completedAt: Date?

  public var succeeded: Bool { errorMessage == nil && uncoveredStableIds.isEmpty }
}

public enum AlarmSyncVerificationError: LocalizedError, Equatable, Sendable {
  case missingPlatformAlarms(Int)
  case orphanedPlatformAlarms(Int)

  public var errorDescription: String? {
    switch self {
    case .missingPlatformAlarms(let count):
      return "AlarmKit verification is missing \(count) expected alarm(s)."
    case .orphanedPlatformAlarms(let count):
      return "AlarmKit verification found \(count) orphaned alarm(s)."
    }
  }
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

  public func synchronize(overrides: LeadTimeOverrides? = nil, now: Date = Date()) async throws -> AlarmSyncSummary {
    let schedule = try await scheduleService.fetchSchedule()
    let result = try await synchronizeValidated(schedule: schedule, overrides: overrides, now: now)
    // Preserve the explicit direct-service authorization contract used by diagnostics/tests.
    // The Commander coordinator calls synchronizeValidated directly so it can keep the
    // canonical schedule current and activate fallback coverage when AlarmKit is denied.
    if result.errorMessage == AlarmAdapterError.authorizationDenied.localizedDescription {
      throw AlarmAdapterError.authorizationDenied
    }
    return result
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
      return failureSummary(
        schedule: schedule,
        payload: desiredPayload,
        state: state,
        error: availabilityReason(availability)
      )
    }

    switch await adapter.authorizationStatus() {
    case .authorized:
      break
    case .notDetermined:
      do {
        try await adapter.requestAuthorization()
      } catch {
        return failureSummary(
          schedule: schedule,
          payload: desiredPayload,
          state: state,
          error: error.localizedDescription
        )
      }
    case .denied:
      return failureSummary(
        schedule: schedule,
        payload: desiredPayload,
        state: state,
        error: AlarmAdapterError.authorizationDenied.localizedDescription
      )
    }

    do {
      try await repairPersistedPlatformMapping(state: &state)
    } catch {
      try await store.save(state)
      return failureSummary(
        schedule: schedule,
        payload: desiredPayload,
        state: state,
        error: error.localizedDescription
      )
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

      try await verifyPlatformState(state)

      state.lastSuccessfulPayload = desiredPayload
      state.lastSuccessfulSync = now
      try await store.save(state)
      return summary(
        scheduleVersion: schedule.scheduleVersion,
        payload: desiredPayload,
        plan: plan,
        created: created,
        updated: updated,
        cancelled: cancelled,
        uncoveredStableIds: [],
        error: nil,
        completedAt: now
      )
    } catch {
      try await store.save(state)
      let knownPlatformIDs = await knownPlatformIDsIfAvailable()
      return summary(
        scheduleVersion: schedule.scheduleVersion,
        payload: desiredPayload,
        plan: plan,
        created: created,
        updated: updated,
        cancelled: cancelled,
        uncoveredStableIds: uncoveredStableIds(payload: desiredPayload, state: state, knownPlatformIDs: knownPlatformIDs),
        error: error.localizedDescription,
        completedAt: nil
      )
    }
  }

  private func failureSummary(
    schedule: Schedule,
    payload: NativeAlarmPayload,
    state: ManagedAlarmState,
    error: String
  ) -> AlarmSyncSummary {
    let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: payload)
    return summary(
      scheduleVersion: schedule.scheduleVersion,
      payload: payload,
      plan: plan,
      created: 0,
      updated: 0,
      cancelled: 0,
      uncoveredStableIds: uncoveredStableIds(payload: payload, state: state, knownPlatformIDs: nil),
      error: error,
      completedAt: nil
    )
  }

  private func availabilityReason(_ availability: AlarmKitAvailability) -> String {
    if case .unavailable(let reason) = availability { return reason }
    return "AlarmKit is unavailable."
  }

  private func repairPersistedPlatformMapping(state: inout ManagedAlarmState) async throws {
    guard let existingIDs = try await adapter.existingPlatformAlarmIDs() else { return }

    let managedIDs = Set(state.records.values.map(\.platformAlarmID))
    let orphanedIDs = existingIDs.subtracting(managedIDs)
    for orphanedID in orphanedIDs.sorted() {
      try await adapter.cancel(platformAlarmID: orphanedID)
    }

    let before = state.records.count
    state.records = state.records.filter { existingIDs.contains($0.value.platformAlarmID) }
    if state.records.count != before {
      try await store.save(state)
    }
  }

  private func verifyPlatformState(_ state: ManagedAlarmState) async throws {
    guard let existingIDs = try await adapter.existingPlatformAlarmIDs() else { return }
    let expectedIDs = Set(state.records.values.map(\.platformAlarmID))
    let missing = expectedIDs.subtracting(existingIDs)
    if !missing.isEmpty {
      throw AlarmSyncVerificationError.missingPlatformAlarms(missing.count)
    }
    let orphaned = existingIDs.subtracting(expectedIDs)
    if !orphaned.isEmpty {
      throw AlarmSyncVerificationError.orphanedPlatformAlarms(orphaned.count)
    }
  }

  private func knownPlatformIDsIfAvailable() async -> Set<String>? {
    do {
      return try await adapter.existingPlatformAlarmIDs()
    } catch {
      return nil
    }
  }

  private func uncoveredStableIds(
    payload: NativeAlarmPayload,
    state: ManagedAlarmState,
    knownPlatformIDs: Set<String>?
  ) -> [String] {
    payload.alarms.compactMap { alarm in
      guard let record = state.records[alarm.stableId], record.alarm == alarm else {
        return alarm.stableId
      }
      if let knownPlatformIDs, !knownPlatformIDs.contains(record.platformAlarmID) {
        return alarm.stableId
      }
      return nil
    }.sorted()
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

  private func summary(
    scheduleVersion: Int,
    payload: NativeAlarmPayload,
    plan: AlarmReconciliationPlan,
    created: Int,
    updated: Int,
    cancelled: Int,
    uncoveredStableIds: [String],
    error: String?,
    completedAt: Date?
  ) -> AlarmSyncSummary {
    AlarmSyncSummary(
      scheduleVersion: scheduleVersion,
      desiredAlarmCount: payload.alarms.count,
      plan: plan,
      appliedCreate: created,
      appliedUpdate: updated,
      appliedCancel: cancelled,
      uncoveredStableIds: uncoveredStableIds,
      errorMessage: error,
      completedAt: completedAt
    )
  }
}

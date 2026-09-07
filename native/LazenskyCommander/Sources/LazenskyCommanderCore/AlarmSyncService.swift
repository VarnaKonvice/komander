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
  public let reconciliationHistory: [AlarmReconciliationHistoryEntry]

  public init(
    scheduleVersion: Int?,
    desiredAlarmCount: Int,
    plan: AlarmReconciliationPlan,
    appliedCreate: Int,
    appliedUpdate: Int,
    appliedCancel: Int,
    errorMessage: String?,
    completedAt: Date?,
    verified: Bool,
    repairAttempts: Int,
    reconciliationHistory: [AlarmReconciliationHistoryEntry] = []
  ) {
    self.scheduleVersion = scheduleVersion
    self.desiredAlarmCount = desiredAlarmCount
    self.plan = plan
    self.appliedCreate = appliedCreate
    self.appliedUpdate = appliedUpdate
    self.appliedCancel = appliedCancel
    self.errorMessage = errorMessage
    self.completedAt = completedAt
    self.verified = verified
    self.repairAttempts = repairAttempts
    self.reconciliationHistory = reconciliationHistory
  }

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

  public func synchronize(
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date? = nil
  ) async throws -> AlarmSyncSummary {
    let schedule = try await scheduleService.fetchSchedule()
    let result = try await synchronizeValidated(
      schedule: schedule,
      overrides: overrides,
      projectionRevision: projectionRevision,
      now: now ?? Date()
    )
    // Preserve the standalone service API's historical permission signal. The Commander
    // coordinator intentionally uses synchronizeValidated so a denied AlarmKit projection
    // never blocks acceptance of the canonical schedule or the fallback path.
    if result.errorMessage == AlarmAdapterError.authorizationDenied.localizedDescription {
      throw AlarmAdapterError.authorizationDenied
    }
    return result
  }

  public func synchronize(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date = Date()
  ) async throws -> AlarmSyncSummary {
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    return try await synchronize(
      schedule: schedule,
      payload: payload,
      overrides: overrides,
      projectionRevision: projectionRevision,
      now: now
    )
  }

  func synchronizeValidated(
    schedule: Schedule,
    overrides: LeadTimeOverrides? = nil,
    projectionRevision: Int = 0,
    now: Date = Date()
  ) async throws -> AlarmSyncSummary {
    let payload = try NativeAlarmContract.payloadValidated(schedule: schedule, overrides: overrides)
    return try await synchronize(
      schedule: schedule,
      payload: payload,
      overrides: overrides,
      projectionRevision: projectionRevision,
      now: now
    )
  }

  private func synchronize(
    schedule: Schedule,
    payload: NativeAlarmPayload,
    overrides: LeadTimeOverrides?,
    projectionRevision: Int,
    now: Date
  ) async throws -> AlarmSyncSummary {
    let desiredPayload = try desiredPayload(from: payload, now: now)
    await adapter.prepare(
      schedule: schedule,
      projectionRevision: max(0, projectionRevision),
      overrides: overrides
    )
    var state = try await store.load()
    var presentationContexts: [String: AlarmPresentationContext] = [:]
    for alarm in desiredPayload.alarms {
      presentationContexts[alarm.stableId] = try await adapter.presentationContext(for: alarm)
    }
    var protectedAlertingIDs = Set<String>()
    func reconciliation(_ state: ManagedAlarmState) -> AlarmReconciliationPlan {
      var plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: desiredPayload)
      let contextChanges = plan.unchanged.filter {
        presentationContexts[$0.stableId] != state.records[$0.stableId]?.presentationContext
      }
      let changedIDs = Set(contextChanges.map(\.stableId))
      plan.unchanged.removeAll { changedIDs.contains($0.stableId) }
      plan.update += contextChanges
      plan.cancel.removeAll { change in
        state.records[change.stableId].map { protectedAlertingIDs.contains($0.platformAlarmID) } == true
      }
      return plan
    }

    let availability = await adapter.availability()
    guard case .available = availability else {
      let plan = reconciliation(state)
      let message: String
      if case .unavailable(let reason) = availability { message = reason } else { message = "AlarmKit is unavailable." }
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: message, completedAt: nil, verified: false, repairs: 0, history: state.reconciliationHistory)
    }

    switch await adapter.authorizationStatus() {
    case .authorized:
      break
    case .notDetermined:
      do {
        try await adapter.requestAuthorization()
      } catch {
        let plan = reconciliation(state)
        return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0, history: state.reconciliationHistory)
      }
    case .denied:
      let plan = reconciliation(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: AlarmAdapterError.authorizationDenied.localizedDescription, completedAt: nil, verified: false, repairs: 0, history: state.reconciliationHistory)
    }

    // A foreground refresh is not a user stop action. Keep an already ringing,
    // unchanged canonical event until it is stopped or the event has ended.
    do {
      let alerting = try await adapter.existingPlatformAlertingAlarmIDs()
      let canonical = Dictionary(uniqueKeysWithValues: payload.alarms.map { ($0.stableId, $0) })
      for record in state.records.values where alerting.contains(record.platformAlarmID) {
        if canonical[record.stableId] == record.alarm,
           try NativeAlarmContract.date(fromLocalISO: record.alarm.leaveAt) <= now,
           try NativeAlarmContract.date(fromLocalISO: record.alarm.endAt) > now {
          protectedAlertingIDs.insert(record.platformAlarmID)
        }
      }
    } catch {
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload,
        plan: reconciliation(state), created: 0, updated: 0, cancelled: 0,
        error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0,
        history: state.reconciliationHistory)
    }

    let historyID = UUID()
    let beforeHistory = await reconciliationHistoryObservations(payload: desiredPayload, state: state)
    state.appendReconciliationHistory(
      AlarmReconciliationHistoryEntry(
        id: historyID,
        scheduleVersion: schedule.scheduleVersion,
        startedAt: now,
        desiredAlarmCount: desiredPayload.alarms.count,
        before: beforeHistory
      )
    )
    try? await store.save(state)

    var repairs = 0
    // Updates/cancellations do not need the old timer's endpoint; verify their replacements below.
    let retainedStableIDs = Set(reconciliation(state).unchanged.map(\.stableId))
    let futurePlatformIDs = Set(state.records.values.filter { retainedStableIDs.contains($0.stableId) }.map(\.platformAlarmID))
    let platformIDs: Set<String>?
    let fixedAlertDates: [String: Date]?
    do {
      platformIDs = try await adapter.existingPlatformAlarmIDs()
      fixedAlertDates = platformIDs == nil ? nil : try await adapter.existingPlatformFixedAlertDates(for: futurePlatformIDs)
    } catch {
      let plan = reconciliation(state)
      state = await finalizedHistoryState(
        state,
        id: historyID,
        payload: desiredPayload,
        completedAt: nil,
        repairs: repairs,
        verified: false,
        error: error.localizedDescription
      )
      try? await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: 0, history: state.reconciliationHistory)
    }

    // Real AlarmKit exposes its daemon state, so production verifies persisted IDs and effective
    // alert deadlines here. Minimal non-platform test adapters may return nil to opt out of this
    // platform-specific observation; their unit tests then exercise reconciliation only.
    do {
      if let platformIDs {
        let invalidBeforeWrite = try invalidStableIDs(in: state, platformIDs: platformIDs, fixedAlertDates: fixedAlertDates, timingIDs: futurePlatformIDs)
        if !invalidBeforeWrite.isEmpty {
          repairs += 1
          for stableID in invalidBeforeWrite {
            guard let record = state.records[stableID] else { continue }
            if platformIDs.contains(record.platformAlarmID) {
              try await adapter.cancel(platformAlarmID: record.platformAlarmID)
            }
            state.records.removeValue(forKey: stableID)
          }
          try await store.save(state)
        }
      }
    } catch {
      // Keep the ID when cancellation failed: creating a replacement could ring twice.
      try? await store.save(state)
      let plan = reconciliation(state)
      state = await finalizedHistoryState(
        state,
        id: historyID,
        payload: desiredPayload,
        completedAt: nil,
        repairs: repairs,
        verified: false,
        error: error.localizedDescription
      )
      try? await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: 0, updated: 0, cancelled: 0, error: error.localizedDescription, completedAt: nil, verified: false, repairs: repairs, history: state.reconciliationHistory)
    }

    let plan = reconciliation(state)
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
        try await create(change, state: &state, presentationContext: presentationContexts[change.stableId])
        updated += 1
        try await store.save(state)
      }
      for change in plan.create {
        try await create(change, state: &state, presentationContext: presentationContexts[change.stableId])
        created += 1
        try await store.save(state)
      }

      if var verification = try await inspectPlatform(state: state, protectedAlertingIDs: protectedAlertingIDs) {
        if !verification.invalidStableIDs.isEmpty || !verification.orphanPlatformIDs.isEmpty {
          repairs += 1

          let desiredByStableID = Dictionary(uniqueKeysWithValues: desiredPayload.alarms.map { ($0.stableId, $0) })
          for stableID in verification.invalidStableIDs {
            if let record = state.records[stableID] {
              if verification.platformIDs.contains(record.platformAlarmID) {
                try await adapter.cancel(platformAlarmID: record.platformAlarmID)
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
            state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: platformAlarmID, alarm: alarm, presentationContext: presentationContexts[alarm.stableId])
            created += 1
            try await store.save(state)
          }

          guard let repairedVerification = try await inspectPlatform(state: state, protectedAlertingIDs: protectedAlertingIDs) else {
            throw AlarmAdapterError.verificationFailed
          }
          verification = repairedVerification
          guard verification.invalidStableIDs.isEmpty, verification.orphanPlatformIDs.isEmpty else {
            throw AlarmAdapterError.verificationFailed
          }
        }
      }

      state.lastSuccessfulPayload = desiredPayload
      state.lastSuccessfulSync = now
      state = await finalizedHistoryState(
        state,
        id: historyID,
        payload: desiredPayload,
        completedAt: now,
        repairs: repairs,
        verified: true,
        error: nil
      )
      try await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: nil, completedAt: now, verified: true, repairs: repairs, history: state.reconciliationHistory)
    } catch {
      state = await finalizedHistoryState(
        state,
        id: historyID,
        payload: desiredPayload,
        completedAt: nil,
        repairs: repairs,
        verified: false,
        error: error.localizedDescription
      )
      try? await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: desiredPayload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: error.localizedDescription, completedAt: nil, verified: false, repairs: repairs, history: state.reconciliationHistory)
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

  private func reconciliationHistoryObservations(
    payload: NativeAlarmPayload,
    state: ManagedAlarmState
  ) async -> [AlarmReconciliationObservation] {
    let desired = payload.alarms.sorted { lhs, rhs in
      if lhs.leaveAt != rhs.leaveAt { return lhs.leaveAt < rhs.leaveAt }
      return lhs.stableId < rhs.stableId
    }
    let managedIDs = Set(desired.compactMap { state.records[$0.stableId]?.platformAlarmID })

    let platformIDs: Set<String>?
    do {
      platformIDs = try await adapter.existingPlatformAlarmIDs()
    } catch {
      return desired.map { alarm in
        AlarmReconciliationObservation(
          stableId: alarm.stableId,
          title: alarm.title,
          expectedLeaveAt: alarm.leaveAt,
          platformAlarmID: state.records[alarm.stableId]?.platformAlarmID,
          platformExists: nil,
          actualLeaveAt: nil,
          readbackError: "Stav alarmů se nepodařilo přečíst: \(error.localizedDescription)"
        )
      }
    }

    let dates: [String: Date]?
    var timingError: String?
    if platformIDs == nil || managedIDs.isEmpty {
      dates = nil
    } else {
      do {
        dates = try await adapter.existingPlatformFixedAlertDates(for: managedIDs)
      } catch {
        dates = nil
        timingError = "Časy alarmů se nepodařilo přečíst: \(error.localizedDescription)"
      }
    }

    return desired.map { alarm in
      let platformID = state.records[alarm.stableId]?.platformAlarmID
      let exists = platformID.flatMap { id in platformIDs.map { $0.contains(id) } }
      return AlarmReconciliationObservation(
        stableId: alarm.stableId,
        title: alarm.title,
        expectedLeaveAt: alarm.leaveAt,
        platformAlarmID: platformID,
        platformExists: exists,
        actualLeaveAt: platformID.flatMap { dates?[$0] },
        readbackError: platformID == nil ? nil : timingError
      )
    }
  }

  private func finalizedHistoryState(
    _ state: ManagedAlarmState,
    id: UUID,
    payload: NativeAlarmPayload,
    completedAt: Date?,
    repairs: Int,
    verified: Bool,
    error: String?
  ) async -> ManagedAlarmState {
    var updated = state
    let after = await reconciliationHistoryObservations(payload: payload, state: updated)
    updated.updateReconciliationHistory(
      id: id,
      completedAt: completedAt,
      after: after,
      repairAttempts: repairs,
      verified: verified,
      errorMessage: error
    )
    return updated
  }

  private func invalidStableIDs(
    in state: ManagedAlarmState,
    platformIDs: Set<String>,
    fixedAlertDates: [String: Date]?,
    timingIDs: Set<String>? = nil
  ) throws -> Set<String> {
    var invalid = Set<String>()
    for record in state.records.values {
      guard platformIDs.contains(record.platformAlarmID) else {
        invalid.insert(record.stableId)
        continue
      }
      guard let fixedAlertDates else { continue }
      if let timingIDs, !timingIDs.contains(record.platformAlarmID) { continue }
      let expected = try NativeAlarmContract.date(fromLocalISO: record.alarm.leaveAt)
      guard let actual = fixedAlertDates[record.platformAlarmID], abs(actual.timeIntervalSince(expected)) <= 1 else {
        invalid.insert(record.stableId)
        continue
      }
    }
    return invalid
  }

  private func inspectPlatform(state: ManagedAlarmState, protectedAlertingIDs: Set<String>) async throws -> (
    platformIDs: Set<String>,
    invalidStableIDs: Set<String>,
    orphanPlatformIDs: Set<String>
  )? {
    guard let platformIDs = try await adapter.existingPlatformAlarmIDs() else { return nil }
    let expectedIDs = Set(state.records.values.map(\.platformAlarmID))
    let timingIDs = expectedIDs.subtracting(protectedAlertingIDs)
    let fixedAlertDates = try await adapter.existingPlatformFixedAlertDates(for: timingIDs)
    let invalid = try invalidStableIDs(in: state, platformIDs: platformIDs, fixedAlertDates: fixedAlertDates, timingIDs: timingIDs)
    let orphanIDs = platformIDs.subtracting(expectedIDs)
    return (platformIDs, invalid, orphanIDs)
  }

  private func create(_ change: AlarmChange, state: inout ManagedAlarmState, presentationContext: AlarmPresentationContext?) async throws {
    guard let alarm = change.nextAlarm else { return }
    let previousID = state.records[alarm.stableId]?.platformAlarmID
    let platformAlarmID = try await adapter.schedule(alarm, replacing: previousID)
    state.records[alarm.stableId] = ManagedAlarmRecord(stableId: alarm.stableId, platformAlarmID: platformAlarmID, alarm: alarm, presentationContext: presentationContext)
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
    error: String?,
    completedAt: Date?,
    verified: Bool,
    repairs: Int,
    history: [AlarmReconciliationHistoryEntry]
  ) -> AlarmSyncSummary {
    AlarmSyncSummary(
      scheduleVersion: scheduleVersion,
      desiredAlarmCount: payload.alarms.count,
      plan: plan,
      appliedCreate: created,
      appliedUpdate: updated,
      appliedCancel: cancelled,
      errorMessage: error,
      completedAt: completedAt,
      verified: verified,
      repairAttempts: repairs,
      reconciliationHistory: history
    )
  }
}

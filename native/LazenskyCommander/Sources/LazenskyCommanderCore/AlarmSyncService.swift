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

  public var succeeded: Bool { errorMessage == nil }
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
    let payload = try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
    var state = try await store.load()

    let availability = await adapter.availability()
    guard case .available = availability else {
      let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: payload)
      let message: String
      if case .unavailable(let reason) = availability { message = reason } else { message = "AlarmKit is unavailable." }
      return summary(scheduleVersion: schedule.scheduleVersion, payload: payload, plan: plan, created: 0, updated: 0, cancelled: 0, error: message, completedAt: nil)
    }
    switch await adapter.authorizationStatus() {
    case .authorized: break
    case .notDetermined: try await adapter.requestAuthorization()
    case .denied: throw AlarmAdapterError.authorizationDenied
    }

    if let existingIDs = try await adapter.existingPlatformAlarmIDs() {
      let before = state.records.count
      state.records = state.records.filter { existingIDs.contains($0.value.platformAlarmID) }
      if state.records.count != before { try await store.save(state) }
    }
    let plan = AlarmReconciler.reconcile(current: state.records.values.map(\.alarm), next: payload)

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
      state.lastSuccessfulPayload = payload
      state.lastSuccessfulSync = now
      try await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: payload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: nil, completedAt: now)
    } catch {
      try await store.save(state)
      return summary(scheduleVersion: schedule.scheduleVersion, payload: payload, plan: plan, created: created, updated: updated, cancelled: cancelled, error: error.localizedDescription, completedAt: nil)
    }
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

  private func summary(scheduleVersion: Int, payload: NativeAlarmPayload, plan: AlarmReconciliationPlan, created: Int, updated: Int, cancelled: Int, error: String?, completedAt: Date?) -> AlarmSyncSummary {
    AlarmSyncSummary(scheduleVersion: scheduleVersion, desiredAlarmCount: payload.alarms.count, plan: plan, appliedCreate: created, appliedUpdate: updated, appliedCancel: cancelled, errorMessage: error, completedAt: completedAt)
  }
}

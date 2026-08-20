#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func decodesProductionScheduleAndBuildsPayload() throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let payload = try NativeAlarmContract.payload(schedule: schedule)
  #expect(payload.contractVersion == 1)
  #expect(payload.scheduleVersion == 4)
  #expect(payload.alarms.count == schedule.events.count)
  #expect(payload.alarms.first(where: { $0.stableId == "synthetic-0815-bath" })?.leaveAt == "2026-08-15T09:30:00")
}

@Test func invalidScheduleAndDuplicateStableIDAreRejected() throws {
  let decoded = try decodeSchedule(named: "data/schedule.json")
  let schedule = Schedule(schemaVersion: decoded.schemaVersion, scheduleVersion: decoded.scheduleVersion, updatedAt: decoded.updatedAt, stay: decoded.stay, events: [decoded.events[0], decoded.events[0]], settings: decoded.settings)
  #expect(throws: ScheduleValidationError.duplicateStableId("synthetic-0815-breakfast")) {
    try NativeAlarmContract.validate(schedule)
  }
}

@Test func crossPlatformReconciliationFixtureParity() throws {
  let fixture = try loadFixture()
  #expect(fixture.contractVersion == 1)
  for item in fixture.cases {
    let plan = AlarmReconciler.reconcile(current: item.currentAlarms, next: item.nextPayload)
    #expect(plan.create.map(\.stableId) == item.expected.create, "\(item.name): create")
    #expect(plan.update.map(\.stableId) == item.expected.update, "\(item.name): update")
    #expect(plan.cancel.map(\.stableId) == item.expected.cancel, "\(item.name): cancel")
    #expect(plan.unchanged.map(\.stableId) == item.expected.unchanged, "\(item.name): unchanged")
  }
}

@Test func explicitOverrideFixtureChangesLeaveAtAndRequiresUpdate() throws {
  let fixture = try loadFixture().explicitOverrideCase
  let current = try NativeAlarmContract.payload(schedule: fixture.schedule, overrides: fixture.currentOverrides)
  let next = try NativeAlarmContract.payload(schedule: fixture.schedule, overrides: fixture.nextOverrides)
  #expect(current.alarms[0].leaveAt == fixture.expected.currentLeaveAt)
  #expect(next.alarms[0].leaveAt == fixture.expected.nextLeaveAt)
  #expect(next.alarms[0].effectiveLeadTimeMinutes == 0)
  #expect(AlarmReconciler.reconcile(current: current.alarms, next: next).update.map(\.stableId) == fixture.expected.update)
}

@Test func secondSuccessfulSyncIsIdempotent() async throws {
  let schedule = try decodeSchedule(named: "data/schedule.json")
  let store = InMemoryAlarmStateStore()
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: StaticScheduleService(schedule: schedule), store: store, adapter: adapter)
  let first = try await service.synchronize(now: Date(timeIntervalSince1970: 1))
  let second = try await service.synchronize(now: Date(timeIntervalSince1970: 2))
  #expect(first.appliedCreate == schedule.events.count)
  #expect(second.appliedCreate == 0)
  #expect(second.appliedUpdate == 0)
  #expect(second.plan.unchanged.count == schedule.events.count)
  #expect(await adapter.scheduledCount() == schedule.events.count)
}

@Test func fetchFailureDoesNotCancelExistingAlarm() async throws {
  let existing = NativeAlarm(stableId: "kept", kind: .procedure, title: "Kept", location: "Room", startAt: "2026-08-20T10:00:00", endAt: "2026-08-20T10:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T10:00:00")
  let initial = ManagedAlarmState(records: ["kept": ManagedAlarmRecord(stableId: "kept", platformAlarmID: "alarm-kept", alarm: existing)])
  let store = InMemoryAlarmStateStore(initial)
  let adapter = RecordingAlarmAdapter()
  let service = AlarmSyncService(scheduleService: FailingScheduleService(), store: store, adapter: adapter)
  var didThrow = false
  do { _ = try await service.synchronize() } catch { didThrow = true }
  #expect(didThrow)
  #expect(await adapter.cancelledCount() == 0)
  #expect((try await store.load()).records["kept"]?.platformAlarmID == "alarm-kept")
}

private func decodeSchedule(named path: String) throws -> Schedule {
  try JSONDecoder().decode(Schedule.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent(path)))
}

private func loadFixture() throws -> NativeFixture {
  try JSONDecoder().decode(NativeFixture.self, from: Data(contentsOf: repositoryRoot().appendingPathComponent("tests/fixtures/native-alarm-reconciliation-v1.json")))
}

private func repositoryRoot() -> URL {
  URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private struct NativeFixture: Decodable {
  let contractVersion: Int
  let cases: [FixtureCase]
  let explicitOverrideCase: ExplicitOverrideCase
}

private struct FixtureCase: Decodable {
  let name: String
  let currentAlarms: [NativeAlarm]
  let nextPayload: NativeAlarmPayload
  let expected: ExpectedActions
}

private struct ExplicitOverrideCase: Decodable {
  let schedule: Schedule
  let currentOverrides: LeadTimeOverrides
  let nextOverrides: LeadTimeOverrides
  let expected: ExplicitOverrideExpectation
}

private struct ExpectedActions: Decodable {
  let create: [String]
  let update: [String]
  let cancel: [String]
  let unchanged: [String]
}

private struct ExplicitOverrideExpectation: Decodable {
  let currentLeaveAt: String
  let nextLeaveAt: String
  let create: [String]
  let update: [String]
  let cancel: [String]
  let unchanged: [String]
}

private struct StaticScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private struct FailingScheduleService: ScheduleServing {
  func fetchSchedule() async throws -> Schedule { throw URLError(.notConnectedToInternet) }
}

private actor RecordingAlarmAdapter: AlarmAdapting {
  private var scheduled = 0
  private var cancelled = 0

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    scheduled += 1
    return platformAlarmID ?? "alarm-\(alarm.stableId)"
  }
  func cancel(platformAlarmID: String) throws { cancelled += 1 }
  func scheduledCount() -> Int { scheduled }
  func cancelledCount() -> Int { cancelled }
}
#endif

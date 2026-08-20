import Foundation
import LazenskyCommanderCore

@main
enum LazenskyCommanderCoreCheck {
  static func main() async {
    do {
      let root = try repositoryRoot()
      let schedule = try decode(Schedule.self, from: root.appendingPathComponent("data/schedule.json"))
      let fixture = try decode(Fixture.self, from: root.appendingPathComponent("tests/fixtures/native-alarm-reconciliation-v1.json"))

      let payload = try NativeAlarmContract.payload(schedule: schedule)
      try require(payload.alarms.count == schedule.events.count, "Schedule decoding or payload construction failed.")
      try require(payload.alarms.first(where: { $0.stableId == "synthetic-0815-bath" })?.leaveAt == "2026-08-15T09:30:00", "Canonical procedure leaveAt differs from fixture contract.")

      for item in fixture.cases {
        let plan = AlarmReconciler.reconcile(current: item.currentAlarms, next: item.nextPayload)
        try require(plan.create.map(\.stableId) == item.expected.create, "\(item.name): create")
        try require(plan.update.map(\.stableId) == item.expected.update, "\(item.name): update")
        try require(plan.cancel.map(\.stableId) == item.expected.cancel, "\(item.name): cancel")
        try require(plan.unchanged.map(\.stableId) == item.expected.unchanged, "\(item.name): unchanged")
      }

      let current = try NativeAlarmContract.payload(schedule: fixture.explicitOverrideCase.schedule, overrides: fixture.explicitOverrideCase.currentOverrides)
      let next = try NativeAlarmContract.payload(schedule: fixture.explicitOverrideCase.schedule, overrides: fixture.explicitOverrideCase.nextOverrides)
      try require(current.alarms[0].leaveAt == fixture.explicitOverrideCase.expected.currentLeaveAt, "Current override leaveAt mismatch.")
      try require(next.alarms[0].leaveAt == fixture.explicitOverrideCase.expected.nextLeaveAt, "Updated override leaveAt mismatch.")
      try require(AlarmReconciler.reconcile(current: current.alarms, next: next).update.map(\.stableId) == fixture.explicitOverrideCase.expected.update, "Override-only change did not update.")

      let store = InMemoryAlarmStateStore()
      let adapter = CheckAdapter()
      let sync = AlarmSyncService(scheduleService: StaticSchedule(schedule: schedule), store: store, adapter: adapter)
      let first = try await sync.synchronize(now: Date(timeIntervalSince1970: 1))
      let second = try await sync.synchronize(now: Date(timeIntervalSince1970: 2))
      try require(first.appliedCreate == schedule.events.count, "First sync did not create every alarm.")
      try require(second.appliedCreate == 0 && second.appliedUpdate == 0 && second.plan.unchanged.count == schedule.events.count, "Second sync is not idempotent.")

      print("Swift core check passed: schedule decoding, fixture parity, override update, and idempotent sync.")
    } catch {
      fputs("Swift core check failed: \(error.localizedDescription)\n", stderr)
      Foundation.exit(1)
    }
  }

  private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckError(message) }
  }

  private static func repositoryRoot() throws -> URL {
    let manager = FileManager.default
    var candidate = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
    while candidate.path != "/" {
      if manager.fileExists(atPath: candidate.appendingPathComponent("data/schedule.json").path) { return candidate }
      candidate.deleteLastPathComponent()
    }
    throw CheckError("Repository root containing data/schedule.json was not found.")
  }
}

private struct CheckError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

private struct Fixture: Decodable {
  let cases: [FixtureCase]
  let explicitOverrideCase: ExplicitOverrideCase
}

private struct FixtureCase: Decodable {
  let name: String
  let currentAlarms: [NativeAlarm]
  let nextPayload: NativeAlarmPayload
  let expected: Expected
}

private struct ExplicitOverrideCase: Decodable {
  let schedule: Schedule
  let currentOverrides: LeadTimeOverrides
  let nextOverrides: LeadTimeOverrides
  let expected: ExpectedOverride
}

private struct Expected: Decodable {
  let create: [String]
  let update: [String]
  let cancel: [String]
  let unchanged: [String]
}

private struct ExpectedOverride: Decodable {
  let currentLeaveAt: String
  let nextLeaveAt: String
  let update: [String]
}

private struct StaticSchedule: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor CheckAdapter: AlarmAdapting {
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() throws {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String { platformAlarmID ?? "alarm-\(alarm.stableId)" }
  func cancel(platformAlarmID: String) throws {}
}

import Foundation
import LazenskyCommanderCore

@main
enum LazenskyCommanderCoreCheck {
  static func main() async {
    do {
      let root = try repositoryRoot()
      let schedule = try decode(Schedule.self, from: root.appendingPathComponent("data/schedule.json"))
      let fixture = try decode(Fixture.self, from: root.appendingPathComponent("tests/fixtures/native-alarm-reconciliation-v1.json"))
      let appInfo = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp/Info.plist")), options: [], format: nil) as? [String: Any]
      let usageDescription = appInfo?["NSAlarmKitUsageDescription"] as? String
      try require(!(usageDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true), "NSAlarmKitUsageDescription is missing or empty.")

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

      let pastAdapter = CheckAdapter()
      let pastSync = AlarmSyncService(scheduleService: StaticSchedule(schedule: schedule), store: InMemoryAlarmStateStore(), adapter: pastAdapter)
      let pastSummary = try await pastSync.synchronize(now: NativeAlarmContract.date(fromLocalISO: "2026-08-22T12:00:00"))
      try require(pastSummary.desiredAlarmCount == 0 && pastSummary.succeeded, "Past canonical alarms were not filtered from the AlarmKit desired set.")
      let pastActiveAlarmCount = await pastAdapter.activeAlarmCount()
      try require(pastActiveAlarmCount == 0, "Past canonical alarms reached the platform adapter.")

      let parsedID = PlatformAlarmIdentifier.newPersistedValue()
      try require(PlatformAlarmIdentifier.uuid(from: parsedID) != nil && PlatformAlarmIdentifier.uuid(from: "invalid") == nil, "Platform alarm UUID conversion failed.")
      let leaveAt = try NativeAlarmContract.date(fromLocalISO: "2026-08-20T09:30:00")
      var prague = Calendar(identifier: .gregorian)
      prague.timeZone = TimeZone(identifier: "Europe/Prague")!
      try require(prague.component(.hour, from: leaveAt) == 9 && prague.component(.minute, from: leaveAt) == 30, "Local ISO time shifted before AlarmKit conversion.")
      try require(NativeAlarmPresentation.title(for: payload.alarms[0]).hasPrefix("Čas vyrazit:"), "Alarm title is not user-facing.")

      let mutableSource = MutableSchedule(schedule: schedule)
      let stateStore = InMemoryAlarmStateStore()
      let system = CheckAdapter()
      let orchestrator = AlarmSyncService(scheduleService: mutableSource, store: stateStore, adapter: system)
      let orchestrationNow = Date(timeIntervalSince1970: 1)
      _ = try await orchestrator.synchronize(now: orchestrationNow)
      let createdState = await stateStore.load()
      try require(createdState.records.count == schedule.events.count && createdState.records.values.allSatisfy { PlatformAlarmIdentifier.uuid(from: $0.platformAlarmID) != nil }, "Create did not persist generated platform IDs.")
      let corrected = try scheduleChangingFirstEvent(schedule, start: "07:35", version: schedule.scheduleVersion + 1)
      await mutableSource.replace(corrected)
      let updated = try await orchestrator.synchronize(now: orchestrationNow)
      try require(updated.appliedUpdate == 1, "Time correction did not produce an update.")
      let removed = try scheduleRemovingLastEvent(corrected, version: corrected.scheduleVersion + 1)
      await mutableSource.replace(removed)
      let cancelled = try await orchestrator.synchronize(now: orchestrationNow)
      try require(cancelled.appliedCancel == 1, "Removed event did not produce a cancel.")

      let staleAlarm = NativeAlarm(stableId: "stale", kind: .procedure, title: "Stale", location: "Room", startAt: "2026-08-20T10:00:00", endAt: "2026-08-20T10:30:00", effectiveLeadTimeMinutes: 0, leaveAt: "2026-08-20T10:00:00")
      let staleStore = InMemoryAlarmStateStore(ManagedAlarmState(records: ["stale": ManagedAlarmRecord(stableId: "stale", platformAlarmID: PlatformAlarmIdentifier.newPersistedValue(), alarm: staleAlarm)]))
      let staleService = AlarmSyncService(scheduleService: StaticSchedule(schedule: schedule), store: staleStore, adapter: CheckAdapter())
      _ = try await staleService.synchronize(now: Date(timeIntervalSince1970: 1))
      let staleState = await staleStore.load()
      try require(staleState.records["stale"] == nil, "Missing system alarm left a stale mapping.")

      let deniedStore = InMemoryAlarmStateStore()
      let deniedService = AlarmSyncService(scheduleService: StaticSchedule(schedule: schedule), store: deniedStore, adapter: CheckAdapter(authorization: .denied))
      var denied = false
      do { _ = try await deniedService.synchronize(now: Date(timeIntervalSince1970: 1)) } catch { denied = true }
      let deniedState = await deniedStore.load()
      try require(denied && deniedState.records.isEmpty, "Denied authorization persisted a false success.")

      print("Swift core check passed: contract parity, future-only AlarmKit desired set, local ISO, UUID, titles, create/update/cancel, stale mapping, denied authorization, and AlarmKit usage description.")
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

  private static func scheduleChangingFirstEvent(_ schedule: Schedule, start: String, version: Int) throws -> Schedule {
    var root = try scheduleJSONObject(schedule)
    var events = root["events"] as? [[String: Any]] ?? []
    events[0]["start"] = start
    root["events"] = events
    root["scheduleVersion"] = version
    return try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: root))
  }

  private static func scheduleRemovingLastEvent(_ schedule: Schedule, version: Int) throws -> Schedule {
    var root = try scheduleJSONObject(schedule)
    var events = root["events"] as? [[String: Any]] ?? []
    _ = events.popLast()
    root["events"] = events
    root["scheduleVersion"] = version
    return try JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: root))
  }

  private static func scheduleJSONObject(_ schedule: Schedule) throws -> [String: Any] {
    guard let root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(schedule)) as? [String: Any] else {
      throw CheckError("Schedule could not be converted for the sync check.")
    }
    return root
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
  private let authorization: AlarmAuthorizationStatus
  private var activeIDs = Set<String>()

  init(authorization: AlarmAuthorizationStatus = .authorized) {
    self.authorization = authorization
  }

  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { authorization }
  func requestAuthorization() throws { if authorization != .authorized { throw AlarmAdapterError.authorizationDenied } }
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) throws -> String {
    let id = PlatformAlarmIdentifier.newPersistedValue()
    activeIDs.insert(id)
    return id
  }
  func cancel(platformAlarmID: String) throws { activeIDs.remove(platformAlarmID) }
  func existingPlatformAlarmIDs() async throws -> Set<String>? { activeIDs }
  func activeAlarmCount() -> Int { activeIDs.count }
}

private actor MutableSchedule: ScheduleServing {
  private var schedule: Schedule
  init(schedule: Schedule) { self.schedule = schedule }
  func fetchSchedule() async throws -> Schedule { schedule }
  func replace(_ value: Schedule) { schedule = value }
}

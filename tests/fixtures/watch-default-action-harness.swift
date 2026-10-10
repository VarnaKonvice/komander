// Host regression harness: compile the actual WatchCommanderModel, with only
// watchOS notification service and App Group location replaced by test doubles.
import Foundation
import LazenskyCommanderCore

actor WatchLocalNotificationService {
  private var paused = true
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var reads = 0
  init(preferences: WatchStandaloneAlarmPreferences) {}
  func authorizationStatus() async -> WatchNotificationAuthorizationState {
    reads += 1
    if paused { await withCheckedContinuation { waiters.append($0) } }
    return .authorized
  }
  func release() {
    paused = false
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
  func requestAuthorization() async throws -> WatchNotificationAuthorizationState {
    fatalError("MVP must never request standalone Watch authorization")
  }
  func reconcile(schedule: Schedule?, enabled: Bool, overrides: LeadTimeOverrides? = nil,
                 projectionRevision: Int = 0) async throws -> WatchNotificationPlan {
    precondition(!enabled, "MVP must never schedule standalone Watch alerts")
    return WatchNotificationPlan()
  }
}

enum WatchCacheLocation {
  static var dataset: CommanderScheduleDataset = .production
  static let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  static func makeCache(didStore: (@Sendable (WatchScheduleSnapshot) async -> Void)? = nil) -> FileWatchScheduleCache {
    FileWatchScheduleCache(directoryURL: directory, dataset: .production, didStore: didStore)
  }
  static func makeAcceptanceCache() -> FileWatchScheduleCache {
    FileWatchScheduleCache(directoryURL: directory.appendingPathComponent("acceptance"), dataset: .acceptance)
  }
  static func migrateLegacyCacheIfNeeded() async throws {}
}

@main struct WatchDefaultActionHarness {
  @MainActor static func main() async throws {
    let deadline = Task.detached {
      try? await Task.sleep(for: .seconds(10))
      guard !Task.isCancelled else { return }
      print("FAIL: root/cache opening blocked on notification service")
      exit(2)
    }
    defer { deadline.cancel() }
    let directory = WatchCacheLocation.directory
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "watch-default-action-tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = WatchStandaloneAlarmPreferences(defaults: defaults)
    preferences.isEnabled = true // Old preference must not re-enable MVP alerts.
    let service = WatchLocalNotificationService(preferences: preferences)
    let cache = WatchCacheLocation.makeCache()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let testDay = calendar.date(byAdding: .day, value: 1, to: Date())!
    let parts = calendar.dateComponents([.year, .month, .day], from: testDay)
    let testDate = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    func snapshot(_ version: Int, _ id: String, revision: Int = 0) -> WatchScheduleSnapshot {
      let data = try! JSONSerialization.data(withJSONObject: [
        "schemaVersion": 1, "scheduleVersion": version, "updatedAt": ISO8601DateFormatter().string(from: Date()),
        "stay": [:], "events": [["stableId": id, "date": testDate, "start": "10:00", "end": "10:20",
          "title": id, "location": "Budova 2", "kind": "procedure"]],
        "settings": ["defaultLeadTimeMinutes": 20, "procedureTypeOverrides": [:], "mealOverrides": [:]]
      ])
      let schedule = try! JSONDecoder().decode(Schedule.self, from: data)
      return .init(schedule: schedule, leadTimeOverrides: .init(defaultLeadTimeMinutes: 30), projectionRevision: revision)
    }
    let first = snapshot(1, "cached-event")
    _ = try await cache.acceptAndLoad(first)
    let cold = WatchCommanderModel(cache: cache, alarmPreferences: preferences, notificationService: service)
    await cold.bootstrap()
    precondition(cold.snapshot == first)
    precondition(!cold.standaloneAlarmsEnabled)
    print("PASS cold root loads canonical disk snapshot while notification service is blocked")
    while await service.reads == 0 { await Task.yield() }
    let current = snapshot(2, "replacement-event", revision: 3)
    _ = try await cache.acceptAndLoad(current)
    await cold.handleForeground()
    precondition(cold.snapshot == current)
    let now = try NativeAlarmContract.date(fromLocalISO: "\(testDate)T09:35:00")
    precondition(cold.currentState(at: now).event?.stableId == "replacement-event")
    precondition(cold.leadTimeOverrides == current.leadTimeOverrides)
    print("PASS warm foreground reloads current cache and captured lead time without a notification payload")
    async let bootstrap: Void = cold.bootstrap()
    let newest = snapshot(3, "newest-event", revision: 4)
    _ = try await cold.receive(newest)
    await bootstrap
    precondition(cold.snapshot == newest)
    _ = try await cold.receive(first)
    precondition(cold.snapshot == newest)
    print("PASS concurrent bootstrap/transport and stale replay retain the newest canonical snapshot")
    let restarted = WatchCommanderModel(cache: cache, alarmPreferences: preferences, notificationService: service)
    await restarted.bootstrap()
    precondition(restarted.snapshot == newest)
    print("PASS cold restart reads persisted canonical snapshot")
    let missing = FileWatchScheduleCache(directoryURL: directory.appendingPathComponent("missing"), dataset: .production)
    WatchCacheLocation.dataset = .acceptance // Disable production network recovery in this isolated host harness.
    let empty = WatchCommanderModel(cache: missing, alarmPreferences: preferences, notificationService: service)
    await empty.bootstrap()
    precondition(empty.snapshot == nil && empty.currentState(at: now).event == nil)
    WatchCacheLocation.dataset = .production
    print("PASS non-production missing cache opens root with no fabricated payload event")
    await service.release()
    print("5 Watch model runtime regressions passed")
  }
}

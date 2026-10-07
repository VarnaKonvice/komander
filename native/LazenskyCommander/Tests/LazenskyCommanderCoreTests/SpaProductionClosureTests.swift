import Foundation
import Testing
@testable import LazenskyCommanderCore

private func closureSchedule(id: String, version: Int = 1) -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-30T06:00:00Z",
    stay: ["commanderDataset": "production"], events: [
      .init(stableId: id, date: "2026-09-30", start: "10:00", end: "10:20", title: "Procedura",
        location: "Budova 2", kind: .procedure, procedureType: nil, mealType: nil, leadTimeMinutes: nil)
    ], settings: .init(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:]))
}

@Test func mislabeledPhysicalAndVisualFixturesCannotEnterProduction() throws {
  for id in ["mvpPhysical.magnet.1790707860", "visual-review.magnet", "widgetDemo.procedure"] {
    let schedule = closureSchedule(id: id, version: Int.max)
    #expect(!CommanderScheduleDataset.production.accepts(schedule))
    #expect(!CommanderScheduleDataset.acceptance.accepts(schedule))
    #expect(throws: (any Error).self) {
      try CommanderNotificationContract.desired(snapshot: .init(schedule: schedule), dataset: .production,
        channel: "production", includeDeparture: true, now: .distantPast)
    }
  }
}

@Test func physicalSnapshotAlreadyOnDiskCannotBlockLowerVersionProductionCache() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let physical = WatchScheduleSnapshot(schedule: closureSchedule(id: "mvpPhysical.magnet.1790707860", version: Int.max))
  try JSONEncoder().encode(physical).write(to: directory.appendingPathComponent(FileWatchScheduleCache.defaultFileName))
  let cache = FileWatchScheduleCache(directoryURL: directory, dataset: .production)
  #expect(try await cache.load() == nil)
  let canonical = WatchScheduleSnapshot(schedule: closureSchedule(id: "real-event"),
    leadTimeOverrides: .init(defaultLeadTimeMinutes: 30), projectionRevision: 2)
  let receipt = try await cache.acceptAndLoad(canonical)
  #expect(receipt.decision == .stored)
  #expect(receipt.snapshot == canonical)
  #expect(try await cache.acceptAndLoad(physical).decision == .rejectedInvalid)
  #expect(try await cache.load() == canonical)
}

@Test func rejectedPhysicalFixtureStillHasOwnershipForScopedAlarmCleanup() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let suite = "closure-ownership." + UUID().uuidString
  defer {
    try? FileManager.default.removeItem(at: directory)
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
  }
  let ledger = FileAlarmOwnershipStore(defaults: UserDefaults(suiteName: suite)!, directoryURL: directory,
    key: "ownership", legacyStateKey: "state", dataset: .production)
  let physical = try await ledger.reserve(stableID: "mvpPhysical.magnet.1790707860")
  let production = try await ledger.reserve(stableID: "real-event")
  let acceptance = try await ledger.reserve(stableID: PhysicalAcceptanceRun.stableIDPrefix + "other")
  #expect(try await ledger.ids() == Set([physical, production]))
  #expect(try await ledger.ids().contains(acceptance) == false)
  try await ledger.forget(physical)
  #expect(try await ledger.ids() == Set([production]))
}

@Test func genericWidgetDemoIsDateRelativeAndAlwaysIsolated() throws {
  let now = try NativeAlarmContract.date(fromLocalISO: "2027-01-05T09:00:00")
  let demo = CommanderWidgetDemoSchedule.make(now: now)
  try NativeAlarmContract.validateCanonical(demo)
  #expect(demo.events.allSatisfy { $0.date == "2027-01-05" && $0.stableId.hasPrefix("widgetDemo.") })
  #expect(demo.stay["commanderDataset"] == "widgetDemo")
  #expect(!CommanderScheduleDataset.production.accepts(demo))
  #expect(!CommanderScheduleDataset.acceptance.accepts(demo))
  #expect(!demo.events.contains { $0.stableId.hasPrefix("mvpPhysical.") })
}

@Test func normalBuildHasNoPhysicalLaunchBranchOrFixtureCompileFlags() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  func read(_ path: String) throws -> String {
    try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
  }
  let app = try read("native/LazenskyCommanderApp/LazenskyCommanderApp/LazenskyCommanderApp.swift")
  let input = app.components(separatedBy: "private struct CommanderLaunchInput")[1]
    .components(separatedBy: "private struct InjectedScheduleService")[0]
  #expect(!app.contains("COMMANDER_MVP_PHYSICAL"))
  #expect(!input.contains("CommanderWidgetDemoSchedule"))
  #expect(input.contains("#if COMMANDER_ACCEPTANCE_FIXTURES"))
  #expect(input.contains("#else\n    scheduleService = URLSessionScheduleService(configuration: configuration)"))
  let project = try read("native/LazenskyCommanderApp/LazenskyCommanderApp.xcodeproj/project.pbxproj")
  for flag in ["COMMANDER_MVP_PHYSICAL", "COMMANDER_WIDGET_DEMO", "COMMANDER_VISUAL_REVIEW", "COMMANDER_ACCEPTANCE_FIXTURES"] {
    #expect(!project.contains(flag))
  }
  let demo = try read("native/LazenskyCommander/Sources/LazenskyCommanderCore/CommanderWidgetDemoSchedule.swift")
  #expect(!demo.contains("2026-09-29"))
  #expect(!demo.contains("1790707860"))
  #expect(!demo.contains("Magnetoterapie"))
  #expect(AppConfiguration().channel == .production)
  #expect(AppConfiguration().scheduleURL.absoluteString == "https://raw.githubusercontent.com/VarnaKonvice/komander/main/data/schedule.json")
}

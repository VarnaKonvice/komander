import Foundation
import Testing
@testable import LazenskyCommanderCore

private func widgetProduction(version: Int = 13) -> WatchScheduleSnapshot {
  WatchScheduleSnapshot(schedule: Schedule(
    schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-30T08:00:00Z",
    stay: [:], events: [ScheduleEvent(stableId: "darkov-2026-10-01-masaz-1000",
      date: "2026-10-01", start: "10:00", end: "10:20", title: "Masáž", location: "RS",
      kind: .procedure, procedureType: "Masáž", mealType: nil, leadTimeMinutes: nil)],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 10, procedureTypeOverrides: [:], mealOverrides: [:])))
}

@Test func phoneWidgetProductionFirstPublishAndReadback() async throws {
  let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: container) }
  let snapshot = widgetProduction()
  let cache = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
  #expect(try await cache.load() == nil)
  let receipt = try await cache.acceptAndLoad(snapshot)
  #expect(receipt.decision == .stored)
  try receipt.verifyPublished(snapshot)
  let file = container.appendingPathComponent("CommanderPhoneWidget-production/watch-schedule-snapshot-v1.json")
  #expect(try JSONDecoder().decode(WatchScheduleSnapshot.self, from: Data(contentsOf: file)) == snapshot)
  let restarted = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
  #expect(try await restarted.load() == snapshot)
  let unchanged = try await restarted.acceptAndLoad(snapshot)
  #expect(unchanged.decision == .unchanged)
  try unchanged.verifyPublished(snapshot)
}

@Test func phoneWidgetForeignDatasetsCannotPublishAsProduction() async throws {
  let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: container) }
  let production = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
  let acceptance = try CommanderPhoneWidgetCache.require(dataset: .acceptance, containerURL: container)
  let fixture = WatchScheduleSnapshot(schedule: try CommanderAcceptanceSchedule(
    now: NativeAlarmContract.date(fromLocalISO: "2026-09-30T10:00:00"), scenario: .singleRenderer).schedule)
  try await acceptance.acceptAndLoad(fixture).verifyPublished(fixture)
  #expect(try await production.load() == nil)
  for foreign in [fixture, WatchScheduleSnapshot(schedule: CommanderWidgetDemoSchedule.make()),
                  WatchScheduleSnapshot(schedule: CommanderVisualReviewSchedule.make(now: Date()))] {
    let rejected = try await production.acceptAndLoad(foreign)
    #expect(rejected.decision == .rejectedInvalid)
    #expect(rejected.snapshot == nil)
    #expect(throws: CommanderPhoneWidgetPublishError.rejected(.rejectedInvalid)) {
      try rejected.verifyPublished(foreign)
    }
  }
  let snapshot = widgetProduction()
  try await production.acceptAndLoad(snapshot).verifyPublished(snapshot)
  #expect(try await acceptance.load() == fixture)
  #expect(try await acceptance.acceptAndLoad(snapshot).decision == .rejectedInvalid)
  #expect(try await production.load() == snapshot)
}

@Test func phoneWidgetRecoversInvalidForeignAndStaleDiskStatesWithoutDowngradingValidData() async throws {
  let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: container) }
  let directory = container.appendingPathComponent("CommanderPhoneWidget-production")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let file = directory.appendingPathComponent(FileWatchScheduleCache.defaultFileName)
  let snapshot = widgetProduction()
  let foreign = WatchScheduleSnapshot(schedule: try CommanderAcceptanceSchedule(
    now: NativeAlarmContract.date(fromLocalISO: "2026-09-30T10:00:00"), scenario: .singleRenderer).schedule)
  let invalidContract = WatchScheduleSnapshot(contractVersion: 99, schedule: snapshot.schedule)
  let states = try [Data("{truncated".utf8), JSONEncoder().encode(foreign),
    JSONEncoder().encode(WatchScheduleSnapshot(schedule: CommanderWidgetDemoSchedule.make())),
    JSONEncoder().encode(invalidContract), JSONEncoder().encode(widgetProduction(version: 12))]
  for bytes in states {
    try bytes.write(to: file)
    let cache = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
    let recovered = try await cache.acceptAndLoad(snapshot)
    #expect(recovered.decision == .stored)
    try recovered.verifyPublished(snapshot)
    #expect(try await cache.load() == snapshot)
  }
  let cache = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
  let newer = widgetProduction(version: 14)
  try await cache.acceptAndLoad(newer).verifyPublished(newer)
  let rejected = try await cache.acceptAndLoad(snapshot)
  #expect(rejected.decision == .rejectedVersion(current: 14, incoming: 13))
  #expect(rejected.snapshot == newer)
  #expect(throws: CommanderPhoneWidgetPublishError.rejected(rejected.decision)) {
    try rejected.verifyPublished(snapshot)
  }
  #expect(try await cache.load() == newer)
}

@Test func phoneWidgetMissingContainerAndMissingReadbackAreExplicitFailures() throws {
  #expect(throws: CommanderPhoneWidgetPublishError.missingAppGroup) {
    try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: nil)
  }
  for decision in [WatchScheduleCacheDecision.stored, .unchanged] {
    #expect(throws: CommanderPhoneWidgetPublishError.readbackMismatch) {
      try WatchScheduleCacheReceipt(decision: decision, snapshot: nil).verifyPublished(widgetProduction())
    }
  }
}

@Test func phoneWidgetIOFailureIsNotReportedAsPublication() async throws {
  let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: container) }
  try Data("not-a-directory".utf8).write(to: container)
  let cache = try CommanderPhoneWidgetCache.require(dataset: .production, containerURL: container)
  await #expect(throws: (any Error).self) {
    try await cache.acceptAndLoad(widgetProduction()).verifyPublished(widgetProduction())
  }
}

@Test func phoneWidgetProviderOnlyReadsSharedProductionCache() throws {
  let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let source = try String(contentsOf: repo.appendingPathComponent(
    "native/LazenskyCommanderApp/LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift"), encoding: .utf8)
  #expect(source.contains("CommanderPhoneWidgetCache.make(dataset: .production)?.load()"))
  for forbidden in ["URLSession", "fetchSchedule", "acceptAndLoad", "cache.accept(", "Data(contentsOf:", "WatchTimelinePlanner.points", "CommanderHomeWidgetPresentation.compute"] {
    #expect(!source.contains(forbidden))
  }
}

@Test func phoneWidgetTimelinePreservesCanonicalTransitionsAndPresentation() throws {
  let snapshot = widgetProduction()
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-10-01T09:00:00")
  let points = try CommanderPhoneWidgetTimeline.points(snapshot: snapshot, now: now)
  let dates = Set(points.map(\.date))
  let expected = try WatchTimelinePlanner.points(schedule: snapshot.schedule, now: now)
    .map(\.date).filter { $0 <= now.addingTimeInterval(CommanderPhoneWidgetTimeline.horizon) }
  #expect(Set(expected).isSubset(of: dates))
  for time in ["09:00:00", "09:50:00", "10:00:00", "10:20:00"] {
    let date = try NativeAlarmContract.date(fromLocalISO: "2026-10-01T" + time)
    let point = try #require(points.first { $0.date == date })
    let reference = CommanderHomeWidgetPresentation.compute(schedule: snapshot.schedule, now: date,
      overrides: snapshot.leadTimeOverrides)
    #expect(point.presentation.live == reference)
    #expect(point.presentation.remainingProcedureCount == (time < "10:20:00" ? 1 : 0))
  }
}

@Test func phoneWidgetTimelineStaysSparseWhileCoveringNextDay() throws {
  let events = (1...28).flatMap { day in
    (7...13).map { hour in
      ScheduleEvent(stableId: "darkov-\(day)-\(hour)", date: String(format: "2026-10-%02d", day),
        start: String(format: "%02d:00", hour), end: String(format: "%02d:20", hour),
        title: "Masáž", location: "RS", kind: .procedure, procedureType: "Masáž", mealType: nil, leadTimeMinutes: nil)
    }
  }
  let schedule = Schedule(schemaVersion: 1, scheduleVersion: 13, updatedAt: "2026-09-30T08:00:00Z",
    stay: [:], events: events, settings: widgetProduction().schedule.settings)
  let now = try NativeAlarmContract.date(fromLocalISO: "2026-10-01T08:00:00")
  let start = ContinuousClock.now
  let points = try CommanderPhoneWidgetTimeline.points(snapshot: .init(schedule: schedule), now: now)
  // The former full-month planner took 59 seconds for the 194-event production
  // schedule before WidgetKit could even start rendering. Leave ample CI margin.
  #expect(start.duration(to: .now) < .seconds(10))
  #expect(points.count < 80)
  #expect(!points.contains { abs($0.date.timeIntervalSince(now.addingTimeInterval(60))) < 0.5 })
  #expect(points.first?.presentation.live.event?.stableId == "darkov-1-8")
  #expect(points.first?.presentation.remainingProcedureCount == 6)
  #expect(points.allSatisfy { $0.date <= now.addingTimeInterval(CommanderPhoneWidgetTimeline.horizon) })
}

@Test func phoneWidgetPresentationRejectsExpiredSchedule() throws {
  let snapshot = widgetProduction()
  let projection = try CommanderScheduleProjection(schedule: snapshot.schedule)
  let afterExpiry = try NativeAlarmContract.date(fromLocalISO: "2026-10-02T10:20:00")
  let presentation = CommanderPhoneWidgetPresentation(projection: projection, at: afterExpiry)
  #expect(!presentation.hasSchedule)
  #expect(presentation.live.state == .noSchedule)
  #expect(presentation.remainingProcedureCount == 0)
}

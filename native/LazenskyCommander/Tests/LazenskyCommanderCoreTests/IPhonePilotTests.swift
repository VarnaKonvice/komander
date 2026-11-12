import Foundation
import Testing
@testable import LazenskyCommanderCore

private func pilotSchedule(version: Int = 2, title: String = "Koupel", date: String = "2026-10-25") -> Schedule {
  Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-10-01T00:00:00Z", stay: [:],
    events: [
      ScheduleEvent(stableId: "procedure", date: date, start: "00:10", end: "00:30", title: title,
        location: "LDB, přízemí; A", kind: .procedure, procedureType: "Koupel", mealType: nil, leadTimeMinutes: nil),
      ScheduleEvent(stableId: "meal", date: date, start: "12:00", end: "12:45", title: "Oběd",
        location: "Jídelna", kind: .meal, procedureType: nil, mealType: "Oběd", leadTimeMinutes: nil)
    ], settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:]))
}

@Test func pilotImportAcceptsCanonicalJSONAndRejectsLegacyAndInvalidBytes() throws {
  let schedule = pilotSchedule()
  #expect(try ScheduleFileImport.decode(JSONEncoder().encode(schedule)) == schedule)
  for text in ["{}", "{bad", "{\"stay\":{},\"items\":[]}"] {
    #expect(throws: (any Error).self) { try ScheduleFileImport.decode(Data(text.utf8)) }
  }
  #expect(throws: (any Error).self) {
    try ScheduleFileImport.decode(Data(repeating: 32, count: ScheduleFileImport.maximumByteCount + 1))
  }
  #expect(throws: ScheduleValidationError.self) {
    try ScheduleFileImport.decode(JSONEncoder().encode(pilotSchedule(title: "AlarmKit fyzický test")))
  }
}

@Test func pilotImportUsesCanonicalStoreAndAlarmPathWithoutNetworkOrWatch() async throws {
  let current = pilotSchedule(version: 1)
  let incoming = pilotSchedule(version: 2, title: "Nová koupel")
  let store = InMemoryScheduleSnapshotStore(current)
  let adapter = PilotAlarmAdapter()
  let service = AlarmSyncService(scheduleService: PilotOfflineSource(), store: InMemoryAlarmStateStore(), adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: PilotOfflineSource(), alarmSyncService: service,
    scheduleStore: store, dataset: .production)
  let overrides = LeadTimeOverrides(eventOverrides: ["procedure": 30])
  let result = try await coordinator.synchronize(source: .imported(incoming), overrides: overrides,
    projectionRevision: 3, now: NativeAlarmContract.date(fromLocalISO: "2026-10-24T12:00:00"))
  #expect(result.schedule == incoming)
  #expect(await store.load() == incoming)
  #expect(result.alarmSummary.succeeded)
  #expect(result.watchDeliveryStatus == .notConfigured)
  #expect(result.watchSnapshot.projectionRevision == 3)
  #expect(await adapter.alarms().first { $0.stableId == "procedure" }?.leaveAt == "2026-10-24T23:40:00")
  let replay = try await coordinator.synchronize(source: .imported(incoming), overrides: overrides,
    now: NativeAlarmContract.date(fromLocalISO: "2026-10-24T12:00:00"))
  #expect(replay.scheduleDecision == .unchanged)
  #expect(await adapter.alarms().count == incoming.events.count)
  let reopened = CommanderScheduleSyncCoordinator(scheduleService: PilotOfflineSource(), alarmSyncService: service,
    scheduleStore: store)
  let cached = try await reopened.synchronize(source: .cached, overrides: overrides,
    now: NativeAlarmContract.date(fromLocalISO: "2026-10-24T12:00:00"))
  #expect(cached.schedule == incoming && cached.watchSnapshot.leadTimeOverrides == overrides)
  let staleNetwork = CommanderScheduleSyncCoordinator(scheduleService: PilotStaticSource(schedule: current),
    alarmSyncService: service, scheduleStore: store)
  #expect(try await staleNetwork.synchronize(overrides: overrides).schedule == incoming)
}

@Test func pilotConflictingAndInvalidImportsLeaveStoreAndAlarmsUntouched() async throws {
  let current = pilotSchedule()
  let store = InMemoryScheduleSnapshotStore(current)
  let adapter = PilotAlarmAdapter()
  let service = AlarmSyncService(scheduleService: PilotOfflineSource(), store: InMemoryAlarmStateStore(), adapter: adapter)
  let coordinator = CommanderScheduleSyncCoordinator(scheduleService: PilotOfflineSource(), alarmSyncService: service,
    scheduleStore: store)
  for incoming in [pilotSchedule(version: 1), pilotSchedule(title: "Konflikt"), pilotSchedule(version: 3, date: "2026-02-30")] {
    await #expect(throws: (any Error).self) { try await coordinator.synchronize(source: .imported(incoming)) }
    #expect(await store.load() == current)
    #expect(await adapter.alarms().isEmpty)
  }
  await #expect(throws: (any Error).self) {
    try await coordinator.synchronize(source: .imported(pilotSchedule(version: 3)),
      overrides: LeadTimeOverrides(defaultLeadTimeMinutes: -1))
  }
  #expect(await store.load() == current)
}

@Test func pilotCalendarExportsAllEventsAndExactLocalDepartureAcrossMidnightAndDST() throws {
  let schedule = pilotSchedule()
  let overrides = LeadTimeOverrides(eventOverrides: ["procedure": 30])
  let stamp = try NativeAlarmContract.date(fromLocalISO: "2026-10-25T12:00:00")
  let text = try ScheduleCalendarExport.make(schedule: schedule, overrides: overrides, generatedAt: stamp)
  #expect(text.components(separatedBy: "BEGIN:VEVENT").count - 1 == schedule.events.count)
  #expect(text.contains("DTSTAMP:20261025T110000Z"))
  #expect(text.contains("DTSTART;TZID=Europe/Prague:20261025T001000"))
  #expect(text.contains("DTEND;TZID=Europe/Prague:20261025T003000"))
  #expect(text.contains("Odejít nejpozději: 2026-10-24 23:40:00"))
  #expect(text.contains("CATEGORIES:Jídla") && text.contains("CATEGORIES:Procedury"))
  #expect(text.contains("BEGIN:VTIMEZONE") && text.contains("TZID:Europe/Prague"))
  #expect(text.hasSuffix("END:VCALENDAR\r\n"))
}

@Test func pilotCalendarMarksVisitsSeparatelyFromTherapies() throws {
  let visit = ScheduleEvent(
    stableId: "visit", date: "2026-10-25", start: "07:30", end: "09:00",
    title: "Lékařská vizita", location: "Ordinace", kind: .procedure,
    procedureType: "Vizita", mealType: nil, leadTimeMinutes: 5
  )
  let base = pilotSchedule()
  let schedule = Schedule(
    schemaVersion: base.schemaVersion, scheduleVersion: base.scheduleVersion,
    updatedAt: base.updatedAt, stay: base.stay, events: base.events + [visit], settings: base.settings
  )
  let text = try ScheduleCalendarExport.make(schedule: schedule)
  #expect(text.contains("CATEGORIES:Vizity"))
  #expect(text.contains("SUMMARY:Lékařská vizita"))
}

@Test func pilotCalendarEscapesInjectionAndFoldsUTF8WithoutSplittingCharacters() throws {
  let title = String(repeating: "Žluťoučká 🛁", count: 20) + "\r\nBEGIN:VEVENT; test, \\"
  let text = try ScheduleCalendarExport.make(schedule: pilotSchedule(title: title))
  #expect(text.components(separatedBy: "\r\nBEGIN:VEVENT\r\n").count - 1 == 2)
  for line in text.components(separatedBy: "\r\n") { #expect(line.utf8.count <= 75) }
  let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
  #expect(unfolded.contains("\\nBEGIN:VEVENT\\; test\\, \\\\"))
  #expect(unfolded.contains("LOCATION:LDB\\, přízemí\\; A"))
}

@Test func pilotCalendarUIDsStayStableAcrossVersionsAndPreferenceChanges() throws {
  func uids(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n ", with: "").components(separatedBy: "\r\n").filter { $0.hasPrefix("UID:") }
  }
  let first = try ScheduleCalendarExport.make(schedule: pilotSchedule())
  let second = try ScheduleCalendarExport.make(schedule: pilotSchedule(version: 3, title: "Změněná koupel"),
    overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 40))
  #expect(uids(first) == uids(second))
}

private struct PilotOfflineSource: ScheduleServing {
  func fetchSchedule() throws -> Schedule { throw URLError(.notConnectedToInternet) }
}
private struct PilotStaticSource: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() -> Schedule { schedule }
}
private actor PilotAlarmAdapter: AlarmAdapting {
  private var stored: [String: NativeAlarm] = [:]
  func availability() -> AlarmKitAvailability { .available }
  func authorizationStatus() -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() {}
  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) -> String {
    let id = platformAlarmID ?? UUID().uuidString
    stored[id] = alarm
    return id
  }
  func cancel(platformAlarmID: String) { stored.removeValue(forKey: platformAlarmID) }
  func existingPlatformAlarmIDs() -> Set<String>? { Set(stored.keys) }
  func existingPlatformFixedAlertDates() throws -> [String: Date]? {
    try stored.mapValues { try NativeAlarmContract.date(fromLocalISO: $0.leaveAt) }
  }
  func alarms() -> [NativeAlarm] { Array(stored.values) }
}

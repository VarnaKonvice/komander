import Foundation
import Testing
@testable import LazenskyCommanderCore

@Suite("CommanderProcedureContinuity")
struct CommanderProcedureContinuityTests {
  @Test func suppressesOnlyImmediateConfiguredContinuationInsideGap() throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 20)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "VÍŘIVÁ KOUPEL"),
      event("b", start: "09:30", end: "09:50", type: "Jódobrom")
    ])

    let matches = try CommanderProcedureContinuity.matches(schedule: schedule, profile: profile)

    #expect(matches.count == 1)
    #expect(matches.first?.precedingStableID == "a")
    #expect(matches.first?.continuingStableID == "b")
    #expect(matches.first?.gapMinutes == 10)
    #expect(try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule, profile: profile
    ) == ["b"])
  }

  @Test func samePairHoursApartIsNotContinuation() throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 20)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka"),
      event("b", start: "14:00", end: "14:20", type: "Jodobrom")
    ])

    #expect(try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule, profile: profile
    ).isEmpty)
  }

  @Test func unrelatedProcedureBetweenConfiguredPairBreaksContinuation() throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 30)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka"),
      event("x", start: "09:25", end: "09:35", type: "Masáž"),
      event("b", start: "09:40", end: "10:00", type: "Jodobrom")
    ])

    #expect(try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule, profile: profile
    ).isEmpty)
  }

  @Test func threeProcedureChainSuppressesSecondAndThirdAlerts() throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 15),
      .init(fromCanonicalType: "jodobrom", toCanonicalType: "bazen", maximumGapMinutes: 15)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka"),
      event("b", start: "09:25", end: "09:45", type: "Jodobrom"),
      event("c", start: "09:50", end: "10:20", type: "Bazén")
    ])

    #expect(try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule, profile: profile
    ) == ["b", "c"])
  }

  @Test func sameLocationRuleRejectsDifferentRooms() throws {
    let profile = try makeProfile(rules: [
      .init(
        fromCanonicalType: "virivka",
        toCanonicalType: "jodobrom",
        maximumGapMinutes: 20,
        requiresSameLocation: true
      )
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka", location: "Vodoléčba A"),
      event("b", start: "09:25", end: "09:45", type: "Jodobrom", location: "Vodoléčba B")
    ])

    #expect(try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule, profile: profile
    ).isEmpty)
  }

  @Test func notificationProjectionOmitsBothStartAndDepartureForContinuation() throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 20)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka"),
      event("b", start: "09:30", end: "09:50", type: "Jodobrom")
    ])
    let excluded = try CommanderProcedureContinuity.suppressedAlertStableIDs(
      schedule: schedule,
      profile: profile
    )
    let now = try NativeAlarmContract.dateTime(date: "2026-10-31", time: "08:00")
    let notifications = try CommanderNotificationContract.desired(
      snapshot: WatchScheduleSnapshot(schedule: schedule),
      dataset: .production,
      channel: "production",
      includeDeparture: true,
      now: now,
      limit: 60,
      alertExclusions: excluded
    )

    #expect(notifications.count == 2)
    #expect(notifications.allSatisfy { $0.payload["stableId"] == "a" })
    #expect(Set(notifications.compactMap { $0.payload["kind"] }) == ["start", "leave"])
  }

  @Test func profileSyncCancelsContinuationAlarmWithoutChangingSchedule() async throws {
    let profile = try makeProfile(rules: [
      .init(fromCanonicalType: "virivka", toCanonicalType: "jodobrom", maximumGapMinutes: 20)
    ])
    let schedule = makeSchedule(events: [
      event("a", start: "09:00", end: "09:20", type: "Vířivka"),
      event("b", start: "09:30", end: "09:50", type: "Jodobrom")
    ])
    let source = ContinuityScheduleService(schedule: schedule)
    let store = InMemoryAlarmStateStore()
    let adapter = ContinuityAlarmAdapter()
    let alarmSync = AlarmSyncService(scheduleService: source, store: store, adapter: adapter)
    let scheduleStore = InMemoryScheduleSnapshotStore()
    let now = try NativeAlarmContract.dateTime(date: "2026-10-31", time: "08:00")

    let ordinary = CommanderScheduleSyncCoordinator(
      scheduleService: source,
      alarmSyncService: alarmSync,
      scheduleStore: scheduleStore
    )
    let first = try await ordinary.synchronize(now: now)
    #expect(first.alarmSummary.desiredAlarmCount == 2)
    #expect(first.suppressedAlertStableIDs.isEmpty)

    let profiled = CommanderScheduleSyncCoordinator(
      scheduleService: source,
      alarmSyncService: alarmSync,
      scheduleStore: scheduleStore,
      spaProfile: profile
    )
    let second = try await profiled.synchronize(source: .cached, now: now)

    #expect(second.schedule == schedule)
    #expect(second.watchSnapshot.schedule == schedule)
    #expect(second.suppressedAlertStableIDs == ["b"])
    #expect(second.alarmSummary.desiredAlarmCount == 1)
    #expect(second.alarmSummary.plan.cancel.map(\.stableId) == ["b"])
    #expect(Set((await store.load()).records.keys) == ["a"])
  }

  @Test func openWindowMealSchedulesAlarmAtOpeningWithoutChangingCanonicalSchedule() async throws {
    let schedule = makeSchedule(events: [
      ScheduleEvent(
        stableId: "breakfast",
        date: "2026-10-31",
        start: "07:00",
        end: "09:00",
        title: "Snídaně",
        location: "Jídelna",
        kind: .meal,
        procedureType: nil,
        mealType: "Snídaně",
        leadTimeMinutes: nil
      )
    ])
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "selfpayer",
      displayName: "Samoplátce",
      procedures: [],
      mealShifts: [
        CommanderSpaMealShift(
          id: "selfpayer",
          displayName: "Volný režim",
          meals: [
            CommanderSpaMealTemplate(
              mealType: "Snídaně",
              start: "07:00",
              end: "09:00",
              timingMode: .openWindow
            )
          ]
        )
      ]
    )
    try profile.validate()

    let source = ContinuityScheduleService(schedule: schedule)
    let alarmStore = InMemoryAlarmStateStore()
    let adapter = ContinuityAlarmAdapter()
    let coordinator = CommanderScheduleSyncCoordinator(
      scheduleService: source,
      alarmSyncService: AlarmSyncService(
        scheduleService: source,
        store: alarmStore,
        adapter: adapter
      ),
      scheduleStore: InMemoryScheduleSnapshotStore(),
      spaProfile: profile
    )
    let now = try NativeAlarmContract.dateTime(date: "2026-10-31", time: "06:30")
    let result = try await coordinator.synchronize(now: now)

    #expect(result.schedule == schedule)
    #expect(result.alarmSummary.desiredAlarmCount == 1)
    let record = try #require((await alarmStore.load()).records["breakfast"])
    #expect(record.alarm.effectiveLeadTimeMinutes == 0)
    #expect(record.alarm.leaveAt.hasSuffix("T07:00:00"))
  }

  @Test func oldProfileJSONWithoutContinuationRulesStillDecodes() throws {
    let json = """
    {
      "schemaVersion": 1,
      "profileVersion": 1,
      "spaID": "legacy",
      "displayName": "Legacy",
      "timeZoneIdentifier": "Europe/Prague",
      "procedures": [],
      "mealShifts": []
    }
    """.data(using: .utf8)!

    let profile = try JSONDecoder().decode(CommanderSpaProfile.self, from: json)
    #expect(profile.continuationRules.isEmpty)
    try profile.validate()
  }

  @Test func continuationRuleMustReferenceKnownProcedureAndBoundedGap() throws {
    let unknown = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "a", displayName: "A", category: .other)
      ],
      continuationRules: [
        .init(fromCanonicalType: "a", toCanonicalType: "missing", maximumGapMinutes: 20)
      ]
    )
    #expect(throws: CommanderSpaProfileValidationError.unknownContinuationProcedure("missing")) {
      try unknown.validate()
    }

    let invalidGap = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "a", displayName: "A", category: .other),
        .init(canonicalType: "b", displayName: "B", category: .other)
      ],
      continuationRules: [
        .init(fromCanonicalType: "a", toCanonicalType: "b", maximumGapMinutes: 181)
      ]
    )
    #expect(throws: CommanderSpaProfileValidationError.invalidContinuationGap("a->b")) {
      try invalidGap.validate()
    }
  }

  private func makeProfile(
    rules: [CommanderSpaContinuationRule]
  ) throws -> CommanderSpaProfile {
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "virivka", displayName: "Vířivka", aliases: ["VÍŘIVÁ KOUPEL"], category: .water),
        .init(canonicalType: "jodobrom", displayName: "Jodobrom", aliases: ["Jódobrom"], category: .heatWrap),
        .init(canonicalType: "bazen", displayName: "Bazén", category: .water),
        .init(canonicalType: "masaz", displayName: "Masáž", category: .massage)
      ],
      continuationRules: rules
    )
    try profile.validate()
    return profile
  }

  private func makeSchedule(events: [ScheduleEvent]) -> Schedule {
    Schedule(
      schemaVersion: 1,
      scheduleVersion: 1,
      updatedAt: "2026-10-31T12:00:00+01:00",
      stay: ["spa": "Test", "dateFrom": "2026-10-31", "dateTo": "2026-11-01"],
      events: events,
      settings: ScheduleSettings(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: [:],
        mealOverrides: [:]
      )
    )
  }

  private func event(
    _ id: String,
    start: String,
    end: String,
    type: String,
    location: String = "Vodoléčba"
  ) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id,
      date: "2026-10-31",
      start: start,
      end: end,
      title: type,
      location: location,
      kind: .procedure,
      procedureType: type,
      mealType: nil,
      leadTimeMinutes: nil
    )
  }
}


private struct ContinuityScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor ContinuityAlarmAdapter: AlarmAdapting {
  private var identifiers: Set<String> = []

  func availability() async -> AlarmKitAvailability { .available }
  func authorizationStatus() async -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() async throws {}

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String {
    if let platformAlarmID { identifiers.remove(platformAlarmID) }
    let id = "continuity." + alarm.stableId
    identifiers.insert(id)
    return id
  }

  func cancel(platformAlarmID: String) async throws {
    identifiers.remove(platformAlarmID)
  }

  func existingPlatformAlarmIDs() async throws -> Set<String>? { nil }
}

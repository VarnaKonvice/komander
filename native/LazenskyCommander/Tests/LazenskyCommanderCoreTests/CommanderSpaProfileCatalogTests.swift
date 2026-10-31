import Foundation
import Testing
@testable import LazenskyCommanderCore

@Suite("CommanderSpaProfileCatalog")
struct CommanderSpaProfileCatalogTests {
  @Test func missingSpaIDUsesGenericMode() throws {
    let catalog = try CommanderSpaProfileCatalog(profiles: [partnerProfile()])
    let schedule = schedule(stay: ["spa": "Lázně bez ID"])

    #expect(catalog.resolve(schedule: schedule) == .genericMissingSpaID)
  }

  @Test func unknownSpaIDUsesGenericMode() throws {
    let catalog = try CommanderSpaProfileCatalog(profiles: [partnerProfile()])
    let schedule = schedule(stay: ["spaID": "unknown-spa"])

    #expect(catalog.resolve(schedule: schedule) == .genericUnknownSpaID("unknown-spa"))
  }

  @Test func knownSpaIDResolvesCaseInsensitively() throws {
    let profile = partnerProfile()
    let catalog = try CommanderSpaProfileCatalog(profiles: [profile])
    let schedule = schedule(stay: ["spaID": "  PARTNER-1  "])

    #expect(catalog.resolve(schedule: schedule) == .matched(profile))
  }

  @Test func duplicateSpaIDsAreRejected() {
    let first = partnerProfile()
    let second = CommanderSpaProfile(
      profileVersion: 2,
      spaID: "PARTNER-1",
      displayName: "Jiný profil",
      procedures: []
    )

    #expect(throws: CommanderSpaProfileCatalogError.duplicateSpaID("PARTNER-1")) {
      _ = try CommanderSpaProfileCatalog(profiles: [first, second])
    }
  }

  @Test func coordinatorAppliesCatalogProfileOnlyWhenSpaIDMatches() async throws {
    let profile = partnerProfile()
    let catalog = try CommanderSpaProfileCatalog(profiles: [profile])
    let matchedSchedule = schedule(
      stay: ["spaID": "partner-1"],
      events: [
        procedure("a", start: "09:00", end: "09:20", type: "Vířivka"),
        procedure("b", start: "09:30", end: "09:50", type: "Jodobrom")
      ]
    )

    let matched = try await synchronize(schedule: matchedSchedule, catalog: catalog)
    #expect(matched.spaProfileResolution == .matched(profile))
    #expect(matched.suppressedAlertStableIDs == ["b"])
    #expect(matched.alarmSummary.desiredAlarmCount == 1)

    let unknownSchedule = schedule(
      stay: ["spaID": "other-spa"],
      events: matchedSchedule.events
    )
    let generic = try await synchronize(schedule: unknownSchedule, catalog: catalog)
    #expect(generic.spaProfileResolution == .genericUnknownSpaID("other-spa"))
    #expect(generic.suppressedAlertStableIDs.isEmpty)
    #expect(generic.alarmSummary.desiredAlarmCount == 2)
  }

  @Test func profileAuditRulesStayAttachedToResolvedProfile() throws {
    let profile = partnerProfile()
    let catalog = try CommanderSpaProfileCatalog(profiles: [profile])
    let resolved = catalog.resolve(schedule: schedule(stay: ["spaID": "partner-1"]))

    #expect(resolved.profile?.scheduleAuditRules?.auditPolicy == .petrSpaOperational)
    #expect(CommanderSpaProfileCatalog.empty.resolve(
      schedule: schedule(stay: ["spaID": "partner-1"])
    ) == .genericUnknownSpaID("partner-1"))
  }

  private func partnerProfile() -> CommanderSpaProfile {
    CommanderSpaProfile(
      profileVersion: 1,
      spaID: "partner-1",
      displayName: "Partnerské lázně",
      procedures: [
        .init(canonicalType: "virivka", displayName: "Vířivka", category: .water),
        .init(canonicalType: "jodobrom", displayName: "Jodobrom", category: .heatWrap)
      ],
      continuationRules: [
        .init(
          fromCanonicalType: "virivka",
          toCanonicalType: "jodobrom",
          maximumGapMinutes: 20
        )
      ],
      scheduleAuditRules: .init(
        minimumProceduresMondayThroughSaturday: 3,
        sundayExpectedProcedureCount: 0,
        sundayExpectedMealTypes: ["Snídaně", "Oběd", "Večeře"]
      )
    )
  }

  private func schedule(
    stay: [String: String],
    events: [ScheduleEvent] = []
  ) -> Schedule {
    Schedule(
      schemaVersion: 1,
      scheduleVersion: 1,
      updatedAt: "2026-10-31T12:00:00+01:00",
      stay: stay,
      events: events,
      settings: .init(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: [:],
        mealOverrides: [:]
      )
    )
  }

  private func procedure(
    _ id: String,
    start: String,
    end: String,
    type: String
  ) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id,
      date: "2026-10-31",
      start: start,
      end: end,
      title: type,
      location: "Vodoléčba",
      kind: .procedure,
      procedureType: type,
      mealType: nil,
      leadTimeMinutes: nil
    )
  }

  private func synchronize(
    schedule: Schedule,
    catalog: CommanderSpaProfileCatalog
  ) async throws -> CommanderScheduleSyncResult {
    let source = CatalogScheduleService(schedule: schedule)
    return try await CommanderScheduleSyncCoordinator(
      scheduleService: source,
      alarmSyncService: AlarmSyncService(
        scheduleService: source,
        store: InMemoryAlarmStateStore(),
        adapter: CatalogAlarmAdapter()
      ),
      scheduleStore: InMemoryScheduleSnapshotStore(),
      spaProfileCatalog: catalog
    ).synchronize(
      now: try NativeAlarmContract.dateTime(date: "2026-10-31", time: "08:00")
    )
  }
}

private struct CatalogScheduleService: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

private actor CatalogAlarmAdapter: AlarmAdapting {
  private var identifiers: Set<String> = []

  func availability() async -> AlarmKitAvailability { .available }
  func authorizationStatus() async -> AlarmAuthorizationStatus { .authorized }
  func requestAuthorization() async throws {}

  func schedule(_ alarm: NativeAlarm, replacing platformAlarmID: String?) async throws -> String {
    if let platformAlarmID { identifiers.remove(platformAlarmID) }
    let id = "catalog." + alarm.stableId
    identifiers.insert(id)
    return id
  }

  func cancel(platformAlarmID: String) async throws {
    identifiers.remove(platformAlarmID)
  }

  func existingPlatformAlarmIDs() async throws -> Set<String>? { nil }
}

import Foundation
import Testing
@testable import LazenskyCommanderCore

@Suite("CommanderSpaProfile")
struct CommanderSpaProfileTests {
  @Test func resolvesProcedureByCanonicalNameDisplayNameAndAlias() throws {
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "darkov",
      displayName: "Lázně Darkov",
      procedures: [
        CommanderSpaProcedureDefinition(
          canonicalType: "viriva-koupel-hkk",
          displayName: "Vířivá koupel HKK",
          aliases: ["VÍŘ.HKK", "Viriva HKK"],
          category: .water,
          expectedDurationMinutes: 20,
          defaultLeadTimeMinutes: 20
        )
      ]
    )

    try profile.validate()

    #expect(profile.procedureDefinition(matching: "viriva koupel hkk")?.canonicalType == "viriva-koupel-hkk")
    #expect(profile.procedureDefinition(matching: "VÍŘ.HKK")?.canonicalType == "viriva-koupel-hkk")
    #expect(profile.procedureDefinition(matching: "Vířivá koupel HKK")?.category == .water)
  }

  @Test func duplicateAliasAcrossProceduresIsRejected() {
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "a", displayName: "Procedura A", aliases: ["MAG"], category: .electro),
        .init(canonicalType: "b", displayName: "Procedura B", aliases: ["mag"], category: .rehabilitation)
      ]
    )

    #expect(throws: CommanderSpaProfileValidationError.duplicateProcedureAlias("mag")) {
      try profile.validate()
    }
  }

  @Test func mealShiftValidationAcceptsOrdinarySpaTimes() throws {
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "darkov",
      displayName: "Lázně Darkov",
      procedures: [],
      mealShifts: [
        CommanderSpaMealShift(
          id: "first",
          displayName: "I. směna",
          meals: [
            .init(mealType: "Snídaně", start: "06:45", end: "07:00"),
            .init(mealType: "Oběd", start: "11:00", end: "11:15"),
            .init(mealType: "Večeře", start: "16:45", end: "17:00")
          ]
        )
      ]
    )

    try profile.validate()
    #expect(profile.mealShifts.first?.meals.count == 3)
  }

  @Test func spaProfileCanCarryOperationalAuditRules() throws {
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "darkov",
      displayName: "Lázně Darkov",
      procedures: [],
      scheduleAuditRules: CommanderSpaScheduleAuditRules(
        minimumProceduresMondayThroughSaturday: 3,
        sundayExpectedProcedureCount: 0,
        sundayExpectedMealTypes: ["Snídaně", "Oběd", "Večeře"]
      )
    )

    try profile.validate()
    let policy = try #require(profile.scheduleAuditRules?.auditPolicy)
    #expect(policy == .petrSpaOperational)
  }

  @Test func invalidSpaAuditRulesAreRejected() {
    let invalidCount = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [],
      scheduleAuditRules: .init(minimumProceduresMondayThroughSaturday: 101)
    )
    #expect(throws: CommanderSpaProfileValidationError.invalidAuditProcedureCount(
      "minimumProceduresMondayThroughSaturday"
    )) {
      try invalidCount.validate()
    }

    let duplicateMeal = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [],
      scheduleAuditRules: .init(
        sundayExpectedMealTypes: ["Snídaně", "snidane"]
      )
    )
    #expect(throws: CommanderSpaProfileValidationError.duplicateAuditMealType("snidane")) {
      try duplicateMeal.validate()
    }
  }

  @Test func openWindowMealDefaultsToAlarmAtWindowOpening() throws {
    let meal = CommanderSpaMealTemplate(
      mealType: "Snídaně",
      start: "07:00",
      end: "09:00",
      timingMode: .openWindow
    )
    #expect(meal.effectiveOpeningAlarmLeadTimeMinutes == 0)

    let encoded = try JSONEncoder().encode(meal)
    let decoded = try JSONDecoder().decode(CommanderSpaMealTemplate.self, from: encoded)
    #expect(decoded == meal)
  }

  @Test func legacyMealTemplateDecodesAsFixedSlot() throws {
    let json = """
    {
      "mealType": "Snídaně",
      "start": "07:30",
      "end": "08:00"
    }
    """.data(using: .utf8)!
    let meal = try JSONDecoder().decode(CommanderSpaMealTemplate.self, from: json)
    #expect(meal.timingMode == .fixedSlot)
    #expect(meal.effectiveOpeningAlarmLeadTimeMinutes == nil)
  }

  @Test func openWindowCanUseExplicitOpeningLeadTime() throws {
    let meal = CommanderSpaMealTemplate(
      mealType: "Oběd",
      start: "11:30",
      end: "13:30",
      timingMode: .openWindow,
      openingAlarmLeadTimeMinutes: 10
    )
    #expect(meal.effectiveOpeningAlarmLeadTimeMinutes == 10)
  }

  @Test func invalidProcedureDurationAndLeadTimeAreRejected() {
    let tooLong = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "x", displayName: "X", category: .other, expectedDurationMinutes: 0)
      ]
    )
    #expect(throws: CommanderSpaProfileValidationError.invalidProcedureDuration("x")) {
      try tooLong.validate()
    }

    let invalidLead = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "test",
      displayName: "Test",
      procedures: [
        .init(canonicalType: "x", displayName: "X", category: .other, defaultLeadTimeMinutes: 181)
      ]
    )
    #expect(throws: CommanderSpaProfileValidationError.invalidLeadTime("x")) {
      try invalidLead.validate()
    }
  }

  @Test func spaProfileNeverChangesCanonicalPatientTimes() throws {
    let event = ScheduleEvent(
      stableId: "stay-1-motomed",
      date: "2026-10-23",
      start: "08:15",
      end: "08:35",
      title: "Motomed",
      location: "FYZ48",
      kind: .procedure,
      procedureType: "Motomed",
      mealType: nil,
      leadTimeMinutes: nil
    )
    let profile = CommanderSpaProfile(
      profileVersion: 1,
      spaID: "darkov",
      displayName: "Lázně Darkov",
      procedures: [
        .init(
          canonicalType: "motomed",
          displayName: "Motomed",
          category: .rehabilitation,
          expectedDurationMinutes: 20,
          defaultLeadTimeMinutes: 25
        )
      ]
    )

    try profile.validate()
    let matched = try #require(profile.procedureDefinition(matching: event.procedureType ?? event.title))
    #expect(matched.expectedDurationMinutes == 20)
    #expect(event.start == "08:15")
    #expect(event.end == "08:35")
  }
}

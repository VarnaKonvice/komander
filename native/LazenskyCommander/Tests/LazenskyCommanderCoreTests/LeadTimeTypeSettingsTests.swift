#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func procedureTypeLeadTimeIgnoresIndividualEventOverrides() throws {
  let schedule = settingsLeadTimeSchedule()
  let overrides = LeadTimeOverrides(eventOverrides: ["procedure-a": 3])

  #expect(try NativeAlarmContract.typeLeadTime(kind: .procedure, type: "Koupel", schedule: schedule, overrides: overrides) == 25)
  #expect(try NativeAlarmContract.resolvedTypeLeadTime(kind: .procedure, type: "Koupel", schedule: schedule, overrides: overrides).source == .scheduleTypeOverride)
  #expect(try NativeAlarmContract.resolvedLeadTime(event: schedule.events[0], schedule: schedule, overrides: overrides).source == .localEventOverride)
}

@Test func mealTypeLeadTimeIgnoresIndividualEventOverrides() throws {
  let schedule = settingsLeadTimeSchedule()
  let overrides = LeadTimeOverrides(eventOverrides: ["meal-a": 4])

  #expect(try NativeAlarmContract.typeLeadTime(kind: .meal, type: "Snídaně", schedule: schedule, overrides: overrides) == 15)
  #expect(try NativeAlarmContract.resolvedTypeLeadTime(kind: .meal, type: "Snídaně", schedule: schedule, overrides: overrides).source == .scheduleTypeOverride)
  #expect(try NativeAlarmContract.resolvedLeadTime(event: schedule.events[2], schedule: schedule, overrides: overrides).source == .localEventOverride)
}

@Test func changingTypeLeadTimePreservesEventOverridePriority() throws {
  let schedule = settingsLeadTimeSchedule()
  var overrides = LeadTimeOverrides(eventOverrides: ["procedure-a": 3])
  overrides.procedureTypeOverrides["Koupel"] = 30

  #expect(overrides.eventOverrides["procedure-a"] == 3)
  #expect(try NativeAlarmContract.typeLeadTime(kind: .procedure, type: "Koupel", schedule: schedule, overrides: overrides) == 30)
  #expect(try NativeAlarmContract.resolvedLeadTime(event: schedule.events[0], schedule: schedule, overrides: overrides) == ResolvedLeadTime(minutes: 3, source: .localEventOverride))
  #expect(try NativeAlarmContract.resolvedLeadTime(event: schedule.events[1], schedule: schedule, overrides: overrides) == ResolvedLeadTime(minutes: 30, source: .localTypeOverride))
}

@Test func typeLeadTimeFallsBackToCanonicalDefaultWithoutTypeOverride() throws {
  let schedule = Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "procedure-a",
        date: "2026-08-20",
        start: "09:00",
        end: "09:30",
        title: "Koupel",
        location: "Balneo",
        kind: .procedure,
        procedureType: "Koupel",
        mealType: nil,
        leadTimeMinutes: 5
      )
    ],
    settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
  )
  let overrides = LeadTimeOverrides(eventOverrides: ["procedure-a": 3])

  #expect(try NativeAlarmContract.resolvedTypeLeadTime(kind: .procedure, type: "Koupel", schedule: schedule, overrides: overrides) == ResolvedLeadTime(minutes: 20, source: .scheduleDefault))
  #expect(try NativeAlarmContract.resolvedTypeLeadTime(kind: .procedure, type: "Koupel", schedule: schedule, overrides: LeadTimeOverrides(defaultLeadTimeMinutes: 12)) == ResolvedLeadTime(minutes: 12, source: .localDefault))
}

@Test func settingsViewUsesTypeLeadTimeForGeneralRows() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = root.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp")
  let settings = try String(contentsOf: app.appendingPathComponent("CommanderSettingsView.swift"), encoding: .utf8)
  #expect(settings.contains("NativeAlarmContract.typeLeadTime("))
  #expect(!settings.contains("return model.effectiveLeadTimeMinutes(for: event)"))
}

private func settingsLeadTimeSchedule() -> Schedule {
  Schedule(
    schemaVersion: 1,
    scheduleVersion: 1,
    updatedAt: "2026-08-20T00:00:00Z",
    stay: [:],
    events: [
      ScheduleEvent(
        stableId: "procedure-a",
        date: "2026-08-20",
        start: "09:00",
        end: "09:30",
        title: "Koupel A",
        location: "Balneo",
        kind: .procedure,
        procedureType: "Koupel",
        mealType: nil,
        leadTimeMinutes: 5
      ),
      ScheduleEvent(
        stableId: "procedure-b",
        date: "2026-08-20",
        start: "10:00",
        end: "10:30",
        title: "Koupel B",
        location: "Balneo",
        kind: .procedure,
        procedureType: "Koupel",
        mealType: nil,
        leadTimeMinutes: nil
      ),
      ScheduleEvent(
        stableId: "meal-a",
        date: "2026-08-20",
        start: "07:30",
        end: "08:00",
        title: "Snídaně",
        location: "Jídelna",
        kind: .meal,
        procedureType: nil,
        mealType: "Snídaně",
        leadTimeMinutes: 6
      ),
      ScheduleEvent(
        stableId: "meal-b",
        date: "2026-08-21",
        start: "07:30",
        end: "08:00",
        title: "Snídaně",
        location: "Jídelna",
        kind: .meal,
        procedureType: nil,
        mealType: "Snídaně",
        leadTimeMinutes: nil
      )
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 20,
      procedureTypeOverrides: ["Koupel": 25],
      mealOverrides: ["Snídaně": 15]
    )
  )
}
#endif

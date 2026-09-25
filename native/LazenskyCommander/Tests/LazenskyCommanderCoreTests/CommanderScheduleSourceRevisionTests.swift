import Testing
@testable import LazenskyCommanderCore

struct CommanderScheduleSourceRevisionTests {
  @Test func exactSourceRevisionReconcilesOneToOne() {
    let event = procedure(id: "canonical.a", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž", location: "Rehabilitace")
    let revision = CommanderScheduleSourceRevision(
      revisionId: "paper-1",
      capturedAt: "2026-09-01T08:00:00Z",
      coverageFrom: "2026-09-02",
      coverageTo: "2026-09-02",
      reason: .initial,
      sourceAssetHashes: ["sha256:paper1"],
      rows: [row(id: "p1-r1", from: event)]
    )
    let report = CommanderScheduleSourceReconciler.reconcile(revision: revision, canonical: schedule(events: [event]))
    #expect(report.isExact)
    #expect(report.matchedCount == 1)
  }

  @Test func changedTimeOrLocationCannotSilentlyPass() {
    let event = procedure(id: "canonical.a", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž", location: "Rehabilitace")
    let changed = CommanderScheduleSourceRow(
      sourceRowId: "p2-r1",
      date: "2026-09-02",
      start: "09:00",
      end: "09:40",
      title: "Masáž",
      location: "Balneo",
      kind: .procedure,
      procedureType: "Masáž"
    )
    let revision = CommanderScheduleSourceRevision(
      revisionId: "paper-2",
      capturedAt: "2026-09-02T12:00:00Z",
      coverageFrom: "2026-09-02",
      coverageTo: "2026-09-02",
      reason: .clinicianRequestedChange,
      rows: [changed]
    )
    let report = CommanderScheduleSourceReconciler.reconcile(revision: revision, canonical: schedule(events: [event]))
    #expect(!report.isExact)
    #expect(report.mismatches.count == 1)
    #expect(report.mismatches[0].differingFields == ["end", "location"])
  }

  @Test func reconciliationReportsBothMissingAndExtraRows() {
    let event = procedure(id: "canonical.a", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž", location: "Rehabilitace")
    let unrelated = CommanderScheduleSourceRow(
      sourceRowId: "paper-extra",
      date: "2026-09-03",
      start: "10:00",
      end: "10:20",
      title: "Magnetoterapie",
      location: "Elektroléčba",
      kind: .procedure,
      procedureType: "Magnetoterapie"
    )
    let revision = CommanderScheduleSourceRevision(
      revisionId: "paper-3",
      capturedAt: "2026-09-02T12:00:00Z",
      coverageFrom: "2026-09-02",
      coverageTo: "2026-09-03",
      reason: .replacementSheet,
      rows: [unrelated]
    )
    let report = CommanderScheduleSourceReconciler.reconcile(revision: revision, canonical: schedule(events: [event]))
    #expect(report.missingSourceRows == ["paper-extra"])
    #expect(report.extraCanonicalStableIds == ["canonical.a"])
  }


  @Test func applyingRevisionReplacesOnlyDeclaredCoverage() throws {
    let day2 = procedure(id: "old.day2", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž", location: "Rehabilitace")
    let day3 = procedure(id: "keep.day3", date: "2026-09-03", start: "10:00", end: "10:20", title: "Magnetoterapie", location: "Elektroléčba")
    let changed = CommanderScheduleSourceRow(
      sourceRowId: "change-1", date: "2026-09-02", start: "11:00", end: "11:30",
      title: "Ergoterapie", location: "Rehabilitace", kind: .procedure, procedureType: "Ergoterapie"
    )
    let revision = CommanderScheduleSourceRevision(
      revisionId: "doctor-change", capturedAt: "2026-09-02T08:00:00Z",
      coverageFrom: "2026-09-02", coverageTo: "2026-09-02", reason: .clinicianRequestedChange, rows: [changed]
    )

    let result = try CommanderScheduleRevisionApplier.applying(
      revision, to: schedule(events: [day2, day3]), newScheduleVersion: 2, updatedAt: "2026-09-02T08:01:00Z"
    )
    #expect(result.events.count == 2)
    #expect(!result.events.contains { $0.stableId == "old.day2" })
    #expect(result.events.contains { $0.stableId == "keep.day3" })
    #expect(result.events.contains { $0.title == "Ergoterapie" && $0.date == "2026-09-02" })
  }

  @Test func unchangedSourceRowPreservesStableIdAcrossRevision() throws {
    let event = procedure(id: "keep.me", date: "2026-09-02", start: "09:00", end: "09:30", title: "Masáž", location: "Rehabilitace")
    let revision = CommanderScheduleSourceRevision(
      revisionId: "replacement", capturedAt: "2026-09-02T08:00:00Z", coverageFrom: "2026-09-02", coverageTo: "2026-09-02",
      reason: .replacementSheet, rows: [row(id: "same-row", from: event)]
    )
    let result = try CommanderScheduleRevisionApplier.applying(
      revision, to: schedule(events: [event]), newScheduleVersion: 2, updatedAt: "2026-09-02T08:01:00Z"
    )
    #expect(result.events.count == 1)
    #expect(result.events[0].stableId == "keep.me")
  }

  @Test func stayExtensionCanExpandTwentyEightDaysToThirtyFiveWithoutAppendingOverOldWindow() throws {
    let base = Schedule(
      schemaVersion: 1, scheduleVersion: 1, updatedAt: "2026-09-01T08:00:00Z",
      stay: ["dateFrom": "2026-09-01", "dateTo": "2026-09-28"],
      events: [], settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
    )
    let extensionRow = CommanderScheduleSourceRow(
      sourceRowId: "extension-1", date: "2026-10-05", start: "07:30", end: "08:00", title: "Snídaně",
      location: "Jídelna", kind: .meal, mealType: "Snídaně"
    )
    let revision = CommanderScheduleSourceRevision(
      revisionId: "extension-week", capturedAt: "2026-09-28T12:00:00Z", coverageFrom: "2026-09-29", coverageTo: "2026-10-05",
      reason: .stayExtension, rows: [extensionRow]
    )
    let result = try CommanderScheduleRevisionApplier.applying(
      revision, to: base, newScheduleVersion: 2, updatedAt: "2026-09-28T12:01:00Z", extendedStayTo: "2026-10-05"
    )
    #expect(result.stay["dateTo"] == "2026-10-05")
    #expect(CommanderScheduleAudit.run(result).stayDayCount == 35)
    #expect(result.events.count == 1)
  }

  private func row(id: String, from event: ScheduleEvent) -> CommanderScheduleSourceRow {
    CommanderScheduleSourceRow(
      sourceRowId: id,
      sourcePage: 1,
      date: event.date,
      start: event.start,
      end: event.end,
      title: event.title,
      location: event.location,
      kind: event.kind,
      procedureType: event.procedureType,
      mealType: event.mealType
    )
  }

  private func procedure(id: String, date: String, start: String, end: String, title: String, location: String) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id,
      date: date,
      start: start,
      end: end,
      title: title,
      location: location,
      kind: .procedure,
      procedureType: title,
      mealType: nil,
      leadTimeMinutes: nil
    )
  }

  private func schedule(events: [ScheduleEvent]) -> Schedule {
    Schedule(
      schemaVersion: 1,
      scheduleVersion: 1,
      updatedAt: "2026-09-01T08:00:00Z",
      stay: ["dateFrom": "2026-09-01", "dateTo": "2026-10-05"],
      events: events,
      settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
    )
  }
}

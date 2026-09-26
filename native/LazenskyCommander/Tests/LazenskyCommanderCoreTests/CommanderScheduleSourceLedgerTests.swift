import Testing
@testable import LazenskyCommanderCore

struct CommanderScheduleSourceLedgerTests {
  @Test func exactFullStaySourceCanVerifySchedule() throws {
    let schedule = makeSchedule(version: 1, from: "2026-09-01", to: "2026-09-03", events: [
      event("a", "2026-09-01", "09:00"),
      event("b", "2026-09-02", "10:00"),
      event("c", "2026-09-03", "11:00")
    ])
    let revision = sourceRevision(
      id: "paper-1", from: "2026-09-01", to: "2026-09-03", schedule: schedule,
      hashes: ["sha256:paper-1"]
    )
    let reconciliation = CommanderScheduleSourceReconciler.reconcile(revision: revision, canonical: schedule)
    let ledger = try CommanderScheduleSourceLedgerEngine.accepting(
      revision: revision,
      reconciliation: reconciliation,
      schedule: schedule,
      into: CommanderScheduleSourceLedgerEngine.empty(for: schedule)
    )
    let coverage = try CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: schedule, ledger: ledger)
    #expect(coverage.isComplete)
    let gate = CommanderScheduleAcceptanceGate.evaluate(schedule: schedule, sourceLedger: ledger)
    #expect(gate.status == .verified)
  }

  @Test func partialRevisionInvalidatesOnlyItsCoverage() throws {
    let v1 = makeSchedule(version: 1, from: "2026-09-01", to: "2026-09-03", events: [
      event("a", "2026-09-01", "09:00"),
      event("b", "2026-09-02", "10:00"),
      event("c", "2026-09-03", "11:00")
    ])
    let baseRevision = sourceRevision(id: "base", from: "2026-09-01", to: "2026-09-03", schedule: v1, hashes: ["sha256:base"])
    let baseReport = CommanderScheduleSourceReconciler.reconcile(revision: baseRevision, canonical: v1)
    let ledgerV1 = try CommanderScheduleSourceLedgerEngine.accepting(
      revision: baseRevision, reconciliation: baseReport, schedule: v1,
      into: CommanderScheduleSourceLedgerEngine.empty(for: v1)
    )

    let v2 = makeSchedule(version: 2, from: "2026-09-01", to: "2026-09-03", events: [
      event("a", "2026-09-01", "09:00"),
      event("changed", "2026-09-02", "12:00"),
      event("c", "2026-09-03", "11:00")
    ])
    let carried = try CommanderScheduleSourceLedgerEngine.carryingForward(
      ledgerV1,
      to: v2,
      invalidating: [.init(from: "2026-09-02", to: "2026-09-02")]
    )
    #expect(carried.days["2026-09-01"] != nil)
    #expect(carried.days["2026-09-02"] == nil)
    #expect(carried.days["2026-09-03"] != nil)

    let coverageBefore = try CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: v2, ledger: carried)
    #expect(coverageBefore.missingDates == ["2026-09-02"])

    let replacement = sourceRevision(id: "change", from: "2026-09-02", to: "2026-09-02", schedule: v2, hashes: ["sha256:change"])
    let replacementReport = CommanderScheduleSourceReconciler.reconcile(revision: replacement, canonical: v2)
    let ledgerV2 = try CommanderScheduleSourceLedgerEngine.accepting(
      revision: replacement, reconciliation: replacementReport, schedule: v2, into: carried
    )
    #expect(try CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: v2, ledger: ledgerV2).isComplete)
  }

  @Test func extensionLeavesNewDaysUnverifiedUntilNewPaperIsAccepted() throws {
    let v1 = makeSchedule(version: 1, from: "2026-09-01", to: "2026-09-02", events: [
      event("a", "2026-09-01", "09:00"), event("b", "2026-09-02", "10:00")
    ])
    let base = sourceRevision(id: "base", from: "2026-09-01", to: "2026-09-02", schedule: v1, hashes: ["sha256:base"])
    let baseReport = CommanderScheduleSourceReconciler.reconcile(revision: base, canonical: v1)
    let ledgerV1 = try CommanderScheduleSourceLedgerEngine.accepting(
      revision: base, reconciliation: baseReport, schedule: v1,
      into: CommanderScheduleSourceLedgerEngine.empty(for: v1)
    )

    let v2 = makeSchedule(version: 2, from: "2026-09-01", to: "2026-09-04", events: [
      event("a", "2026-09-01", "09:00"), event("b", "2026-09-02", "10:00"),
      event("c", "2026-09-03", "11:00"), event("d", "2026-09-04", "12:00")
    ])
    let carried = try CommanderScheduleSourceLedgerEngine.carryingForward(ledgerV1, to: v2)
    let coverage = try CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: v2, ledger: carried)
    #expect(coverage.missingDates == ["2026-09-03", "2026-09-04"])
    #expect(CommanderScheduleAcceptanceGate.evaluate(schedule: v2, sourceLedger: carried).status == .sourceVerificationRequired)
  }

  @Test func sourceEvidenceHashIsRequiredForFinalVerification() throws {
    let schedule = makeSchedule(version: 1, from: "2026-09-01", to: "2026-09-01", events: [event("a", "2026-09-01", "09:00")])
    let revision = sourceRevision(id: "paper", from: "2026-09-01", to: "2026-09-01", schedule: schedule, hashes: [])
    let reconciliation = CommanderScheduleSourceReconciler.reconcile(revision: revision, canonical: schedule)
    let ledger = try CommanderScheduleSourceLedgerEngine.accepting(
      revision: revision, reconciliation: reconciliation, schedule: schedule,
      into: CommanderScheduleSourceLedgerEngine.empty(for: schedule)
    )
    let coverage = try CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: schedule, ledger: ledger)
    #expect(coverage.evidenceMissingDates == ["2026-09-01"])
    #expect(CommanderScheduleAcceptanceGate.evaluate(schedule: schedule, sourceLedger: ledger).status == .sourceVerificationRequired)
  }

  @Test func acknowledgedWarningStillRequiresSourceVerification() {
    let schedule = makeSchedule(version: 7, from: "2026-09-05", to: "2026-09-05", events: [
      event("a", "2026-09-05", "09:00"), event("b", "2026-09-05", "10:00")
    ])
    let initial = CommanderScheduleAcceptanceGate.evaluate(schedule: schedule, policy: .petrSpaOperational)
    #expect(initial.status == .reviewRequired)
    let warning = initial.review.openWarnings[0]
    let ack = CommanderScheduleAuditAcknowledgement(
      scheduleVersion: 7, reviewKey: warning.reviewKey, confirmedAt: "2026-09-05T08:00:00Z"
    )
    let afterAck = CommanderScheduleAcceptanceGate.evaluate(
      schedule: schedule, policy: .petrSpaOperational, acknowledgements: [ack]
    )
    #expect(afterAck.status == .sourceVerificationRequired)
  }

  private func event(_ id: String, _ date: String, _ start: String) -> ScheduleEvent {
    ScheduleEvent(
      stableId: id, date: date, start: start, end: endTime(start), title: "Procedura \(id)",
      location: "Rehabilitace", kind: .procedure, procedureType: "Procedura", mealType: nil, leadTimeMinutes: nil
    )
  }

  private func endTime(_ start: String) -> String {
    let parts = start.split(separator: ":").compactMap { Int($0) }
    let minutes = parts[0] * 60 + parts[1] + 20
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  private func makeSchedule(version: Int, from: String, to: String, events: [ScheduleEvent]) -> Schedule {
    Schedule(
      schemaVersion: 1, scheduleVersion: version, updatedAt: "2026-09-01T08:00:00Z",
      stay: ["dateFrom": from, "dateTo": to], events: events,
      settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:], mealOverrides: [:])
    )
  }

  private func sourceRevision(
    id: String,
    from: String,
    to: String,
    schedule: Schedule,
    hashes: [String]
  ) -> CommanderScheduleSourceRevision {
    let rows = schedule.events
      .filter { $0.date >= from && $0.date <= to }
      .map { event in
        CommanderScheduleSourceRow(
          sourceRowId: "\(id).\(event.stableId)", sourcePage: 1, date: event.date,
          start: event.start, end: event.end, title: event.title, location: event.location,
          kind: event.kind, procedureType: event.procedureType, mealType: event.mealType
        )
      }
    return CommanderScheduleSourceRevision(
      revisionId: id, capturedAt: "2026-09-01T08:00:00Z",
      coverageFrom: from, coverageTo: to, reason: .replacementSheet,
      sourceAssetHashes: hashes, rows: rows
    )
  }
}

import Foundation

public enum PhysicalAcceptanceError: LocalizedError {
  case midnightBoundary
  case wrongApplication
  case cleanupIncomplete

  public var errorDescription: String? {
    switch self {
    case .midnightBoundary: "Test by překročil půlnoc. Spusťte jej po půlnoci."
    case .wrongApplication: "Fyzický test vyžaduje izolovanou aplikaci Commander Test."
    case .cleanupIncomplete: "Předchozí testovací alarmy se nepodařilo odstranit. Nový test nebyl spuštěn."
    }
  }
}

public struct PhysicalAcceptanceRun: Equatable, Sendable {
  public static let bundleID = "com.varnakonvice.lazenskycommander.physicalacceptance"
  public static let storageSuite = "com.varnakonvice.lazenskycommander.physicalAcceptance.v1"
  public static let stableIDPrefix = "physicalAcceptance."
  public let id: UUID
  public let now: Date
  public let schedule: Schedule
  public let projectionRevision = 1
  public var namespace: String { Self.stableIDPrefix + id.uuidString }
  public var overrides: LeadTimeOverrides { LeadTimeOverrides() }

  public init(now: Date, id: UUID = UUID()) throws {
    self.id = id
    self.now = now
    // Accelerated spa-day E2E. It deliberately contains an alarm for the next
    // procedure while breakfast is still running, a following procedure in the
    // same Live Activity window, and a later dinner in a separate window.
    let anchor = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 60) * 60)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    guard calendar.isDate(now, inSameDayAs: anchor.addingTimeInterval(24 * 60)) else {
      throw PhysicalAcceptanceError.midnightBoundary
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    let day = formatter.string(from: now)
    formatter.dateFormat = "HH:mm"
    func time(_ minute: Int) -> String { formatter.string(from: anchor.addingTimeInterval(Double(minute * 60))) }
    let prefix = Self.stableIDPrefix + id.uuidString
    schedule = Schedule(schemaVersion: 1, scheduleVersion: 1, updatedAt: ISO8601DateFormatter().string(from: now), stay: ["spa": "Lokální fyzický E2E"], events: [
      ScheduleEvent(stableId: prefix + ".breakfast", date: day, start: time(5), end: time(10), title: "TEST – Snídaně", location: "Testovací jídelna", kind: .meal, procedureType: nil, mealType: "Snídaně", leadTimeMinutes: 1),
      ScheduleEvent(stableId: prefix + ".magnet", date: day, start: time(9), end: time(12), title: "TEST – Magnetoterapie", location: "Elektroléčba · budova 2", kind: .procedure, procedureType: "Magnetoterapie", mealType: nil, leadTimeMinutes: 3),
      ScheduleEvent(stableId: prefix + ".rehab", date: day, start: time(14), end: time(16), title: "TEST – Rehabilitace", location: "Rehabilitace · tělocvična", kind: .procedure, procedureType: "Rehabilitace", mealType: nil, leadTimeMinutes: 2),
      ScheduleEvent(stableId: prefix + ".dinner", date: day, start: time(21), end: time(24), title: "TEST – Večeře", location: "Testovací jídelna", kind: .meal, procedureType: nil, mealType: "Večeře", leadTimeMinutes: 2)
    ], settings: ScheduleSettings(defaultLeadTimeMinutes: 2, procedureTypeOverrides: [:], mealOverrides: [:]))
    try NativeAlarmContract.validateCanonical(schedule)
  }

  public func payload() throws -> NativeAlarmPayload {
    try NativeAlarmContract.payload(schedule: schedule, overrides: overrides)
  }
}

public struct PhysicalAcceptanceCleanupPlan: Equatable, Sendable {
  public let cancelIDs: Set<String>
  public let unknownIDs: Set<String>
  public init(ownedIDs: Set<String>, platformIDs: Set<String>) {
    cancelIDs = ownedIDs.intersection(platformIDs)
    unknownIDs = platformIDs.subtracting(ownedIDs)
  }
}

public actor PhysicalAcceptanceOwnershipStore {
  public static let ownershipKey = "ownedPlatformAlarms.v1"
  private let defaults: UserDefaults

  public init(suiteName: String = PhysicalAcceptanceRun.storageSuite) {
    precondition(suiteName == PhysicalAcceptanceRun.storageSuite || suiteName.hasPrefix(PhysicalAcceptanceRun.storageSuite + ".test."))
    defaults = UserDefaults(suiteName: suiteName)!
  }
  public func allIDs() -> Set<String> { Set(ledger().keys) }
  public func ids(runID: UUID) -> Set<String> {
    Set(ledger().filter { $0.value == runID.uuidString }.keys)
  }
  public func remember(_ id: String, runID: UUID) {
    var entries = ledger()
    entries[id] = runID.uuidString
    defaults.set(entries, forKey: Self.ownershipKey)
  }
  public func forget(_ id: String) {
    var entries = ledger()
    entries.removeValue(forKey: id)
    defaults.set(entries, forKey: Self.ownershipKey)
  }
  private func ledger() -> [String: String] {
    defaults.dictionary(forKey: Self.ownershipKey) as? [String: String] ?? [:]
  }
}

private struct LocalAcceptanceSchedule: ScheduleServing {
  let schedule: Schedule
  func fetchSchedule() async throws -> Schedule { schedule }
}

public struct PhysicalAcceptanceSession: Sendable {
  public let run: PhysicalAcceptanceRun
  public let alarmStore = InMemoryAlarmStateStore()
  public let scheduleStore = InMemoryScheduleSnapshotStore()
  private let coordinator: CommanderScheduleSyncCoordinator

  public init(run: PhysicalAcceptanceRun, adapter: any AlarmAdapting) {
    self.run = run
    let local = LocalAcceptanceSchedule(schedule: run.schedule)
    coordinator = CommanderScheduleSyncCoordinator(
      scheduleService: local,
      alarmSyncService: AlarmSyncService(scheduleService: local, store: alarmStore, adapter: adapter),
      scheduleStore: scheduleStore,
      watchDelivery: nil
    )
  }
  public func synchronize(now: Date) async throws -> CommanderScheduleSyncResult {
    try await coordinator.synchronize(overrides: run.overrides, projectionRevision: run.projectionRevision, now: now)
  }
}

public struct PhysicalAlarmObservation: Equatable, Sendable {
  public let platformID: String
  public let stableID: String?
  public let configuredAt: Date?
  public let scheduleKind: String
  public let fixedScheduleAt: Date?
  public let preAlert: TimeInterval?
  public let postAlert: TimeInterval?
  public let state: String
  public let fireDate: Date?

  public init(platformID: String, stableID: String?, configuredAt: Date?, scheduleKind: String, fixedScheduleAt: Date?, preAlert: TimeInterval?, postAlert: TimeInterval?, state: String, fireDate: Date?) {
    self.platformID = platformID; self.stableID = stableID; self.configuredAt = configuredAt
    self.scheduleKind = scheduleKind; self.fixedScheduleAt = fixedScheduleAt
    self.preAlert = preAlert; self.postAlert = postAlert; self.state = state; self.fireDate = fireDate
  }
}

public struct PhysicalPreflightRow: Sendable {
  public let alarm: NativeAlarm
  public let leadTime: ResolvedLeadTime
  public let expectedAlertAt: Date
  public let actual: PhysicalAlarmObservation?
  public let issues: [String]
}

public struct PhysicalAcceptancePreflight: Sendable {
  public let checkedAt: Date
  public let rows: [PhysicalPreflightRow]
  public let issues: [String]
  public var expectedAlarmCount: Int { rows.count }
  public var verifiedAlarmCount: Int { rows.filter { $0.issues.isEmpty }.count }
  public var ready: Bool { !rows.isEmpty && issues.isEmpty && verifiedAlarmCount == rows.count }

  public init(run: PhysicalAcceptanceRun, observations: [PhysicalAlarmObservation], managed: ManagedAlarmState, syncVerified: Bool, procedureActivityPrepared: Bool, now: Date) throws {
    checkedAt = now
    let payload = try run.payload()
    var problems: [String] = []
    if !syncVerified { problems.append("Synchronizace zatím není ověřená.") }
    if !procedureActivityPrepared {
      problems.append("Commander Live Activity zatím není naplánovaná ani aktivní.")
    }
    let expectedCount = payload.alarms.count
    if observations.count != expectedCount ||
       Set(observations.map(\.platformID)).count != expectedCount ||
       Set(observations.map(\.platformID)) != Set(managed.records.values.map(\.platformAlarmID)) {
      problems.append("Počet nebo identita systémových alarmů neodpovídá \(expectedCount) spravovaným alarmům.")
    }
    if let first = payload.alarms.first, try NativeAlarmContract.date(fromLocalISO: first.leaveAt).timeIntervalSince(now) < 60 {
      problems.append("Do prvního alarmu zbývá méně než minuta. Tento běh není připravený.")
    }

    rows = try payload.alarms.map { alarm in
      let event = run.schedule.events.first { $0.stableId == alarm.stableId }!
      let resolution = try NativeAlarmContract.resolvedLeadTime(event: event, schedule: run.schedule, overrides: run.overrides)
      let matches = observations.filter { $0.stableID == alarm.stableId }
      let actual = matches.count == 1 ? matches.first : nil
      let expectedAlertAt = try NativeAlarmContract.date(fromLocalISO: alarm.leaveAt)
      var errors: [String] = []

      if let actual, let configuredAt = actual.configuredAt {
        if configuredAt < run.now || configuredAt > now { errors.append("Neplatný čas konfigurace.") }
        if managed.records[alarm.stableId]?.platformAlarmID != actual.platformID { errors.append("Nesouhlasí spravované ID.") }
        if actual.preAlert != nil { errors.append("Alert-only alarm nemá mít preAlert.") }
        if actual.postAlert != nil { errors.append("Alert-only alarm nemá mít postAlert.") }
        if actual.scheduleKind != "fixed" ||
           actual.fixedScheduleAt.map({ abs($0.timeIntervalSince(expectedAlertAt)) <= 1 }) != true {
          errors.append("AlarmKit alarm není naplánovaný přímo na canonical leaveAt.")
        }
        if actual.state != "scheduled" {
          errors.append("Budoucí AlarmKit alarm není ve stavu scheduled.")
        }

        let endpoint = AlarmCountdown.effectiveAlertDate(
          fixedScheduleAt: actual.fixedScheduleAt,
          preAlert: actual.preAlert,
          countdownFireDate: actual.fireDate
        )
        if let endpoint {
          if abs(endpoint.timeIntervalSince(expectedAlertAt)) > 1 {
            errors.append("Výsledný čas alarmu neodpovídá času odchodu.")
          }
        } else {
          errors.append("Systém neposkytl dostatek údajů k ověření času alarmu.")
        }
      } else {
        errors.append("Chybí jednoznačné systémové ověření a čas konfigurace.")
      }

      return PhysicalPreflightRow(
        alarm: alarm,
        leadTime: resolution,
        expectedAlertAt: expectedAlertAt,
        actual: actual,
        issues: errors
      )
    }
    issues = problems
  }
}

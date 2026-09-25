import Foundation

public enum CommanderScheduleRevisionReason: String, Codable, Equatable, Sendable {
  case initial
  case patientRequestedChange
  case clinicianRequestedChange
  case stayExtension
  case replacementSheet
  case other
}

public struct CommanderScheduleSourceRow: Codable, Equatable, Sendable {
  public let sourceRowId: String
  public let sourcePage: Int?
  public let date: String
  public let start: String
  public let end: String
  public let title: String
  public let location: String
  public let kind: ScheduleKind
  public let procedureType: String?
  public let mealType: String?

  public init(
    sourceRowId: String,
    sourcePage: Int? = nil,
    date: String,
    start: String,
    end: String,
    title: String,
    location: String,
    kind: ScheduleKind,
    procedureType: String? = nil,
    mealType: String? = nil
  ) {
    self.sourceRowId = sourceRowId
    self.sourcePage = sourcePage
    self.date = date
    self.start = start
    self.end = end
    self.title = title
    self.location = location
    self.kind = kind
    self.procedureType = procedureType
    self.mealType = mealType
  }
}

public struct CommanderScheduleSourceRevision: Codable, Equatable, Sendable {
  public let revisionId: String
  public let capturedAt: String
  public let coverageFrom: String
  public let coverageTo: String
  public let reason: CommanderScheduleRevisionReason
  public let sourceAssetHashes: [String]
  public let rows: [CommanderScheduleSourceRow]

  public init(
    revisionId: String,
    capturedAt: String,
    coverageFrom: String,
    coverageTo: String,
    reason: CommanderScheduleRevisionReason,
    sourceAssetHashes: [String] = [],
    rows: [CommanderScheduleSourceRow]
  ) {
    self.revisionId = revisionId
    self.capturedAt = capturedAt
    self.coverageFrom = coverageFrom
    self.coverageTo = coverageTo
    self.reason = reason
    self.sourceAssetHashes = sourceAssetHashes
    self.rows = rows
  }
}

public struct CommanderScheduleFieldMismatch: Codable, Equatable, Sendable {
  public let sourceRowId: String
  public let canonicalStableId: String
  public let differingFields: [String]
}

public struct CommanderScheduleReconciliationReport: Codable, Equatable, Sendable {
  public let revisionId: String
  public let canonicalScheduleVersion: Int
  public let coverageFrom: String
  public let coverageTo: String
  public let matchedCount: Int
  public let missingSourceRows: [String]
  public let extraCanonicalStableIds: [String]
  public let mismatches: [CommanderScheduleFieldMismatch]

  public var isExact: Bool {
    missingSourceRows.isEmpty && extraCanonicalStableIds.isEmpty && mismatches.isEmpty
  }
}

/// Compares a captured source sheet revision against the canonical schedule in the
/// exact coverage window of that sheet. The audit is deliberately conservative:
/// it does not invent rows, repair times, or silently accept near-matches.
public enum CommanderScheduleSourceReconciler {
  public static func reconcile(
    revision: CommanderScheduleSourceRevision,
    canonical schedule: Schedule
  ) -> CommanderScheduleReconciliationReport {
    let canonical = schedule.events
      .filter { $0.date >= revision.coverageFrom && $0.date <= revision.coverageTo }
      .sorted(by: eventSort)

    var unmatchedCanonical = Set(canonical.indices)
    var matchedCount = 0
    var missing: [String] = []
    var mismatches: [CommanderScheduleFieldMismatch] = []

    for row in revision.rows.sorted(by: rowSort) {
      if let exactIndex = unmatchedCanonical.first(where: { exact(row, canonical[$0]) }) {
        matchedCount += 1
        unmatchedCanonical.remove(exactIndex)
        continue
      }

      let near = unmatchedCanonical.filter { nearIdentity(row, canonical[$0]) }
      if near.count == 1, let index = near.first {
        let event = canonical[index]
        let fields = differingFields(row, event)
        if !fields.isEmpty {
          mismatches.append(.init(
            sourceRowId: row.sourceRowId,
            canonicalStableId: event.stableId,
            differingFields: fields
          ))
          unmatchedCanonical.remove(index)
          continue
        }
      }

      missing.append(row.sourceRowId)
    }

    let extras = unmatchedCanonical
      .map { canonical[$0].stableId }
      .sorted()

    return CommanderScheduleReconciliationReport(
      revisionId: revision.revisionId,
      canonicalScheduleVersion: schedule.scheduleVersion,
      coverageFrom: revision.coverageFrom,
      coverageTo: revision.coverageTo,
      matchedCount: matchedCount,
      missingSourceRows: missing.sorted(),
      extraCanonicalStableIds: extras,
      mismatches: mismatches.sorted { $0.sourceRowId < $1.sourceRowId }
    )
  }

  private static func exact(_ row: CommanderScheduleSourceRow, _ event: ScheduleEvent) -> Bool {
    row.date == event.date &&
    row.start == event.start &&
    row.end == event.end &&
    normalize(row.title) == normalize(event.title) &&
    normalize(row.location) == normalize(event.location) &&
    row.kind == event.kind &&
    normalizeOptional(row.procedureType) == normalizeOptional(event.procedureType) &&
    normalizeOptional(row.mealType) == normalizeOptional(event.mealType)
  }

  /// A near identity is strict enough to avoid guessing, but lets the report say
  /// *which field differs* for the common transcription-error case.
  private static func nearIdentity(_ row: CommanderScheduleSourceRow, _ event: ScheduleEvent) -> Bool {
    row.date == event.date && row.start == event.start && row.kind == event.kind
  }

  private static func differingFields(_ row: CommanderScheduleSourceRow, _ event: ScheduleEvent) -> [String] {
    var result: [String] = []
    if row.end != event.end { result.append("end") }
    if normalize(row.title) != normalize(event.title) { result.append("title") }
    if normalize(row.location) != normalize(event.location) { result.append("location") }
    if normalizeOptional(row.procedureType) != normalizeOptional(event.procedureType) { result.append("procedureType") }
    if normalizeOptional(row.mealType) != normalizeOptional(event.mealType) { result.append("mealType") }
    return result
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .lowercased(with: Locale(identifier: "cs_CZ"))
  }

  private static func normalizeOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized = normalize(value)
    return normalized.isEmpty ? nil : normalized
  }

  private static func eventSort(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
    (lhs.date, lhs.start, lhs.end, lhs.stableId) < (rhs.date, rhs.start, rhs.end, rhs.stableId)
  }

  private static func rowSort(_ lhs: CommanderScheduleSourceRow, _ rhs: CommanderScheduleSourceRow) -> Bool {
    (lhs.date, lhs.start, lhs.end, lhs.sourceRowId) < (rhs.date, rhs.start, rhs.end, rhs.sourceRowId)
  }
}

public enum CommanderScheduleRevisionApplyError: LocalizedError, Equatable, Sendable {
  case invalidCoverage
  case invalidNewScheduleVersion
  case coverageOutsideStay
  case invalidExtension

  public var errorDescription: String? {
    switch self {
    case .invalidCoverage: return "Neplatný rozsah zdrojové revize."
    case .invalidNewScheduleVersion: return "Nová verze rozpisu musí být vyšší než současná."
    case .coverageOutsideStay: return "Zdrojová revize zasahuje mimo aktuální pobyt."
    case .invalidExtension: return "Neplatné prodloužení pobytu."
    }
  }
}

/// Applies one verified source-sheet revision as a replacement of its declared
/// coverage window. It never appends rows blindly on top of the old window.
public enum CommanderScheduleRevisionApplier {
  public static func applying(
    _ revision: CommanderScheduleSourceRevision,
    to schedule: Schedule,
    newScheduleVersion: Int,
    updatedAt: String,
    extendedStayTo: String? = nil
  ) throws -> Schedule {
    guard newScheduleVersion > schedule.scheduleVersion else {
      throw CommanderScheduleRevisionApplyError.invalidNewScheduleVersion
    }
    guard validDate(revision.coverageFrom),
          validDate(revision.coverageTo),
          revision.coverageFrom <= revision.coverageTo else {
      throw CommanderScheduleRevisionApplyError.invalidCoverage
    }

    var stay = schedule.stay
    let originalStayFrom = stay["dateFrom"]
    let originalStayTo = stay["dateTo"]

    if let extendedStayTo {
      guard validDate(extendedStayTo),
            let currentTo = originalStayTo,
            extendedStayTo >= currentTo else {
        throw CommanderScheduleRevisionApplyError.invalidExtension
      }
      stay["dateTo"] = extendedStayTo
    }

    guard let stayFrom = originalStayFrom,
          let stayTo = stay["dateTo"],
          validDate(stayFrom), validDate(stayTo),
          revision.coverageFrom >= stayFrom,
          revision.coverageTo <= stayTo else {
      throw CommanderScheduleRevisionApplyError.coverageOutsideStay
    }

    let oldWindow = schedule.events.filter {
      $0.date >= revision.coverageFrom && $0.date <= revision.coverageTo
    }
    let outsideWindow = schedule.events.filter {
      $0.date < revision.coverageFrom || $0.date > revision.coverageTo
    }

    var availableOld = Set(oldWindow.indices)
    var replacement: [ScheduleEvent] = []
    replacement.reserveCapacity(revision.rows.count)

    for row in revision.rows.sorted(by: sourceRowSort) {
      if let exactIndex = availableOld.first(where: { sourceRowExactlyMatchesEvent(row, oldWindow[$0]) }) {
        let old = oldWindow[exactIndex]
        replacement.append(ScheduleEvent(
          stableId: old.stableId,
          date: row.date,
          start: row.start,
          end: row.end,
          title: row.title,
          location: row.location,
          kind: row.kind,
          procedureType: row.procedureType,
          mealType: row.mealType,
          leadTimeMinutes: old.leadTimeMinutes
        ))
        availableOld.remove(exactIndex)
      } else {
        replacement.append(ScheduleEvent(
          stableId: generatedStableId(revisionId: revision.revisionId, sourceRowId: row.sourceRowId),
          date: row.date,
          start: row.start,
          end: row.end,
          title: row.title,
          location: row.location,
          kind: row.kind,
          procedureType: row.procedureType,
          mealType: row.mealType,
          leadTimeMinutes: nil
        ))
      }
    }

    let result = Schedule(
      schemaVersion: schedule.schemaVersion,
      scheduleVersion: newScheduleVersion,
      updatedAt: updatedAt,
      stay: stay,
      events: (outsideWindow + replacement).sorted(by: eventSort),
      settings: schedule.settings
    )
    try NativeAlarmContract.validateCanonical(result)
    return result
  }

  private static func validDate(_ value: String) -> Bool {
    (try? NativeAlarmContract.dateTime(date: value, time: "00:00")) != nil
  }

  private static func generatedStableId(revisionId: String, sourceRowId: String) -> String {
    "source.\(stableComponent(revisionId)).\(stableComponent(sourceRowId))"
  }

  private static func stableComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalar = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
    let collapsed = scalar.replacingOccurrences(of: "--", with: "-")
    return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private static func sourceRowExactlyMatchesEvent(_ row: CommanderScheduleSourceRow, _ event: ScheduleEvent) -> Bool {
    row.date == event.date && row.start == event.start && row.end == event.end &&
    normalized(row.title) == normalized(event.title) &&
    normalized(row.location) == normalized(event.location) &&
    row.kind == event.kind &&
    normalizedOptional(row.procedureType) == normalizedOptional(event.procedureType) &&
    normalizedOptional(row.mealType) == normalizedOptional(event.mealType)
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .lowercased(with: Locale(identifier: "cs_CZ"))
  }

  private static func normalizedOptional(_ value: String?) -> String? {
    guard let value else { return nil }
    let result = normalized(value)
    return result.isEmpty ? nil : result
  }

  private static func sourceRowSort(_ lhs: CommanderScheduleSourceRow, _ rhs: CommanderScheduleSourceRow) -> Bool {
    (lhs.date, lhs.start, lhs.end, lhs.sourceRowId) < (rhs.date, rhs.start, rhs.end, rhs.sourceRowId)
  }

  private static func eventSort(_ lhs: ScheduleEvent, _ rhs: ScheduleEvent) -> Bool {
    (lhs.date, lhs.start, lhs.end, lhs.stableId) < (rhs.date, rhs.start, rhs.end, rhs.stableId)
  }
}

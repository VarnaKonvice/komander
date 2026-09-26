import CryptoKit
import Foundation

public struct CommanderScheduleCoverageRange: Codable, Equatable, Sendable {
  public let from: String
  public let to: String

  public init(from: String, to: String) {
    self.from = from
    self.to = to
  }

  public func contains(_ date: String) -> Bool {
    date >= from && date <= to
  }
}

public struct CommanderScheduleSourceDayVerification: Codable, Equatable, Sendable {
  public let date: String
  public let sourceRevisionId: String
  public let sourceAssetHashes: [String]
  public let canonicalSHA256: String

  public init(
    date: String,
    sourceRevisionId: String,
    sourceAssetHashes: [String],
    canonicalSHA256: String
  ) {
    self.date = date
    self.sourceRevisionId = sourceRevisionId
    self.sourceAssetHashes = sourceAssetHashes
    self.canonicalSHA256 = canonicalSHA256
  }
}

public struct CommanderScheduleSourceLedger: Codable, Equatable, Sendable {
  public let scheduleVersion: Int
  public let days: [String: CommanderScheduleSourceDayVerification]

  public init(scheduleVersion: Int, days: [String: CommanderScheduleSourceDayVerification] = [:]) {
    self.scheduleVersion = scheduleVersion
    self.days = days
  }
}

public enum CommanderScheduleSourceLedgerError: LocalizedError, Equatable, Sendable {
  case reconciliationNotExact
  case revisionMismatch
  case scheduleVersionMismatch
  case coverageMismatch
  case invalidStayRange

  public var errorDescription: String? {
    switch self {
    case .reconciliationNotExact: return "Zdrojový papír není v přesné shodě s kanonickým rozpisem."
    case .revisionMismatch: return "Reconciliace nepatří ke stejné zdrojové revizi."
    case .scheduleVersionMismatch: return "Reconciliace nepatří k aktuální verzi rozpisu."
    case .coverageMismatch: return "Rozsah reconciliace neodpovídá rozsahu zdrojové revize."
    case .invalidStayRange: return "Nelze určit platný rozsah pobytu."
    }
  }
}

public struct CommanderScheduleSourceCoverageStatus: Equatable, Sendable {
  public let missingDates: [String]
  public let staleDates: [String]
  public let evidenceMissingDates: [String]

  public var isComplete: Bool {
    missingDates.isEmpty && staleDates.isEmpty && evidenceMissingDates.isEmpty
  }
}

/// Ledger of exact source-to-canonical verification by day.
///
/// Per-day stamps make partial replacement sheets safe: unchanged days can carry forward to
/// a newer schedule version only when their canonical content hash is unchanged. The declared
/// replacement range is always invalidated even when the resulting rows happen to look equal,
/// because the newer paper becomes the authoritative source for that range.
public enum CommanderScheduleSourceLedgerEngine {
  public static func empty(for schedule: Schedule) -> CommanderScheduleSourceLedger {
    CommanderScheduleSourceLedger(scheduleVersion: schedule.scheduleVersion)
  }

  public static func carryingForward(
    _ previous: CommanderScheduleSourceLedger?,
    to schedule: Schedule,
    invalidating ranges: [CommanderScheduleCoverageRange] = []
  ) throws -> CommanderScheduleSourceLedger {
    let dates = try stayDates(schedule)
    guard let previous else { return empty(for: schedule) }

    var retained: [String: CommanderScheduleSourceDayVerification] = [:]
    for date in dates {
      guard !ranges.contains(where: { $0.contains(date) }),
            let stamp = previous.days[date],
            stamp.canonicalSHA256 == canonicalSHA256(for: schedule, date: date)
      else { continue }
      retained[date] = stamp
    }
    return CommanderScheduleSourceLedger(scheduleVersion: schedule.scheduleVersion, days: retained)
  }

  public static func accepting(
    revision: CommanderScheduleSourceRevision,
    reconciliation: CommanderScheduleReconciliationReport,
    schedule: Schedule,
    into ledger: CommanderScheduleSourceLedger
  ) throws -> CommanderScheduleSourceLedger {
    guard reconciliation.isExact else {
      throw CommanderScheduleSourceLedgerError.reconciliationNotExact
    }
    guard reconciliation.revisionId == revision.revisionId else {
      throw CommanderScheduleSourceLedgerError.revisionMismatch
    }
    guard reconciliation.canonicalScheduleVersion == schedule.scheduleVersion,
          ledger.scheduleVersion == schedule.scheduleVersion else {
      throw CommanderScheduleSourceLedgerError.scheduleVersionMismatch
    }
    guard reconciliation.coverageFrom == revision.coverageFrom,
          reconciliation.coverageTo == revision.coverageTo else {
      throw CommanderScheduleSourceLedgerError.coverageMismatch
    }

    let stay = Set(try stayDates(schedule))
    let coverageDates = try dates(from: revision.coverageFrom, to: revision.coverageTo)
    guard coverageDates.allSatisfy(stay.contains) else {
      throw CommanderScheduleSourceLedgerError.coverageMismatch
    }

    var days = ledger.days
    for date in coverageDates {
      days[date] = CommanderScheduleSourceDayVerification(
        date: date,
        sourceRevisionId: revision.revisionId,
        sourceAssetHashes: revision.sourceAssetHashes.sorted(),
        canonicalSHA256: canonicalSHA256(for: schedule, date: date)
      )
    }
    return CommanderScheduleSourceLedger(scheduleVersion: schedule.scheduleVersion, days: days)
  }

  public static func coverageStatus(
    schedule: Schedule,
    ledger: CommanderScheduleSourceLedger
  ) throws -> CommanderScheduleSourceCoverageStatus {
    let dates = try stayDates(schedule)
    var missing: [String] = []
    var stale: [String] = []
    var noEvidence: [String] = []

    for date in dates {
      guard let stamp = ledger.days[date] else {
        missing.append(date)
        continue
      }
      if stamp.canonicalSHA256 != canonicalSHA256(for: schedule, date: date) {
        stale.append(date)
      }
      if stamp.sourceAssetHashes.isEmpty {
        noEvidence.append(date)
      }
    }

    return CommanderScheduleSourceCoverageStatus(
      missingDates: missing,
      staleDates: stale,
      evidenceMissingDates: noEvidence
    )
  }

  public static func canonicalSHA256(for schedule: Schedule, date: String) -> String {
    let rows = schedule.events
      .filter { $0.date == date }
      .sorted { ($0.start, $0.end, $0.stableId) < ($1.start, $1.end, $1.stableId) }
      .map { event in
        [
          event.stableId,
          event.date,
          event.start,
          event.end,
          event.title,
          event.location,
          event.kind.rawValue,
          event.procedureType ?? "",
          event.mealType ?? "",
          event.leadTimeMinutes.map(String.init) ?? ""
        ].joined(separator: "\u{001F}")
      }
      .joined(separator: "\u{001E}")
    let digest = SHA256.hash(data: Data(rows.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func stayDates(_ schedule: Schedule) throws -> [String] {
    guard let from = schedule.stay["dateFrom"], let to = schedule.stay["dateTo"] else {
      throw CommanderScheduleSourceLedgerError.invalidStayRange
    }
    return try dates(from: from, to: to)
  }

  private static func dates(from: String, to: String) throws -> [String] {
    guard let start = try? NativeAlarmContract.dateTime(date: from, time: "00:00"),
          let end = try? NativeAlarmContract.dateTime(date: to, time: "00:00"),
          start <= end else {
      throw CommanderScheduleSourceLedgerError.invalidStayRange
    }
    var result: [String] = []
    var day = start
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd"
    while day <= end {
      result.append(formatter.string(from: day))
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    return result
  }
}

public enum CommanderScheduleAcceptanceStatus: String, Codable, Equatable, Sendable {
  case blocked
  case reviewRequired
  case sourceVerificationRequired
  case verified
}

public struct CommanderScheduleAcceptanceReport: Equatable, Sendable {
  public let status: CommanderScheduleAcceptanceStatus
  public let audit: CommanderScheduleAuditReport
  public let review: CommanderScheduleAuditReviewState
  public let sourceCoverage: CommanderScheduleSourceCoverageStatus?

  public var isVerified: Bool { status == .verified }
}

public enum CommanderScheduleAcceptanceGate {
  public static func evaluate(
    schedule: Schedule,
    policy: CommanderScheduleAuditPolicy = .init(),
    acknowledgements: [CommanderScheduleAuditAcknowledgement] = [],
    sourceLedger: CommanderScheduleSourceLedger? = nil
  ) -> CommanderScheduleAcceptanceReport {
    let audit = CommanderScheduleAudit.run(schedule, policy: policy)
    let review = CommanderScheduleAuditReview.resolve(report: audit, acknowledgements: acknowledgements)

    if !review.errors.isEmpty {
      return CommanderScheduleAcceptanceReport(status: .blocked, audit: audit, review: review, sourceCoverage: nil)
    }
    if !review.openWarnings.isEmpty {
      return CommanderScheduleAcceptanceReport(status: .reviewRequired, audit: audit, review: review, sourceCoverage: nil)
    }
    guard let sourceLedger,
          let sourceCoverage = try? CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: schedule, ledger: sourceLedger),
          sourceCoverage.isComplete else {
      let coverage = sourceLedger.flatMap { try? CommanderScheduleSourceLedgerEngine.coverageStatus(schedule: schedule, ledger: $0) }
      return CommanderScheduleAcceptanceReport(
        status: .sourceVerificationRequired,
        audit: audit,
        review: review,
        sourceCoverage: coverage
      )
    }
    return CommanderScheduleAcceptanceReport(
      status: .verified,
      audit: audit,
      review: review,
      sourceCoverage: sourceCoverage
    )
  }
}

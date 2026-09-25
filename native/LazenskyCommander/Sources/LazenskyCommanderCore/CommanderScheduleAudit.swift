import Foundation

public enum CommanderScheduleAuditSeverity: String, Codable, Equatable, Sendable {
  case warning
  case error
}

public struct CommanderScheduleAuditIssue: Codable, Equatable, Sendable {
  public let severity: CommanderScheduleAuditSeverity
  public let code: String
  public let message: String
  public let stableId: String?
  public let date: String?

  public init(
    severity: CommanderScheduleAuditSeverity,
    code: String,
    message: String,
    stableId: String? = nil,
    date: String? = nil
  ) {
    self.severity = severity
    self.code = code
    self.message = message
    self.stableId = stableId
    self.date = date
  }
}


public struct CommanderScheduleAuditPolicy: Equatable, Sendable {
  public let minimumProceduresMondayThroughSaturday: Int?
  public let sundayExpectedProcedureCount: Int?
  public let sundayExpectedMealTypes: Set<String>

  public init(
    minimumProceduresMondayThroughSaturday: Int? = nil,
    sundayExpectedProcedureCount: Int? = nil,
    sundayExpectedMealTypes: Set<String> = []
  ) {
    self.minimumProceduresMondayThroughSaturday = minimumProceduresMondayThroughSaturday
    self.sundayExpectedProcedureCount = sundayExpectedProcedureCount
    self.sundayExpectedMealTypes = sundayExpectedMealTypes
  }

  /// Operational expectation for Petr's spa stays. These are review warnings,
  /// not a claim that Czech law universally mandates this exact daily pattern.
  public static let petrSpaOperational = CommanderScheduleAuditPolicy(
    minimumProceduresMondayThroughSaturday: 3,
    sundayExpectedProcedureCount: 0,
    sundayExpectedMealTypes: ["Snídaně", "Oběd", "Večeře"]
  )
}

public struct CommanderScheduleAuditReport: Codable, Equatable, Sendable {
  public let scheduleVersion: Int
  public let stayFrom: String?
  public let stayTo: String?
  public let stayDayCount: Int?
  public let eventCount: Int
  public let procedureCount: Int
  public let mealCount: Int
  public let issues: [CommanderScheduleAuditIssue]

  public var hasErrors: Bool { issues.contains { $0.severity == .error } }
  public var needsReview: Bool { !issues.isEmpty }
  public var isClean: Bool { issues.isEmpty }
}

/// Safety-oriented structural audit of the canonical Commander schedule.
///
/// This intentionally does *not* claim that the schedule matches the paper source.
/// Source-to-canonical reconciliation is a separate acceptance layer because an
/// internally valid schedule can still contain a transcription/import mistake.
public enum CommanderScheduleAudit {
  public static func run(_ schedule: Schedule, policy: CommanderScheduleAuditPolicy = .init()) -> CommanderScheduleAuditReport {
    var issues: [CommanderScheduleAuditIssue] = []

    do {
      try NativeAlarmContract.validateCanonical(schedule)
    } catch {
      issues.append(.init(
        severity: .error,
        code: "canonical-validation",
        message: error.localizedDescription
      ))
    }

    let stayFrom = normalizedStayDate(schedule.stay["dateFrom"])
    let stayTo = normalizedStayDate(schedule.stay["dateTo"])
    let stayRange = parsedStayRange(from: stayFrom, to: stayTo, issues: &issues)

    var semanticKeys = Set<String>()
    let orderedEvents = schedule.events.sorted {
      ($0.date, $0.start, $0.end, $0.stableId) < ($1.date, $1.start, $1.end, $1.stableId)
    }

    for event in orderedEvents {
      if let range = stayRange,
         let eventDate = try? NativeAlarmContract.dateTime(date: event.date, time: "00:00"),
         (eventDate < range.from || eventDate > range.to) {
        issues.append(.init(
          severity: .error,
          code: "event-outside-stay",
          message: "Událost je mimo interval pobytu \(stayFrom ?? "?") až \(stayTo ?? "?").",
          stableId: event.stableId,
          date: event.date
        ))
      }

      let semanticKey = [
        event.date, event.start, event.end, event.title, event.location, event.kind.rawValue
      ].joined(separator: "|").precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "cs_CZ"))
      if !semanticKeys.insert(semanticKey).inserted {
        issues.append(.init(
          severity: .error,
          code: "semantic-duplicate",
          message: "Stejná událost je v rozpisu více než jednou.",
          stableId: event.stableId,
          date: event.date
        ))
      }
    }

    let eventsByDate = Dictionary(grouping: orderedEvents, by: \.date)
    for (date, dayEvents) in eventsByDate {
      let parsed = dayEvents.compactMap { event -> (ScheduleEvent, Date, Date)? in
        guard let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
              let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end)
        else { return nil }
        return (event, start, end)
      }.sorted { $0.1 < $1.1 }

      for pairIndex in 1..<parsed.count {
        let previous = parsed[pairIndex - 1]
        let current = parsed[pairIndex]
        if current.1 < previous.2 {
          issues.append(.init(
            severity: .warning,
            code: "overlap-review",
            message: "Časový překryv vyžaduje ruční kontrolu: \(previous.0.title) a \(current.0.title).",
            stableId: current.0.stableId,
            date: date
          ))
        }
      }
    }

    if let range = stayRange {
      auditOperationalExpectations(
        eventsByDate: eventsByDate,
        range: range,
        policy: policy,
        issues: &issues
      )

      let allDates = Set(schedule.events.map(\.date))
      var day = range.from
      while day <= range.to {
        let date = formatDate(day)
        if !allDates.contains(date) {
          issues.append(.init(
            severity: .warning,
            code: "day-without-events",
            message: "Den pobytu nemá v kanonickém rozpisu žádnou událost; ověřit proti zdrojovému papíru.",
            date: date
          ))
        }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
        day = next
      }
    }

    return CommanderScheduleAuditReport(
      scheduleVersion: schedule.scheduleVersion,
      stayFrom: stayFrom,
      stayTo: stayTo,
      stayDayCount: stayRange.map { inclusiveDayCount(from: $0.from, to: $0.to) },
      eventCount: schedule.events.count,
      procedureCount: schedule.events.filter { $0.kind == .procedure }.count,
      mealCount: schedule.events.filter { $0.kind == .meal }.count,
      issues: issues.sorted {
        ($0.date ?? "", $0.severity.rawValue, $0.code, $0.stableId ?? "") <
        ($1.date ?? "", $1.severity.rawValue, $1.code, $1.stableId ?? "")
      }
    )
  }

  private struct StayRange {
    let from: Date
    let to: Date
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar
  }

  private static func normalizedStayDate(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func auditOperationalExpectations(
    eventsByDate: [String: [ScheduleEvent]],
    range: StayRange,
    policy: CommanderScheduleAuditPolicy,
    issues: inout [CommanderScheduleAuditIssue]
  ) {
    var day = range.from
    while day <= range.to {
      let date = formatDate(day)
      let dayEvents = eventsByDate[date] ?? []
      let procedureCount = dayEvents.filter { $0.kind == .procedure }.count
      let weekday = calendar.component(.weekday, from: day)

      if weekday == 1 {
        if let expected = policy.sundayExpectedProcedureCount, procedureCount != expected {
          issues.append(.init(
            severity: .warning,
            code: "sunday-procedure-review",
            message: "Neděle má \(procedureCount) procedur, očekávání je \(expected); ověřit proti aktuálnímu papíru.",
            date: date
          ))
        }

        if !policy.sundayExpectedMealTypes.isEmpty {
          let actualMeals = Set(dayEvents.filter { $0.kind == .meal }.map {
            normalized($0.mealType ?? $0.title)
          })
          let missingMeals = policy.sundayExpectedMealTypes
            .filter { !actualMeals.contains(normalized($0)) }
            .sorted()
          if !missingMeals.isEmpty {
            issues.append(.init(
              severity: .warning,
              code: "sunday-meals-review",
              message: "V neděli chybí očekávané jídlo/jídla: \(missingMeals.joined(separator: ", ")); ověřit proti papíru.",
              date: date
            ))
          }
        }
      } else if let minimum = policy.minimumProceduresMondayThroughSaturday, procedureCount < minimum {
        issues.append(.init(
          severity: .warning,
          code: "low-procedure-count-review",
          message: "Den má jen \(procedureCount) procedur, provozní očekávání je alespoň \(minimum); ověřit proti papíru nebo lékařské změně.",
          date: date
        ))
      }

      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
  }

  private static func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
      .precomposedStringWithCanonicalMapping
      .lowercased(with: Locale(identifier: "cs_CZ"))
  }

  private static func parsedStayRange(
    from: String?,
    to: String?,
    issues: inout [CommanderScheduleAuditIssue]
  ) -> StayRange? {
    guard let from else {
      issues.append(.init(severity: .error, code: "missing-stay-from", message: "Chybí začátek pobytu (stay.dateFrom)."))
      return nil
    }
    guard let to else {
      issues.append(.init(severity: .error, code: "missing-stay-to", message: "Chybí konec pobytu (stay.dateTo)."))
      return nil
    }
    guard let start = try? NativeAlarmContract.dateTime(date: from, time: "00:00") else {
      issues.append(.init(severity: .error, code: "invalid-stay-from", message: "Neplatné datum začátku pobytu: \(from)."))
      return nil
    }
    guard let end = try? NativeAlarmContract.dateTime(date: to, time: "00:00") else {
      issues.append(.init(severity: .error, code: "invalid-stay-to", message: "Neplatné datum konce pobytu: \(to)."))
      return nil
    }
    guard end >= start else {
      issues.append(.init(severity: .error, code: "invalid-stay-range", message: "Konec pobytu je před začátkem pobytu."))
      return nil
    }
    return StayRange(from: start, to: end)
  }

  private static func inclusiveDayCount(from: Date, to: Date) -> Int {
    (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
  }

  private static func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}

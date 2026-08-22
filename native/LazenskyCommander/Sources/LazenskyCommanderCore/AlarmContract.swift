import Foundation

public enum NativeAlarmContract {
  public static let contractVersion = 1
  private static let prague = TimeZone(identifier: "Europe/Prague")!

  public static func validate(_ schedule: Schedule) throws {
    guard schedule.schemaVersion == 1 else { throw ScheduleValidationError.unsupportedSchemaVersion(schedule.schemaVersion) }
    guard schedule.scheduleVersion >= 0 else { throw ScheduleValidationError.invalidScheduleVersion }
    try validateLeadTime(schedule.settings.defaultLeadTimeMinutes, field: "settings.defaultLeadTimeMinutes")
    for (name, value) in schedule.settings.procedureTypeOverrides { try validateLeadTime(value, field: "settings.procedureTypeOverrides.\(name)") }
    for (name, value) in schedule.settings.mealOverrides { try validateLeadTime(value, field: "settings.mealOverrides.\(name)") }
    var stableIds = Set<String>()
    for event in schedule.events {
      for (name, value) in [("stableId", event.stableId), ("title", event.title), ("location", event.location)] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw ScheduleValidationError.missingField("events[].\(name)")
      }
      guard stableIds.insert(event.stableId).inserted else { throw ScheduleValidationError.duplicateStableId(event.stableId) }
      let start = try dateTime(date: event.date, time: event.start)
      let end = try dateTime(date: event.date, time: event.end)
      guard end >= start else { throw ScheduleValidationError.invalidEventRange(event.stableId) }
      if let leadTimeMinutes = event.leadTimeMinutes { try validateLeadTime(leadTimeMinutes, field: "events[].leadTimeMinutes") }
    }
  }

  public static func payload(schedule: Schedule, overrides: LeadTimeOverrides? = nil) throws -> NativeAlarmPayload {
    try validate(schedule)
    return try payloadValidated(schedule: schedule, overrides: overrides)
  }

  static func payloadValidated(schedule: Schedule, overrides: LeadTimeOverrides? = nil) throws -> NativeAlarmPayload {
    let alarms = try schedule.events.map {
      try alarm(event: $0, schedule: schedule, overrides: overrides)
    }.sorted { [$0.startAt, $0.endAt, $0.stableId].joined(separator: "|") < [$1.startAt, $1.endAt, $1.stableId].joined(separator: "|") }
    return NativeAlarmPayload(contractVersion: contractVersion, scheduleVersion: schedule.scheduleVersion, alarms: alarms)
  }

  static func alarm(event: ScheduleEvent, schedule: Schedule, overrides: LeadTimeOverrides? = nil) throws -> NativeAlarm {
    let startAt = try dateTime(date: event.date, time: event.start)
    let endAt = try dateTime(date: event.date, time: event.end)
    let leadTime = try effectiveLeadTime(event: event, schedule: schedule, overrides: overrides)
    let leaveAt = startAt.addingTimeInterval(TimeInterval(-leadTime * 60))
    return NativeAlarm(stableId: event.stableId, kind: event.kind, title: event.title, location: event.location, startAt: format(startAt), endAt: format(endAt), effectiveLeadTimeMinutes: leadTime, leaveAt: format(leaveAt))
  }

  public static func effectiveLeadTime(event: ScheduleEvent, schedule: Schedule, overrides: LeadTimeOverrides? = nil) throws -> Int {
    let type = normalized(event.kind == .meal ? (event.mealType ?? event.title) : (event.procedureType ?? event.title))
    if let value = overrides?.eventOverrides[event.stableId] { try validateLeadTime(value, field: "overrides.eventOverrides.\(event.stableId)"); return value }
    let localType = event.kind == .meal ? overrides?.mealOverrides : overrides?.procedureTypeOverrides
    if let value = value(for: type, in: localType) { try validateLeadTime(value, field: "overrides.type"); return value }
    if let value = overrides?.defaultLeadTimeMinutes { try validateLeadTime(value, field: "overrides.defaultLeadTimeMinutes"); return value }
    if let value = event.leadTimeMinutes { return value }
    let sourceType = event.kind == .meal ? schedule.settings.mealOverrides : schedule.settings.procedureTypeOverrides
    if let value = value(for: type, in: sourceType) { return value }
    return schedule.settings.defaultLeadTimeMinutes
  }

  public static func dateTime(date: String, time: String) throws -> Date {
    let dateParts = date.split(separator: "-").compactMap { Int($0) }
    guard dateParts.count == 3 else { throw ScheduleValidationError.invalidDate(date) }
    let timeParts = time.split(separator: ":").compactMap { Int($0) }
    guard timeParts.count == 2, (0...23).contains(timeParts[0]), (0...59).contains(timeParts[1]) else { throw ScheduleValidationError.invalidTime(time) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = prague
    let components = DateComponents(timeZone: prague, year: dateParts[0], month: dateParts[1], day: dateParts[2], hour: timeParts[0], minute: timeParts[1])
    guard let result = calendar.date(from: components) else { throw ScheduleValidationError.invalidDate(date) }
    let verified = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
    guard verified.year == dateParts[0], verified.month == dateParts[1], verified.day == dateParts[2], verified.hour == timeParts[0], verified.minute == timeParts[1] else { throw ScheduleValidationError.invalidDate(date) }
    return result
  }

  /// Parses the contract's timezone-free local ISO representation in Europe/Prague.
  public static func date(fromLocalISO value: String) throws -> Date {
    let parts = value.split(separator: "T", maxSplits: 1).map(String.init)
    guard parts.count == 2 else { throw ScheduleValidationError.invalidDate(value) }
    let time = parts[1].hasSuffix(":00") ? String(parts[1].dropLast(3)) : parts[1]
    return try dateTime(date: parts[0], time: time)
  }

  private static func validateLeadTime(_ value: Int, field: String) throws {
    guard (0...180).contains(value) else { throw ScheduleValidationError.invalidLeadTime(field) }
  }

  private static func normalized(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "cs_CZ"))
  }

  private static func value(for key: String, in values: [String: Int]?) -> Int? {
    values?.first(where: { normalized($0.key) == key })?.value
  }

  private static func format(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = prague
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formatter.string(from: date)
  }
}

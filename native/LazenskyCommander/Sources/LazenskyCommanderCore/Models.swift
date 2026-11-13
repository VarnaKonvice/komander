import Foundation

public enum ScheduleKind: String, Codable, Hashable, Sendable {
  case meal
  case procedure
}

public struct ScheduleEvent: Codable, Equatable, Sendable {
  public let stableId: String
  public let date: String
  public let start: String
  public let end: String
  public let title: String
  public let location: String
  public let kind: ScheduleKind
  public let procedureType: String?
  public let mealType: String?
  public let leadTimeMinutes: Int?

  public init(
    stableId: String, date: String, start: String, end: String, title: String, location: String,
    kind: ScheduleKind, procedureType: String? = nil, mealType: String? = nil,
    leadTimeMinutes: Int? = nil
  ) {
    self.stableId = stableId
    self.date = date
    self.start = start
    self.end = end
    self.title = title
    self.location = location
    self.kind = kind
    self.procedureType = procedureType
    self.mealType = mealType
    self.leadTimeMinutes = leadTimeMinutes
  }
}

public enum CommanderEventSemantics {
  public static func isVisit(_ event: ScheduleEvent) -> Bool {
    guard event.kind == .procedure else { return false }
    let value = [event.procedureType, event.title]
      .compactMap { $0 }
      .map(normalized)
      .joined(separator: " ")
    return [
      "vizita",
      "lekarska kontrola",
      "lekarska prohlidka",
      "kontrola u lekare",
      "prohlidka u lekare",
      "doctor visit"
    ].contains { value.contains($0) }
  }

  public static func isTherapy(_ event: ScheduleEvent) -> Bool {
    event.kind == .procedure && !isVisit(event)
  }

  public static func isSystemOnlyTestArtifact(_ event: ScheduleEvent) -> Bool {
    normalized(event.title).contains("alarmkit")
  }

  public static func calendarCategory(_ event: ScheduleEvent) -> String {
    if event.kind == .meal { return "Jídla" }
    if isVisit(event) { return "Vizity" }
    return "Procedury"
  }

  private static func normalized(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
      .lowercased(with: Locale(identifier: "cs_CZ"))
  }
}

public struct ScheduleSettings: Codable, Equatable, Sendable {
  public let defaultLeadTimeMinutes: Int
  public let procedureTypeOverrides: [String: Int]
  public let mealOverrides: [String: Int]

  public init(
    defaultLeadTimeMinutes: Int,
    procedureTypeOverrides: [String: Int] = [:],
    mealOverrides: [String: Int] = [:]
  ) {
    self.defaultLeadTimeMinutes = defaultLeadTimeMinutes
    self.procedureTypeOverrides = procedureTypeOverrides
    self.mealOverrides = mealOverrides
  }
}

public struct Schedule: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let scheduleVersion: Int
  public let updatedAt: String
  public let stay: [String: String]
  public let events: [ScheduleEvent]
  public let settings: ScheduleSettings

  public init(
    schemaVersion: Int, scheduleVersion: Int, updatedAt: String,
    stay: [String: String], events: [ScheduleEvent], settings: ScheduleSettings
  ) {
    self.schemaVersion = schemaVersion
    self.scheduleVersion = scheduleVersion
    self.updatedAt = updatedAt
    self.stay = stay
    self.events = events
    self.settings = settings
  }
}



public enum CommanderProcedureCategory: String, Codable, CaseIterable, Sendable {
  case rehabilitation
  case electro
  case water
  case massage
  case heatWrap
  case other

  public static func classify(_ value: String) -> CommanderProcedureCategory {
    let normalized = value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
      .lowercased(with: Locale(identifier: "cs_CZ"))

    if ["jodobrom", "parafin", "parafango", "slatin", "raselin", "zabal"].contains(where: normalized.contains) {
      return .heatWrap
    }
    if ["elektro", "magnet", "ultrazvuk", "galvan", "ctyrkomor", "razov", "shockwave"].contains(where: normalized.contains) {
      return .electro
    }
    if ["hydrojet", "hydro jet", "masaz"].contains(where: normalized.contains) {
      return .massage
    }
    if ["vodolec", "viriv", "whirlpool", "perlick", "uhlicit", "bazen", "plav", "koupel"].contains(where: normalized.contains) {
      return .water
    }
    if ["imoove", "i-moove", "fyzioter", "fyzio", "rehab", "ltv", "ergoter", "cvic", "chuze", "chodici pas", "walking pas", "senzomotor", "motodlaha"].contains(where: normalized.contains) {
      return .rehabilitation
    }
    return .other
  }
}

public struct LeadTimeOverrides: Codable, Equatable, Sendable {
  public var defaultLeadTimeMinutes: Int?
  public var procedureTypeOverrides: [String: Int]
  public var procedureCategoryOverrides: [String: Int]
  public var mealOverrides: [String: Int]
  public var eventOverrides: [String: Int]

  public init(
    defaultLeadTimeMinutes: Int? = nil,
    procedureTypeOverrides: [String: Int] = [:],
    procedureCategoryOverrides: [String: Int] = [:],
    mealOverrides: [String: Int] = [:],
    eventOverrides: [String: Int] = [:]
  ) {
    self.defaultLeadTimeMinutes = defaultLeadTimeMinutes
    self.procedureTypeOverrides = procedureTypeOverrides
    self.procedureCategoryOverrides = procedureCategoryOverrides
    self.mealOverrides = mealOverrides
    self.eventOverrides = eventOverrides
  }

  private enum CodingKeys: String, CodingKey {
    case defaultLeadTimeMinutes
    case procedureTypeOverrides
    case procedureCategoryOverrides
    case mealOverrides
    case eventOverrides
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    defaultLeadTimeMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultLeadTimeMinutes)
    procedureTypeOverrides = try values.decodeIfPresent([String: Int].self, forKey: .procedureTypeOverrides) ?? [:]
    procedureCategoryOverrides = try values.decodeIfPresent([String: Int].self, forKey: .procedureCategoryOverrides) ?? [:]
    mealOverrides = try values.decodeIfPresent([String: Int].self, forKey: .mealOverrides) ?? [:]
    eventOverrides = try values.decodeIfPresent([String: Int].self, forKey: .eventOverrides) ?? [:]
  }
}

public struct NativeAlarm: Codable, Equatable, Sendable {
  public let stableId: String
  public let kind: ScheduleKind
  public let title: String
  public let location: String
  public let startAt: String
  public let endAt: String
  public let effectiveLeadTimeMinutes: Int
  public let leaveAt: String

  public init(stableId: String, kind: ScheduleKind, title: String, location: String, startAt: String, endAt: String, effectiveLeadTimeMinutes: Int, leaveAt: String) {
    self.stableId = stableId
    self.kind = kind
    self.title = title
    self.location = location
    self.startAt = startAt
    self.endAt = endAt
    self.effectiveLeadTimeMinutes = effectiveLeadTimeMinutes
    self.leaveAt = leaveAt
  }
}

public struct NativeAlarmPayload: Codable, Equatable, Sendable {
  public let contractVersion: Int
  public let scheduleVersion: Int
  public let alarms: [NativeAlarm]

  public init(contractVersion: Int = 1, scheduleVersion: Int, alarms: [NativeAlarm]) {
    self.contractVersion = contractVersion
    self.scheduleVersion = scheduleVersion
    self.alarms = alarms
  }
}

public enum ScheduleValidationError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case invalidScheduleVersion
  case invalidUpdatedAt(String)
  case duplicateStableId(String)
  case missingField(String)
  case invalidDate(String)
  case invalidTime(String)
  case invalidEventRange(String)
  case invalidLeadTime(String)
  case systemOnlyEvent(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version): return "Unsupported schemaVersion: \(version)."
    case .invalidScheduleVersion: return "Canonical scheduleVersion must be positive."
    case .invalidUpdatedAt(let value): return "Invalid updatedAt: \(value)."
    case .duplicateStableId(let stableId): return "Duplicate stableId: \(stableId)."
    case .missingField(let field): return "Missing required field: \(field)."
    case .invalidDate(let value): return "Invalid date: \(value)."
    case .invalidTime(let value): return "Invalid time: \(value)."
    case .invalidEventRange(let stableId): return "Event ends before it starts: \(stableId)."
    case .invalidLeadTime(let field): return "Invalid lead time: \(field)."
    case .systemOnlyEvent(let stableId): return "Interní testovací událost nesmí být součástí klientského rozpisu: \(stableId)."
    }
  }
}

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
}

public struct ScheduleSettings: Codable, Equatable, Sendable {
  public let defaultLeadTimeMinutes: Int
  public let procedureTypeOverrides: [String: Int]
  public let mealOverrides: [String: Int]
}

public struct Schedule: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let scheduleVersion: Int
  public let updatedAt: String
  public let stay: [String: String]
  public let events: [ScheduleEvent]
  public let settings: ScheduleSettings
}

public struct LeadTimeOverrides: Codable, Equatable, Sendable {
  public var defaultLeadTimeMinutes: Int?
  public var procedureTypeOverrides: [String: Int]
  public var mealOverrides: [String: Int]
  public var eventOverrides: [String: Int]

  public init(defaultLeadTimeMinutes: Int? = nil, procedureTypeOverrides: [String: Int] = [:], mealOverrides: [String: Int] = [:], eventOverrides: [String: Int] = [:]) {
    self.defaultLeadTimeMinutes = defaultLeadTimeMinutes
    self.procedureTypeOverrides = procedureTypeOverrides
    self.mealOverrides = mealOverrides
    self.eventOverrides = eventOverrides
  }

  private enum CodingKeys: String, CodingKey {
    case defaultLeadTimeMinutes
    case procedureTypeOverrides
    case mealOverrides
    case eventOverrides
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    defaultLeadTimeMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultLeadTimeMinutes)
    procedureTypeOverrides = try values.decodeIfPresent([String: Int].self, forKey: .procedureTypeOverrides) ?? [:]
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
  case invalidUpdatedAt
  case duplicateStableId(String)
  case missingField(String)
  case invalidDate(String)
  case invalidTime(String)
  case invalidEventRange(String)
  case invalidLeadTime(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version): return "Unsupported schemaVersion: \(version)."
    case .invalidScheduleVersion: return "scheduleVersion must be positive for a canonical schedule."
    case .invalidUpdatedAt: return "updatedAt must be a valid ISO-8601 timestamp."
    case .duplicateStableId(let stableId): return "Duplicate stableId: \(stableId)."
    case .missingField(let field): return "Missing required field: \(field)."
    case .invalidDate(let value): return "Invalid date: \(value)."
    case .invalidTime(let value): return "Invalid time: \(value)."
    case .invalidEventRange(let stableId): return "Event ends before it starts: \(stableId)."
    case .invalidLeadTime(let field): return "Invalid lead time: \(field)."
    }
  }
}

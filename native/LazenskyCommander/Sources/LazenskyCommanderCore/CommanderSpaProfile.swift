import Foundation

public struct CommanderSpaProfile: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let profileVersion: Int
  public let spaID: String
  public let displayName: String
  public let timeZoneIdentifier: String
  public let procedures: [CommanderSpaProcedureDefinition]
  public let mealShifts: [CommanderSpaMealShift]

  public init(
    schemaVersion: Int = 1,
    profileVersion: Int,
    spaID: String,
    displayName: String,
    timeZoneIdentifier: String = "Europe/Prague",
    procedures: [CommanderSpaProcedureDefinition],
    mealShifts: [CommanderSpaMealShift] = []
  ) {
    self.schemaVersion = schemaVersion
    self.profileVersion = profileVersion
    self.spaID = spaID
    self.displayName = displayName
    self.timeZoneIdentifier = timeZoneIdentifier
    self.procedures = procedures
    self.mealShifts = mealShifts
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw CommanderSpaProfileValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard profileVersion > 0 else {
      throw CommanderSpaProfileValidationError.invalidProfileVersion
    }
    guard !spaID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("spaID")
    }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("displayName")
    }
    guard TimeZone(identifier: timeZoneIdentifier) != nil else {
      throw CommanderSpaProfileValidationError.invalidTimeZone(timeZoneIdentifier)
    }

    var procedureKeys: Set<String> = []
    for procedure in procedures {
      try procedure.validate()
      for key in procedure.lookupKeys {
        guard procedureKeys.insert(key).inserted else {
          throw CommanderSpaProfileValidationError.duplicateProcedureAlias(key)
        }
      }
    }

    var shiftIDs: Set<String> = []
    for shift in mealShifts {
      try shift.validate()
      let normalizedID = Self.normalizedLookupKey(shift.id)
      guard shiftIDs.insert(normalizedID).inserted else {
        throw CommanderSpaProfileValidationError.duplicateMealShift(shift.id)
      }
    }
  }

  public func procedureDefinition(matching rawValue: String) -> CommanderSpaProcedureDefinition? {
    let key = Self.normalizedLookupKey(rawValue)
    guard !key.isEmpty else { return nil }
    return procedures.first { $0.lookupKeys.contains(key) }
  }

  public static func normalizedLookupKey(_ value: String) -> String {
    value
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
      .lowercased(with: Locale(identifier: "cs_CZ"))
      .split(whereSeparator: { $0.isWhitespace || $0 == "." || $0 == "-" || $0 == "_" })
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

public struct CommanderSpaProcedureDefinition: Codable, Equatable, Sendable {
  public let canonicalType: String
  public let displayName: String
  public let aliases: [String]
  public let category: CommanderProcedureCategory
  public let expectedDurationMinutes: Int?
  public let defaultLeadTimeMinutes: Int?

  public init(
    canonicalType: String,
    displayName: String,
    aliases: [String] = [],
    category: CommanderProcedureCategory,
    expectedDurationMinutes: Int? = nil,
    defaultLeadTimeMinutes: Int? = nil
  ) {
    self.canonicalType = canonicalType
    self.displayName = displayName
    self.aliases = aliases
    self.category = category
    self.expectedDurationMinutes = expectedDurationMinutes
    self.defaultLeadTimeMinutes = defaultLeadTimeMinutes
  }

  fileprivate var lookupKeys: Set<String> {
    Set(([canonicalType, displayName] + aliases).map(CommanderSpaProfile.normalizedLookupKey).filter { !$0.isEmpty })
  }

  fileprivate func validate() throws {
    guard !canonicalType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("procedure.canonicalType")
    }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("procedure.displayName")
    }
    if let expectedDurationMinutes, !(1...480).contains(expectedDurationMinutes) {
      throw CommanderSpaProfileValidationError.invalidProcedureDuration(canonicalType)
    }
    if let defaultLeadTimeMinutes, !(0...180).contains(defaultLeadTimeMinutes) {
      throw CommanderSpaProfileValidationError.invalidLeadTime(canonicalType)
    }
  }
}

public struct CommanderSpaMealShift: Codable, Equatable, Sendable {
  public let id: String
  public let displayName: String
  public let meals: [CommanderSpaMealTemplate]

  public init(id: String, displayName: String, meals: [CommanderSpaMealTemplate]) {
    self.id = id
    self.displayName = displayName
    self.meals = meals
  }

  fileprivate func validate() throws {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("mealShift.id")
    }
    guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("mealShift.displayName")
    }
    var mealTypes: Set<String> = []
    for meal in meals {
      try meal.validate()
      let key = CommanderSpaProfile.normalizedLookupKey(meal.mealType)
      guard mealTypes.insert(key).inserted else {
        throw CommanderSpaProfileValidationError.duplicateMealType(meal.mealType)
      }
    }
  }
}

public struct CommanderSpaMealTemplate: Codable, Equatable, Sendable {
  public let mealType: String
  public let start: String
  public let end: String

  public init(mealType: String, start: String, end: String) {
    self.mealType = mealType
    self.start = start
    self.end = end
  }

  fileprivate func validate() throws {
    guard !mealType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("meal.mealType")
    }
    guard Self.minutes(start) != nil else {
      throw CommanderSpaProfileValidationError.invalidTime(start)
    }
    guard Self.minutes(end) != nil else {
      throw CommanderSpaProfileValidationError.invalidTime(end)
    }
    guard let startMinutes = Self.minutes(start),
          let endMinutes = Self.minutes(end),
          endMinutes > startMinutes
    else {
      throw CommanderSpaProfileValidationError.invalidMealRange(mealType)
    }
  }

  private static func minutes(_ value: String) -> Int? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (0...23).contains(hour),
          (0...59).contains(minute)
    else { return nil }
    return hour * 60 + minute
  }
}

public enum CommanderSpaProfileValidationError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case invalidProfileVersion
  case missingField(String)
  case invalidTimeZone(String)
  case duplicateProcedureAlias(String)
  case invalidProcedureDuration(String)
  case invalidLeadTime(String)
  case duplicateMealShift(String)
  case duplicateMealType(String)
  case invalidTime(String)
  case invalidMealRange(String)

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported spa profile schemaVersion: \(version)."
    case .invalidProfileVersion:
      return "Spa profileVersion must be positive."
    case .missingField(let field):
      return "Missing spa profile field: \(field)."
    case .invalidTimeZone(let value):
      return "Invalid spa profile time zone: \(value)."
    case .duplicateProcedureAlias(let value):
      return "Ambiguous procedure alias: \(value)."
    case .invalidProcedureDuration(let value):
      return "Invalid expected procedure duration: \(value)."
    case .invalidLeadTime(let value):
      return "Invalid default procedure lead time: \(value)."
    case .duplicateMealShift(let value):
      return "Duplicate meal shift: \(value)."
    case .duplicateMealType(let value):
      return "Duplicate meal type in one shift: \(value)."
    case .invalidTime(let value):
      return "Invalid spa profile time: \(value)."
    case .invalidMealRange(let value):
      return "Meal end must be after start: \(value)."
    }
  }
}

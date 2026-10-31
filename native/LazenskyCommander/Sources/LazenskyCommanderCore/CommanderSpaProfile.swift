import Foundation

public struct CommanderSpaProfile: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let profileVersion: Int
  public let spaID: String
  public let displayName: String
  public let timeZoneIdentifier: String
  public let procedures: [CommanderSpaProcedureDefinition]
  public let continuationRules: [CommanderSpaContinuationRule]
  public let scheduleAuditRules: CommanderSpaScheduleAuditRules?
  public let mealShifts: [CommanderSpaMealShift]

  public init(
    schemaVersion: Int = 1,
    profileVersion: Int,
    spaID: String,
    displayName: String,
    timeZoneIdentifier: String = "Europe/Prague",
    procedures: [CommanderSpaProcedureDefinition],
    continuationRules: [CommanderSpaContinuationRule] = [],
    scheduleAuditRules: CommanderSpaScheduleAuditRules? = nil,
    mealShifts: [CommanderSpaMealShift] = []
  ) {
    self.schemaVersion = schemaVersion
    self.profileVersion = profileVersion
    self.spaID = spaID
    self.displayName = displayName
    self.timeZoneIdentifier = timeZoneIdentifier
    self.procedures = procedures
    self.continuationRules = continuationRules
    self.scheduleAuditRules = scheduleAuditRules
    self.mealShifts = mealShifts
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case profileVersion
    case spaID
    case displayName
    case timeZoneIdentifier
    case procedures
    case continuationRules
    case scheduleAuditRules
    case mealShifts
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    profileVersion = try values.decode(Int.self, forKey: .profileVersion)
    spaID = try values.decode(String.self, forKey: .spaID)
    displayName = try values.decode(String.self, forKey: .displayName)
    timeZoneIdentifier = try values.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? "Europe/Prague"
    procedures = try values.decodeIfPresent([CommanderSpaProcedureDefinition].self, forKey: .procedures) ?? []
    continuationRules = try values.decodeIfPresent([CommanderSpaContinuationRule].self, forKey: .continuationRules) ?? []
    scheduleAuditRules = try values.decodeIfPresent(CommanderSpaScheduleAuditRules.self, forKey: .scheduleAuditRules)
    mealShifts = try values.decodeIfPresent([CommanderSpaMealShift].self, forKey: .mealShifts) ?? []
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(schemaVersion, forKey: .schemaVersion)
    try values.encode(profileVersion, forKey: .profileVersion)
    try values.encode(spaID, forKey: .spaID)
    try values.encode(displayName, forKey: .displayName)
    try values.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    try values.encode(procedures, forKey: .procedures)
    try values.encode(continuationRules, forKey: .continuationRules)
    try values.encodeIfPresent(scheduleAuditRules, forKey: .scheduleAuditRules)
    try values.encode(mealShifts, forKey: .mealShifts)
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

    let canonicalTypes = Set(procedures.map {
      Self.normalizedLookupKey($0.canonicalType)
    })
    var continuationPairs: Set<String> = []
    for rule in continuationRules {
      try rule.validate(knownProcedureTypes: canonicalTypes)
      guard continuationPairs.insert(rule.normalizedPairKey).inserted else {
        throw CommanderSpaProfileValidationError.duplicateContinuationRule(rule.normalizedPairKey)
      }
    }

    try scheduleAuditRules?.validate()

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

public struct CommanderSpaScheduleAuditRules: Codable, Equatable, Sendable {
  public let minimumProceduresMondayThroughSaturday: Int?
  public let sundayExpectedProcedureCount: Int?
  public let sundayExpectedMealTypes: [String]

  public init(
    minimumProceduresMondayThroughSaturday: Int? = nil,
    sundayExpectedProcedureCount: Int? = nil,
    sundayExpectedMealTypes: [String] = []
  ) {
    self.minimumProceduresMondayThroughSaturday = minimumProceduresMondayThroughSaturday
    self.sundayExpectedProcedureCount = sundayExpectedProcedureCount
    self.sundayExpectedMealTypes = sundayExpectedMealTypes
  }

  public var auditPolicy: CommanderScheduleAuditPolicy {
    CommanderScheduleAuditPolicy(
      minimumProceduresMondayThroughSaturday: minimumProceduresMondayThroughSaturday,
      sundayExpectedProcedureCount: sundayExpectedProcedureCount,
      sundayExpectedMealTypes: Set(sundayExpectedMealTypes)
    )
  }

  fileprivate func validate() throws {
    if let minimumProceduresMondayThroughSaturday,
       !(0...100).contains(minimumProceduresMondayThroughSaturday) {
      throw CommanderSpaProfileValidationError.invalidAuditProcedureCount(
        "minimumProceduresMondayThroughSaturday"
      )
    }
    if let sundayExpectedProcedureCount,
       !(0...100).contains(sundayExpectedProcedureCount) {
      throw CommanderSpaProfileValidationError.invalidAuditProcedureCount(
        "sundayExpectedProcedureCount"
      )
    }

    var mealKeys: Set<String> = []
    for mealType in sundayExpectedMealTypes {
      let key = CommanderSpaProfile.normalizedLookupKey(mealType)
      guard !key.isEmpty else {
        throw CommanderSpaProfileValidationError.missingField("scheduleAuditRules.sundayExpectedMealTypes")
      }
      guard mealKeys.insert(key).inserted else {
        throw CommanderSpaProfileValidationError.duplicateAuditMealType(mealType)
      }
    }
  }
}

public struct CommanderSpaContinuationRule: Codable, Equatable, Sendable {
  public let fromCanonicalType: String
  public let toCanonicalType: String
  public let maximumGapMinutes: Int
  public let requiresSameLocation: Bool

  public init(
    fromCanonicalType: String,
    toCanonicalType: String,
    maximumGapMinutes: Int,
    requiresSameLocation: Bool = false
  ) {
    self.fromCanonicalType = fromCanonicalType
    self.toCanonicalType = toCanonicalType
    self.maximumGapMinutes = maximumGapMinutes
    self.requiresSameLocation = requiresSameLocation
  }

  fileprivate var normalizedPairKey: String {
    let from = CommanderSpaProfile.normalizedLookupKey(fromCanonicalType)
    let to = CommanderSpaProfile.normalizedLookupKey(toCanonicalType)
    return "\(from)->\(to)"
  }

  fileprivate func validate(knownProcedureTypes: Set<String>) throws {
    let from = CommanderSpaProfile.normalizedLookupKey(fromCanonicalType)
    let to = CommanderSpaProfile.normalizedLookupKey(toCanonicalType)
    guard !from.isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("continuation.fromCanonicalType")
    }
    guard !to.isEmpty else {
      throw CommanderSpaProfileValidationError.missingField("continuation.toCanonicalType")
    }
    guard knownProcedureTypes.contains(from) else {
      throw CommanderSpaProfileValidationError.unknownContinuationProcedure(fromCanonicalType)
    }
    guard knownProcedureTypes.contains(to) else {
      throw CommanderSpaProfileValidationError.unknownContinuationProcedure(toCanonicalType)
    }
    guard (0...180).contains(maximumGapMinutes) else {
      throw CommanderSpaProfileValidationError.invalidContinuationGap(normalizedPairKey)
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
  case unknownContinuationProcedure(String)
  case invalidContinuationGap(String)
  case duplicateContinuationRule(String)
  case invalidAuditProcedureCount(String)
  case duplicateAuditMealType(String)
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
    case .unknownContinuationProcedure(let value):
      return "Unknown procedure in continuation rule: \(value)."
    case .invalidContinuationGap(let value):
      return "Invalid continuation gap: \(value)."
    case .duplicateContinuationRule(let value):
      return "Duplicate continuation rule: \(value)."
    case .invalidAuditProcedureCount(let value):
      return "Invalid schedule audit procedure count: \(value)."
    case .duplicateAuditMealType(let value):
      return "Duplicate schedule audit meal type: \(value)."
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

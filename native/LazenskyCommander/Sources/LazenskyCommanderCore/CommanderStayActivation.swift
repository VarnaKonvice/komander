import Foundation

public enum CommanderStayActivationSource: String, Codable, Equatable, Sendable {
  case spaContract
  case appleIAP
  case web
  case complimentary
}

public enum CommanderStayActivationState: String, Codable, Equatable, Sendable {
  case processing
  case paymentRequired
  case active
  case expired
  case revoked
}

public struct CommanderStayActivation: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let activationID: String
  public let stayID: String
  public let state: CommanderStayActivationState
  public let source: CommanderStayActivationSource?
  public let updatedAt: String
  public let validFrom: String?
  public let validUntil: String?

  public init(
    schemaVersion: Int = 1,
    activationID: String,
    stayID: String,
    state: CommanderStayActivationState,
    source: CommanderStayActivationSource? = nil,
    updatedAt: String,
    validFrom: String? = nil,
    validUntil: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.activationID = activationID
    self.stayID = stayID
    self.state = state
    self.source = source
    self.updatedAt = updatedAt
    self.validFrom = validFrom
    self.validUntil = validUntil
  }

  public func validate() throws {
    guard schemaVersion == 1 else {
      throw CommanderStayActivationValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard !activationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderStayActivationValidationError.missingField("activationID")
    }
    guard !stayID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CommanderStayActivationValidationError.missingField("stayID")
    }
    guard Self.parseTimestamp(updatedAt) != nil else {
      throw CommanderStayActivationValidationError.invalidTimestamp("updatedAt")
    }

    let from = try Self.optionalTimestamp(validFrom, field: "validFrom")
    let until = try Self.optionalTimestamp(validUntil, field: "validUntil")
    if let from, let until, until < from {
      throw CommanderStayActivationValidationError.invalidValidityRange
    }

    if state == .active, source == nil {
      throw CommanderStayActivationValidationError.activeWithoutSource
    }
  }

  private static func optionalTimestamp(_ value: String?, field: String) throws -> Date? {
    guard let value else { return nil }
    guard let parsed = parseTimestamp(value) else {
      throw CommanderStayActivationValidationError.invalidTimestamp(field)
    }
    return parsed
  }

  private static func parseTimestamp(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }
}

public enum CommanderStayAccessResolution: Equatable, Sendable {
  case legacyUnmanaged
  case activationMissing
  case processing
  case paymentRequired
  case active(CommanderStayActivationSource)
  case expired
  case revoked

  public var permitsScheduleUse: Bool {
    switch self {
    case .legacyUnmanaged, .active:
      true
    case .activationMissing, .processing, .paymentRequired, .expired, .revoked:
      false
    }
  }

  public var requiresCustomerPayment: Bool {
    self == .paymentRequired
  }
}

public struct CommanderStayAccessPolicy: Equatable, Sendable {
  public let requiresActivation: Bool

  public init(requiresActivation: Bool = false) {
    self.requiresActivation = requiresActivation
  }

  public func resolve(_ activation: CommanderStayActivation?) throws -> CommanderStayAccessResolution {
    guard let activation else {
      return requiresActivation ? .activationMissing : .legacyUnmanaged
    }

    try activation.validate()
    switch activation.state {
    case .processing:
      return .processing
    case .paymentRequired:
      return .paymentRequired
    case .active:
      guard let source = activation.source else {
        throw CommanderStayActivationValidationError.activeWithoutSource
      }
      return .active(source)
    case .expired:
      return .expired
    case .revoked:
      return .revoked
    }
  }
}

public enum CommanderStayActivationValidationError: LocalizedError, Equatable {
  case unsupportedSchemaVersion(Int)
  case missingField(String)
  case invalidTimestamp(String)
  case invalidValidityRange
  case activeWithoutSource

  public var errorDescription: String? {
    switch self {
    case .unsupportedSchemaVersion(let version):
      return "Unsupported stay activation schemaVersion: \(version)."
    case .missingField(let field):
      return "Missing stay activation field: \(field)."
    case .invalidTimestamp(let field):
      return "Invalid stay activation timestamp: \(field)."
    case .invalidValidityRange:
      return "Stay activation validUntil must not be before validFrom."
    case .activeWithoutSource:
      return "Active stay activation requires an activation source."
    }
  }
}

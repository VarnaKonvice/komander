import Foundation

public enum CommanderSpaProfileResolution: Equatable, Sendable {
  case matched(CommanderSpaProfile)
  case genericMissingSpaID
  case genericUnknownSpaID(String)

  public var profile: CommanderSpaProfile? {
    guard case .matched(let profile) = self else { return nil }
    return profile
  }

  public var isGeneric: Bool { profile == nil }
}

public enum CommanderSpaProfileCatalogError: LocalizedError, Equatable {
  case duplicateSpaID(String)

  public var errorDescription: String? {
    switch self {
    case .duplicateSpaID(let spaID):
      return "Duplicate spa profile ID: \(spaID)."
    }
  }
}

public struct CommanderSpaProfileCatalog: Sendable {
  private let profilesByID: [String: CommanderSpaProfile]

  public static let empty = CommanderSpaProfileCatalog(uncheckedProfiles: [])

  public init(profiles: [CommanderSpaProfile]) throws {
    var resolved: [String: CommanderSpaProfile] = [:]
    for profile in profiles {
      try profile.validate()
      let key = Self.normalizedSpaID(profile.spaID)
      guard resolved[key] == nil else {
        throw CommanderSpaProfileCatalogError.duplicateSpaID(profile.spaID)
      }
      resolved[key] = profile
    }
    profilesByID = resolved
  }

  private init(uncheckedProfiles profiles: [CommanderSpaProfile]) {
    profilesByID = Dictionary(
      uniqueKeysWithValues: profiles.map { (Self.normalizedSpaID($0.spaID), $0) }
    )
  }

  public func resolve(schedule: Schedule) -> CommanderSpaProfileResolution {
    guard
      let rawSpaID = schedule.stay["spaID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      !rawSpaID.isEmpty
    else {
      return .genericMissingSpaID
    }

    let key = Self.normalizedSpaID(rawSpaID)
    guard let profile = profilesByID[key] else {
      return .genericUnknownSpaID(rawSpaID)
    }
    return .matched(profile)
  }

  public func profile(spaID: String) -> CommanderSpaProfile? {
    profilesByID[Self.normalizedSpaID(spaID)]
  }

  private static func normalizedSpaID(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
  }
}

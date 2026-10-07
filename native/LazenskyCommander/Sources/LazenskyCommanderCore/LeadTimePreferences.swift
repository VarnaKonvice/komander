import Foundation

public struct LeadTimePreferences: Codable {
  public let overrides: LeadTimeOverrides
  public let revision: Int

  public init(overrides: LeadTimeOverrides, revision: Int) {
    self.overrides = overrides
    self.revision = revision
  }
}

@MainActor
public final class LeadTimePreferencesStore {
  private let defaults: UserDefaults
  private let key: String
  private let isPersistent: Bool

  public init(defaults: UserDefaults = .standard, key: String, isPersistent: Bool = true) {
    self.defaults = defaults
    self.key = key
    self.isPersistent = isPersistent
  }

  public func load() -> LeadTimePreferences {
    guard
      isPersistent,
      let data = defaults.data(forKey: key),
      let saved = try? JSONDecoder().decode(LeadTimePreferences.self, from: data)
    else {
      return LeadTimePreferences(overrides: LeadTimeOverrides(), revision: 0)
    }
    return LeadTimePreferences(
      overrides: Self.normalized(saved.overrides),
      revision: max(0, saved.revision)
    )
  }

  public func save(_ preferences: LeadTimePreferences) {
    guard isPersistent, let data = try? JSONEncoder().encode(preferences) else { return }
    defaults.set(data, forKey: key)
  }

  public static func normalized(_ overrides: LeadTimeOverrides) -> LeadTimeOverrides {
    LeadTimeOverrides(
      defaultLeadTimeMinutes: valid(overrides.defaultLeadTimeMinutes),
      procedureTypeOverrides: valid(overrides.procedureTypeOverrides),
      procedureCategoryOverrides: valid(overrides.procedureCategoryOverrides),
      mealOverrides: valid(overrides.mealOverrides),
      eventOverrides: valid(overrides.eventOverrides)
    )
  }

  private static func valid(_ value: Int?) -> Int? {
    guard let value, (0...180).contains(value) else { return nil }
    return value
  }

  private static func valid(_ values: [String: Int]) -> [String: Int] {
    values.filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (0...180).contains($0.value) }
  }
}

/// Preview selection is launch-local; legacy UserDefaults flags are never consulted.
public enum CommanderPreviewPolicy {
  public static func enabled(arguments: [String]) -> Bool {
    !arguments.contains("-CommanderDisableDesignPreview") &&
      (arguments.contains("-CommanderDesignPreview") || arguments.contains("-CommanderApprovedVisualProof"))
  }
}

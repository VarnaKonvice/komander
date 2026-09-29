import Foundation

/// A write-ahead ownership ledger. Reserve before calling the platform so an interrupted
/// schedule can retry the same ID, even if ManagedAlarmState was never saved.
public actor FileAlarmOwnershipStore {
  private let defaults: UserDefaults
  private let directoryURL: URL
  private let fileURL: URL
  private let legacyStateKey: String
  private let legacyOwnershipKey: String?

  public init(defaults: UserDefaults = .standard, directoryURL: URL, key: String,
              legacyStateKey: String, legacyOwnershipKey: String? = nil) {
    self.defaults = defaults
    self.directoryURL = directoryURL
    self.fileURL = directoryURL.appendingPathComponent(key + ".json")
    self.legacyStateKey = legacyStateKey
    self.legacyOwnershipKey = legacyOwnershipKey
  }

  private func load() throws -> [String: String] {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: fileURL))
    }
    var owned: [String: String] = [:]
    if let data = defaults.data(forKey: legacyStateKey) {
      let state = try JSONDecoder().decode(ManagedAlarmState.self, from: data)
      for record in state.records.values { owned[record.stableId] = record.platformAlarmID }
    }
    if let legacyOwnershipKey {
      for id in defaults.stringArray(forKey: legacyOwnershipKey) ?? []
        where !owned.values.contains(id) {
        owned["legacy:" + id] = id
      }
    }
    return owned
  }

  public func ids() throws -> Set<String> { Set(try load().values) }

  public func reserve(stableID: String) throws -> String {
    var owned = try load()
    let id = owned[stableID] ?? UUID().uuidString
    owned[stableID] = id
    try save(owned)
    return id
  }

  public func forget(_ id: String) throws {
    var owned = try load()
    owned = owned.filter { $0.value != id }
    try save(owned)
  }

  private func save(_ owned: [String: String]) throws {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try JSONEncoder().encode(owned).write(to: fileURL, options: .atomic)
  }
}

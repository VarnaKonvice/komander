import Foundation

public struct ManagedAlarmRecord: Codable, Equatable, Sendable {
  public let stableId: String
  public let platformAlarmID: String
  public let alarm: NativeAlarm

  public init(stableId: String, platformAlarmID: String, alarm: NativeAlarm) {
    self.stableId = stableId
    self.platformAlarmID = platformAlarmID
    self.alarm = alarm
  }
}

public struct ManagedAlarmState: Codable, Equatable, Sendable {
  public var records: [String: ManagedAlarmRecord]
  public var lastSuccessfulPayload: NativeAlarmPayload?
  public var lastSuccessfulSync: Date?

  public init(records: [String: ManagedAlarmRecord] = [:], lastSuccessfulPayload: NativeAlarmPayload? = nil, lastSuccessfulSync: Date? = nil) {
    self.records = records
    self.lastSuccessfulPayload = lastSuccessfulPayload
    self.lastSuccessfulSync = lastSuccessfulSync
  }
}

public protocol AlarmStateStoring: Sendable {
  func load() async throws -> ManagedAlarmState
  func save(_ state: ManagedAlarmState) async throws
}

public actor UserDefaultsAlarmStateStore: AlarmStateStoring {
  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "lazensky.commander.managedAlarms.v1") {
    self.defaults = defaults
    self.key = key
  }

  public func load() throws -> ManagedAlarmState {
    guard let data = defaults.data(forKey: key) else { return ManagedAlarmState() }
    return try JSONDecoder().decode(ManagedAlarmState.self, from: data)
  }

  public func save(_ state: ManagedAlarmState) throws {
    defaults.set(try JSONEncoder().encode(state), forKey: key)
  }
}

public actor InMemoryAlarmStateStore: AlarmStateStoring {
  private var value: ManagedAlarmState

  public init(_ value: ManagedAlarmState = ManagedAlarmState()) { self.value = value }
  public func load() -> ManagedAlarmState { value }
  public func save(_ state: ManagedAlarmState) { value = state }
}

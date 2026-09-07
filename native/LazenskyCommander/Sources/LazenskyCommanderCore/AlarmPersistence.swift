import Foundation

public struct ManagedAlarmRecord: Codable, Equatable, Sendable {
  public let stableId: String
  public let platformAlarmID: String
  public let alarm: NativeAlarm
  public let presentationContext: AlarmPresentationContext?

  public init(stableId: String, platformAlarmID: String, alarm: NativeAlarm, presentationContext: AlarmPresentationContext? = nil) {
    self.stableId = stableId
    self.platformAlarmID = platformAlarmID
    self.alarm = alarm
    self.presentationContext = presentationContext
  }
}

public struct AlarmReconciliationObservation: Codable, Equatable, Sendable, Identifiable {
  public let stableId: String
  public let title: String
  public let expectedLeaveAt: String
  public let platformAlarmID: String?
  public let platformExists: Bool?
  public let actualLeaveAt: Date?
  public let readbackError: String?

  public var id: String { stableId }

  public init(
    stableId: String,
    title: String,
    expectedLeaveAt: String,
    platformAlarmID: String?,
    platformExists: Bool?,
    actualLeaveAt: Date?,
    readbackError: String? = nil
  ) {
    self.stableId = stableId
    self.title = title
    self.expectedLeaveAt = expectedLeaveAt
    self.platformAlarmID = platformAlarmID
    self.platformExists = platformExists
    self.actualLeaveAt = actualLeaveAt
    self.readbackError = readbackError
  }

  public var hasMismatch: Bool {
    if readbackError != nil { return true }
    guard let platformAlarmID else { return false }
    if platformExists == false { return true }
    guard platformExists == true else { return false }
    guard let actualLeaveAt,
          let expected = try? NativeAlarmContract.date(fromLocalISO: expectedLeaveAt)
    else { return true }
    return abs(actualLeaveAt.timeIntervalSince(expected)) > 1
  }

  public var diagnosticText: String? {
    if let readbackError { return readbackError }
    guard platformAlarmID != nil else { return nil }
    if platformExists == false { return "Systém tento alarm nenašel." }
    guard platformExists == true else { return "Stav alarmu se nepodařilo přečíst." }
    guard let actualLeaveAt,
          let expected = try? NativeAlarmContract.date(fromLocalISO: expectedLeaveAt)
    else { return "Čas alarmu se nepodařilo doložit." }
    if abs(actualLeaveAt.timeIntervalSince(expected)) > 1 {
      return "Čas alarmu v systému nesouhlasil s požadovaným časem."
    }
    return nil
  }
}

public struct AlarmReconciliationHistoryEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let scheduleVersion: Int
  public let startedAt: Date
  public var completedAt: Date?
  public let desiredAlarmCount: Int
  public var before: [AlarmReconciliationObservation]
  public var after: [AlarmReconciliationObservation]
  public var repairAttempts: Int
  public var verified: Bool
  public var errorMessage: String?

  public init(
    id: UUID = UUID(),
    scheduleVersion: Int,
    startedAt: Date,
    completedAt: Date? = nil,
    desiredAlarmCount: Int,
    before: [AlarmReconciliationObservation] = [],
    after: [AlarmReconciliationObservation] = [],
    repairAttempts: Int = 0,
    verified: Bool = false,
    errorMessage: String? = nil
  ) {
    self.id = id
    self.scheduleVersion = scheduleVersion
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.desiredAlarmCount = desiredAlarmCount
    self.before = before
    self.after = after
    self.repairAttempts = repairAttempts
    self.verified = verified
    self.errorMessage = errorMessage
  }

  public var hadProblemBeforeChanges: Bool {
    before.contains(where: \.hasMismatch)
  }

  public var hasProblem: Bool {
    errorMessage != nil || !verified || hadProblemBeforeChanges || after.contains(where: \.hasMismatch)
  }
}

public struct ManagedAlarmState: Codable, Equatable, Sendable {
  public static let reconciliationHistoryLimit = 12

  public var records: [String: ManagedAlarmRecord]
  public var lastSuccessfulPayload: NativeAlarmPayload?
  public var lastSuccessfulSync: Date?
  public var reconciliationHistory: [AlarmReconciliationHistoryEntry]

  public init(
    records: [String: ManagedAlarmRecord] = [:],
    lastSuccessfulPayload: NativeAlarmPayload? = nil,
    lastSuccessfulSync: Date? = nil,
    reconciliationHistory: [AlarmReconciliationHistoryEntry] = []
  ) {
    self.records = records
    self.lastSuccessfulPayload = lastSuccessfulPayload
    self.lastSuccessfulSync = lastSuccessfulSync
    self.reconciliationHistory = Array(reconciliationHistory.suffix(Self.reconciliationHistoryLimit))
  }

  public mutating func appendReconciliationHistory(_ entry: AlarmReconciliationHistoryEntry) {
    reconciliationHistory.append(entry)
    if reconciliationHistory.count > Self.reconciliationHistoryLimit {
      reconciliationHistory.removeFirst(reconciliationHistory.count - Self.reconciliationHistoryLimit)
    }
  }

  public mutating func updateReconciliationHistory(
    id: UUID,
    completedAt: Date?,
    after: [AlarmReconciliationObservation],
    repairAttempts: Int,
    verified: Bool,
    errorMessage: String?
  ) {
    guard let index = reconciliationHistory.lastIndex(where: { $0.id == id }) else { return }
    reconciliationHistory[index].completedAt = completedAt
    reconciliationHistory[index].after = after
    reconciliationHistory[index].repairAttempts = repairAttempts
    reconciliationHistory[index].verified = verified
    reconciliationHistory[index].errorMessage = errorMessage
  }

  private enum CodingKeys: String, CodingKey {
    case records, lastSuccessfulPayload, lastSuccessfulSync, reconciliationHistory
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    records = try container.decodeIfPresent([String: ManagedAlarmRecord].self, forKey: .records) ?? [:]
    lastSuccessfulPayload = try container.decodeIfPresent(NativeAlarmPayload.self, forKey: .lastSuccessfulPayload)
    lastSuccessfulSync = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
    reconciliationHistory = Array(
      (try container.decodeIfPresent([AlarmReconciliationHistoryEntry].self, forKey: .reconciliationHistory) ?? [])
        .suffix(Self.reconciliationHistoryLimit)
    )
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
    do {
      return try JSONDecoder().decode(ManagedAlarmState.self, from: data)
    } catch {
      defaults.removeObject(forKey: key)
      return ManagedAlarmState()
    }
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

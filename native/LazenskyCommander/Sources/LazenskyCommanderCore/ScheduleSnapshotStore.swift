import Foundation

public enum ScheduleSnapshotDecision: Equatable, Sendable {
  case stored
  case unchanged
  case rejectedVersion(current: Int, incoming: Int)
}

public protocol ScheduleSnapshotStoring: Sendable {
  func load() async throws -> Schedule?
  func save(_ schedule: Schedule) async throws
  func accept(_ schedule: Schedule) async throws -> ScheduleSnapshotDecision
}

public extension ScheduleSnapshotStoring {
  @discardableResult
  func accept(_ schedule: Schedule) async throws -> ScheduleSnapshotDecision {
    try NativeAlarmContract.validateCanonical(schedule)
    let decision = ScheduleSnapshotPolicy.decision(incoming: schedule, existing: try await load())
    if decision == .stored { try await save(schedule) }
    return decision
  }
}

public actor UserDefaultsScheduleSnapshotStore: ScheduleSnapshotStoring {
  private let defaults: UserDefaults
  private let key: String

  public init(defaults: UserDefaults = .standard, key: String = "lazensky.commander.scheduleSnapshot.v1") {
    self.defaults = defaults
    self.key = key
  }

  public func load() throws -> Schedule? {
    guard let data = defaults.data(forKey: key) else { return nil }
    do {
      let schedule = try JSONDecoder().decode(Schedule.self, from: data)
      try NativeAlarmContract.validateCanonical(schedule)
      return schedule
    } catch {
      defaults.removeObject(forKey: key)
      return nil
    }
  }

  public func accept(_ schedule: Schedule) throws -> ScheduleSnapshotDecision {
    try NativeAlarmContract.validateCanonical(schedule)
    let decision = ScheduleSnapshotPolicy.decision(incoming: schedule, existing: try load())
    if decision == .stored { try save(schedule) }
    return decision
  }

  public func save(_ schedule: Schedule) throws {
    try NativeAlarmContract.validateCanonical(schedule)
    defaults.set(try JSONEncoder().encode(schedule), forKey: key)
  }
}

public actor InMemoryScheduleSnapshotStore: ScheduleSnapshotStoring {
  private var schedule: Schedule?

  public init(_ schedule: Schedule? = nil) {
    self.schedule = schedule
  }

  public func accept(_ incoming: Schedule) throws -> ScheduleSnapshotDecision {
    try NativeAlarmContract.validateCanonical(incoming)
    let decision = ScheduleSnapshotPolicy.decision(incoming: incoming, existing: schedule)
    if decision == .stored { schedule = incoming }
    return decision
  }

  public func load() -> Schedule? { schedule }
  public func save(_ schedule: Schedule) { self.schedule = schedule }
}

public enum ScheduleSnapshotPolicy {
  public static func decision(incoming: Schedule, existing: Schedule?) -> ScheduleSnapshotDecision {
    guard let existing else { return .stored }
    if incoming == existing { return .unchanged }
    guard incoming.scheduleVersion > existing.scheduleVersion else {
      return .rejectedVersion(current: existing.scheduleVersion, incoming: incoming.scheduleVersion)
    }
    return .stored
  }
}

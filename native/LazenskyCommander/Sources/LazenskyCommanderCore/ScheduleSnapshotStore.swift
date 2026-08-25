import Foundation

public enum ScheduleSnapshotDecision: Equatable, Sendable {
  case stored
  case unchanged
  case rejectedVersion(current: Int, incoming: Int)
}

public protocol ScheduleSnapshotStoring: Sendable {
  func load() async throws -> Schedule?
  func save(_ schedule: Schedule) async throws
}

public extension ScheduleSnapshotStoring {
  @discardableResult
  func accept(_ schedule: Schedule) async throws -> ScheduleSnapshotDecision {
    try NativeAlarmContract.validateCanonical(schedule)
    guard let existing = try await load() else {
      try await save(schedule)
      return .stored
    }
    if existing == schedule { return .unchanged }
    guard schedule.scheduleVersion > existing.scheduleVersion else {
      return .rejectedVersion(current: existing.scheduleVersion, incoming: schedule.scheduleVersion)
    }
    try await save(schedule)
    return .stored
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

  public func load() -> Schedule? { schedule }
  public func save(_ schedule: Schedule) { self.schedule = schedule }
}

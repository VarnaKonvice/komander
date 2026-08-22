import Foundation

public protocol ScheduleSnapshotStoring: Sendable {
  func load() async throws -> Schedule?
  func save(_ schedule: Schedule) async throws
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
    let schedule = try JSONDecoder().decode(Schedule.self, from: data)
    try NativeAlarmContract.validate(schedule)
    return schedule
  }

  public func save(_ schedule: Schedule) throws {
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

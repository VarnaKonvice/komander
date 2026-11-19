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

public enum LocalPaperScheduleFile {
  public static func isRequired(for schedule: Schedule) -> Bool {
    schedule.paperDetails != nil || schedule.stay["source"] == "Lokální OCR · klientský rozpis"
  }

  public static func read(from url: URL) -> Schedule? {
    guard let data = try? Data(contentsOf: url), let schedule = try? JSONDecoder().decode(Schedule.self, from: data),
          (try? NativeAlarmContract.validateCanonical(schedule)) != nil else { return nil }
    return schedule
  }

  public static func write(_ schedule: Schedule, to url: URL) throws {
    var directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var resources = URLResourceValues()
    resources.isExcludedFromBackup = true
    try directory.setResourceValues(resources)
    let data = try JSONEncoder().encode(schedule)
#if os(iOS)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
    try data.write(to: url, options: .atomic)
#endif
  }

  public static func remove(at url: URL) throws {
    do { try FileManager.default.removeItem(at: url) }
    catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {}
  }

  public static func latest(local: URL?, defaults: UserDefaults, key: String) -> Schedule? {
    let standard = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Schedule.self, from: $0) }
    guard let privateCopy = local.flatMap({ read(from: $0) }) else { return standard }
    return privateCopy.scheduleVersion >= (standard?.scheduleVersion ?? Int.min) ? privateCopy : standard
  }
}

public actor UserDefaultsScheduleSnapshotStore: ScheduleSnapshotStoring {
  private let defaults: UserDefaults
  private let key: String
  private let paperFile: URL?

  public init(defaults: UserDefaults = .standard, key: String = "lazensky.commander.scheduleSnapshot.v1", paperFile: URL? = nil) {
    self.defaults = defaults
    self.key = key
    self.paperFile = paperFile
  }

  public func load() throws -> Schedule? {
    guard let schedule = LocalPaperScheduleFile.latest(local: paperFile, defaults: defaults, key: key) else {
      defaults.removeObject(forKey: key)
      return nil
    }
    do {
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
    if LocalPaperScheduleFile.isRequired(for: schedule), let paperFile {
      try LocalPaperScheduleFile.write(schedule, to: paperFile)
      defaults.removeObject(forKey: key)
    } else {
      defaults.set(try JSONEncoder().encode(schedule), forKey: key)
      if let paperFile { try? LocalPaperScheduleFile.remove(at: paperFile) }
    }
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

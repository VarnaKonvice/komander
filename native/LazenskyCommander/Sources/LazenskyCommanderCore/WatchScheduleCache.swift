import Foundation

public enum WatchScheduleCacheDecision: Equatable, Sendable {
  case stored
  case unchanged
  case rejectedInvalid
  case rejectedVersion(current: Int, incoming: Int)
}

public actor FileWatchScheduleCache {
  public static let defaultFileName = "watch-schedule-snapshot-v1.json"

  private let directoryURL: URL
  private let fileURL: URL
  private let dataset: CommanderScheduleDataset?
  private let didStore: (@Sendable (WatchScheduleSnapshot) async -> Void)?

  public init(
    directoryURL: URL,
    fileName: String = defaultFileName,
    dataset: CommanderScheduleDataset? = nil,
    didStore: (@Sendable (WatchScheduleSnapshot) async -> Void)? = nil
  ) {
    self.directoryURL = directoryURL
    self.dataset = dataset
    self.fileURL = directoryURL.appendingPathComponent(fileName, isDirectory: false)
    self.didStore = didStore
  }

  public func load() throws -> WatchScheduleSnapshot? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    let data = try Data(contentsOf: fileURL)
    guard
      let snapshot = try? JSONDecoder().decode(WatchScheduleSnapshot.self, from: data),
      dataset?.accepts(snapshot.schedule) != false,
      snapshot.contractVersion == WatchScheduleSnapshot.currentContractVersion,
      (try? WatchScheduleTransportCodec.encode(snapshot)) != nil
    else { return nil }
    return snapshot
  }

  @discardableResult
  public func accept(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleCacheDecision {
    guard dataset?.accepts(snapshot.schedule) != false else { return .rejectedInvalid }
    let decision = WatchScheduleCachePolicy.decision(incoming: snapshot, existing: try load())
    guard decision == .stored else { return decision }

    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    await didStore?(snapshot)
    return .stored
  }
}

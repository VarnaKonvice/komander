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
  public let fileURL: URL
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

  public func remove() throws {
    if FileManager.default.fileExists(atPath: fileURL.path) {
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  @discardableResult
  public func accept(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleCacheDecision {
    let receipt = try commitAndLoad(snapshot)
    if receipt.decision == .stored, let loaded = receipt.snapshot { await didStore?(loaded) }
    return receipt.decision
  }

  public func acceptAndLoad(_ snapshot: WatchScheduleSnapshot) throws -> WatchScheduleCacheReceipt {
    let receipt = try commitAndLoad(snapshot)
    if receipt.decision == .stored, let didStore, let loaded = receipt.snapshot {
      Task { await didStore(loaded) }
    }
    return receipt
  }

  private func commitAndLoad(_ snapshot: WatchScheduleSnapshot) throws -> WatchScheduleCacheReceipt {
    guard dataset?.accepts(snapshot.schedule) != false else {
      return WatchScheduleCacheReceipt(decision: .rejectedInvalid, snapshot: nil)
    }
    let decision = WatchScheduleCachePolicy.decision(incoming: snapshot, existing: try load())
    if decision == .stored {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      var options: Data.WritingOptions = [.atomic]
      #if os(iOS) || os(watchOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
      #endif
      try encoder.encode(snapshot).write(to: fileURL, options: options)
    }
    let loaded = try load()
    // No suspension between accepting and verifying bytes actually read from disk.
    return WatchScheduleCacheReceipt(decision: decision, snapshot: loaded)
  }
}

public struct WatchScheduleCacheReceipt: Sendable {
  public let decision: WatchScheduleCacheDecision
  public let snapshot: WatchScheduleSnapshot?
}

/// iPhone app and extension share a dataset-specific file. Only the app writes.
public enum CommanderPhoneWidgetCache {
  public static func directoryName(dataset: CommanderScheduleDataset) -> String {
    "CommanderPhoneWidget-" + dataset.rawValue
  }

  public static func require(
    dataset: CommanderScheduleDataset, containerURL: URL?
  ) throws -> FileWatchScheduleCache {
    guard let containerURL else { throw CommanderPhoneWidgetPublishError.missingAppGroup }
    return FileWatchScheduleCache(
      directoryURL: containerURL.appendingPathComponent(directoryName(dataset: dataset), isDirectory: true),
      dataset: dataset)
  }

  #if os(iOS)
  public static func require(dataset: CommanderScheduleDataset) throws -> FileWatchScheduleCache {
    try require(dataset: dataset, containerURL: FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: CommanderWatchWidgetContract.appGroupIdentifier))
  }

  public static func make(dataset: CommanderScheduleDataset) -> FileWatchScheduleCache? {
    try? require(dataset: dataset)
  }
  #endif
}

public enum CommanderPhoneWidgetPublishError: LocalizedError, Equatable {
  case missingAppGroup
  case rejected(WatchScheduleCacheDecision)
  case readbackMismatch

  public var errorDescription: String? {
    switch self {
    case .missingAppGroup:
      "App Group container unavailable: \(CommanderWatchWidgetContract.appGroupIdentifier)"
    case .rejected(let decision):
      "Widget snapshot rejected: \(decision)"
    case .readbackMismatch:
      "Widget snapshot disk read-back does not match the accepted snapshot."
    }
  }
}

public extension WatchScheduleCacheReceipt {
  /// A policy decision alone is not proof of publication. Verify the exact bytes
  /// decoded from disk, including canonical contents and local projection.
  func verifyPublished(_ expected: WatchScheduleSnapshot) throws {
    switch decision {
    case .stored, .unchanged: break
    case .rejectedInvalid, .rejectedVersion:
      throw CommanderPhoneWidgetPublishError.rejected(decision)
    }
    guard snapshot == expected else { throw CommanderPhoneWidgetPublishError.readbackMismatch }
  }
}

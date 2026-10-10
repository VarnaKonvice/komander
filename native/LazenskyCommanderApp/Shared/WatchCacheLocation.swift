import Foundation
import LazenskyCommanderCore

enum WatchCacheLocation {
  static var dataset: CommanderScheduleDataset {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    .acceptance
    #else
    .production
    #endif
  }

  private static var cacheDirectoryName: String {
    #if COMMANDER_ACCEPTANCE_FIXTURES
    "CommanderAcceptanceCache"
    #else
    CommanderWatchWidgetContract.cacheDirectoryName
    #endif
  }

  static func makeCache(
    didStore: (@Sendable (WatchScheduleSnapshot) async -> Void)? = nil
  ) -> FileWatchScheduleCache {
    FileWatchScheduleCache(directoryURL: directoryURL(), dataset: dataset, didStore: didStore)
  }

  static func makeAcceptanceCache() -> FileWatchScheduleCache {
    FileWatchScheduleCache(directoryURL: directoryURL().deletingLastPathComponent()
      .appendingPathComponent("CommanderAcceptanceCache"), dataset: .acceptance)
  }

  static func directoryURL(fileManager: FileManager = .default) -> URL {
    guard let base = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: CommanderWatchWidgetContract.appGroupIdentifier
    ) else {
      preconditionFailure("Watch schedule App Group container is unavailable.")
    }
    return base
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent(cacheDirectoryName, isDirectory: true)
  }

  private static func legacyDirectoryURL(fileManager: FileManager = .default) -> URL {
    guard let base = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: CommanderWatchWidgetContract.appGroupIdentifier
    ) else {
      preconditionFailure("Watch schedule App Group container is unavailable.")
    }
    return base.appendingPathComponent(cacheDirectoryName, isDirectory: true)
  }

  static func migrateLegacyCacheIfNeeded() async throws {
    let destination = makeCache()
    if try await destination.load() != nil { return }

    let legacy = FileWatchScheduleCache(
      directoryURL: legacyDirectoryURL(),
      dataset: dataset
    )
    guard let snapshot = try await legacy.load() else { return }
    _ = try await destination.accept(snapshot)
  }
}

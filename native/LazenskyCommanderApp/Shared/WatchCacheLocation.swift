import Foundation
import LazenskyCommanderCore

enum WatchCacheLocation {
  private static var dataset: CommanderScheduleDataset {
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

  static func directoryURL(fileManager: FileManager = .default) -> URL {
    guard let base = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: CommanderWatchWidgetContract.appGroupIdentifier
    ) else {
      preconditionFailure("Watch schedule App Group container is unavailable.")
    }
    return base.appendingPathComponent(
      cacheDirectoryName,
      isDirectory: true
    )
  }
}

import Foundation
import LazenskyCommanderCore

enum WatchCacheLocation {
  static func makeCache(
    didStore: (@Sendable (WatchScheduleSnapshot) async -> Void)? = nil
  ) -> FileWatchScheduleCache {
    FileWatchScheduleCache(directoryURL: directoryURL(), didStore: didStore)
  }

  static func directoryURL(fileManager: FileManager = .default) -> URL {
    guard let base = fileManager.containerURL(
      forSecurityApplicationGroupIdentifier: CommanderWatchWidgetContract.appGroupIdentifier
    ) else {
      preconditionFailure("Watch schedule App Group container is unavailable.")
    }
    return base.appendingPathComponent(
      CommanderWatchWidgetContract.cacheDirectoryName,
      isDirectory: true
    )
  }
}

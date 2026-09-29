import Foundation

/// The extension keeps a validated last-known snapshot across reloads and network outages.
/// The cache's version decision also protects overlapping refreshes from older responses.
public struct CommanderWidgetSnapshotLoader: Sendable {
  private let service: any ScheduleServing
  private let cache: FileWatchScheduleCache

  public init(service: any ScheduleServing, cache: FileWatchScheduleCache) {
    self.service = service
    self.cache = cache
  }

  public func load() async -> WatchScheduleSnapshot? {
    var fallback = try? await cache.load()
    do {
      let fetched = WatchScheduleSnapshot(schedule: try await service.fetchSchedule())
      switch try await cache.accept(fetched) {
      case .stored, .unchanged: fallback = fetched
      case .rejectedInvalid, .rejectedVersion: break
      }
    } catch {
      // Re-read after suspension: another refresh may have stored a newer version.
    }
    return (try? await cache.load()) ?? fallback
  }
}

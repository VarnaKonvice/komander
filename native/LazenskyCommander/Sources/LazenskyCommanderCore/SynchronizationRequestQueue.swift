public struct CommanderSynchronizationRequest: Equatable, Sendable {
  public let maxAttempts: Int
  public let automatic: Bool
  public let source: CommanderScheduleSource

  public init(maxAttempts: Int, automatic: Bool, source: CommanderScheduleSource = .remote) {
    self.maxAttempts = max(1, maxAttempts)
    self.automatic = automatic
    self.source = source
  }
}

/// Coalesces requests that arrive while a synchronization pass is suspended in platform I/O.
/// The current pass is never interrupted, and at least one follow-up pass consumes the newest
/// model state before the queue becomes idle again.
public struct CommanderSynchronizationRequestQueue: Sendable {
  private var isRunning = false
  private var pending: [CommanderSynchronizationRequest] = []

  public var hasPendingCachedProjection: Bool { pending.contains { $0.source == .cached } }

  public init() {}

  public mutating func submit(
    maxAttempts: Int,
    automatic: Bool,
    source: CommanderScheduleSource = .remote
  ) -> CommanderSynchronizationRequest? {
    let request = CommanderSynchronizationRequest(
      maxAttempts: maxAttempts,
      automatic: automatic,
      source: source
    )
    guard isRunning else {
      isRunning = true
      return request
    }

    if let index = pending.firstIndex(where: { $0.source == source }) {
      let previous = pending[index]
      pending[index] = CommanderSynchronizationRequest(
        maxAttempts: max(previous.maxAttempts, request.maxAttempts),
        automatic: previous.automatic && request.automatic,
        source: source
      )
    } else if source == .cached {
      // Project local edits before any queued network refresh, without dropping either request.
      pending.insert(request, at: 0)
    } else {
      pending.append(request)
    }
    return nil
  }

  public mutating func completeCurrentAndTakeNext() -> CommanderSynchronizationRequest? {
    if !pending.isEmpty {
      return pending.removeFirst()
    }
    isRunning = false
    return nil
  }
}

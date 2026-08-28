public struct CommanderSynchronizationRequest: Equatable, Sendable {
  public let maxAttempts: Int
  public let automatic: Bool

  public init(maxAttempts: Int, automatic: Bool) {
    self.maxAttempts = max(1, maxAttempts)
    self.automatic = automatic
  }
}

/// Coalesces requests that arrive while a synchronization pass is suspended in platform I/O.
/// The current pass is never interrupted, and at least one follow-up pass consumes the newest
/// model state before the queue becomes idle again.
public struct CommanderSynchronizationRequestQueue: Sendable {
  private var isRunning = false
  private var pending: CommanderSynchronizationRequest?

  public init() {}

  public mutating func submit(
    maxAttempts: Int,
    automatic: Bool
  ) -> CommanderSynchronizationRequest? {
    let request = CommanderSynchronizationRequest(
      maxAttempts: maxAttempts,
      automatic: automatic
    )
    guard isRunning else {
      isRunning = true
      return request
    }

    if let pending {
      self.pending = CommanderSynchronizationRequest(
        maxAttempts: max(pending.maxAttempts, request.maxAttempts),
        automatic: pending.automatic && request.automatic
      )
    } else {
      pending = request
    }
    return nil
  }

  public mutating func completeCurrentAndTakeNext() -> CommanderSynchronizationRequest? {
    if let pending {
      self.pending = nil
      return pending
    }
    isRunning = false
    return nil
  }
}

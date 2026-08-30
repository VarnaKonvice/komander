/// Per-pass recovery decisions. Only the latest AlarmKit verification can require fallback;
/// optional Watch delivery never arms it or requests another iPhone synchronization.
public struct CommanderSynchronizationRecovery: Sendable {
  public private(set) var needsFallback = false
  public private(set) var shouldRetry = false

  public init() {}

  public mutating func recordAlarmVerification(succeeded: Bool) {
    needsFallback = !succeeded
    shouldRetry = !succeeded
  }

  public mutating func requestRetry() {
    shouldRetry = true
  }
}

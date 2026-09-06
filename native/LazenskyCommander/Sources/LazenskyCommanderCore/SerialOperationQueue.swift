/// Serializes complete asynchronous side effects, including suspension points.
/// Actor isolation alone serializes only the work between awaits.
public actor CommanderSerialOperationQueue {
  private var tail: Task<Void, Never>?

  public init() {}

  public func run<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let previous = tail
    let task = Task {
      await previous?.value
      return try await operation()
    }
    tail = Task { _ = await task.result }
    return try await task.value
  }
}

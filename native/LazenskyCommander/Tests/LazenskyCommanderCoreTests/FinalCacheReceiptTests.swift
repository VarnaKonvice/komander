import Foundation
import Testing
@testable import LazenskyCommanderCore

private actor ReceiptHookGate {
  var released = false
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    if released { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}

@Test func atomicCacheReceiptDoesNotWaitForDownstreamHookAndSurvivesRestart() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let gate = ReceiptHookGate()
  let cache = FileWatchScheduleCache(directoryURL: directory, dataset: .acceptance) { _ in
    await gate.wait() // Represents a notification center operation that has not returned.
  }
  let schedule = try CommanderAcceptanceSchedule(
    now: NativeAlarmContract.date(fromLocalISO: "2026-09-29T10:00:00"), scenario: .singleRenderer).schedule
  let newest = WatchScheduleSnapshot(schedule: schedule, projectionRevision: 3)
  let receipt = try await cache.acceptAndLoad(newest)
  #expect(receipt.decision == .stored)
  #expect(receipt.snapshot == newest)
  await gate.release()
  let restarted = FileWatchScheduleCache(directoryURL: directory, dataset: .acceptance)
  #expect(try await restarted.load() == newest)
  let old = try await restarted.acceptAndLoad(.init(schedule: schedule, projectionRevision: 2))
  #expect(old.snapshot == newest)
  #expect(old.decision != .stored)
  #expect(try await restarted.acceptAndLoad(newest).decision == .unchanged)
}

@Test func cacheDatasetReceiptNeverAcknowledgesForeignInput() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let cache = FileWatchScheduleCache(directoryURL: directory, dataset: .production)
  let schedule = try CommanderAcceptanceSchedule(
    now: NativeAlarmContract.date(fromLocalISO: "2026-09-29T10:00:00"), scenario: .singleRenderer).schedule
  let receipt = try await cache.acceptAndLoad(.init(schedule: schedule))
  #expect(receipt.decision == .rejectedInvalid)
  #expect(receipt.snapshot == nil)
  #expect(try await cache.load() == nil)
}

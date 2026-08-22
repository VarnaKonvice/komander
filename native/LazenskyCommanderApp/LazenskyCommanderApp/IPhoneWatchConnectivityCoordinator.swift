import Foundation
import LazenskyCommanderCore
import WatchConnectivity

enum IPhoneWatchConnectivityError: LocalizedError {
  case unsupported

  var errorDescription: String? {
    switch self {
    case .unsupported: "WatchConnectivity není na tomto zařízení dostupné."
    }
  }
}

@MainActor
final class IPhoneWatchConnectivityCoordinator: NSObject, WatchScheduleSnapshotDelivering, WCSessionDelegate {
  private let session: WCSession?
  private var pendingApplicationContext: [String: Any]?

  private(set) var diagnostic = "Aktivuji WatchConnectivity…"

  override init() {
    session = WCSession.isSupported() ? .default : nil
    super.init()
    guard let session else {
      diagnostic = "WatchConnectivity není dostupné"
      return
    }
    session.delegate = self
    session.activate()
  }

  func deliver(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleDeliveryDisposition {
    guard let session else { throw IPhoneWatchConnectivityError.unsupported }
    let applicationContext = try WatchScheduleTransportCodec.applicationContext(for: snapshot)
    pendingApplicationContext = applicationContext

    guard session.activationState == .activated else {
      diagnostic = "Čeká na aktivaci WatchConnectivity"
      session.activate()
      return .queued
    }
    return try publishPendingContext(using: session)
  }

  private func publishPendingContext(using session: WCSession) throws -> WatchScheduleDeliveryDisposition {
    guard let pendingApplicationContext else { return .sent }
    try session.updateApplicationContext(pendingApplicationContext)
    self.pendingApplicationContext = nil
    diagnostic = "Poslední rozpis předán Apple Watch"
    return .sent
  }

  private func didActivate(errorDescription: String?) {
    if let errorDescription {
      diagnostic = "Aktivace WatchConnectivity selhala: \(errorDescription)"
      return
    }
    guard let session else { return }
    do {
      _ = try publishPendingContext(using: session)
      if pendingApplicationContext == nil, diagnostic != "Poslední rozpis předán Apple Watch" {
        diagnostic = "WatchConnectivity aktivní"
      }
    } catch {
      diagnostic = "Předání Apple Watch selhalo: \(error.localizedDescription)"
    }
  }

  private func reactivate() {
    diagnostic = "WatchConnectivity se znovu aktivuje"
    session?.activate()
  }

  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let errorDescription = error?.localizedDescription
    Task { @MainActor [weak self] in
      self?.didActivate(errorDescription: errorDescription)
    }
  }

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
    Task { @MainActor [weak self] in
      self?.diagnostic = "WatchConnectivity neaktivní"
    }
  }

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    Task { @MainActor [weak self] in
      self?.reactivate()
    }
  }
}

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
  private var acknowledgedScheduleVersion: Int?

  private(set) var diagnostic = "Aktivuji WatchConnectivity…"

  override init() {
    session = WCSession.isSupported() ? .default : nil
    super.init()
    guard let session else {
      diagnostic = "WatchConnectivity není dostupné"
      return
    }
    session.delegate = self
    receiveAcknowledgement(from: session.receivedApplicationContext)
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

  func verifiedScheduleVersion() async -> Int? {
    acknowledgedScheduleVersion
  }

  private func publishPendingContext(using session: WCSession) throws -> WatchScheduleDeliveryDisposition {
    guard let pendingApplicationContext else { return .sent }
    try session.updateApplicationContext(pendingApplicationContext)
    self.pendingApplicationContext = nil
    diagnostic = "Rozpis odeslán, čekám na potvrzení Watch"
    return .sent
  }

  private func receiveAcknowledgement(from applicationContext: [String: Any]) {
    guard let acknowledgement = try? WatchScheduleAcknowledgementCodec.decode(applicationContext: applicationContext) else { return }
    acknowledgedScheduleVersion = acknowledgement.scheduleVersion
    diagnostic = "Apple Watch ověřily rozpis v\(acknowledgement.scheduleVersion)"
  }

  private func didActivate(errorDescription: String?, receivedApplicationContext: [String: Any]) {
    if let errorDescription {
      diagnostic = "Aktivace WatchConnectivity selhala: \(errorDescription)"
      return
    }
    receiveAcknowledgement(from: receivedApplicationContext)
    guard let session else { return }
    do {
      _ = try publishPendingContext(using: session)
      if pendingApplicationContext == nil,
         acknowledgedScheduleVersion == nil,
         diagnostic != "Rozpis odeslán, čekám na potvrzení Watch" {
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
    let receivedApplicationContext = session.receivedApplicationContext
    Task { @MainActor [weak self] in
      self?.didActivate(errorDescription: errorDescription, receivedApplicationContext: receivedApplicationContext)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    Task { @MainActor [weak self] in
      self?.receiveAcknowledgement(from: applicationContext)
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

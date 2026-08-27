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
  private var acknowledgedProjectionIdentity: WatchScheduleProjectionIdentity?

  private(set) var diagnostic = "Aktivuji WatchConnectivity…"

  override init() {
    session = WCSession.isSupported() ? .default : nil
    super.init()
    guard let session else {
      diagnostic = "WatchConnectivity není dostupné"
      return
    }
    session.delegate = self
    recordAcknowledgement(Self.acknowledgement(from: session.receivedApplicationContext))
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
    acknowledgedProjectionIdentity?.scheduleVersion
  }

  func verifiedProjectionIdentity() async -> WatchScheduleProjectionIdentity? {
    acknowledgedProjectionIdentity
  }

  private func publishPendingContext(using session: WCSession) throws -> WatchScheduleDeliveryDisposition {
    guard let pendingApplicationContext else { return .sent }
    try session.updateApplicationContext(pendingApplicationContext)
    self.pendingApplicationContext = nil
    diagnostic = "Rozpis odeslán, čekám na potvrzení Watch"
    return .sent
  }

  private func recordAcknowledgement(_ acknowledgement: WatchScheduleAcknowledgement?) {
    guard let acknowledgement else { return }
    acknowledgedProjectionIdentity = acknowledgement.projectionIdentity
    diagnostic = "Apple Watch ověřily rozpis v\(acknowledgement.scheduleVersion)/r\(acknowledgement.projectionRevision)"
  }

  nonisolated private static func acknowledgement(from applicationContext: [String: Any]) -> WatchScheduleAcknowledgement? {
    try? WatchScheduleAcknowledgementCodec.decode(applicationContext: applicationContext)
  }

  private func didActivate(errorDescription: String?, acknowledgement: WatchScheduleAcknowledgement?) {
    if let errorDescription {
      diagnostic = "Aktivace WatchConnectivity selhala: \(errorDescription)"
      return
    }
    recordAcknowledgement(acknowledgement)
    guard let session else { return }
    do {
      _ = try publishPendingContext(using: session)
      if pendingApplicationContext == nil,
         acknowledgedProjectionIdentity == nil,
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
    let acknowledgement = Self.acknowledgement(from: session.receivedApplicationContext)
    Task { @MainActor [weak self] in
      self?.didActivate(errorDescription: errorDescription, acknowledgement: acknowledgement)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    let acknowledgement = Self.acknowledgement(from: applicationContext)
    Task { @MainActor [weak self] in
      self?.recordAcknowledgement(acknowledgement)
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

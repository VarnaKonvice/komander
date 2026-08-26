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
    recordAcknowledgement(Self.acknowledgementVersion(from: session.receivedApplicationContext))
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

  private func recordAcknowledgement(_ scheduleVersion: Int?) {
    guard let scheduleVersion else { return }
    acknowledgedScheduleVersion = scheduleVersion
    diagnostic = "Apple Watch ověřily rozpis v\(scheduleVersion)"
  }

  nonisolated private static func acknowledgementVersion(from applicationContext: [String: Any]) -> Int? {
    try? WatchScheduleAcknowledgementCodec.decode(applicationContext: applicationContext).scheduleVersion
  }

  private func didActivate(errorDescription: String?, acknowledgedVersion: Int?) {
    if let errorDescription {
      diagnostic = "Aktivace WatchConnectivity selhala: \(errorDescription)"
      return
    }
    recordAcknowledgement(acknowledgedVersion)
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
    let acknowledgedVersion = Self.acknowledgementVersion(from: session.receivedApplicationContext)
    Task { @MainActor [weak self] in
      self?.didActivate(errorDescription: errorDescription, acknowledgedVersion: acknowledgedVersion)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    let acknowledgedVersion = Self.acknowledgementVersion(from: applicationContext)
    Task { @MainActor [weak self] in
      self?.recordAcknowledgement(acknowledgedVersion)
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

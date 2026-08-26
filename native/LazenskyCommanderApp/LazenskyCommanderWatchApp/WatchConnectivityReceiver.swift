import Foundation
import LazenskyCommanderCore
import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
  private weak var model: WatchCommanderModel?
  private let session: WCSession?
  private var didStart = false
  private var pendingAcknowledgementVersion: Int?

  init(model: WatchCommanderModel) {
    self.model = model
    session = WCSession.isSupported() ? .default : nil
    super.init()
  }

  func activate() {
    guard !didStart, let session else { return }
    didStart = true
    session.delegate = self
    receivePendingContext(from: session)
    session.activate()
  }

  private func receivePendingContext(from session: WCSession) {
    guard let data = Self.payloadData(from: session.receivedApplicationContext) else { return }
    receive(data)
  }

  private func receive(_ data: Data) {
    Task { @MainActor [weak self] in
      guard let self, let model else { return }
      do {
        let snapshot = try WatchScheduleTransportCodec.decode(data)
        let decision = try await model.receive(snapshot)
        model.recordTransportError(nil)

        switch decision {
        case .stored, .unchanged, .rejectedVersion:
          // ACK the version actually loaded from the atomic cache, never merely the incoming payload.
          if let verifiedVersion = model.schedule?.scheduleVersion {
            acknowledge(scheduleVersion: verifiedVersion)
          }
        case .rejectedInvalid:
          break
        }
      } catch {
        model.recordTransportError(error.localizedDescription)
      }
    }
  }

  private func acknowledge(scheduleVersion: Int) {
    pendingAcknowledgementVersion = scheduleVersion
    guard let session, session.activationState == .activated else {
      session?.activate()
      return
    }
    publishPendingAcknowledgement(using: session)
  }

  private func publishPendingAcknowledgement(using session: WCSession) {
    guard let scheduleVersion = pendingAcknowledgementVersion else { return }
    do {
      try session.updateApplicationContext(
        WatchScheduleAcknowledgementCodec.applicationContext(scheduleVersion: scheduleVersion)
      )
      pendingAcknowledgementVersion = nil
      model?.recordTransportError(nil)
    } catch {
      model?.recordTransportError("Potvrzení rozpisu iPhonu selhalo: \(error.localizedDescription)")
    }
  }

  nonisolated private static func payloadData(from applicationContext: [String: Any]) -> Data? {
    applicationContext[WatchScheduleTransportCodec.applicationContextKey] as? Data
  }

  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let errorDescription = error?.localizedDescription
    let payload = Self.payloadData(from: session.receivedApplicationContext)
    let isActivated = activationState == .activated
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let errorDescription {
        model?.recordTransportError(errorDescription)
      }
      if isActivated, let activeSession = self.session {
        publishPendingAcknowledgement(using: activeSession)
      }
      if let payload { receive(payload) }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    guard let payload = Self.payloadData(from: applicationContext) else { return }
    Task { @MainActor [weak self] in
      self?.receive(payload)
    }
  }
}

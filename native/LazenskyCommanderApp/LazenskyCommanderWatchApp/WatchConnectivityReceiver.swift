import Foundation
import LazenskyCommanderCore
import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
  private weak var model: WatchCommanderModel?
  private let session: WCSession?
  private var didStart = false
  private var pendingAcknowledgement: WatchScheduleProjectionIdentity?

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
    let applicationContext = session.receivedApplicationContext
    if let data = Self.payloadData(from: applicationContext) { receive(data) }
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
          // ACK the exact projection actually loaded from the atomic cache, never merely
          // the incoming payload. This proves both canonical version and local lead-time revision.
          if let identity = model.projectionIdentity {
            acknowledge(identity)
          }
        case .rejectedInvalid:
          break
        }
      } catch {
        model.recordTransportError(error.localizedDescription)
      }
    }
  }

  private func acknowledge(_ identity: WatchScheduleProjectionIdentity) {
    pendingAcknowledgement = identity
    guard let session, session.activationState == .activated else {
      session?.activate()
      return
    }
    publishPendingAcknowledgement(using: session)
  }

  private func publishPendingAcknowledgement(using session: WCSession) {
    guard let identity = pendingAcknowledgement else { return }
    let context = WatchScheduleAcknowledgementCodec.merging(
      scheduleVersion: identity.scheduleVersion,
      projectionRevision: identity.projectionRevision,
      into: [:]
    )

    do {
      try session.updateApplicationContext(context)
      pendingAcknowledgement = nil
      model?.recordTransportError(nil)
    } catch {
      model?.recordTransportError("Potvrzení iPhonu selhalo: \(error.localizedDescription)")
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
    let applicationContext = session.receivedApplicationContext
    let scheduleData = Self.payloadData(from: applicationContext)
    let isActivated = activationState == .activated
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let errorDescription {
        model?.recordTransportError(errorDescription)
      }
      if isActivated, let activeSession = self.session {
        publishPendingAcknowledgement(using: activeSession)
      }
      if let scheduleData { receive(scheduleData) }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    let scheduleData = Self.payloadData(from: applicationContext)
    Task { @MainActor [weak self] in
      if let scheduleData { self?.receive(scheduleData) }
    }
  }

}

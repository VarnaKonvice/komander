import Foundation
import LazenskyCommanderCore
import WatchConnectivity

@MainActor
final class WatchConnectivityReceiver: NSObject, WCSessionDelegate {
  private weak var model: WatchCommanderModel?
  private let session: WCSession?
  private var didStart = false

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
        _ = try await model.receive(snapshot)
        model.recordTransportError(nil)
      } catch {
        model.recordTransportError(error.localizedDescription)
      }
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
    Task { @MainActor [weak self] in
      guard let self else { return }
      if let errorDescription {
        model?.recordTransportError(errorDescription)
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

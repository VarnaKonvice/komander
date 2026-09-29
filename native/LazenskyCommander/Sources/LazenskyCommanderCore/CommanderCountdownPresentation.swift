import Foundation

/// Shared semantic model. Layout, font and timer mechanism belong to the surface.
/// Live Activity's event-context mode is deliberately stable while its process sleeps.
public struct CommanderCountdownPresentation: Equatable, Sendable {
  public let status: String
  public let countdownLabel: String
  public let target: Date?
  public let referenceLabel: String?
  public let referenceDate: Date?
  public let symbol: String

  public init(liveState: CommanderLiveStateResult) {
    switch liveState.state {
    case .upcoming:
      self.init(status: "Vyrazit za", countdownLabel: "Do odchodu",
                target: liveState.leaveAt, referenceLabel: "Odchod",
                referenceDate: liveState.leaveAt, symbol: "figure.walk")
    case .leaveNow:
      self.init(status: "Vyrazit teď", countdownLabel: "Začíná za",
                target: liveState.startAt, referenceLabel: "Začátek",
                referenceDate: liveState.startAt, symbol: "clock.badge")
    case .inProgress:
      self.init(status: liveState.event?.kind == .meal ? "Právě jídlo" : "Právě probíhá",
                countdownLabel: "Do konce", target: liveState.endAt,
                referenceLabel: "Konec", referenceDate: liveState.endAt, symbol: "clock.badge")
    case .dayDone, .noSchedule:
      self.init(status: liveState.state == .dayDone ? "Skončilo" : "Žádný program",
                countdownLabel: "", target: nil, referenceLabel: nil,
                referenceDate: nil, symbol: liveState.state == .dayDone ? "checkmark.circle.fill" : "clock.badge")
    }
  }

  /// A suspended widget must not invent an active phase from a one-off Date().
  /// Stop/foreground owns the explicit mode; the system owns the live timer.
  public init(
    presentationMode: CommanderLiveActivityPresentationMode,
    isStale: Bool,
    leaveAt: Date,
    startAt: Date,
    endAt: Date
  ) {
    if isStale {
      self.init(status: "Skončilo", countdownLabel: "", target: nil,
                referenceLabel: "Konec", referenceDate: endAt,
                symbol: "checkmark.circle.fill")
      return
    }

    switch presentationMode {
    case .departureCountdown:
      self.init(status: "Vyrazit za", countdownLabel: "Do odchodu",
                target: leaveAt, referenceLabel: "Odchod",
                referenceDate: leaveAt, symbol: "figure.walk")
    case .startCountdown:
      self.init(status: "Vyrazit teď", countdownLabel: "Začíná za",
                target: startAt, referenceLabel: "Začátek",
                referenceDate: startAt, symbol: "clock.badge")
    case .eventContext:
      self.init(status: "Začátek " + startAt.formatted(date: .omitted, time: .shortened),
                countdownLabel: "Do konce", target: endAt,
                referenceLabel: "Konec", referenceDate: endAt,
                symbol: "clock.badge")
    }
  }

  private init(status: String, countdownLabel: String, target: Date?,
               referenceLabel: String?, referenceDate: Date?, symbol: String) {
    self.status = status
    self.countdownLabel = countdownLabel
    self.target = target
    self.referenceLabel = referenceLabel
    self.referenceDate = referenceDate
    self.symbol = symbol
  }

  public func countdownText(at now: Date) -> String? {
    guard let target else { return nil }
    let delta = target.timeIntervalSince(now)
    guard delta.isFinite else { return nil }
    let remaining = Int(max(0, delta).rounded(.up))
    return "\(remaining / 60):" + String(format: "%02d", remaining % 60)
  }
}

import Foundation

/// Shared semantic model. Layout, font and timer mechanism belong to the surface.
public struct CommanderCountdownPresentation: Equatable, Sendable {
  public let status: String
  public let countdownLabel: String
  public let target: Date?
  public let referenceLabel: String?
  public let referenceDate: Date?
  public let symbol: String
  public let isScheduleFallback: Bool

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

  /// Required story at a supplied instant. Freshness never changes event phase.
  /// This calculation does not promise that ActivityKit will execute it later.
  public init(
    presentationMode: CommanderLiveActivityPresentationMode,
    leaveAt: Date,
    startAt: Date,
    endAt: Date,
    at now: Date
  ) {
    if now >= endAt {
      self.init(status: "Skončilo", countdownLabel: "", target: nil,
                referenceLabel: nil, referenceDate: nil, symbol: "checkmark.circle.fill")
    } else if now >= startAt {
      self.init(status: "Právě probíhá", countdownLabel: "Do konce",
                target: endAt, referenceLabel: "Konec",
                referenceDate: endAt, symbol: "clock.badge")
    } else if presentationMode == .departureCountdown && now < leaveAt {
      self.init(status: "Vyrazit za", countdownLabel: "Do odchodu",
                target: leaveAt, referenceLabel: "Odchod",
                referenceDate: leaveAt, symbol: "figure.walk")
    } else {
      self.init(status: "Začátek za", countdownLabel: "Do začátku",
                target: startAt, referenceLabel: "Začátek",
                referenceDate: startAt, symbol: "clock.badge")
    }
  }

  /// PLATFORM LIMIT: one staleDate cannot schedule both start and end changes.
  /// No live countdown or phase assertion may survive in this archived fallback.
  /// This is deliberately separate from the required deterministic story above.
  public static var suspendedScheduleFallback: Self {
    .init(status: "Časový plán", countdownLabel: "", target: nil,
          referenceLabel: "Rozpis", referenceDate: nil, symbol: "clock",
          isScheduleFallback: true)
  }

  private init(status: String, countdownLabel: String, target: Date?,
               referenceLabel: String?, referenceDate: Date?, symbol: String,
               isScheduleFallback: Bool = false) {
    self.status = status
    self.countdownLabel = countdownLabel
    self.target = target
    self.referenceLabel = referenceLabel
    self.referenceDate = referenceDate
    self.symbol = symbol
    self.isScheduleFallback = isScheduleFallback
  }

  public func countdownText(at now: Date) -> String? {
    guard let target else { return nil }
    let delta = target.timeIntervalSince(now)
    guard delta.isFinite else { return nil }
    let remaining = Int(max(0, delta).rounded(.up))
    return "\(remaining / 60):" + String(format: "%02d", remaining % 60)
  }
}

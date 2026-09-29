import Foundation

public struct WatchAcceptanceProbe: Codable, Equatable, Sendable {
  public static let currentContractVersion = 1

  public let contractVersion: Int
  public let isActive: Bool
  public let event: ScheduleEvent?
  public let leaveAt: Date?
  public let startAt: Date?
  public let endAt: Date?

  public init(
    stableId: String,
    title: String,
    location: String,
    kind: ScheduleKind,
    procedureType: String? = nil,
    mealType: String? = nil,
    leaveAt: Date,
    startAt: Date,
    endAt: Date
  ) {
    contractVersion = Self.currentContractVersion
    isActive = true
    self.leaveAt = leaveAt
    self.startAt = startAt
    self.endAt = endAt

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .current

    let dateFormatter = DateFormatter()
    dateFormatter.calendar = calendar
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = calendar.timeZone
    dateFormatter.dateFormat = "yyyy-MM-dd"

    let timeFormatter = DateFormatter()
    timeFormatter.calendar = calendar
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")
    timeFormatter.timeZone = calendar.timeZone
    timeFormatter.dateFormat = "HH:mm"

    event = ScheduleEvent(
      stableId: stableId,
      date: dateFormatter.string(from: startAt),
      start: timeFormatter.string(from: startAt),
      end: timeFormatter.string(from: endAt),
      title: title,
      location: location,
      kind: kind,
      procedureType: procedureType,
      mealType: mealType,
      leadTimeMinutes: nil
    )
  }

  private init(inactive: Void) {
    contractVersion = Self.currentContractVersion
    isActive = false
    event = nil
    leaveAt = nil
    startAt = nil
    endAt = nil
  }

  public static var inactive: WatchAcceptanceProbe {
    WatchAcceptanceProbe(inactive: ())
  }

  public func liveState(at now: Date) -> CommanderLiveStateResult? {
    guard
      isActive,
      contractVersion == Self.currentContractVersion,
      let event,
      let leaveAt,
      let startAt,
      let endAt
    else { return nil }

    guard let resolution = CommanderLiveActivityTimeline.resolve(
      events: [.init(stableId: event.stableId, leaveAt: leaveAt, startAt: startAt, endAt: endAt)], at: now
    ) else { return nil }
    let state: CommanderLiveState = resolution.phase == .ended ? .dayDone
      : resolution.phase == .active ? .inProgress : resolution.departureDue ? .leaveNow : .upcoming

    let leadMinutes = max(0, Int(ceil(startAt.timeIntervalSince(leaveAt) / 60)))
    return CommanderLiveStateResult(
      state: state,
      event: event,
      nextEvent: nil,
      startAt: startAt,
      endAt: endAt,
      leaveAt: leaveAt,
      now: now,
      leadTimeMinutes: leadMinutes
    )
  }
}

public enum WatchAcceptanceProbeCodec {
  public static let applicationContextKey = "lazensky.commander.watch.acceptanceProbe.v1"
  public static let transportNonceKey = "lazensky.commander.watch.acceptanceNonce.v1"

  public static func encode(_ probe: WatchAcceptanceProbe) throws -> Data {
    try JSONEncoder().encode(probe)
  }

  public static func decode(_ data: Data) throws -> WatchAcceptanceProbe {
    let probe = try JSONDecoder().decode(WatchAcceptanceProbe.self, from: data)
    guard probe.contractVersion == WatchAcceptanceProbe.currentContractVersion,
          !probe.isActive || (
            probe.event != nil && probe.leaveAt != nil && probe.startAt != nil && probe.endAt != nil
            && probe.leaveAt! <= probe.startAt! && probe.startAt! < probe.endAt!
          )
    else {
      throw CocoaError(.coderReadCorrupt)
    }
    return probe
  }

  public static func applicationContext(for probe: WatchAcceptanceProbe) throws -> [String: Any] {
    [
      applicationContextKey: try encode(probe)
    ]
  }

  public static func decode(applicationContext: [String: Any]) throws -> WatchAcceptanceProbe? {
    guard let data = applicationContext[applicationContextKey] as? Data else { return nil }
    return try decode(data)
  }

  public static func merging(
    probe: WatchAcceptanceProbe?,
    into applicationContext: [String: Any]
  ) throws -> [String: Any] {
    var merged = applicationContext
    if let probe {
      merged[applicationContextKey] = try encode(probe)
    } else {
      merged.removeValue(forKey: applicationContextKey)
    }
    return merged
  }
}


public extension WatchAcceptanceProbe {
  static let inactiveAcknowledgementToken = "inactive"

  var acknowledgementToken: String {
    guard isActive,
          let stableId = event?.stableId,
          let startAt
    else {
      return Self.inactiveAcknowledgementToken
    }
    return stableId + "|" + String(format: "%.3f", startAt.timeIntervalSince1970)
  }
}

public enum WatchAcceptanceAcknowledgementCodec {
  public static let applicationContextKey =
    "lazensky.commander.watch.acceptanceAcknowledgement.v1"
  public static let transportNonceKey =
    "lazensky.commander.watch.acceptanceAcknowledgementNonce.v1"

  public static func merging(
    token: String,
    into applicationContext: [String: Any]
  ) -> [String: Any] {
    var merged = applicationContext
    merged[applicationContextKey] = token
    return merged
  }

  public static func decode(applicationContext: [String: Any]) -> String? {
    applicationContext[applicationContextKey] as? String
  }
}

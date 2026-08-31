import Foundation

public enum WatchScheduleTransportError: LocalizedError, Equatable, Sendable {
  case missingApplicationContextPayload
  case invalidPayload
  case unsupportedEnvelopeVersion(Int)
  case invalidMessageType(String)
  case invalidSnapshotContractVersion(Int)
  case invalidSchedule

  public var errorDescription: String? {
    switch self {
    case .missingApplicationContextPayload:
      "Watch application context neobsahuje schedule envelope."
    case .invalidPayload:
      "Watch schedule envelope nelze dekódovat."
    case .unsupportedEnvelopeVersion(let version):
      "Watch schedule envelope používá nepodporovanou verzi \(version)."
    case .invalidMessageType(let messageType):
      "Watch schedule envelope má neznámý typ \(messageType)."
    case .invalidSnapshotContractVersion(let version):
      "Watch schedule snapshot používá nepodporovanou verzi \(version)."
    case .invalidSchedule:
      "Watch schedule snapshot obsahuje nevalidní rozpis."
    }
  }
}

public struct WatchScheduleTransportEnvelope: Codable, Equatable, Sendable {
  public static let currentContractVersion = 1
  public static let scheduleMessageType = "lazensky.commander.watch-schedule"

  public let contractVersion: Int
  public let messageType: String
  public let scheduleSnapshot: WatchScheduleSnapshot

  public init(
    contractVersion: Int = currentContractVersion,
    messageType: String = scheduleMessageType,
    scheduleSnapshot: WatchScheduleSnapshot
  ) {
    self.contractVersion = contractVersion
    self.messageType = messageType
    self.scheduleSnapshot = scheduleSnapshot
  }
}

public enum WatchScheduleTransportCodec {
  public static let applicationContextKey = "com.varnakonvice.lazenskycommander.watch-schedule-envelope.v1"

  public static func encode(_ snapshot: WatchScheduleSnapshot) throws -> Data {
    try validate(snapshot)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(WatchScheduleTransportEnvelope(scheduleSnapshot: snapshot))
  }

  public static func decode(_ data: Data) throws -> WatchScheduleSnapshot {
    guard let envelope = try? JSONDecoder().decode(WatchScheduleTransportEnvelope.self, from: data) else {
      throw WatchScheduleTransportError.invalidPayload
    }
    guard envelope.contractVersion == WatchScheduleTransportEnvelope.currentContractVersion else {
      throw WatchScheduleTransportError.unsupportedEnvelopeVersion(envelope.contractVersion)
    }
    guard envelope.messageType == WatchScheduleTransportEnvelope.scheduleMessageType else {
      throw WatchScheduleTransportError.invalidMessageType(envelope.messageType)
    }
    try validate(envelope.scheduleSnapshot)
    return envelope.scheduleSnapshot
  }

  public static func applicationContext(for snapshot: WatchScheduleSnapshot) throws -> [String: Any] {
    [applicationContextKey: try encode(snapshot)]
  }

  public static func decode(applicationContext: [String: Any]) throws -> WatchScheduleSnapshot {
    guard let data = applicationContext[applicationContextKey] as? Data else {
      throw WatchScheduleTransportError.missingApplicationContextPayload
    }
    return try decode(data)
  }

  private static func validate(_ snapshot: WatchScheduleSnapshot) throws {
    guard snapshot.contractVersion == WatchScheduleSnapshot.currentContractVersion,
          snapshot.projectionRevision >= 0 else {
      throw WatchScheduleTransportError.invalidSnapshotContractVersion(snapshot.contractVersion)
    }
    do {
      try NativeAlarmContract.validateCanonical(snapshot.schedule)
      _ = try NativeAlarmContract.payload(
        schedule: snapshot.schedule,
        overrides: snapshot.leadTimeOverrides
      )
    } catch {
      throw WatchScheduleTransportError.invalidSchedule
    }
  }
}

public struct WatchScheduleAcknowledgement: Codable, Equatable, Sendable {
  public static let currentContractVersion = 1
  public let contractVersion: Int
  public let scheduleVersion: Int
  public let projectionRevision: Int

  public init(
    contractVersion: Int = currentContractVersion,
    scheduleVersion: Int,
    projectionRevision: Int = 0
  ) {
    self.contractVersion = contractVersion
    self.scheduleVersion = scheduleVersion
    self.projectionRevision = max(0, projectionRevision)
  }

  public var projectionIdentity: WatchScheduleProjectionIdentity {
    WatchScheduleProjectionIdentity(
      scheduleVersion: scheduleVersion,
      projectionRevision: projectionRevision
    )
  }

  private enum CodingKeys: String, CodingKey {
    case contractVersion
    case scheduleVersion
    case projectionRevision
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    contractVersion = try values.decode(Int.self, forKey: .contractVersion)
    scheduleVersion = try values.decode(Int.self, forKey: .scheduleVersion)
    projectionRevision = max(0, try values.decodeIfPresent(Int.self, forKey: .projectionRevision) ?? 0)
  }
}

public enum WatchScheduleAcknowledgementCodec {
  public static let applicationContextKey = "com.varnakonvice.lazenskycommander.watch-schedule-ack.v1"

  public static func applicationContext(
    scheduleVersion: Int,
    projectionRevision: Int = 0
  ) throws -> [String: Any] {
    guard scheduleVersion > 0, projectionRevision >= 0 else {
      throw WatchScheduleTransportError.invalidSchedule
    }
    let acknowledgement = WatchScheduleAcknowledgement(
      scheduleVersion: scheduleVersion,
      projectionRevision: projectionRevision
    )
    return [applicationContextKey: try JSONEncoder().encode(acknowledgement)]
  }

  public static func decode(applicationContext: [String: Any]) throws -> WatchScheduleAcknowledgement {
    guard let data = applicationContext[applicationContextKey] as? Data else {
      throw WatchScheduleTransportError.missingApplicationContextPayload
    }
    guard let acknowledgement = try? JSONDecoder().decode(WatchScheduleAcknowledgement.self, from: data) else {
      throw WatchScheduleTransportError.invalidPayload
    }
    guard acknowledgement.contractVersion == WatchScheduleAcknowledgement.currentContractVersion,
          acknowledgement.scheduleVersion > 0,
          acknowledgement.projectionRevision >= 0
    else { throw WatchScheduleTransportError.invalidPayload }
    return acknowledgement
  }
}

public enum WatchScheduleDeliveryDisposition: Equatable, Sendable {
  case queued
  case sent
}

public protocol WatchScheduleSnapshotDelivering: Sendable {
  func deliver(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleDeliveryDisposition
  func verifiedScheduleVersion() async -> Int?
  func verifiedProjectionIdentity() async -> WatchScheduleProjectionIdentity?
}

public extension WatchScheduleSnapshotDelivering {
  func verifiedScheduleVersion() async -> Int? { nil }

  func verifiedProjectionIdentity() async -> WatchScheduleProjectionIdentity? {
    guard let scheduleVersion = await verifiedScheduleVersion() else { return nil }
    return WatchScheduleProjectionIdentity(scheduleVersion: scheduleVersion, projectionRevision: 0)
  }
}

public enum WatchScheduleDeliveryStatus: Equatable, Sendable {
  case notConfigured
  case notAttempted
  case queued
  case sent
  case verified
  case failed(String)
}

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
    guard snapshot.contractVersion == WatchScheduleSnapshot.currentContractVersion else {
      throw WatchScheduleTransportError.invalidSnapshotContractVersion(snapshot.contractVersion)
    }
    do {
      try NativeAlarmContract.validate(snapshot.schedule)
    } catch {
      throw WatchScheduleTransportError.invalidSchedule
    }
  }
}

public enum WatchScheduleDeliveryDisposition: Equatable, Sendable {
  case queued
  case sent
}

public protocol WatchScheduleSnapshotDelivering: Sendable {
  func deliver(_ snapshot: WatchScheduleSnapshot) async throws -> WatchScheduleDeliveryDisposition
}

public enum WatchScheduleDeliveryStatus: Equatable, Sendable {
  case notConfigured
  case notAttempted
  case queued
  case sent
  case failed(String)
}

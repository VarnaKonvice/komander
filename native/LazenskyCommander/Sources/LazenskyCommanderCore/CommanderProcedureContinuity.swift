import Foundation

public struct CommanderProcedureContinuationMatch: Equatable, Sendable {
  public let precedingStableID: String
  public let continuingStableID: String
  public let fromCanonicalType: String
  public let toCanonicalType: String
  public let gapMinutes: Int

  public init(
    precedingStableID: String,
    continuingStableID: String,
    fromCanonicalType: String,
    toCanonicalType: String,
    gapMinutes: Int
  ) {
    self.precedingStableID = precedingStableID
    self.continuingStableID = continuingStableID
    self.fromCanonicalType = fromCanonicalType
    self.toCanonicalType = toCanonicalType
    self.gapMinutes = gapMinutes
  }
}

public enum CommanderProcedureContinuity {
  public static func matches(
    schedule: Schedule,
    profile: CommanderSpaProfile
  ) throws -> [CommanderProcedureContinuationMatch] {
    try profile.validate()
    guard !profile.continuationRules.isEmpty else { return [] }

    let procedureEvents = schedule.events.filter { $0.kind == .procedure }
    let byDate = Dictionary(grouping: procedureEvents) { $0.date }
    var result: [CommanderProcedureContinuationMatch] = []

    for date in byDate.keys.sorted() {
      let ordered = (byDate[date] ?? []).sorted {
        ($0.start, $0.end, $0.stableId) < ($1.start, $1.end, $1.stableId)
      }
      guard ordered.count > 1 else { continue }

      for index in 0..<(ordered.count - 1) {
        let first = ordered[index]
        let second = ordered[index + 1]

        guard
          let firstDefinition = profile.procedureDefinition(
            matching: first.procedureType ?? first.title
          ),
          let secondDefinition = profile.procedureDefinition(
            matching: second.procedureType ?? second.title
          ),
          let rule = matchingRule(
            from: firstDefinition.canonicalType,
            to: secondDefinition.canonicalType,
            in: profile
          ),
          let firstEnd = try? NativeAlarmContract.dateTime(date: first.date, time: first.end),
          let secondStart = try? NativeAlarmContract.dateTime(date: second.date, time: second.start)
        else { continue }

        let gapSeconds = secondStart.timeIntervalSince(firstEnd)
        guard gapSeconds >= 0 else { continue }
        let gapMinutes = Int(gapSeconds / 60)
        guard gapMinutes <= rule.maximumGapMinutes else { continue }

        if rule.requiresSameLocation {
          let firstLocation = CommanderSpaProfile.normalizedLookupKey(first.location)
          let secondLocation = CommanderSpaProfile.normalizedLookupKey(second.location)
          guard !firstLocation.isEmpty, firstLocation == secondLocation else { continue }
        }

        result.append(
          CommanderProcedureContinuationMatch(
            precedingStableID: first.stableId,
            continuingStableID: second.stableId,
            fromCanonicalType: firstDefinition.canonicalType,
            toCanonicalType: secondDefinition.canonicalType,
            gapMinutes: gapMinutes
          )
        )
      }
    }

    return result
  }

  public static func suppressedAlertStableIDs(
    schedule: Schedule,
    profile: CommanderSpaProfile
  ) throws -> Set<String> {
    Set(try matches(schedule: schedule, profile: profile).map { $0.continuingStableID })
  }

  private static func matchingRule(
    from: String,
    to: String,
    in profile: CommanderSpaProfile
  ) -> CommanderSpaContinuationRule? {
    let normalizedFrom = CommanderSpaProfile.normalizedLookupKey(from)
    let normalizedTo = CommanderSpaProfile.normalizedLookupKey(to)
    return profile.continuationRules.first {
      CommanderSpaProfile.normalizedLookupKey($0.fromCanonicalType) == normalizedFrom &&
      CommanderSpaProfile.normalizedLookupKey($0.toCanonicalType) == normalizedTo
    }
  }
}

import Foundation

public struct AlarmChange: Equatable, Sendable {
  public let stableId: String
  public let currentAlarm: NativeAlarm?
  public let nextAlarm: NativeAlarm?
}

public struct AlarmReconciliationPlan: Equatable, Sendable {
  public var create: [AlarmChange]
  public var update: [AlarmChange]
  public var cancel: [AlarmChange]
  public var unchanged: [AlarmChange]

  public init(create: [AlarmChange] = [], update: [AlarmChange] = [], cancel: [AlarmChange] = [], unchanged: [AlarmChange] = []) {
    self.create = create
    self.update = update
    self.cancel = cancel
    self.unchanged = unchanged
  }
}

public enum AlarmReconciler {
  public static func reconcile(current: [NativeAlarm], next: NativeAlarmPayload) -> AlarmReconciliationPlan {
    var currentByStableId = Dictionary(uniqueKeysWithValues: current.map { ($0.stableId, $0) })
    var plan = AlarmReconciliationPlan()
    for nextAlarm in next.alarms {
      guard let currentAlarm = currentByStableId.removeValue(forKey: nextAlarm.stableId) else {
        plan.create.append(AlarmChange(stableId: nextAlarm.stableId, currentAlarm: nil, nextAlarm: nextAlarm))
        continue
      }
      if sameAlarmContent(currentAlarm, nextAlarm) {
        plan.unchanged.append(AlarmChange(stableId: nextAlarm.stableId, currentAlarm: currentAlarm, nextAlarm: nextAlarm))
      } else {
        plan.update.append(AlarmChange(stableId: nextAlarm.stableId, currentAlarm: currentAlarm, nextAlarm: nextAlarm))
      }
    }
    plan.cancel = currentByStableId.keys.sorted().compactMap { stableId in
      currentByStableId[stableId].map { AlarmChange(stableId: stableId, currentAlarm: $0, nextAlarm: nil) }
    }
    return plan
  }

  public static func sameAlarmContent(_ lhs: NativeAlarm, _ rhs: NativeAlarm) -> Bool {
    lhs.kind == rhs.kind && lhs.title == rhs.title && lhs.location == rhs.location && lhs.startAt == rhs.startAt && lhs.endAt == rhs.endAt && lhs.effectiveLeadTimeMinutes == rhs.effectiveLeadTimeMinutes && lhs.leaveAt == rhs.leaveAt
  }
}

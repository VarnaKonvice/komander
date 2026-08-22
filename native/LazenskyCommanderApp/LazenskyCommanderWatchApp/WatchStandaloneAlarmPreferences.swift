import Foundation
import LazenskyCommanderCore

final class WatchStandaloneAlarmPreferences: @unchecked Sendable {
  private enum Key {
    static let isEnabled = "watchStandaloneAlarmsEnabled"
    static let lastReconciledScheduleVersion = "watchStandaloneAlarmsLastScheduleVersion"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults? = UserDefaults(
    suiteName: CommanderWatchWidgetContract.appGroupIdentifier
  )) {
    guard let defaults else {
      preconditionFailure("Watch alarm App Group preferences are unavailable.")
    }
    self.defaults = defaults
  }

  var isEnabled: Bool {
    get { defaults.bool(forKey: Key.isEnabled) }
    set { defaults.set(newValue, forKey: Key.isEnabled) }
  }

  var lastReconciledScheduleVersion: Int? {
    get {
      guard defaults.object(forKey: Key.lastReconciledScheduleVersion) != nil else { return nil }
      return defaults.integer(forKey: Key.lastReconciledScheduleVersion)
    }
    set {
      if let newValue {
        defaults.set(newValue, forKey: Key.lastReconciledScheduleVersion)
      } else {
        defaults.removeObject(forKey: Key.lastReconciledScheduleVersion)
      }
    }
  }
}

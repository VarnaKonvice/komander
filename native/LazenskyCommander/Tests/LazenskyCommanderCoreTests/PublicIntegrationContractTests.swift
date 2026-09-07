#if canImport(Testing)
import Testing
import LazenskyCommanderCore

// Keep this import non-testable: app and Watch targets cannot see internal APIs.
// Behavioral fixtures elsewhere deliberately use internal memberwise initializers.
@Test func appAndWatchIntegrationEntryPointsArePublic() {
  let project: (ScheduleEvent, Schedule, LeadTimeOverrides?) throws -> NativeAlarm = NativeAlarmContract.alarm
  _ = project
  #expect(!WatchNotificationPlan().hasChanges)
}
#endif

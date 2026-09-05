#if canImport(Testing)
import Foundation
import Testing
@testable import LazenskyCommanderCore

@Test func provisioningMetadataReadsTypedDatesAndChecksTheAppIdentifier() throws {
  for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
    let data = try profilePlist(format: format)
    let metadata = ProvisioningProfileMetadata.decodePropertyList(data, bundleIdentifier: provisioningBundle)
    #expect(metadata?.creationDate == provisioningDate("2026-08-31T10:00:00Z"))
    #expect(metadata?.expirationDate == provisioningDate("2026-09-07T10:00:00Z"))
    #expect(metadata?.recommendedRefreshAt == provisioningDate("2026-09-06T10:00:00Z"))
    #expect(ProvisioningProfileMetadata.decodePropertyList(data, bundleIdentifier: "com.someone.else") == nil)
  }
  let wildcard = try profilePlist(appID: "TEAM.com.varnakonvice.*")
  #expect(ProvisioningProfileMetadata.decodePropertyList(wildcard, bundleIdentifier: provisioningBundle) != nil)
  #expect(ProvisioningProfileMetadata.decodePropertyList(wildcard, bundleIdentifier: "com.varnakonviceevil.app") == nil)
}

@Test func missingInvalidOrUnsignedProvisioningProfilesAreUnavailable() throws {
  #expect(ProvisioningProfileMetadata.readEmbeddedProfile(at: nil, bundleIdentifier: provisioningBundle) == nil)
  #expect(ProvisioningProfileMetadata.readEmbeddedProfile(at: URL(fileURLWithPath: "/nonexistent/profile"), bundleIdentifier: provisioningBundle) == nil)
  #expect(ProvisioningProfileMetadata.decodePropertyList(Data("invalid".utf8), bundleIdentifier: provisioningBundle) == nil)
  for invalid: [String: Any] in [[:], ["CreationDate": "2026-08-31"], ["ExpirationDate": Date()]] {
    let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
    #expect(ProvisioningProfileMetadata.decodePropertyList(data, bundleIdentifier: provisioningBundle) == nil)
  }
  #expect(ProvisioningProfileMetadata(creationDate: Date(timeIntervalSince1970: .nan), expirationDate: Date()) == nil)
  #expect(ProvisioningProfileMetadata(creationDate: Date(timeIntervalSince1970: 20), expirationDate: Date(timeIntervalSince1970: 10)) == nil)
  #expect(ProvisioningProfileMetadata(creationDate: Date(timeIntervalSince1970: 20), expirationDate: Date(timeIntervalSince1970: 20)) == nil)
}

@Test func provisioningCMSReadsOnlyTheBoundedEncapsulatedPropertyList() throws {
  let plist = try profilePlist()
  let cms = profileCMS(plist)
  #expect(ProvisioningCMS.propertyList(in: cms) == plist)
  #expect(ProvisioningCMS.propertyList(in: plist) == nil)
  #expect(ProvisioningCMS.propertyList(in: Data("garbage".utf8) + cms) == nil)
  #expect(ProvisioningCMS.propertyList(in: cms + Data([0])) == nil)
  for length in 0..<cms.count {
    #expect(ProvisioningCMS.propertyList(in: cms.prefix(length)) == nil)
  }
  #expect(ProvisioningCMS.propertyList(in: Data([0x30, 0x80, 0, 0])) == nil)
  #expect(ProvisioningCMS.propertyList(in: Data([0x30, 0x84, 0xff, 0xff, 0xff, 0xff])) == nil)
  #expect(ProvisioningCMS.propertyList(in: Data(repeating: 0, count: 1_048_577)) == nil)
  var wrongOID = cms
  let oidIndex = try #require(wrongOID.firstRange(of: Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 1, 7, 2])))
  wrongOID[oidIndex.upperBound - 1] = 1
  #expect(ProvisioningCMS.propertyList(in: wrongOID) == nil)
}

@Test func provisioningFileReaderUsesTheEmbeddedCMSNotAStandalonePlist() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("embedded.mobileprovision")
  let plist = try profilePlist()
  try profileCMS(plist).write(to: url)
  #expect(ProvisioningProfileMetadata.readEmbeddedProfile(at: url, bundleIdentifier: provisioningBundle) != nil)
  try plist.write(to: url)
  #expect(ProvisioningProfileMetadata.readEmbeddedProfile(at: url, bundleIdentifier: provisioningBundle) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LC_TEST_EMBEDDED_PROFILE"] != nil))
func localSignedProfileMatchesSecurityCMSDecodedMetadata() throws {
  let env = ProcessInfo.processInfo.environment
  let embedded = try #require(env["LC_TEST_EMBEDDED_PROFILE"])
  let decoded = try #require(env["LC_TEST_DECODED_PROFILE"])
  let metadata = try #require(ProvisioningProfileMetadata.readEmbeddedProfile(at: URL(fileURLWithPath: embedded), bundleIdentifier: provisioningBundle))
  let plist = try Data(contentsOf: URL(fileURLWithPath: decoded))
  #expect(metadata == ProvisioningProfileMetadata.decodePropertyList(plist, bundleIdentifier: provisioningBundle))
}

@Test func provisioningDeadlineSubtractsCalendarDayAcrossDSTAndYearBoundary() throws {
  for (expiration, expected) in [
    ("2026-03-29T10:00:00Z", "2026-03-28T11:00:00Z"),
    ("2026-10-25T11:00:00Z", "2026-10-24T10:00:00Z"),
    ("2027-01-01T11:00:00Z", "2026-12-31T11:00:00Z")
  ] {
    let profile = try #require(ProvisioningProfileMetadata(creationDate: provisioningDate("2026-01-01T00:00:00Z"), expirationDate: provisioningDate(expiration)))
    #expect(profile.recommendedRefreshAt == provisioningDate(expected))
  }
}

@Test @MainActor func earlierRenewalReplacesExactlyOneReminderAndPreservesForeignNotifications() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let old = provisioningProfile()
  let new = provisioningProfile(creation: "2026-09-02T10:00:00Z", expiration: "2026-09-09T10:00:00Z")
  #expect(await service.refresh(profile: old, now: old.creationDate) == .scheduled(old.recommendedRefreshAt))
  #expect(await service.refresh(profile: new, now: new.creationDate) == .scheduled(new.recommendedRefreshAt))
  #expect(notifications.pending.count == 2)
  #expect(notifications.pending[ProvisioningReminderRequest.identifier]?.fireAt == new.recommendedRefreshAt)
  #expect(notifications.pending["lazensky.commander.iphone.fallback.procedure"] == notifications.foreign)
  #expect(notifications.replacements == 2)
  #expect(notifications.removedPending == [ProvisioningReminderRequest.identifier, ProvisioningReminderRequest.identifier])
}

@Test @MainActor func sameProfileNeverMovesDeadlineToTodayPlusSixOrDuplicatesReminder() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  _ = await service.refresh(profile: profile, now: profile.creationDate)
  #expect(await service.refresh(profile: profile, now: provisioningDate("2026-09-04T10:00:00Z")) == .scheduled(profile.recommendedRefreshAt))
  #expect(notifications.replacements == 1)
  #expect(notifications.pending[ProvisioningReminderRequest.identifier]?.fireAt == provisioningDate("2026-09-06T10:00:00Z"))
}

@Test @MainActor func dueProfileKeepsAlreadyDeliveredProvisioningReminder() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  notifications.pending[ProvisioningReminderRequest.identifier] = ProvisioningReminderRequest(
    fireAt: profile.recommendedRefreshAt,
    profileCreatedAt: profile.creationDate,
    profileExpiresAt: profile.expirationDate
  )
  notifications.delivered.insert(ProvisioningReminderRequest.identifier)

  #expect(await service.refresh(profile: profile, now: profile.recommendedRefreshAt) == .due)
  #expect(notifications.pending[ProvisioningReminderRequest.identifier] == nil)
  #expect(notifications.delivered.contains(ProvisioningReminderRequest.identifier))
  #expect(notifications.pending["lazensky.commander.iphone.fallback.procedure"] == notifications.foreign)
  #expect(notifications.delivered.contains("lazensky.commander.iphone.fallback.procedure"))
}

@Test @MainActor func newValidProvisioningProfileClearsOldDeliveredReminder() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let renewed = provisioningProfile(creation: "2026-09-02T10:00:00Z", expiration: "2026-09-09T10:00:00Z")
  notifications.delivered.insert(ProvisioningReminderRequest.identifier)

  #expect(await service.refresh(profile: renewed, now: renewed.creationDate) == .scheduled(renewed.recommendedRefreshAt))
  #expect(notifications.pending[ProvisioningReminderRequest.identifier]?.fireAt == renewed.recommendedRefreshAt)
  #expect(!notifications.delivered.contains(ProvisioningReminderRequest.identifier))
  #expect(notifications.delivered.contains("lazensky.commander.iphone.fallback.procedure"))
}

@Test @MainActor func pendingProvisioningReminderCanBeReplacedAndCancelledSeparately() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let old = provisioningProfile()
  let renewed = provisioningProfile(creation: "2026-09-02T10:00:00Z", expiration: "2026-09-09T10:00:00Z")

  #expect(await service.refresh(profile: old, now: old.creationDate) == .scheduled(old.recommendedRefreshAt))
  #expect(await service.refresh(profile: renewed, now: renewed.creationDate) == .scheduled(renewed.recommendedRefreshAt))
  #expect(notifications.pending[ProvisioningReminderRequest.identifier]?.fireAt == renewed.recommendedRefreshAt)
  #expect(notifications.replacements == 2)

  #expect(await service.refresh(profile: renewed, now: renewed.recommendedRefreshAt) == .due)
  #expect(notifications.pending[ProvisioningReminderRequest.identifier] == nil)
  #expect(notifications.pending["lazensky.commander.iphone.fallback.procedure"] == notifications.foreign)
}

@Test @MainActor func provisioningPermissionIsOnlyRequestedByAnExplicitUserAction() async {
  let notifications = ProvisioningNotificationsFake()
  notifications.authorization = .notRequested
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  #expect(await service.refresh(profile: profile, now: profile.creationDate) == .permissionRequired)
  #expect(notifications.permissionRequests == 0)
  #expect(notifications.replacements == 0)
  #expect(await service.refresh(profile: profile, now: profile.creationDate, requestPermission: true) == .scheduled(profile.recommendedRefreshAt))
  #expect(notifications.permissionRequests == 1)
  notifications.authorization = .denied
  #expect(await service.refresh(profile: profile, now: profile.creationDate, requestPermission: true) == .denied)
  #expect(notifications.permissionRequests == 1)
  #expect(notifications.pending[ProvisioningReminderRequest.identifier] == nil)
  #expect(notifications.pending.count == 1)
}

@Test @MainActor func expiredDueAndUnavailableProfilesDoNotRepeatedlyArmPastReminders() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  _ = await service.refresh(profile: profile, now: profile.creationDate)
  for _ in 0..<2 {
    #expect(await service.refresh(profile: profile, now: profile.recommendedRefreshAt) == .due)
    #expect(await service.refresh(profile: profile, now: profile.expirationDate) == .expired)
    #expect(await service.refresh(profile: nil, now: profile.creationDate) == .unavailable)
  }
  #expect(notifications.replacements == 1)
  #expect(notifications.pending == ["lazensky.commander.iphone.fallback.procedure": notifications.foreign])
  #expect(notifications.delivered.contains("lazensky.commander.iphone.fallback.procedure"))
}

@Test @MainActor func provisioningSchedulingFailureAndReadbackMismatchNeverReportScheduled() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  notifications.failAdd = true
  #expect(await service.refresh(profile: profile, now: profile.creationDate) == .failed)
  notifications.failAdd = false
  notifications.dropAdd = true
  #expect(await service.refresh(profile: profile, now: profile.creationDate) == .failed)
  notifications.dropAdd = false
  #expect(await service.refresh(profile: profile, now: profile.creationDate) == .scheduled(profile.recommendedRefreshAt))
  #expect(notifications.pending.count == 2)
}

@Test @MainActor func overlappingProvisioningRefreshesAreSerialized() async {
  let notifications = ProvisioningNotificationsFake()
  let service = ProvisioningReminderCoordinator(notifications: notifications)
  let profile = provisioningProfile()
  async let first = service.refresh(profile: profile, now: profile.creationDate)
  async let second = service.refresh(profile: profile, now: profile.creationDate)
  let results = await [first, second]
  #expect(results == [.scheduled(profile.recommendedRefreshAt), .scheduled(profile.recommendedRefreshAt)])
  #expect(notifications.replacements == 1)
}

@Test func provisioningReminderIsSeparatedFromAlarmAndScheduleServices() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let app = root.appendingPathComponent("native/LazenskyCommanderApp/LazenskyCommanderApp")
  let service = try String(contentsOf: app.appendingPathComponent("CommanderProvisioningRenewal.swift"), encoding: .utf8)
  #expect(service.contains("withIdentifiers: [identifier]"))
  #expect(service.contains("removePendingNotificationRequests(withIdentifiers: [identifier])"))
  #expect(service.contains("removeDeliveredNotifications(withIdentifiers: [identifier])"))
  #expect(service.contains("options: [.alert, .sound]"))
  #expect(service.contains("AppConfiguration().channel == .production"))
  for forbidden in ["removeAllPending", "AlarmKit", "NativeAlarmContract", "UserDefaults", "fetchSchedule", "synchronize(", "timeSensitive"] {
    #expect(!service.contains(forbidden))
  }
  #expect(!ProvisioningReminderRequest.identifier.hasPrefix("lazensky.commander.iphone.fallback."))
  let tabs = try String(contentsOf: app.appendingPathComponent("CommanderAppTabs.swift"), encoding: .utf8)
  #expect(tabs.contains(".task {"))
  #expect(tabs.contains("guard !CommanderRuntime.alarmFreeVisualTest else { return }"))
  #expect(tabs.contains("await renewal.refresh()"))
  #expect(tabs.contains(".onChange(of: scenePhase)"))
  #expect(tabs.contains("guard phase == .active, !CommanderRuntime.alarmFreeVisualTest else { return }"))
  #expect(tabs.contains("Task { await renewal.refresh() }"))
}

private let provisioningBundle = "com.varnakonvice.lazenskycommander"

private func provisioningDate(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private func provisioningProfile(creation: String = "2026-08-31T10:00:00Z", expiration: String = "2026-09-07T10:00:00Z") -> ProvisioningProfileMetadata {
  ProvisioningProfileMetadata(creationDate: provisioningDate(creation), expirationDate: provisioningDate(expiration))!
}

private func profilePlist(format: PropertyListSerialization.PropertyListFormat = .xml, appID: String = "TEAM.com.varnakonvice.lazenskycommander") throws -> Data {
  try PropertyListSerialization.data(fromPropertyList: [
    "CreationDate": provisioningDate("2026-08-31T10:00:00Z"),
    "ExpirationDate": provisioningDate("2026-09-07T10:00:00Z"),
    "Entitlements": ["application-identifier": appID]
  ], format: format, options: 0)
}

private func profileCMS(_ plist: Data) -> Data {
  let signedOID = der(0x06, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 1, 7, 2]))
  let dataOID = der(0x06, Data([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 1, 7, 1]))
  let encapsulated = der(0x30, dataOID + der(0xa0, der(0x04, plist)))
  return der(0x30, signedOID + der(0xa0, der(0x30, der(0x02, Data([1])) + der(0x31, Data()) + encapsulated + der(0x31, Data()))))
}

private func der(_ tag: UInt8, _ body: Data) -> Data {
  var length = body.count
  var bytes: [UInt8] = []
  repeat { bytes.insert(UInt8(length & 0xff), at: 0); length >>= 8 } while length > 0
  let encoded = body.count < 128 ? [UInt8(body.count)] : [0x80 | UInt8(bytes.count)] + bytes
  return Data([tag] + encoded) + body
}

@MainActor private final class ProvisioningNotificationsFake: ProvisioningReminderNotifications {
  let foreign = ProvisioningReminderRequest(fireAt: provisioningDate("2026-09-01T09:00:00Z"), profileCreatedAt: Date(), profileExpiresAt: Date())
  var pending: [String: ProvisioningReminderRequest] = [:]
  var delivered: Set<String> = []
  var authorization: ProvisioningNotificationPermission = .allowed
  var replacements = 0
  var permissionRequests = 0
  var removedPending: [String] = []
  var removedDelivered: [String] = []
  var failAdd = false
  var dropAdd = false
  init() {
    pending["lazensky.commander.iphone.fallback.procedure"] = foreign
    delivered.insert("lazensky.commander.iphone.fallback.procedure")
  }
  func permission() async -> ProvisioningNotificationPermission { authorization }
  func requestPermission() async throws -> Bool { permissionRequests += 1; authorization = .allowed; return true }
  func pendingReminder() async -> ProvisioningReminderRequest? {
    await Task.yield()
    return pending[ProvisioningReminderRequest.identifier]
  }
  func replaceReminder(_ request: ProvisioningReminderRequest) async throws {
    await clearPendingReminder()
    if failAdd { throw CocoaError(.fileWriteUnknown) }
    replacements += 1
    if !dropAdd { pending[ProvisioningReminderRequest.identifier] = request }
  }
  func clearPendingReminder() async {
    removedPending.append(ProvisioningReminderRequest.identifier)
    pending.removeValue(forKey: ProvisioningReminderRequest.identifier)
  }
  func clearDeliveredReminder() async {
    removedDelivered.append(ProvisioningReminderRequest.identifier)
    delivered.remove(ProvisioningReminderRequest.identifier)
  }
}
#endif

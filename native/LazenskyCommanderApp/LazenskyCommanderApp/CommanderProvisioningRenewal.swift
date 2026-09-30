import LazenskyCommanderCore
import SwiftUI
import UserNotifications

@MainActor final class CommanderProvisioningRenewal: ObservableObject {
  @Published private(set) var profile: ProvisioningProfileMetadata?
  @Published private(set) var status: ProvisioningReminderStatus = .unavailable
  @Published private(set) var isRefreshing = false
  private let coordinator = ProvisioningReminderCoordinator(notifications: ProvisioningNotificationCenter())

  func refresh(requestPermission: Bool = false) async {
    guard AppConfiguration().channel == .production else { return }
    isRefreshing = true
    defer { isRefreshing = false }
    let metadata = ProvisioningProfileMetadata.readEmbeddedProfile(
      at: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
      bundleIdentifier: Bundle.main.bundleIdentifier ?? ""
    )
    profile = metadata
    status = await coordinator.refresh(profile: metadata, now: Date(), requestPermission: requestPermission)
  }
}

struct CommanderProvisioningSection: View {
  @EnvironmentObject private var renewal: CommanderProvisioningRenewal
  @Environment(\.openURL) private var openURL

  var body: some View {
    if AppConfiguration().channel == .production {
      CommanderSectionCard(
        title: "Obnova aplikace",
        symbol: "arrow.clockwise.circle.fill",
        accent: deadlineAccent
      ) {
        if let profile = renewal.profile {
          CommanderDetailRow(
            title: "Platnost aplikace do",
            value: profile.expirationDate.formatted(CommanderScheduleDateStyle.departure),
            symbol: "checkmark.seal.fill",
            accent: CommanderDesignTokens.Colors.primaryPurple
          )
          CommanderDetailRow(
            title: "Obnovit nejpozději",
            value: profile.recommendedRefreshAt.formatted(CommanderScheduleDateStyle.departure),
            symbol: "clock.badge.exclamationmark.fill",
            accent: deadlineAccent,
            valueColor: deadlineAccent
          )
        } else {
          Text("Platnost aplikace není dostupná")
            .commanderFont(.subtitle)
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        }
        CommanderDetailRow(
          title: "Připomenutí",
          value: statusText,
          symbol: "bell.badge.fill",
          accent: reminderAccent,
          valueColor: reminderAccent
        )
        if renewal.status == .permissionRequired || renewal.status == .denied {
          Button {
            if renewal.status == .denied {
              if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } else {
              Task { await renewal.refresh(requestPermission: true) }
            }
          } label: {
            actionLabel("Povolit připomenutí obnovy", symbol: "bell.badge")
          }
          .buttonStyle(.plain)
          .disabled(renewal.isRefreshing)
        } else if renewal.status == .failed {
          Button { Task { await renewal.refresh() } } label: {
            actionLabel("Zkusit připomenutí znovu", symbol: "arrow.clockwise")
          }
          .buttonStyle(.plain)
          .disabled(renewal.isRefreshing)
        }
      }
    }
  }

  private var statusText: String {
    switch renewal.status {
    case .unavailable: "Nedostupné"
    case .permissionRequired, .denied: "Nepovoleno"
    case .scheduled: "Naplánováno"
    case .due: "Obnov aplikaci nyní"
    case .expired: "Platnost vypršela"
    case .failed: "Nepodařilo se nastavit"
    }
  }

  private var deadlineAccent: Color {
    switch renewal.status {
    case .scheduled: CommanderDesignTokens.Colors.mealGreen
    case .permissionRequired, .denied, .failed: CommanderDesignTokens.Colors.urgentOrange
    case .due, .expired: CommanderDesignTokens.Colors.criticalRed
    case .unavailable: CommanderDesignTokens.Colors.textSecondary
    }
  }

  private var reminderAccent: Color {
    switch renewal.status {
    case .scheduled: CommanderDesignTokens.Colors.mealGreen
    case .permissionRequired, .denied, .failed: CommanderDesignTokens.Colors.urgentOrange
    case .due, .expired: CommanderDesignTokens.Colors.criticalRed
    case .unavailable: CommanderDesignTokens.Colors.textSecondary
    }
  }

  private func actionLabel(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .commanderFont(.metric)
      .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
      .padding(CommanderDesignTokens.Spacing.small)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(reminderAccent.opacity(0.18))
      .clipShape(RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset))
      .overlay {
        RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.inset)
          .strokeBorder(reminderAccent.opacity(0.5), lineWidth: 1)
      }
  }
}

@MainActor private final class ProvisioningNotificationCenter: ProvisioningReminderNotifications {
  private let center = UNUserNotificationCenter.current()
  private let identifier = ProvisioningReminderRequest.identifier

  func permission() async -> ProvisioningNotificationPermission {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized, .provisional, .ephemeral: .allowed
    case .notDetermined: .notRequested
    case .denied: .denied
    @unknown default: .denied
    }
  }

  func requestPermission() async throws -> Bool {
    try await center.requestAuthorization(options: [.alert, .sound])
  }

  func pendingReminder() async -> ProvisioningReminderRequest? {
    guard let request = await center.pendingNotificationRequests().first(where: { $0.identifier == identifier }),
          request.content.title == ProvisioningReminderRequest.title,
          request.content.body == ProvisioningReminderRequest.body,
          let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
          let fireAt = trigger.nextTriggerDate(),
          let created = request.content.userInfo["profileCreatedAt"] as? Double,
          let expires = request.content.userInfo["profileExpiresAt"] as? Double else { return nil }
    return ProvisioningReminderRequest(fireAt: fireAt,
      profileCreatedAt: Date(timeIntervalSince1970: created), profileExpiresAt: Date(timeIntervalSince1970: expires))
  }

  func replaceReminder(_ request: ProvisioningReminderRequest) async throws {
    await clearPendingReminder()
    let content = UNMutableNotificationContent()
    content.title = ProvisioningReminderRequest.title
    content.body = ProvisioningReminderRequest.body
    content.sound = .default
    content.interruptionLevel = .active
    content.userInfo = ["profileCreatedAt": request.profileCreatedAt.timeIntervalSince1970,
                        "profileExpiresAt": request.profileExpiresAt.timeIntervalSince1970]
    var calendar = Calendar(identifier: .gregorian)
    // The deadline is already a Prague-calendar date; UTC avoids ambiguous DST triggers.
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireAt)
    components.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
  }

  func clearPendingReminder() async {
    center.removePendingNotificationRequests(withIdentifiers: [identifier])
  }

  func clearDeliveredReminder() async {
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }
}

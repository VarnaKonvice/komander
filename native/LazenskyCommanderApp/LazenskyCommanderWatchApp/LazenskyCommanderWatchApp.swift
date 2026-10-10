import SwiftUI
import UserNotifications
import LazenskyCommanderCore

@main
struct LazenskyCommanderWatchApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: WatchCommanderModel
  @State private var connectivity: WatchConnectivityReceiver
  private let notificationDelegate: CommanderWatchNotificationDelegate

  init() {
    let model = WatchCommanderModel()
    let notificationDelegate = CommanderWatchNotificationDelegate(model: model)
    self.notificationDelegate = notificationDelegate
    UNUserNotificationCenter.current().delegate = notificationDelegate
    _model = State(initialValue: model)
    _connectivity = State(initialValue: WatchConnectivityReceiver(model: model))

  }

  var body: some Scene {
    WindowGroup {
      WatchCommanderView(model: model)
        .task {
          connectivity.activate()
          await model.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          Task { await model.handleForeground() }
        }
    }
    // Use the system long-look/default action; the only destination is WindowGroup.
  }
}

/// Installed during App.init, before a cold-launch response can be delivered.
final class CommanderWatchNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let model: WatchCommanderModel
  init(model: WatchCommanderModel) { self.model = model }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse) async {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
    // Return to watchOS immediately. Opening the app must not await cache I/O,
    // connectivity, or notification authorization/cleanup callbacks.
    Task { @MainActor [model] in
      await model.bootstrap()
    }
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}

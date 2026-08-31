import SwiftUI

@main
struct LazenskyCommanderWatchApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var model: WatchCommanderModel
  @State private var connectivity: WatchConnectivityReceiver

  init() {
    let model = WatchCommanderModel()
    _model = State(initialValue: model)
    _connectivity = State(initialValue: WatchConnectivityReceiver(model: model))
  }

  var body: some Scene {
    WindowGroup {
      WatchCommanderView(model: model)
        .task {
          await model.bootstrap()
          connectivity.activate()
        }
        .onChange(of: scenePhase) { _, phase in
          guard phase == .active else { return }
          Task { await model.handleForeground() }
        }
    }
  }
}

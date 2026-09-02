import SwiftUI

struct CommanderAppTabs: View {
  @ObservedObject var model: CommanderViewModel
  @StateObject private var renewal = CommanderProvisioningRenewal()
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    TabView {
      NavigationStack { CommanderDashboardView(model: model) }
        .tabItem { Label("Dnes", systemImage: "sun.max") }
      NavigationStack { CommanderWeekView(model: model) }
        .tabItem { Label("Týden", systemImage: "calendar") }
      NavigationStack { CommanderStayView(model: model) }
        .tabItem { Label("Pobyt", systemImage: "bed.double") }
      NavigationStack { CommanderInfoView(model: model) }
        .tabItem { Label("Info", systemImage: "info.circle") }
      NavigationStack { CommanderSettingsView(model: model) }
        .tabItem { Label("Nastavení", systemImage: "gearshape") }
    }
    .tint(CommanderDashboardPalette.commanderPurpleLight)
    .environmentObject(renewal)
    .task {
      guard !CommanderRuntime.alarmFreeVisualTest else { return }
      await renewal.refresh()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active, !CommanderRuntime.alarmFreeVisualTest else { return }
      Task { await renewal.refresh() }
    }
  }
}

struct CommanderScheduleEmptyView: View {
  let title: String

  var body: some View {
    VStack(spacing: 16) {
      CommanderNeutralStateVisual()
      Text(title)
        .font(.headline)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CommanderDashboardPalette.backgroundGradient.ignoresSafeArea())
  }
}

enum CommanderScheduleDateStyle {
  static let clock = Date.FormatStyle(
    date: .omitted, time: .shortened,
    locale: Locale(identifier: "cs_CZ"), timeZone: TimeZone(identifier: "Europe/Prague")!
  )
  static let day = Date.FormatStyle(
    date: .complete, time: .omitted,
    locale: Locale(identifier: "cs_CZ"), timeZone: TimeZone(identifier: "Europe/Prague")!
  )
  static let departure = Date.FormatStyle(
    date: .numeric, time: .shortened,
    locale: Locale(identifier: "cs_CZ"), timeZone: TimeZone(identifier: "Europe/Prague")!
  )
}

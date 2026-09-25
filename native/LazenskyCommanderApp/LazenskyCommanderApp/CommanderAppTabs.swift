import SwiftUI

struct CommanderAppTabs: View {
  @ObservedObject var model: CommanderViewModel
  @StateObject private var renewal = CommanderProvisioningRenewal()
  @State private var selectedTab: Int
  @Environment(\.scenePhase) private var scenePhase

  init(model: CommanderViewModel) {
    self.model = model
    _selectedTab = State(initialValue: Self.previewTabIndex())

  }

  private static func previewTabIndex() -> Int {
#if DEBUG
    let args = ProcessInfo.processInfo.arguments
    guard let marker = args.firstIndex(of: "-CommanderPreviewTab"),
          args.indices.contains(marker + 1) else { return 0 }
    switch args[marker + 1].lowercased() {
    case "week", "tyden", "týden": return 1
    case "stay", "pobyt": return 2
    case "info": return 3
    case "settings", "nastaveni", "nastavení": return 4
    default: return 0
    }
#else
    return 0
#endif
  }

  var body: some View {
#if DEBUG && targetEnvironment(simulator)
    if CommanderApprovedVisualProof.mode != nil {
      CommanderApprovedVisualProof()
    } else {
      appContent
    }
#else
    appContent
#endif
  }

  private var appContent: some View {
    VStack(spacing: 0) {
      TabView(selection: $selectedTab) {
        NavigationStack { CommanderDashboardView(model: model) }
          .tabItem { Label("Dnes", systemImage: "sun.max") }
          .toolbar(.hidden, for: .tabBar)
          .tag(0)
        NavigationStack { CommanderWeekView(model: model) }
          .tabItem { Label("Týden", systemImage: "calendar") }
          .toolbar(.hidden, for: .tabBar)
          .tag(1)
        NavigationStack { CommanderStayView(model: model) }
          .tabItem { Label("Pobyt", systemImage: "bed.double") }
          .toolbar(.hidden, for: .tabBar)
          .tag(2)
        NavigationStack { CommanderInfoView(model: model) }
          .tabItem { Label("Info", systemImage: "info.circle") }
          .toolbar(.hidden, for: .tabBar)
          .tag(3)
        NavigationStack { CommanderSettingsView(model: model) }
          .tabItem { Label("Nastavení", systemImage: "gearshape") }
          .toolbar(.hidden, for: .tabBar)
          .tag(4)
      }
      .toolbar(.hidden, for: .tabBar)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()

      CommanderNeonTabBar(selection: $selectedTab)
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.top, 5)
        .padding(.bottom, 5)
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .tint(CommanderDashboardPalette.commanderPurpleLight)
    .environmentObject(renewal)
    .task {
      await renewal.refresh()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await renewal.refresh() }
    }
  }

}

private struct CommanderNeonTabBar: View {
  @Binding var selection: Int

  private let items: [(String, String)] = [
    ("Dnes", "sun.max.fill"),
    ("Týden", "calendar"),
    ("Pobyt", "bed.double.fill"),
    ("Info", "info.circle.fill"),
    ("Nastavení", "gearshape.fill")
  ]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        Button {
          selection = index
        } label: {
          VStack(spacing: 2) {
            Image(systemName: item.1)
              .font(.system(size: 24, weight: .semibold))
            Text(item.0)
              .font(.system(size: 12, weight: selection == index ? .bold : .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
          }
          .foregroundStyle(selection == index
            ? CommanderDesignTokens.Colors.textPrimary
            : CommanderDesignTokens.Colors.textSecondary)
          .frame(maxWidth: .infinity, minHeight: 54)
          .contentShape(Rectangle())
          .background {
            if selection == index {
              RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(LinearGradient(
                  colors: [Color(commanderHex: "#4928BC"), Color(commanderHex: "#0931BB")],
                  startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .overlay {
                  RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(CommanderDesignTokens.Colors.primaryPurple, lineWidth: 1.3)
                    .shadow(color: CommanderDesignTokens.Colors.primaryPurple.opacity(0.50), radius: 1.4)
                    .allowsHitTesting(false)
                }
            }
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.0)
        .accessibilityAddTraits(selection == index ? .isSelected : [])
      }
    }
    .padding(4)
    .background {
      // Opaque blue glass shading avoids a live backdrop blur while scrolling.
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(LinearGradient(
          colors: [Color(commanderHex: "#12399B"), Color(commanderHex: "#081E64")],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(LinearGradient(
          colors: [CommanderDesignTokens.Colors.primaryPurple,
                   CommanderDesignTokens.Colors.procedureCyan,
                   CommanderDesignTokens.Colors.primaryPurple],
          startPoint: .leading, endPoint: .trailing
        ), lineWidth: 1.4)
        .shadow(color: CommanderDesignTokens.Colors.procedureCyan.opacity(0.46), radius: 1.8)
        .allowsHitTesting(false)
    }
    .frame(height: 62)
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

import LazenskyCommanderCore
import SwiftUI

struct CommanderAppTabs: View {
  @ObservedObject var model: CommanderViewModel
  @StateObject private var renewal = CommanderProvisioningRenewal()
  @State private var selectedTab: Int
  @State private var isScheduleAuditPresented = false
  @Environment(\.scenePhase) private var scenePhase

  init(model: CommanderViewModel) {
    self.model = model
    _selectedTab = State(initialValue: Self.previewTabIndex())

  }

  private enum AuditAttention {
    case none
    case warning
    case error

    var color: Color? {
      switch self {
      case .none: nil
      case .warning: CommanderDesignTokens.Colors.urgentOrange
      case .error: CommanderDesignTokens.Colors.criticalRed
      }
    }
  }

  private var auditAttention: AuditAttention {
    guard let schedule = model.latestSchedule else { return .none }
    let report = CommanderScheduleAudit.run(schedule, policy: .petrSpaOperational)
    let review = CommanderScheduleAuditReview.resolve(
      report: report,
      acknowledgements: model.scheduleAuditAcknowledgements
    )
    if !review.errors.isEmpty { return .error }
    if !review.openWarnings.isEmpty { return .warning }
    return .none
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
      ZStack {
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

        if isScheduleAuditPresented {
          NavigationStack {
            CommanderScheduleAuditView(
              model: model,
              onClose: { isScheduleAuditPresented = false }
            )
          }
          .zIndex(10)
        }
      }

      CommanderNeonTabBar(
        selection: Binding(
          get: { isScheduleAuditPresented ? 4 : selectedTab },
          set: { newSelection in
            isScheduleAuditPresented = false
            selectedTab = newSelection
          }
        ),
        settingsAttentionColor: auditAttention.color
      )
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.top, 5)
        .padding(.bottom, 5)
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .tint(CommanderDashboardPalette.commanderPurpleLight)
    .environmentObject(renewal)
    .environment(\.commanderOpenScheduleAudit, CommanderOpenScheduleAuditAction(open: {
      isScheduleAuditPresented = true
    }))
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
  let settingsAttentionColor: Color?

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
            ZStack(alignment: .topTrailing) {
              Image(systemName: item.1)
                .font(.system(size: 24, weight: .semibold))
              if index == 4, let attention = settingsAttentionColor {
                Circle()
                  .fill(attention)
                  .frame(width: 9, height: 9)
                  .overlay(Circle().strokeBorder(Color.white.opacity(0.78), lineWidth: 0.7))
                  .offset(x: 5, y: -3)
                  .accessibilityHidden(true)
              }
            }
            Text(item.0)
              .font(.system(size: 12, weight: selection == index ? .bold : .semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
          }
          .foregroundStyle(
            index == 4 && settingsAttentionColor != nil && selection != index
              ? settingsAttentionColor!
              : selection == index
                ? CommanderDesignTokens.Colors.textPrimary
                : CommanderDesignTokens.Colors.textSecondary
          )
          .frame(maxWidth: .infinity, minHeight: 54)
          .contentShape(Rectangle())
          .background {
            if selection == index || (index == 4 && settingsAttentionColor != nil) {
              RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                  index == 4 && settingsAttentionColor != nil && selection != index
                    ? LinearGradient(
                        colors: [settingsAttentionColor!.opacity(0.18), Color(commanderHex: "#17305F").opacity(0.92)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                      )
                    : LinearGradient(
                        colors: [Color(commanderHex: "#2D347A"), Color(commanderHex: "#17305F")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                      )
                )
                .overlay {
                  RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                      index == 4 && settingsAttentionColor != nil
                        ? settingsAttentionColor!.opacity(selection == index ? 0.78 : 0.62)
                        : CommanderDesignTokens.Colors.primaryPurple.opacity(0.52),
                      lineWidth: 1.0
                    )
                    .shadow(
                      color: index == 4 && settingsAttentionColor != nil
                        ? settingsAttentionColor!.opacity(0.18)
                        : CommanderDesignTokens.Colors.primaryPurple.opacity(0.18),
                      radius: 1.0
                    )
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
      RoundedRectangle(cornerRadius: 19, style: .continuous)
        .fill(LinearGradient(
          colors: [Color(commanderHex: "#1E447E"), Color(commanderHex: "#101E43")],
          startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 19, style: .continuous)
        .strokeBorder(LinearGradient(
          colors: [CommanderDesignTokens.Colors.primaryPurple.opacity(0.40),
                   CommanderDesignTokens.Colors.procedureCyan.opacity(0.30),
                   CommanderDesignTokens.Colors.primaryPurple.opacity(0.40)],
          startPoint: .leading, endPoint: .trailing
        ), lineWidth: 1.0)
        .shadow(color: CommanderDesignTokens.Colors.procedureCyan.opacity(0.14), radius: 1.1)
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

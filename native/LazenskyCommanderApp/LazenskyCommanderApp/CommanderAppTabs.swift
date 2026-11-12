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

  private var auditStatus: CommanderScheduleAuditVisualStatus {
    commanderScheduleAuditVisualStatus(for: model)
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
      clientEntryContent
    }
#else
    clientEntryContent
#endif
  }

  @ViewBuilder
  private var clientEntryContent: some View {
    if let pending = model.pendingSchedule {
      CommanderScheduleApprovalView(model: model, schedule: pending)
    } else if model.alarmOfferPresented {
      CommanderAlarmOfferView(model: model)
    } else if model.calendarOfferPresented {
      CommanderCalendarOfferView(model: model)
    } else {
      appContent
    }
  }


  @ViewBuilder
  private var activeTabContent: some View {
    switch selectedTab {
    case 1:
      NavigationStack { CommanderWeekView(model: model) }
    case 2:
      NavigationStack { CommanderStayView(model: model) }
    case 3:
      NavigationStack { CommanderInfoView(model: model) }
    case 4:
      NavigationStack { CommanderSettingsView(model: model) }
    default:
      NavigationStack { CommanderDashboardView(model: model) }
    }
  }

  private var appContent: some View {
    VStack(spacing: 0) {
      ZStack {
        activeTabContent
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
            selectedTab = newSelection
            if newSelection == 4 && auditStatus.shouldOpenAuditFromSettingsTab {
              isScheduleAuditPresented = true
            } else {
              isScheduleAuditPresented = false
            }
          }
        ),
        settingsAttentionColor: auditStatus.attentionColor
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
    .onChange(of: scenePhase) { phase in
      guard phase == .active else { return }
      Task { await renewal.refresh() }
    }
    .onChange(of: model.todayRouteRevision) { _ in
      selectedTab = 0
      isScheduleAuditPresented = false
    }
    .onOpenURL { url in
      guard CommanderNavigation.opensToday(url) else { return }
      selectedTab = 0
      isScheduleAuditPresented = false
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
import LazenskyCommanderCore
import SwiftUI

struct CommanderScheduleApprovalView: View {
  @ObservedObject var model: CommanderViewModel
  let schedule: Schedule

  private var therapyCount: Int {
    schedule.events.filter { CommanderEventSemantics.isTherapy($0) }.count
  }

  private var mealCount: Int {
    schedule.events.filter { $0.kind == .meal }.count
  }

  private var spaName: String {
    schedule.stay["spa"] ?? "Lázeňský pobyt"
  }

  private var stayDates: String {
    let from = schedule.stay["dateFrom"].flatMap(CommanderDateText.weekdayDate(isoDate:))
      ?? schedule.events.first.flatMap { CommanderDateText.weekdayDate(isoDate: $0.date) }
      ?? "—"
    guard let rawTo = schedule.stay["dateTo"],
          let to = CommanderDateText.weekdayDate(isoDate: rawTo), to != from else { return from }
    return "\(from) – \(to)"
  }

  var body: some View {
    ZStack {
      CommanderDepthBackground().ignoresSafeArea()
      ScrollView {
        VStack(spacing: 18) {
          CommanderPageHeader(title: "Nový rozpis", subtitle: "Připraven k potvrzení")

          VStack(spacing: 10) {
            CommanderSymbolBadge(
              symbol: "calendar.badge.checkmark",
              color: CommanderDesignTokens.Colors.locationBlue,
              size: 76
            )
            Text("Rozpis procedur je připraven")
              .font(.system(size: 30, weight: .bold))
              .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
              .multilineTextAlignment(.center)
            Text("Než se aktivují alarmy, widgety a kalendář, zkontroluj základní údaje a rozpis potvrď.")
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
              .multilineTextAlignment(.center)
          }
          .padding(.top, 8)

          VStack(alignment: .leading, spacing: 13) {
            approvalRow(symbol: "building.2.fill", title: "Lázně", value: spaName)
            approvalRow(symbol: "calendar", title: "Termín", value: stayDates)
            approvalRow(symbol: "cross.case.fill", title: "Terapie", value: "\(therapyCount)")
            approvalRow(symbol: "fork.knife", title: "Jídla", value: "\(mealCount)")
            approvalRow(symbol: "list.bullet.rectangle", title: "Celkem položek", value: "\(schedule.events.count)")
          }
          .padding(16)
          .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthCard)

          if let error = model.scheduleApprovalError {
            Text(error)
              .commanderFont(.subtitle)
              .foregroundStyle(CommanderDesignTokens.Colors.amber)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(14)
              .commanderCard(accent: CommanderDesignTokens.Colors.amber, surface: .depthInset)
          }

          Button {
            model.acceptPendingSchedule()
          } label: {
            Label(model.isSynchronizing ? "Aktivuji rozpis…" : "Přijmout a aktivovat rozpis", systemImage: "checkmark.circle.fill")
              .font(.system(size: 18, weight: .bold))
              .frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.borderedProminent)
          .tint(CommanderDashboardPalette.commanderPurpleLight)
          .disabled(model.isSynchronizing)

          Text("Potvrzením se teprve vytvoří upozornění na odchod a aktualizují widgety. Apple Kalendář se nabídne v následujícím kroku, pokud ještě není povolený.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.vertical, 18)
      }
    }
    .accessibilityIdentifier("schedule-approval")
  }

  private func approvalRow(symbol: String, title: String, value: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.locationBlue)
        .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Text(value)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
  }
}


struct CommanderAlarmOfferView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    ZStack {
      CommanderDepthBackground().ignoresSafeArea()
      VStack(spacing: 20) {
        Spacer()
        CommanderSymbolBadge(
          symbol: "alarm.waves.left.and.right.fill",
          color: CommanderDesignTokens.Colors.amber,
          size: 84
        )
        Text("Povolit upozornění na odchod?")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .multilineTextAlignment(.center)
        Text("Commander používá systémové alarmy, aby tě upozornil v nastaveném předstihu před procedurou nebo jídlem. Po volbě Povolit zobrazí iPhone vlastní systémové potvrzení.")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          .multilineTextAlignment(.center)

        Button {
          model.respondToAlarmOffer(enable: true)
        } label: {
          Label("Povolit alarmy", systemImage: "alarm.fill")
            .font(.system(size: 18, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(CommanderDesignTokens.Colors.amber)

        Button("Teď ne") {
          model.respondToAlarmOffer(enable: false)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Spacer()
      }
      .padding(.horizontal, 28)
    }
    .accessibilityIdentifier("alarm-offer")
  }
}

struct CommanderCalendarOfferView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    ZStack {
      CommanderDepthBackground().ignoresSafeArea()
      VStack(spacing: 20) {
        Spacer()
        CommanderSymbolBadge(
          symbol: "calendar.badge.plus",
          color: CommanderDesignTokens.Colors.locationBlue,
          size: 84
        )
        Text("Přidat pobyt do Apple Kalendáře?")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .multilineTextAlignment(.center)
        Text("Commander může vložit celý potvrzený rozpis do Apple Kalendáře a při změně ho aktualizovat. Oprávnění vyžádá iPhone až po volbě Povolit.")
          .commanderFont(.subtitle)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
          .multilineTextAlignment(.center)

        Button {
          model.respondToCalendarOffer(enable: true)
        } label: {
          Label("Povolit Apple Kalendář", systemImage: "calendar.badge.checkmark")
            .font(.system(size: 18, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(CommanderDesignTokens.Colors.locationBlue)

        Button("Teď ne") {
          model.respondToCalendarOffer(enable: false)
        }
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Spacer()
      }
      .padding(.horizontal, 28)
    }
    .accessibilityIdentifier("calendar-offer")
  }
}

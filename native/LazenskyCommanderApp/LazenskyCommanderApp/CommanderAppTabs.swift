import LazenskyCommanderCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct CommanderAppTabs: View {
  @ObservedObject var model: CommanderViewModel
  @StateObject private var renewal = CommanderProvisioningRenewal()
  @State private var selectedTab: Int
  @State private var isScheduleAuditPresented = false
  @AppStorage("lazensky.commander.terms.acceptedVersion") private var acceptedTermsVersion = 0
  @Environment(\.scenePhase) private var scenePhase

  init(model: CommanderViewModel) {
    self.model = model
    _selectedTab = State(initialValue: Self.previewTabIndex())

  }

  private static let currentTermsVersion = 1

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
    if acceptedTermsVersion < Self.currentTermsVersion {
      CommanderTermsAcceptanceView {
        acceptedTermsVersion = Self.currentTermsVersion
      }
    } else if model.latestSchedule == nil && model.pendingSchedule == nil {
      CommanderFirstStayView(model: model)
    } else if let pending = model.pendingSchedule {
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



struct CommanderTermsAcceptanceView: View {
  let accept: () -> Void
  @State private var hasReviewed = false

  var body: some View {
    NavigationStack {
      ZStack {
        CommanderDepthBackground().ignoresSafeArea()
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              CommanderPageHeader(title: "Podmínky používání", subtitle: "První spuštění")

              VStack(spacing: 10) {
                CommanderSymbolBadge(
                  symbol: "doc.text.fill",
                  color: CommanderDesignTokens.Colors.primaryPurple,
                  size: 76
                )
                Text("Než začneš Commander používat")
                  .font(.system(size: 28, weight: .bold))
                  .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
                  .multilineTextAlignment(.center)
                Text("Přečti si základní pravidla služby. Bez souhlasu nelze pokračovat k aktivaci pobytu.")
                  .commanderFont(.subtitle)
                  .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
                  .multilineTextAlignment(.center)
              }

              NavigationLink {
                CommanderTermsView()
              } label: {
                CommanderNavigationRow(
                  title: "Přečíst podmínky používání",
                  subtitle: "Služba, rozpis, aktivace, alarmy a soukromí",
                  symbol: "doc.text.magnifyingglass",
                  accent: CommanderDesignTokens.Colors.primaryPurple
                )
              }
              .buttonStyle(.plain)
              .simultaneousGesture(TapGesture().onEnded { hasReviewed = true })

              Toggle(isOn: $hasReviewed) {
                Text("Přečetl jsem podmínky a souhlasím s jejich zněním")
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
              }
              .tint(CommanderDashboardPalette.commanderPurpleLight)
              .padding(16)
              .commanderCard(accent: CommanderDesignTokens.Colors.primaryPurple, surface: .depthInset)
            }
            .padding(.horizontal, CommanderDesignTokens.Spacing.page)
            .padding(.vertical, 18)
          }

          Button(action: accept) {
            Label("Souhlasím a pokračovat", systemImage: "checkmark.circle.fill")
              .font(.system(size: 18, weight: .bold))
              .frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.borderedProminent)
          .tint(CommanderDashboardPalette.commanderPurpleLight)
          .disabled(!hasReviewed)
          .padding(.horizontal, CommanderDesignTokens.Spacing.page)
          .padding(.vertical, 12)
          .background(CommanderDashboardPalette.backgroundGradient)
        }
      }
    }
    .accessibilityIdentifier("terms-acceptance")
  }
}

struct CommanderFirstStayView: View {
  @ObservedObject var model: CommanderViewModel
  @State private var step: Step = .start
  @State private var showsFileImporter = false
  @State private var showsDocumentScanner = false
  @State private var photoItem: PhotosPickerItem?
  @State private var selectedSource = ""
  @State private var error: String?
  @State private var isProcessingSource = false
  @State private var firstAttemptOCR: [CommanderOCRPage] = []
  @State private var captureGuidance: String?
  @State private var extraction: CommanderDocumentExtraction?
  @State private var mergedOCR: CommanderMergedOCRPage?
  @State private var canonicalSchedule: Schedule?

  private enum Step { case start, ownSchedule, review, payment }

  var body: some View {
    ZStack {
      CommanderDepthBackground().ignoresSafeArea()
      ScrollView {
        VStack(spacing: 18) {
          CommanderPageHeader(title: "Přidat pobyt", subtitle: "První spuštění")
          switch step {
          case .start: startView
          case .ownSchedule: sourceView
          case .review: reviewView
          case .payment: paymentView
          }
        }
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.vertical, 18)
      }
    }
    .sheet(isPresented: $showsDocumentScanner) {
      CommanderDocumentScanner(
        onComplete: { images in
          showsDocumentScanner = false
          Task { await processImages(images, source: "Vyfocený rozpis") }
        },
        onCancel: { showsDocumentScanner = false }
      )
    }
    .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image]) { result in
      switch result {
      case .success(let url):
        Task { await processDocumentURL(url) }
      case .failure(let failure):
        error = failure.localizedDescription
      }
    }
    .onChange(of: photoItem) { item in
      guard let item else { return }
      Task { await processPhotoItem(item) }
    }
    .alert("Rozpis se nepodařilo zpracovat", isPresented: Binding(
      get: { error != nil },
      set: { if !$0 { error = nil } }
    )) {
      Button("OK", role: .cancel) { error = nil }
    } message: {
      Text(error ?? "Neznámá chyba")
    }
  }

  private var startView: some View {
    VStack(spacing: 16) {
      intro(symbol: "bed.double.fill", title: "Přidej svůj lázeňský pobyt", text: "Commander ti z rozpisu připraví přehled dne, časy odchodu a upozornění.")
      choice(title: "Mám vlastní rozpis", subtitle: "Jsem samoplátce nebo jsem v lázních mimo partnerskou síť", symbol: "doc.viewfinder", accent: CommanderDesignTokens.Colors.locationBlue) { step = .ownSchedule }
      choice(title: "Mám odkaz nebo kód z lázní", subtitle: "Pro pobyt připravený partnerskými lázněmi", symbol: "link.badge.plus", accent: CommanderDashboardPalette.commanderPurpleLight) {
        error = "Tuto partnerskou cestu otestujeme samostatně. Dnes pokračuj jako klient s vlastním rozpisem."
      }
      if let error { note(error) }
    }
  }

  private var sourceView: some View {
    VStack(spacing: 16) {
      intro(symbol: "doc.text.viewfinder", title: "Přidej svůj rozpis", text: "Vyfoť rozpis nebo vyber fotografii či PDF. Commander ho přečte přímo v tomto iPhonu.")
      Button { showsDocumentScanner = true } label: { actionLabel("Vyfotit rozpis", symbol: "camera.viewfinder") }
      PhotosPicker(selection: $photoItem, matching: .images) {
        Label("Vybrat fotografii", systemImage: "photo.on.rectangle.angled")
          .font(.system(size: 18, weight: .bold))
          .frame(maxWidth: .infinity, minHeight: 56)
          .foregroundStyle(.white)
          .background(CommanderDashboardPalette.commanderPurpleLight)
          .clipShape(RoundedRectangle(cornerRadius: 16))
      }
      Button { showsFileImporter = true } label: { actionLabel("Vybrat PDF nebo obrázek", symbol: "doc.fill") }

      if isProcessingSource {
        HStack(spacing: 10) {
          ProgressView().tint(.white)
          Text("Čtu rozpis přímo v telefonu…")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
      }

      if let captureGuidance {
        note(captureGuidance)
        if !firstAttemptOCR.isEmpty {
          Button { useFirstAttempt() } label: { actionLabel("Použít první snímek i tak", symbol: "checkmark.circle") }
        }
      }

      Button("Zpět") { resetSource(); step = .start }
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      Text("Fotografie, PDF ani rozpoznaný text se při tomto zpracování nikam neodesílají.")
        .font(.footnote)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .multilineTextAlignment(.center)
    }
  }

  private var reviewView: some View {
    VStack(spacing: 16) {
      if let extraction {
        intro(symbol: "checkmark.circle.fill", title: "Rozpis byl přečten v telefonu", text: "Commander použil OCR a lokální znalostní katalog. Rozpis klienta zůstává nadřazený všem návrhům.")
        VStack(alignment: .leading, spacing: 12) {
          reviewRow("Lázně", extraction.facility?.name ?? "Z rozpisu nelze určit")
          reviewRow("Nalezené položky", "\(extraction.rows.count)")
          reviewRow("Procedury", "\(extraction.rows.filter { $0.procedure != nil }.count)")
          reviewRow("Jídla", "\(extraction.rows.filter { $0.meal != nil }.count)")
          reviewRow("Ke kontrole", "\(extraction.reviewCount)")
          reviewRow("Podklad", selectedSource.isEmpty ? "Rozpis klienta" : selectedSource)
        }
        .padding(16)
        .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthCard)

        if extraction.reviewCount > 0 {
          note("Commander našel \(extraction.reviewCount) skutečně nejisté položky. Ty musí být vyřešené před platbou; ostatní řádky klient potvrzovat nemusí.")
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(extraction.rows.filter { $0.requiresReview }.prefix(6).enumerated()), id: \.offset) { _, row in
              Text(row.rawText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          .padding(14)
          .commanderCard(accent: CommanderDesignTokens.Colors.amber, surface: .depthInset)
        } else if canonicalSchedule != nil {
          note("Rozpis je připravený z klientského podkladu. Pokud podklad neuvádí konec procedury, Commander žádnou délku nevymýšlí a používá stejný čas začátku i konce.")
          Button { step = .payment } label: { actionLabel("Pokračovat k aktivaci", symbol: "arrow.right.circle.fill") }
        }
      } else {
        note("Rozpis zatím nemá použitelný OCR výsledek.")
      }
      Button("Vybrat jiný rozpis") { resetSource(); step = .ownSchedule }
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    }
  }

  @MainActor
  private func processPhotoItem(_ item: PhotosPickerItem) async {
    isProcessingSource = true
    defer { isProcessingSource = false; photoItem = nil }
    do {
      guard let data = try await item.loadTransferable(type: Data.self),
            let image = CommanderDocumentImageSource.image(from: data) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      await processImages([image], source: "Fotografie rozpisu", managesProgress: false)
    } catch {
      self.error = "Fotografii se nepodařilo přečíst: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func processDocumentURL(_ url: URL) async {
    isProcessingSource = true
    defer { isProcessingSource = false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let images = try CommanderDocumentImageSource.images(from: url)
      await processImages(images, source: url.lastPathComponent, managesProgress: false)
    } catch {
      self.error = "Dokument se nepodařilo přečíst: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func processImages(_ images: [CGImage], source: String, managesProgress: Bool = true) async {
    guard !images.isEmpty else {
      error = "V dokumentu nebyla nalezena žádná čitelná stránka."
      return
    }
    if managesProgress { isProcessingSource = true }
    defer { if managesProgress { isProcessingSource = false } }
    do {
      let qualities = images.map(CommanderDocumentImageQuality.assess)
      var pages: [CommanderOCRPage] = []
      for image in images { pages.append(try await CommanderOnDeviceOCR.recognize(cgImage: image)) }

      let merged: CommanderMergedOCRPage
      if !firstAttemptOCR.isEmpty {
        if firstAttemptOCR.count == pages.count {
          merged = CommanderOCRReconciler.combine(zip(firstAttemptOCR, pages).map(CommanderOCRReconciler.merge))
        } else {
          // Page counts differ, so pairing them would risk mixing different pages. Use the second scan as the safer source.
          merged = CommanderOCRReconciler.combine(pages.map(CommanderOCRReconciler.fromSingle))
        }
        firstAttemptOCR = []
        captureGuidance = nil
      } else if qualities.contains(where: { $0.level == .retryRecommended }) {
        firstAttemptOCR = pages
        selectedSource = source
        let issue = qualities.flatMap(\.issues).first ?? "Fotografie je hůře čitelná"
        captureGuidance = "\(issue). Zkuste rozpis vyfotit ještě jednou: celý papír, bez odlesku a telefon držte přímo nad dokumentem. První snímek Commander zachová a oba výsledky porovná."
        return
      } else {
        merged = CommanderOCRReconciler.combine(pages.map(CommanderOCRReconciler.fromSingle))
      }

      try finishOCR(merged, source: source)
    } catch {
      self.error = "OCR se nepodařilo dokončit: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func useFirstAttempt() {
    guard !firstAttemptOCR.isEmpty else { return }
    do {
      let merged = CommanderOCRReconciler.combine(firstAttemptOCR.map(CommanderOCRReconciler.fromSingle))
      firstAttemptOCR = []
      captureGuidance = nil
      try finishOCR(merged, source: selectedSource.isEmpty ? "Rozpis klienta" : selectedSource)
    } catch {
      self.error = "OCR se nepodařilo dokončit: \(error.localizedDescription)"
    }
  }

  @MainActor
  private func finishOCR(_ merged: CommanderMergedOCRPage, source: String) throws {
    guard !merged.lines.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    let lexicon = try CommanderSpaOCRLexicon.loadBundled()
    let extraction = CommanderDocumentExtractor.extract(merged, lexicon: lexicon)
    guard !extraction.rows.isEmpty else {
      throw NSError(domain: "LazenskyCommander.OCR", code: 1, userInfo: [NSLocalizedDescriptionKey: "Na stránce nebyly rozpoznány procedury ani jídla s použitelným časem."])
    }
    self.mergedOCR = merged
    self.extraction = extraction
    self.canonicalSchedule = extraction.reviewCount == 0 ? try CommanderCanonicalScheduleBuilder.build(from: extraction) : nil
    self.selectedSource = source
    self.step = .review
  }

  @MainActor
  private func resetSource() {
    firstAttemptOCR = []
    captureGuidance = nil
    extraction = nil
    mergedOCR = nil
    canonicalSchedule = nil
    selectedSource = ""
    photoItem = nil
  }

  private var paymentView: some View {
    VStack(spacing: 16) {
      intro(symbol: "creditcard.fill", title: "Aktivace pobytu", text: "Tyto lázně nejsou v partnerské síti. Cena se určuje podle zbývající délky pobytu.")
      VStack(spacing: 5) {
        Text("Krátký pobyt · 1–15 dní")
          .font(.headline)
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        Text("129 Kč")
          .font(.system(size: 42, weight: .bold))
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        Text("jednorázově za tento pobyt")
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      .frame(maxWidth: .infinity)
      .padding(20)
      .commanderCard(accent: CommanderDesignTokens.Colors.amber, surface: .depthCard)
      Button { activateParsedStay() } label: { actionLabel("Simulovat úspěšnou aktivaci", symbol: "checkmark.seal.fill") }
      Text("TEST: žádná platba se dnes neprovede. Ostrá App Store platba bude samostatná systémová vrstva.")
        .font(.footnote)
        .foregroundStyle(CommanderDesignTokens.Colors.amber)
        .multilineTextAlignment(.center)
      if let error { note(error) }
    }
  }

  private func activateParsedStay() {
    do {
      guard let canonicalSchedule else {
        throw NSError(domain: "LazenskyCommander.OCR", code: 30, userInfo: [NSLocalizedDescriptionKey: "Chybí připravený rozpis klienta."])
      }
      try model.stagePendingSchedule(canonicalSchedule)
    } catch {
      self.error = "Aktivaci se nepodařilo připravit: \(error.localizedDescription)"
    }
  }

  private func intro(symbol: String, title: String, text: String) -> some View {
    VStack(spacing: 10) {
      CommanderSymbolBadge(symbol: symbol, color: CommanderDashboardPalette.commanderPurpleLight, size: 80)
      Text(title)
        .font(.system(size: 28, weight: .bold))
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .multilineTextAlignment(.center)
      Text(text)
        .commanderFont(.subtitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
        .multilineTextAlignment(.center)
    }
  }

  private func choice(title: String, subtitle: String, symbol: String, accent: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        CommanderSymbolBadge(symbol: symbol, color: accent, size: 58)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          Text(subtitle)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.leading)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.white)
      }
      .padding(14)
      .commanderCard(accent: accent, surface: .depthInset)
    }
    .buttonStyle(.plain)
  }

  private func actionLabel(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol)
      .font(.system(size: 18, weight: .bold))
      .frame(maxWidth: .infinity, minHeight: 56)
      .foregroundStyle(.white)
      .background(CommanderDashboardPalette.commanderPurpleLight)
      .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private func reviewRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      Spacer()
      Text(value)
        .fontWeight(.bold)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .multilineTextAlignment(.trailing)
    }
  }

  private func note(_ value: String) -> some View {
    Text(value)
      .font(.footnote)
      .foregroundStyle(CommanderDesignTokens.Colors.amber)
      .padding(12)
      .frame(maxWidth: .infinity)
      .commanderCard(accent: CommanderDesignTokens.Colors.amber, surface: .depthInset)
  }

  private static let testSchedule = Schedule(
    schemaVersion: 1,
    scheduleVersion: 2001,
    updatedAt: "2026-11-13T06:30:00Z",
    stay: [
      "spa": "Lázně mimo partnerskou síť",
      "dateFrom": "2026-11-13",
      "dateTo": "2026-11-13",
      "room": "Pokoj klienta",
      "doctor": "",
      "mealShift": "I. směna"
    ],
    events: [
      ScheduleEvent(stableId: "b2c-2026-11-13-viriva-0910", date: "2026-11-13", start: "09:10", end: "09:30", title: "Vířivá koupel HKK", location: "LAZ1 · RS C/1 · vodoléčba", kind: .procedure, procedureType: "Vířivá lázeň", mealType: nil, leadTimeMinutes: 20),
      ScheduleEvent(stableId: "b2c-2026-11-13-motomed-0945", date: "2026-11-13", start: "09:45", end: "10:05", title: "Motomed", location: "FYZ48 · RS C/2 · č.7", kind: .procedure, procedureType: "Individuální LTV", mealType: nil, leadTimeMinutes: 20),
      ScheduleEvent(stableId: "b2c-2026-11-13-obed-1100", date: "2026-11-13", start: "11:00", end: "11:15", title: "Oběd", location: "Jídelna · I. směna", kind: .meal, procedureType: nil, mealType: "Oběd", leadTimeMinutes: 10),
      ScheduleEvent(stableId: "b2c-2026-11-13-imoove-1200", date: "2026-11-13", start: "12:00", end: "12:20", title: "ILTV Imoove", location: "FYZ54 · RS C/2 · č.7", kind: .procedure, procedureType: "ILTV Imoove", mealType: nil, leadTimeMinutes: 20),
      ScheduleEvent(stableId: "b2c-2026-11-13-parafango-1330", date: "2026-11-13", start: "13:30", end: "13:50", title: "Parafango-obklad", location: "LAZ4 · RS C/2 · č.11", kind: .procedure, procedureType: "Zábal", mealType: nil, leadTimeMinutes: 20),
      ScheduleEvent(stableId: "b2c-2026-11-13-vecere-1645", date: "2026-11-13", start: "16:45", end: "17:00", title: "Večeře", location: "Jídelna · I. směna", kind: .meal, procedureType: nil, mealType: "Večeře", leadTimeMinutes: 10)
    ],
    settings: ScheduleSettings(
      defaultLeadTimeMinutes: 20,
      procedureTypeOverrides: ["Individuální LTV": 20, "Vířivá lázeň": 20, "Zábal": 20],
      mealOverrides: ["Oběd": 10, "Večeře": 10]
    )
  )
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

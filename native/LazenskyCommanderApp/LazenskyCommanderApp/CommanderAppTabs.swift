import LazenskyCommanderCore
import PhotosUI
import SwiftUI
import VisionKit
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
  let replacingSchedule: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var step: Step
  @State private var showsFileImporter = false
  @State private var showsDocumentScanner = false
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var error: String?
  @State private var isProcessingSource = false
  @State private var scans: [CommanderOCRPage] = []
  @State private var replacePage: Int?
  @State private var unreadablePages: [Int] = []
  @State private var parsedRows: [CommanderDocumentCandidateRow] = []
  @State private var corrections: [(original: CommanderDocumentCandidateRow, fixed: CommanderDocumentCandidateRow)] = []
  @State private var extraction: CommanderDocumentExtraction?
  @State private var editRow: EditRow?
  @State private var excludedRows: [CommanderDocumentCandidateRow] = []
  @State private var omitRow: EditRow?
  @State private var failedSelections = 0
  @State private var showHeaderEditor = false
  @State private var fixedHeader: [String: String] = [:]
  @State private var reviewedHeaderKeys: Set<String> = []
  @State private var editPrescription: EditPrescription?
  @State private var fixedPrescriptions: [(original: SchedulePrescription, fixed: SchedulePrescription)] = []

  private struct EditPrescription: Identifiable {
    let index: Int
    let original: SchedulePrescription
    let current: SchedulePrescription
    var id: Int { index }
  }

  private enum Step { case start, ownSchedule, review }
  private struct EditRow: Identifiable {
    let index: Int
    let row: CommanderDocumentCandidateRow
    var id: Int { index }
  }

  init(model: CommanderViewModel, replacingSchedule: Bool = false) {
    self.model = model
    self.replacingSchedule = replacingSchedule
    _step = State(initialValue: replacingSchedule ? .ownSchedule : .start)
  }

  var body: some View {
    ZStack {
      CommanderDepthBackground().ignoresSafeArea()
      ScrollView {
        VStack(spacing: 18) {
          CommanderPageHeader(title: replacingSchedule ? "Rozpis z papíru" : "Přidat pobyt", subtitle: "Lázeňský Commander")
          switch step {
          case .start: startView
          case .ownSchedule: sourceView
          case .review: reviewView
          }
        }
        .disabled(isProcessingSource)
        .padding(.horizontal, CommanderDesignTokens.Spacing.page)
        .padding(.vertical, 18)
      }
    }
#if DEBUG && targetEnvironment(simulator)
    .task {
      guard let paths = ProcessInfo.processInfo.environment["LC_OCR_QA_PHOTOS"], scans.isEmpty else { return }
      for path in paths.split(separator: "|") {
        await processDocumentURL(URL(fileURLWithPath: String(path)))
      }
    }
#endif
    .overlay {
      if isProcessingSource {
        ProgressView("Načítám váš rozpis…")
          .padding(20)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
      }
    }
    .sheet(isPresented: $showHeaderEditor) {
      CommanderPaperHeaderEditor(fields: extraction?.details?.fields ?? [:]) { updated in
        let previous = extraction?.details?.fields ?? [:]
        for field in CommanderPaperDocumentReader.fields where previous[field.key] != updated[field.key] ||
          extraction?.headerIssues[field.key] != nil {
          reviewedHeaderKeys.insert(field.key)
          fixedHeader[field.key] = updated[field.key]
        }
        refreshReview()
      }
    }
    .sheet(item: $editPrescription) { item in
      CommanderPrescriptionEditor(item: item.current) { value in
        fixedPrescriptions.removeAll { $0.original == item.original }
        fixedPrescriptions.append((item.original, value))
        refreshReview()
      }
    }
    .sheet(item: $editRow) { edit in
      CommanderPhotoRowEditor(source: edit.row) { fixed in
        let original = parsedRows[edit.index]
        corrections.removeAll { $0.original == original }
        corrections.append((original, fixed))
        refreshReview()
      }
    }
    .sheet(isPresented: $showsDocumentScanner) {
      CommanderDocumentScanner(
        onComplete: { images in
          showsDocumentScanner = false
          Task { await processImages(images) }
        },
        onCancel: { showsDocumentScanner = false; replacePage = nil }
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
    .onChange(of: photoItems) { items in
      guard !items.isEmpty else { return }
      Task { await processPhotoItems(items) }
    }
    .confirmationDialog("Vynechat tento řádek?", isPresented: Binding(
      get: { omitRow != nil }, set: { if !$0 { omitRow = nil } }
    ), titleVisibility: .visible, presenting: omitRow) { edit in
      Button("Vynechat řádek", role: .destructive) {
        excludedRows.append(parsedRows[edit.index])
        refreshReview()
      }
    } message: { edit in Text(edit.row.rawText) }
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
      if VNDocumentCameraViewController.isSupported {
        Button { showsDocumentScanner = true } label: { actionLabel("Vyfotit rozpis", symbol: "camera.viewfinder") }
      }
      photoPicker("Vybrat fotografie")
      Button { showsFileImporter = true } label: { actionLabel("Vybrat PDF nebo obrázek", symbol: "doc.fill") }
      Button(replacingSchedule ? "Zavřít" : "Zpět") {
        if replacingSchedule { dismiss() } else { resetSource(); step = .start }
      }
      .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    }
  }

  private var reviewView: some View {
    VStack(spacing: 16) {
      if let extraction {
        intro(symbol: "checkmark.circle.fill", title: "Zkontrolovat rozpis",
              text: "\(itemCount(extraction.rows.count)) · \(extraction.reviewCount) ke kontrole")
        VStack(alignment: .leading, spacing: 8) {
          Text("Údaje z hlavičky").font(.headline)
          ForEach(CommanderPaperDocumentReader.fields, id: \.key) { field in
            if let value = extraction.details?.fields[field.key] { LabeledContent(field.label, value: value) }
            if let issue = extraction.headerIssues[field.key] {
              Text("\(field.label) · \(issue)").foregroundStyle(CommanderDesignTokens.Colors.amber)
            }
          }
          Button("Opravit údaje z hlavičky") { showHeaderEditor = true }
        }
        .padding(14)
        .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
        if let prescriptions = extraction.details?.prescriptions, !prescriptions.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Předepsané procedury").font(.headline)
            ForEach(prescriptions.indices, id: \.self) { index in
              let item = prescriptions[index]
              Button {
                let original = fixedPrescriptions.first { $0.fixed == item }?.original ?? item
                editPrescription = .init(index: index, original: original, current: item)
              } label: {
                VStack(alignment: .leading) {
                  Text(item.title + (item.count.map { " · \($0)×" } ?? ""))
                  if let note = item.note { Text(note).font(.footnote) }
                }
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(14)
          .commanderCard(accent: CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
        }
        Text("Naplánované události").font(.headline)
        ForEach(unreadablePages, id: \.self) { index in
          VStack(alignment: .leading, spacing: 10) {
            Text("Snímek \(index + 1) se nepodařilo přečíst.")
            if VNDocumentCameraViewController.isSupported {
              Button("Vyfotit tuto část znovu") {
                replacePage = index
                showsDocumentScanner = true
              }
            }
            Button("Odebrat tento snímek") {
              scans.remove(at: index)
              refreshReview()
            }
          }
          .padding(14)
          .commanderCard(accent: CommanderDesignTokens.Colors.amber, surface: .depthInset)
        }
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(extraction.rows.indices, id: \.self) { index in
            let row = extraction.rows[index]
            VStack(alignment: .leading, spacing: 5) {
              Text(row.title.isEmpty ? "Chybí název" : row.title).font(.headline)
              Text([row.dateToken ?? "Datum?", row.timeToken ?? "Čas?", row.endTimeToken, row.location]
                .compactMap { $0 }.joined(separator: " · "))
              if let issue = row.issue {
                Text(issue).foregroundStyle(CommanderDesignTokens.Colors.amber)
                Text(row.rawText).font(.footnote)
                Button("Vynechat nepotřebný řádek") { omitRow = .init(index: index, row: row) }
              }
              Button("Opravit údaje") { editRow = .init(index: index, row: row) }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .commanderCard(accent: row.requiresReview ? CommanderDesignTokens.Colors.amber : CommanderDesignTokens.Colors.locationBlue, surface: .depthInset)
          }
        }
        if failedSelections > 0 {
          note("Některé fotografie se nepodařilo otevřít. Přidej je ještě jednou.")
          Button("Odebrat nepřečtené fotografie") { failedSelections = 0 }
        }
        if extraction.readyWithoutQuestions && unreadablePages.isEmpty && failedSelections == 0 {
          Button { Task { await useSchedule(extraction) } } label: {
            actionLabel("Použít rozpis", symbol: "checkmark.circle.fill")
          }
        }
      }
      if VNDocumentCameraViewController.isSupported {
        if extraction?.reviewCount ?? 0 > 0 && !scans.isEmpty {
          Menu("Nahradit snímek") {
            ForEach(scans.indices, id: \.self) { index in
              Button("Snímek \(index + 1)") {
                replacePage = index
                showsDocumentScanner = true
              }
            }
          }
        }
        Button {
          replacePage = nil
          showsDocumentScanner = true
        } label: { actionLabel("Vyfotit další část", symbol: "camera.viewfinder") }
      }
      photoPicker("Přidat fotografie z Fotek")
      Button("Vybrat jiný rozpis") { resetSource(); step = .ownSchedule }
        .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    }
  }

  private func itemCount(_ count: Int) -> String {
    switch count {
    case 1: return "1 položka"
    case 2...4: return "\(count) položky"
    default: return "\(count) položek"
    }
  }

  private func photoPicker(_ title: String) -> some View {
    PhotosPicker(selection: $photoItems, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
      Label(title, systemImage: "photo.on.rectangle.angled")
        .font(.system(size: 18, weight: .bold))
        .frame(maxWidth: .infinity, minHeight: 56)
        .foregroundStyle(.white)
        .background(CommanderDashboardPalette.commanderPurpleLight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
  }

  @MainActor
  private func processPhotoItems(_ items: [PhotosPickerItem]) async {
    guard !isProcessingSource else { return }
    isProcessingSource = true
    defer { isProcessingSource = false; photoItems = [] }
    var failed = 0
    for item in items {
      do {
        guard let data = try await item.loadTransferable(type: Data.self),
              let image = await Task.detached(priority: .userInitiated, operation: {
                CommanderDocumentImageSource.image(from: data)
              }).value else { throw CocoaError(.fileReadCorruptFile) }
        let page = try await CommanderOnDeviceOCR.recognize(cgImage: image)
        scans.append(page)
      } catch { failed += 1 }
    }
    if failed > 0 { failedSelections += failed; error = "\(failed) fotografií se nepodařilo otevřít. Vyber je znovu." }
    refreshReview()
  }

  @MainActor
  private func processDocumentURL(_ url: URL) async {
    guard !isProcessingSource else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    isProcessingSource = true
    defer { isProcessingSource = false }
    do {
      let pages = try await Task.detached(priority: .userInitiated) { try await CommanderDocumentImageSource.recognize(from: url) }.value
      scans.append(contentsOf: pages)
      refreshReview()
    } catch { self.error = "Dokument se nepodařilo přečíst." }
  }

  @MainActor
  private func processImages(_ images: [CGImage]) async {
    guard !isProcessingSource else { return }
    isProcessingSource = true
    defer { isProcessingSource = false; replacePage = nil }
    do { try await addImages(images, replacing: replacePage) }
    catch { self.error = "Snímek se nepodařilo přečíst: \(error.localizedDescription)" }
  }

  private func addImages(_ images: [CGImage], replacing index: Int? = nil) async throws {
    guard !images.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
    for (offset, image) in images.enumerated() {
      let page = try await CommanderOnDeviceOCR.recognize(cgImage: image)
      if offset == 0, let index, scans.indices.contains(index) { scans[index] = page }
      else { scans.append(page) }
    }
    refreshReview()
  }

  private func refreshReview() {
    guard !scans.isEmpty else { resetSource(); step = .ownSchedule; return }
    do {
      let lexicon = try CommanderSpaOCRLexicon.loadBundled()
      let pages = scans.map(CommanderOCRReconciler.fromSingle)
      unreadablePages = scans.indices.filter { !scans[$0].hasText }
      var result = CommanderDocumentExtractor.extract(pages, lexicon: lexicon)
      result.rows.removeAll { excludedRows.contains($0) }
      parsedRows = result.rows
      for index in result.rows.indices {
        if let correction = corrections.first(where: { $0.original == result.rows[index] }) { result.rows[index] = correction.fixed }
      }
      var fields = result.details?.fields ?? [:]
      for key in reviewedHeaderKeys { fields[key] = fixedHeader[key] }
      var prescriptions: [SchedulePrescription] = []
      for original in result.details?.prescriptions ?? [] {
        let item = fixedPrescriptions.first(where: { $0.original == original })?.fixed ?? original
        if !prescriptions.contains(item) { prescriptions.append(item) }
      }
      result.details = fields.isEmpty && prescriptions.isEmpty ? nil : .init(fields: fields, prescriptions: prescriptions)
      result.headerIssues = CommanderDocumentExtractor.validateHeader(result, unresolved: result.headerIssues.filter {
        !reviewedHeaderKeys.contains($0.key)
      })
      extraction = result
      step = .review
    } catch { self.error = "Rozpis se nepodařilo připravit: \(error.localizedDescription)" }
  }

  private func resetSource() {
    scans = []
    corrections = []
    fixedHeader = [:]
    reviewedHeaderKeys = []
    fixedPrescriptions = []
    excludedRows = []
    failedSelections = 0
    parsedRows = []
    unreadablePages = []
    extraction = nil
    photoItems = []
    replacePage = nil
  }

  @MainActor
  private func useSchedule(_ extraction: CommanderDocumentExtraction) async {
    guard !isProcessingSource, unreadablePages.isEmpty, failedSelections == 0 else { return }
    isProcessingSource = true
    defer { isProcessingSource = false }
    do {
      let schedule = try CommanderCanonicalScheduleBuilder.build(from: extraction)
      if replacingSchedule {
        try await model.importSchedule(schedule)
        dismiss()
      } else {
        try model.stagePendingSchedule(schedule)
      }
    } catch { self.error = "Rozpis se nepodařilo použít: \(error.localizedDescription)" }
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

private struct CommanderPhotoRowEditor: View {
  let source: CommanderDocumentCandidateRow
  let save: (CommanderDocumentCandidateRow) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var date = ""
  @State private var start = ""
  @State private var end = ""
  @State private var title = ""
  @State private var location = ""
  @State private var invalid = false

  var body: some View {
    NavigationStack {
      Form {
        Text(source.rawText)
        TextField("Datum s rokem", text: $date)
        TextField("Začátek (HH:MM)", text: $start)
        TextField("Konec (volitelný)", text: $end)
        TextField("Název", text: $title)
        TextField("Místo (volitelné)", text: $location)
        if invalid { Text("Vyplň platné datum s rokem, začátek a název. Konec může zůstat prázdný.").foregroundStyle(.red) }
        Button("Uložit opravu") {
          guard let row = CommanderDocumentExtractor.correct(source, date: date, start: start, end: end, title: title, location: location) else {
            invalid = true
            return
          }
          save(row)
          dismiss()
        }
      }
      .navigationTitle("Opravit údaje")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } } }
      .onAppear {
        date = source.dateToken ?? ""
        start = source.timeToken ?? ""
        end = source.endTimeToken ?? ""
        title = source.title
        location = source.location ?? ""
      }
    }
  }
}


private struct CommanderPaperHeaderEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State var fields: [String: String]
  let save: ([String: String]) -> Void
  @State private var invalidDate = false

  var body: some View {
    NavigationStack {
      Form {
        ForEach(CommanderPaperDocumentReader.fields, id: \.key) { field in
          VStack(alignment: .leading) {
            Text(field.label).font(.caption)
            TextField(field.key == "dateFrom" || field.key == "dateTo" ? "DD.MM.RRRR" : field.label,
                      text: Binding(get: { fields[field.key] ?? "" }, set: { fields[field.key] = $0 }))
          }
        }
        if invalidDate { Text("Zadej celé datum včetně roku.").foregroundStyle(.red) }
        Button("Uložit hlavičku") {
          var updated = fields.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
          for key in ["dateFrom", "dateTo"] {
            if let value = updated[key] {
              guard let date = CommanderDocumentExtractor.headerDate(value) else { invalidDate = true; return }
              updated[key] = date
            }
          }
          save(updated)
          dismiss()
        }
      }
      .navigationTitle("Údaje z hlavičky")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } } }
    }
  }
}

private struct CommanderPrescriptionEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var count: String
  @State private var note: String
  let save: (SchedulePrescription) -> Void

  init(item: SchedulePrescription, save: @escaping (SchedulePrescription) -> Void) {
    _title = State(initialValue: item.title)
    _count = State(initialValue: item.count.map(String.init) ?? "")
    _note = State(initialValue: item.note ?? "")
    self.save = save
  }

  var body: some View {
    NavigationStack {
      Form {
        TextField("Název procedury", text: $title)
        TextField("Počet", text: $count).keyboardType(.numberPad)
        TextField("Poznámka", text: $note)
        Button("Uložit proceduru") {
          save(.init(title: title.trimmingCharacters(in: .whitespacesAndNewlines), count: Int(count),
                     note: note.isEmpty ? nil : note))
          dismiss()
        }
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                  (!count.isEmpty && !(Int(count).map { $0 > 0 } ?? false)))
      }
      .navigationTitle("Předepsaná procedura")
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zrušit") { dismiss() } } }
    }
  }
}

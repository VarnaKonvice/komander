import Foundation
import LazenskyCommanderCore
import SwiftUI
import UniformTypeIdentifiers

struct CommanderScheduleFilesView: View {
  @ObservedObject var model: CommanderViewModel
  @State private var showsImporter = false
  @State private var candidate: Schedule?
  @State private var showsConfirmation = false
  @State private var exporting = false
  @State private var document = CommanderCalendarDocument()
  @State private var message: String?
  @State private var importing = false

  private var busy: Bool { model.isSynchronizing || importing }

  var body: some View {
    Form {
      Section("Import rozpisu") {
        Text("Vyber kanonický JSON rozpis Commanderu. Import nahradí celý uložený pobyt a přepočítá alarmy, oznámení a widgety. Tvoje lokální předstihy zůstanou zachované.")
        Text("Fotografie a PDF procedurových formulářů nejsou podporované. Změněný rozpis musí mít vyšší verzi než uložený.")
          .font(.footnote)
          .foregroundStyle(.secondary)
        Button("Vybrat JSON soubor", systemImage: "square.and.arrow.down") {
          showsImporter = true
        }
        .disabled(busy)
      }
      Section("Export do kalendáře") {
        Text("Celý aktuální pobyt: procedury i jídla, časy, místa a odchody podle tvých předstihů. Soubor otevři v kalendáři nebo ulož do Souborů.")
        Button("Exportovat pobyt (.ics)", systemImage: "calendar.badge.plus") {
          guard let schedule = model.latestSchedule else { return }
          do {
            document = CommanderCalendarDocument(text: try ScheduleCalendarExport.make(
              schedule: schedule, overrides: model.leadTimeOverrides))
            exporting = true
          } catch {
            message = "Export se nepodařil: \(error.localizedDescription)"
          }
        }
        .disabled(model.latestSchedule == nil || busy)
      }
      if let message {
        Section("Výsledek") {
          Text(message).accessibilityIdentifier("schedule-file-result")
        }
      }
    }
    .navigationTitle("Import a kalendář")
    .navigationBarTitleDisplayMode(.inline)
    .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > ScheduleFileImport.maximumByteCount {
          throw CocoaError(.fileReadTooLarge)
        }
        candidate = try ScheduleFileImport.decode(Data(contentsOf: url))
        showsConfirmation = true
      } catch CocoaError.userCancelled {
      } catch {
        message = "Import se nepodařil. Vyber platný kanonický JSON rozpis. \(error.localizedDescription)"
      }
    }
    .confirmationDialog("Nahradit aktuální rozpis?", isPresented: $showsConfirmation, titleVisibility: .visible) {
      Button("Importovat celý pobyt") {
        guard let schedule = candidate else { return }
        candidate = nil
        importing = true
        Task {
          defer { importing = false }
          do {
            try await model.importSchedule(schedule)
            if model.summary?.succeeded == true, !model.requiresUserAction {
              message = "Rozpis v\(schedule.scheduleVersion) byl přijat: \(schedule.events.count) událostí. Alarmy jsou ověřené."
            } else {
              message = "Rozpis byl přijat. Alarmy nebo oznámení ještě vyžadují kontrolu: \(model.errorMessage ?? model.recoveryStatus)"
            }
          } catch {
            message = "Import se nepodařil: \(error.localizedDescription)"
          }
        }
      }
      .disabled(busy)
      Button("Zrušit", role: .cancel) { candidate = nil }
    } message: {
      if let candidate {
        Text("Verze \(candidate.scheduleVersion) · \(candidate.events.count) událostí. Synchronizace bude dál přijímat pouze novější verze ze společného zdroje.")
      }
    }
    .fileExporter(isPresented: $exporting, document: document,
      contentType: CommanderCalendarDocument.contentType, defaultFilename: "lazensky-commander-pobyt.ics") { result in
      switch result {
      case .success: message = "Kalendář celého pobytu byl exportován."
      case .failure(let error):
        if (error as? CocoaError)?.code != .userCancelled {
          message = "Export se nepodařil: \(error.localizedDescription)"
        }
      }
    }
  }
}

private struct CommanderCalendarDocument: FileDocument {
  static let contentType = UTType(filenameExtension: "ics") ?? .calendarEvent
  static var readableContentTypes: [UTType] { [contentType] }
  var text = ""

  init(text: String = "") { self.text = text }
  init(configuration: ReadConfiguration) throws {
    text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(text.utf8))
  }
}

struct CommanderProductFooter: View {
  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return "Verze \(info["CFBundleShortVersionString"] as? String ?? "?") · build \(info["CFBundleVersion"] as? String ?? "?")"
  }

  var body: some View {
    VStack(spacing: 6) {
      Image("BohanesTechnologiesLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 150, height: 94)
        .accessibilityHidden(true)
      Text("Bohanes Technologies").font(.footnote.weight(.semibold))
      Text("Lázeňský Commander").font(.footnote)
      Text(version).font(.caption)
    }
    .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }
}

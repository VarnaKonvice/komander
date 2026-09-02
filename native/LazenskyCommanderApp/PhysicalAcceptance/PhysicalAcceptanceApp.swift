import ActivityKit
import AlarmKit
import SwiftUI
import LazenskyCommanderCore

@MainActor
final class PhysicalAcceptanceModel: ObservableObject {
  @Published private(set) var run: PhysicalAcceptanceRun?
  @Published private(set) var preflight: PhysicalAcceptancePreflight?
  @Published private(set) var observations: [PhysicalAlarmObservation] = []
  @Published private(set) var status = "Připraveno ke spuštění"
  @Published private(set) var error: String?
  @Published private(set) var isBusy = false
  @Published private(set) var readAt: Date?
  private let ownership = PhysicalAcceptanceOwnershipStore()
  private var adapter: AlarmKitAdapter?
  private var observationTask: Task<Void, Never>?
  private var requests = CommanderSynchronizationRequestQueue()

  func start() {
    guard !isBusy else { return }
    isBusy = true
    Task { await startQueued() }
  }

  private func startQueued() async {
    guard var request = requests.submit(maxAttempts: 3, automatic: false) else { return }
    isBusy = true
    defer { isBusy = false }
    while true {
      await perform(maxAttempts: request.maxAttempts)
      guard let next = requests.completeCurrentAndTakeNext() else { return }
      request = next
    }
  }

  private func perform(maxAttempts: Int) async {
    observationTask?.cancel()
    observationTask = nil
    run = nil; preflight = nil; observations = []; error = nil; readAt = nil
    status = "Ověřuji oprávnění a čistý testovací stav"
    do {
      let runID = UUID()
      let adapter = try AlarmKitAdapter(physicalAcceptanceRunID: runID, ownership: ownership)
      self.adapter = adapter
      if await adapter.authorizationStatus() != .authorized { try await adapter.requestAuthorization() }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        throw AlarmAdapterError.unavailable("Živé aktivity nejsou povolené pro Commander Test.")
      }
      try await AlarmKitAdapter.clearPreviousPhysicalAcceptance(ownership: ownership)
      let run = try PhysicalAcceptanceRun(now: Date(), id: runID)
      self.run = run
      let session = PhysicalAcceptanceSession(run: run, adapter: adapter)
      var summary: AlarmSyncSummary?
      var syncAttempts = 0
      var procedurePrepared = false
      status = "Ověřuji 2 systémové alarmy a 2 živé aktivity"
      for tick in 0..<20 {
        if [0, 4, 10].contains(tick), syncAttempts < maxAttempts,
           summary?.succeeded != true || !procedurePrepared {
          summary = try await session.synchronize(now: Date()).alarmSummary
          syncAttempts += 1
        }
        observations = try await adapter.physicalObservations()
        procedurePrepared = await adapter.physicalProcedureActivityPrepared(run: run)
        let now = Date()
        let check = try await PhysicalAcceptancePreflight(
          run: run, observations: observations, managed: session.alarmStore.load(),
          syncVerified: summary?.succeeded == true,
          procedureActivityPrepared: procedurePrepared, now: now
        )
        preflight = check
        readAt = now
        if check.ready {
          status = "PŘIPRAVENO – 2/2 ověřeno. Zamkněte telefon."
          startReadOnlyObservations(runID: runID)
          return
        }
        try await Task.sleep(for: .seconds(1))
      }
      status = "NEPŘIPRAVENO – tento běh není platný test"
      error = summary?.errorMessage
      startReadOnlyObservations(runID: runID)
    } catch {
      status = "NEPŘIPRAVENO – test nebyl ověřen"
      self.error = error.localizedDescription
    }
  }

  private func startReadOnlyObservations(runID: UUID) {
    observationTask = Task { [weak self] in
      for await _ in AlarmManager.shared.alarmUpdates {
        guard !Task.isCancelled, let self else { return }
        await self.refreshObservations(expectedRunID: runID)
      }
    }
  }

  func refreshObservations(expectedRunID: UUID? = nil) async {
    guard let run, !isBusy, expectedRunID == nil || run.id == expectedRunID, let adapter else { return }
    do {
      let readings = try await adapter.physicalObservations()
      guard self.run?.id == run.id else { return }
      observations = readings
      readAt = Date()
      if preflight?.ready == true,
         let first = preflight?.rows.first?.expectedPlan.scheduledAlertAt,
         Date() >= first {
        status = "Test probíhá – výsledek potvrďte fyzicky"
      }
    } catch { self.error = error.localizedDescription }
  }

  var report: String {
    var lines = [status, "Režim: physicalAcceptance; síť: nepoužita; Watch delivery: vypnuto", "Lokální overrides: žádné (nová prázdná hodnota, bez čtení preferences)"]
    if let run {
      lines += ["Run ID: \(run.id)", "now: \(Self.time(run.now))", "namespace: \(run.namespace)", "projectionRevision: \(run.projectionRevision)"]
    }
    if let preflight {
      lines += ["Ověřeno: \(Self.time(preflight.checkedAt))", "Očekávané alarmy: 2; ověřené: \(preflight.verifiedAlarmCount)", "Skutečné alarmy při posledním čtení: \(observations.count)"]
      for row in preflight.rows {
        lines += ["\(row.alarm.stableId) | \(row.alarm.title)", "lead: \(row.leadTime.minutes) min; source: \(Self.source(row.leadTime.source))", "canonical leaveAt / expected fire: \(row.alarm.leaveAt)", "expected countdown start: \(Self.time(row.expectedCountdownStart))"]
        if let actual = observations.first(where: { $0.stableID == row.alarm.stableId }) ?? row.actual {
          lines += ["AlarmKit ID: \(actual.platformID)", "state: \(actual.state); fixed: \(Self.time(actual.fixedScheduleAt)); schedule: \(actual.scheduleKind)", "preAlert: \(Self.duration(actual.preAlert)); postAlert: \(Self.duration(actual.postAlert)); system fireDate: \(Self.time(actual.fireDate))"]
        }
        lines += row.issues
      }
      lines += preflight.issues
    }
    if let error { lines.append(error) }
    lines.append("Stav PŘIPRAVENO potvrzuje konfiguraci, nikoli automaticky zvuk nebo viditelnost živé aktivity.")
    return lines.joined(separator: "\n")
  }

  static func time(_ date: Date?) -> String {
    guard let date else { return "není dostupné" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "cs_CZ")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")!
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
  }
  static func duration(_ value: TimeInterval?) -> String {
    value.map { String(format: "%.2f s", $0) } ?? "nil"
  }
  static func source(_ source: LeadTimeSource) -> String {
    switch source {
    case .localEventOverride: "lokální override události"
    case .localTypeOverride: "lokální override typu"
    case .localDefault: "lokální výchozí override"
    case .eventOverride: "event override (event.leadTimeMinutes)"
    case .scheduleTypeOverride: "rozpis (settings: override typu)"
    case .scheduleDefault: "rozpis (settings.defaultLeadTimeMinutes)"
    }
  }
}

struct PhysicalAcceptanceView: View {
  @ObservedObject var model: PhysicalAcceptanceModel

  var body: some View {
    Form {
      Section {
        HStack {
          CommanderBrandAssets.circularMark.resizable().scaledToFit().frame(width: 48, height: 48)
          VStack(alignment: .leading) {
            Text("Commander Test").font(.headline)
            Text("Fyzický test alarmů a živých aktivit").font(.caption).foregroundStyle(.secondary)
          }
        }
        Button(action: model.start) {
          Label("Spustit fyzický test", systemImage: "play.fill")
        }.disabled(model.isBusy)
        Text(model.status).font(.headline).foregroundStyle(model.preflight?.ready == true ? .green : .primary)
        if model.isBusy { ProgressView() }
        if let error = model.error { Text(error).foregroundStyle(.red) }
      }

      if let run = model.run {
        Section("Časový plán – sledujte v tomto pořadí") {
          if let check = model.preflight {
            ForEach(check.rows, id: \.alarm.stableId) { row in
              if let event = run.schedule.events.first(where: { $0.stableId == row.alarm.stableId }),
                 let start = try? NativeAlarmContract.dateTime(date: event.date, time: event.start),
                 let end = try? NativeAlarmContract.dateTime(date: event.date, time: event.end) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(event.title).font(.headline)
                  Text("Odchod / alarm: \(PhysicalAcceptanceModel.time(row.expectedPlan.scheduledAlertAt))")
                    .font(.title3.bold()).foregroundStyle(.orange)
                  Text("Začátek: \(PhysicalAcceptanceModel.time(start)) · konec: \(PhysicalAcceptanceModel.time(end))")
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
              }
            }
            Text("Sled: Odchod za → alarm → Právě jídlo → Právě volno / další odchod → alarm → Právě probíhá.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          } else {
            Text("Časy se objeví po systémovém ověření běhu.")
              .foregroundStyle(.secondary)
          }
        }

        Section("Izolovaný běh") {
          field("Run ID", run.id.uuidString)
          field("Testovací čas", PhysicalAcceptanceModel.time(run.now))
          field("Lokální změny časů", "Žádné; uložené preference se nečtou")
          field("Revize", String(run.projectionRevision))
          field("Apple Watch", "Předávání vypnuto")
          field("Síť / GitHub", "Nepoužito")
        }
      }

      if let check = model.preflight {
        Section("Předběžná kontrola") {
          field("Očekávané alarmy", "2")
          field("Ověřené alarmy", "\(check.verifiedAlarmCount)")
          field("Skutečné alarmy", "\(model.observations.count)")
          field("Ověřeno v", PhysicalAcceptanceModel.time(check.checkedAt))
          ForEach(check.issues, id: \.self) { Text($0).foregroundStyle(.red) }
        }
        ForEach(check.rows, id: \.alarm.stableId) { row in
          Section(row.alarm.title) {
            field("Čas na odchod", row.alarm.leaveAt)
            field("Začátek odpočtu", PhysicalAcceptanceModel.time(row.expectedCountdownStart))
            field("Čas alarmu", PhysicalAcceptanceModel.time(row.expectedPlan.scheduledAlertAt))
            field("Předstih", "\(row.leadTime.minutes) min")
            if let actual = model.observations.first(where: { $0.stableID == row.alarm.stableId }) {
              field("Stav alarmu", actual.state)
              field("Pevný začátek", PhysicalAcceptanceModel.time(actual.fixedScheduleAt))
              field("Systémový čas alarmu", PhysicalAcceptanceModel.time(actual.fireDate))
            } else { Text("Alarm již není v aktuálním systémovém seznamu.").foregroundStyle(.secondary) }
            ForEach(row.issues, id: \.self) { Text($0).foregroundStyle(.red) }
          }
        }
        Section {
          field("Poslední systémové ověření", PhysicalAcceptanceModel.time(model.readAt))
          Text("Stav PŘIPRAVENO potvrzuje konfiguraci. Úspěšný fyzický test vyžaduje oba skutečné alarmy a viditelné živé stavy ve výše uvedených časech.").font(.footnote)
          ShareLink(item: model.report) { Label("Sdílet diagnostiku", systemImage: "square.and.arrow.up") }
        }
      }
    }.tint(.purple)
  }

  private func field(_ title: String, _ value: String) -> some View {
    LabeledContent {
      Text(value).multilineTextAlignment(.trailing).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    } label: { Text(title) }
  }
}

@main
struct PhysicalAcceptanceApp: App {
  @StateObject private var model = PhysicalAcceptanceModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      PhysicalAcceptanceView(model: model)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { Task { await model.refreshObservations() } }
        }
    }
  }
}

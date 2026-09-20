import ActivityKit
import AlarmKit
import SwiftUI
import LazenskyCommanderCore

private actor PhysicalAcceptanceLiveActivityPrimer {
  static let stableID = "physicalAcceptance.permissionProbe"

  func prepare() async throws {
    await clear()
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      throw AlarmAdapterError.unavailable("Live Activities jsou v systému vypnuté.")
    }
    let now = Date()
    let attributes = CommanderProcedureLiveActivityAttributes(
      stableId: Self.stableID,
      scheduleVersion: 0,
      iconKey: "",
      title: "Commander Test – příprava",
      location: "Ověření Live Activities",
      kind: .procedure,
      leaveAt: now,
      startAt: now,
      endAt: now.addingTimeInterval(5 * 60),
      nextEvent: nil
    )
    let content = ActivityContent(
      state: CommanderProcedureLiveActivityAttributes.ContentState(),
      staleDate: now.addingTimeInterval(5 * 60),
      relevanceScore: 0
    )
    _ = try Activity<CommanderProcedureLiveActivityAttributes>.request(
      attributes: attributes,
      content: content,
      pushType: nil,
      style: .standard
    )
  }

  func confirmAndClear() async -> Bool {
    for _ in 0..<10 {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        await clear()
        return false
      }
      let probes = Activity<CommanderProcedureLiveActivityAttributes>.activities.filter {
        $0.attributes.stableId == Self.stableID
      }
      if !probes.isEmpty {
        for activity in probes { await activity.end(nil, dismissalPolicy: .immediate) }
        return true
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    await clear()
    return false
  }

  func clear() async {
    for activity in Activity<CommanderProcedureLiveActivityAttributes>.activities
      where activity.attributes.stableId == Self.stableID {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}

@MainActor
final class PhysicalAcceptanceModel: ObservableObject {
  @Published private(set) var run: PhysicalAcceptanceRun?
  @Published private(set) var preflight: PhysicalAcceptancePreflight?
  @Published private(set) var observations: [PhysicalAlarmObservation] = []
  @Published private(set) var preparedCommanderStableIDs: Set<String> = []
  @Published private(set) var readyCommanderStableIDs: Set<String> = []
  @Published private(set) var status = "Nejdřív připravte Live Activities"
  @Published private(set) var error: String?
  @Published private(set) var isBusy = false
  @Published private(set) var readAt: Date?
  @Published private(set) var diagnosticTimeline = "Zatím žádné diagnostické události"
  @Published private(set) var liveActivityPrimerStatus = "Nevyzkoušeno"
  private let ownership = PhysicalAcceptanceOwnershipStore()
  private let liveActivityPrimer = PhysicalAcceptanceLiveActivityPrimer()
  private var adapter: AlarmKitAdapter?
  private var procedureActivities: CommanderProcedureLiveActivityCoordinator?
  private var permissionProbeRequested = false
  private var liveActivitiesPrimed = false
  private var observationTask: Task<Void, Never>?
  private var activityStateTasks: [Task<Void, Never>] = []
  private var lastSnapshotFingerprint: String?
  private var requests = CommanderSynchronizationRequestQueue()

  var primaryActionTitle: String {
    if liveActivitiesPrimed { return "Spustit fyzický test" }
    if permissionProbeRequested { return "Potvrdit povolení a spustit test" }
    return "Připravit Live Activities"
  }

  func start() {
    guard !isBusy else { return }
    if !liveActivitiesPrimed, ActivityAuthorizationInfo().areActivitiesEnabled {
      liveActivitiesPrimed = true
      liveActivityPrimerStatus = "Povoleno systémem"
      beginTimedRun()
      return
    }
    if !liveActivitiesPrimed {
      isBusy = true
      Task { await prepareOrConfirmLiveActivities() }
      return
    }
    beginTimedRun()
  }

  private func beginTimedRun() {
    isBusy = true
    Task { await startQueued() }
  }

  private func prepareOrConfirmLiveActivities() async {
    error = nil
    do {
      if permissionProbeRequested {
        guard await liveActivityPrimer.confirmAndClear() else {
          permissionProbeRequested = false
          liveActivityPrimerStatus = "Live Activities nejsou povolené"
          throw AlarmAdapterError.unavailable("Povolte Live Activities pro Commander Test a spusťte přípravu znovu.")
        }
        permissionProbeRequested = false
        liveActivitiesPrimed = true
        liveActivityPrimerStatus = "Ověřeno před časovaným během"
        status = "Live Activities připravené – spouštím časovaný test"
        beginTimedRun()
        return
      }

      try await liveActivityPrimer.prepare()
      permissionProbeRequested = true
      liveActivityPrimerStatus = "Vyřiďte systémové Povolit / Nepovolovat"
      status = "Nejdřív vyřiďte systémové povolení Live Activities, potom znovu stiskněte tlačítko."
      isBusy = false
    } catch {
      self.error = error.localizedDescription
      isBusy = false
    }
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
    activityStateTasks.forEach { $0.cancel() }
    activityStateTasks = []
    lastSnapshotFingerprint = nil
    run = nil; preflight = nil; observations = []; preparedCommanderStableIDs = []; readyCommanderStableIDs = []; error = nil; readAt = nil
    diagnosticTimeline = "Zatím žádné diagnostické události"
    status = "Ověřuji oprávnění a čistý testovací stav"
    do {
      let runID = UUID()
      let adapter = try AlarmKitAdapter(physicalAcceptanceRunID: runID, ownership: ownership)
      let procedureActivities = CommanderProcedureLiveActivityCoordinator()
      self.adapter = adapter
      self.procedureActivities = procedureActivities
      if await adapter.authorizationStatus() != .authorized { try await adapter.requestAuthorization() }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        throw AlarmAdapterError.unavailable("Živé aktivity nejsou povolené pro Commander Test.")
      }
      try await AlarmKitAdapter.clearPreviousPhysicalAcceptance(ownership: ownership)
      let run = try PhysicalAcceptanceRun(now: Date(), id: runID)
      self.run = run
      recordDiagnostic("RUN vytvořen · \(runID.uuidString)")
      let session = PhysicalAcceptanceSession(run: run, adapter: adapter)
      var summary: AlarmSyncSummary?
      var syncAttempts = 0
      status = "Ověřuji 2 systémové alarmy; Commander čeká na Stop"
      for tick in 0..<20 {
        if [0, 4, 10].contains(tick), syncAttempts < maxAttempts,
           summary?.succeeded != true {
          summary = try await session.synchronize(now: Date()).alarmSummary
          syncAttempts += 1
        }
        await procedureActivities.reconcile(
          schedule: run.schedule,
          overrides: run.overrides,
          projectionRevision: run.projectionRevision
        )
        observations = try await adapter.physicalObservations()
        preparedCommanderStableIDs = await procedureActivities.preparedStableIDs(
          schedule: run.schedule,
          overrides: run.overrides,
          projectionRevision: run.projectionRevision
        )
        let now = Date()
        let check = try await PhysicalAcceptancePreflight(
          run: run, observations: observations, managed: session.alarmStore.load(),
          syncVerified: summary?.succeeded == true,
          procedureActivityPrepared: true, now: now
        )
        preflight = check
        readAt = now
        if check.ready {
          readyCommanderStableIDs = preparedCommanderStableIDs
          recordDiagnostic("READY · alarmy 2/2 · Commander handoff čeká na Stop")
          recordSnapshot(run: run, readings: observations)
          startActivityStateObservers(run: run)
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

  private func recordDiagnostic(_ text: String) {
    CommanderPhysicalAcceptanceDiagnostics.record(text)
    diagnosticTimeline = CommanderPhysicalAcceptanceDiagnostics.read()
      ?? "Zatím žádné diagnostické události"
  }

  private func startActivityStateObservers(run: PhysicalAcceptanceRun) {
    activityStateTasks.forEach { $0.cancel() }
    activityStateTasks = []
    let activities = Activity<CommanderProcedureLiveActivityAttributes>.activities.filter {
      $0.attributes.stableId.hasPrefix(run.namespace + ".")
    }
    for activity in activities {
      let label = Self.shortStableID(activity.attributes.stableId)
      recordDiagnostic("Activity \(label) · \(Self.activityStateName(activity.activityState))")
      activityStateTasks.append(Task { [weak self] in
        for await state in activity.activityStateUpdates {
          guard !Task.isCancelled, let self, self.run?.id == run.id else { return }
          self.recordDiagnostic("Activity \(label) · \(Self.activityStateName(state))")
        }
      })
    }
  }

  private func recordSnapshot(run: PhysicalAcceptanceRun, readings: [PhysicalAlarmObservation]) {
    let alarmPart = readings.sorted { ($0.stableID ?? $0.platformID) < ($1.stableID ?? $1.platformID) }
      .map { "\(Self.shortStableID($0.stableID ?? $0.platformID))=\($0.state)" }
      .joined(separator: ", ")
    let activityPart = Activity<CommanderProcedureLiveActivityAttributes>.activities
      .filter { $0.attributes.stableId.hasPrefix(run.namespace + ".") }
      .sorted { $0.id < $1.id }
      .map { activity in
        let queue = activity.content.state.events
          .map { Self.shortStableID($0.stableId) }
          .joined(separator: "→")
        let queueText = queue.isEmpty ? Self.shortStableID(activity.attributes.stableId) : queue
        return "single[\(queueText)]=\(Self.activityStateName(activity.activityState))"
      }
      .joined(separator: ", ")
    let fingerprint = "A[\(alarmPart)]|L[\(activityPart)]"
    guard fingerprint != lastSnapshotFingerprint else { return }
    lastSnapshotFingerprint = fingerprint
    recordDiagnostic("SNAPSHOT · AlarmKit [\(alarmPart)] · Commander [\(activityPart)]")
  }

  private func reconcileOwnership(with readings: [PhysicalAlarmObservation]) async {
    let platformIDs = Set(readings.map(\.platformID))
    for id in await ownership.allIDs() where !platformIDs.contains(id) {
      await ownership.forget(id)
    }
  }

  func refreshObservations(expectedRunID: UUID? = nil) async {
    diagnosticTimeline = CommanderPhysicalAcceptanceDiagnostics.read()
      ?? "Zatím žádné diagnostické události"
    guard let run, !isBusy, expectedRunID == nil || run.id == expectedRunID,
          let adapter, let procedureActivities else { return }
    do {
      let readings = try await adapter.physicalObservations()
      guard self.run?.id == run.id else { return }
      observations = readings
      preparedCommanderStableIDs = await procedureActivities.preparedStableIDs(
        schedule: run.schedule,
        overrides: run.overrides,
        projectionRevision: run.projectionRevision
      )
      await reconcileOwnership(with: readings)
      recordSnapshot(run: run, readings: readings)
      readAt = Date()
      let now = Date()
      let finalEnd = run.schedule.events.compactMap {
        try? NativeAlarmContract.dateTime(date: $0.date, time: $0.end)
      }.max()
      if preflight?.ready == true, let finalEnd, now >= finalEnd {
        status = "TEST DOKONČEN – zkontrolujte diagnostickou časovou osu"
      } else if preflight?.ready == true,
                let first = preflight?.rows.first?.expectedPlan.scheduledAlertAt,
                now >= first {
        status = "Test probíhá – výsledek potvrďte fyzicky"
      }
    } catch { self.error = error.localizedDescription }
  }

  var report: String {
    var lines = [status, "Režim: physicalAcceptance; síť: nepoužita; Watch delivery: vypnuto", "Lokální overrides: žádné (nová prázdná hodnota, bez čtení preferences)", "Live Activity primer: \(liveActivityPrimerStatus)", "Diagnostická časová osa:\n\(diagnosticTimeline)"]
    if let run {
      lines += ["Run ID: \(run.id)", "now: \(Self.time(run.now))", "namespace: \(run.namespace)", "projectionRevision: \(run.projectionRevision)"]
    }
    if let preflight {
      lines += ["Ověřeno: \(Self.time(preflight.checkedAt))", "Očekávané alarmy: 2; ověřené: \(preflight.verifiedAlarmCount)", "Skutečné alarmy při posledním čtení: \(observations.count)", "Commander handoff: vzniká až po Stop; aktuálně aktivní: \(preparedCommanderStableIDs.count)"]
      for row in preflight.rows {
        lines += ["\(row.alarm.stableId) | \(row.alarm.title)", "lead: \(row.leadTime.minutes) min; source: \(Self.source(row.leadTime.source))", "canonical leaveAt / expected fire: \(row.alarm.leaveAt)", "expected visible/system transition: \(Self.time(row.expectedCountdownStart))"]
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

  static func shortStableID(_ value: String) -> String {
    value.split(separator: ".").last.map(String.init) ?? value
  }

  static func activityStateName(_ state: ActivityState) -> String {
    switch state {
    case .pending: "pending"
    case .active: "active"
    case .stale: "stale"
    case .ended: "ended"
    case .dismissed: "dismissed"
    @unknown default: "unknown"
    }
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
          Label(model.primaryActionTitle, systemImage: "play.fill")
        }.disabled(model.isBusy)
        field("Live Activity primer", model.liveActivityPrimerStatus)
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
            Text("Sled: Odchod za → alarm → Zastavit → Commander ZAČÍNÁ ZA → v startu PRÁVĚ… → po konci DALŠÍ / Skončilo; stejně pro druhou událost.")
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
          field("Commander handoff", "po Stop; aktivní nyní \(model.preparedCommanderStableIDs.count)")
          field("Ověřeno v", PhysicalAcceptanceModel.time(check.checkedAt))
          ForEach(check.issues, id: \.self) { Text($0).foregroundStyle(.red) }
        }
        ForEach(check.rows, id: \.alarm.stableId) { row in
          Section(row.alarm.title) {
            field("Čas na odchod", row.alarm.leaveAt)
            field("Přechod k alarmu", PhysicalAcceptanceModel.time(row.expectedCountdownStart))
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
        Section("Diagnostická časová osa") {
          Text(model.diagnosticTimeline)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
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
        .task {
          if ProcessInfo.processInfo.arguments.contains("--auto-run") {
            model.start()
          }
        }
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { Task { await model.refreshObservations() } }
        }
    }
  }
}
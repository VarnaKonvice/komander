import LazenskyCommanderCore
import SwiftUI

private enum CommanderDashboardPreviewFixtures {
  static let normalDay: Schedule = decode(
    events: """
      {"stableId":"breakfast","date":"2026-08-20","start":"07:30","end":"08:00","title":"Snídaně","location":"Jídelna","kind":"meal","mealType":"Snídaně"},
      {"stableId":"iodobrom","date":"2026-08-20","start":"09:00","end":"09:30","title":"Jodobromová koupel","location":"Balneo","kind":"procedure","procedureType":"Jodobromová koupel"},
      {"stableId":"whirlpool","date":"2026-08-20","start":"10:00","end":"10:30","title":"Vířivá vana","location":"Vodní léčba","kind":"procedure","procedureType":"Vířivá vana"},
      {"stableId":"lunch","date":"2026-08-20","start":"12:00","end":"12:45","title":"Oběd","location":"Jídelna","kind":"meal","mealType":"Oběd"},
      {"stableId":"massage","date":"2026-08-20","start":"14:00","end":"14:20","title":"Klasická masáž","location":"Rehabilitace, box 3","kind":"procedure","procedureType":"Klasická masáž"},
      {"stableId":"dinner","date":"2026-08-20","start":"17:30","end":"18:00","title":"Večeře","location":"Jídelna","kind":"meal","mealType":"Večeře"}
    """
  )

  static func date(_ value: String) -> Date {
    try! NativeAlarmContract.date(fromLocalISO: value)
  }

  private static func decode(events: String) -> Schedule {
    let json = """
    {
      "schemaVersion": 1,
      "scheduleVersion": 1,
      "updatedAt": "2026-08-20T00:00:00Z",
      "stay": {},
      "events": [\(events)],
      "settings": {
        "defaultLeadTimeMinutes": 20,
        "procedureTypeOverrides": {},
        "mealOverrides": {}
      }
    }
    """
    return try! JSONDecoder().decode(Schedule.self, from: Data(json.utf8))
  }
}

private struct CommanderDashboardPreview: View {
  let schedule: Schedule?
  let now: Date

  var body: some View {
    NavigationStack {
      CommanderDashboardContent(
        schedule: schedule,
        overrides: LeadTimeOverrides(),
        now: now,
        isSynchronizing: false,
        synchronize: {}
      )
      .background(CommanderDesignTokens.Colors.background.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
    }
    .preferredColorScheme(.dark)
  }
}

#Preview("Upcoming — Jodobrom") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T08:30:00")
  )
}

#Preview("Leave now — Jodobrom") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T08:45:00")
  )
}

#Preview("In progress — Whirlpool") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T10:05:00")
  )
}

#Preview("Normal day") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T11:00:00")
  )
}

#Preview("Day done") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T20:00:00")
  )
}

#Preview("No schedule") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-21T09:00:00")
  )
}

#Preview("Unsynchronized") {
  CommanderDashboardPreview(
    schedule: nil,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T09:00:00")
  )
}

#Preview("Dnes - velké písmo") {
  CommanderDashboardPreview(
    schedule: CommanderDashboardPreviewFixtures.normalDay,
    now: CommanderDashboardPreviewFixtures.date("2026-08-20T13:21:00")
  )
  .environment(\.dynamicTypeSize, .accessibility3)
}

private struct CommanderWeekDayPreview: View {
  @State var isExpanded: Bool

  var body: some View {
    let days = try! CommanderWeekPresentation.make(
      schedule: CommanderDashboardPreviewFixtures.normalDay,
      now: CommanderDashboardPreviewFixtures.date("2026-08-20T13:21:00")
    )
    ScrollView {
      VStack(spacing: CommanderDesignTokens.Spacing.medium) {
        CommanderGlassHeader(tab: "Týden")
        CommanderWeekDayTile(day: days[0], isExpanded: isExpanded) { isExpanded.toggle() }
      }
      .padding(CommanderDesignTokens.Spacing.page)
    }
    .background(CommanderDesignTokens.Colors.background.ignoresSafeArea())
    .preferredColorScheme(.dark)
  }
}

#Preview("Týden - sbalený den") {
  CommanderWeekDayPreview(isExpanded: false)
}

#Preview("Týden - rozbalený den") {
  CommanderWeekDayPreview(isExpanded: true)
}

#if DEBUG && targetEnvironment(simulator)
// Deterministic visual checks of the real UI components; never changes the device schedule.
struct CommanderApprovedVisualProof: View {
  static var mode: String? {
    let args = ProcessInfo.processInfo.arguments
    guard let index = args.firstIndex(of: "-CommanderApprovedVisualProof"),
          args.indices.contains(index + 1) else { return nil }
    return args[index + 1]
  }

  private static let cases: [(String, String, String, String)] = [
    ("Snídaně", "07:30", "#50B863", "fork.knife"),
    ("Individuální rehabilitace", "08:30", "#2EE6C4", "figure.run"),
    ("Ergoterapie", "09:30", "#2EE6C4", "figure.run"),
    ("Vířivá vana dolních končetin", "10:30", "#2ED4FF", "drop"),
    ("Bazén", "11:30", "#2ED4FF", "drop"),
    ("Masáž", "12:30", "#FF7A59", "leaf.fill"),
    ("Hydrojet", "13:30", "#FF7A59", "leaf.fill"),
    ("Rašelinový zábal", "14:30", "#FFC857", "commander.heat.waves"),
    ("Magnetoterapie", "15:30", "#D6B4FE", "atom"),
    ("Večeře", "17:30", "#50B863", "fork.knife")
  ]

  private var schedule: Schedule {
    let events = ["2026-09-24", "2026-09-25"].flatMap { date in
      Self.cases.enumerated().map { index, item -> [String: String] in
        ["stableId": "proof-\(date)-\(index)", "date": date,
         "start": item.1, "end": String(item.1.prefix(2)) + ":55",
         "title": item.0, "location": index == 0 || index == 9 ? "Jídelna" : "Rehabilitace",
         "kind": index == 0 || index == 9 ? "meal" : "procedure"]
      }
    }
    let object: [String: Any] = [
      "schemaVersion": 1, "scheduleVersion": 1, "updatedAt": "2026-09-24T00:00:00Z",
      "stay": ["dateFrom": "2026-09-24", "dateTo": "2026-09-25"], "events": events,
      "settings": ["defaultLeadTimeMinutes": 20, "procedureTypeOverrides": [:], "mealOverrides": [:]]
    ]
    let schedule = try! JSONDecoder().decode(Schedule.self, from: JSONSerialization.data(withJSONObject: object))
    for (event, reference) in zip(schedule.events.prefix(Self.cases.count), Self.cases) {
      precondition(CommanderVisualAssets.accent(for: event) == reference.2, event.title)
      precondition(CommanderVisualAssets.symbol(for: event) == reference.3, event.title)
    }
    precondition(CommanderVisualAssets.accent(forIconKey: nil) == "#FF5DA8")
    precondition(CommanderVisualAssets.accent(forIconKey: "unknown") == "#FF5DA8")
    return schedule
  }

  var body: some View {
    let schedule = schedule
    let now = try! NativeAlarmContract.date(fromLocalISO: "2026-09-24T09:35:00")
    let days = try! CommanderWeekPresentation.make(schedule: schedule, now: now)
    Group {
      if Self.mode == "today" {
        CommanderDashboardContent(schedule: schedule, overrides: LeadTimeOverrides(), now: now,
                                  isSynchronizing: false, synchronize: {})
      } else {
        ScrollView {
          VStack(spacing: CommanderDesignTokens.Spacing.medium) {
            CommanderGlassHeader(tab: "")
            if Self.mode == "program" || Self.mode == "program-later" {
              CommanderDayTimelineView(items: Self.mode == "program"
                ? Array(days[0].events.prefix(5)) : Array(days[0].events.suffix(5)))
            } else {
              let isToday = Self.mode == "week-today"
              CommanderWeekDayTile(day: days[isToday ? 0 : 1],
                                  isExpanded: Self.mode == "week-expanded",
                                  isToday: isToday, toggle: {})
            }
          }
          .padding(CommanderDesignTokens.Spacing.page)
        }
      }
    }
    .background(CommanderDepthBackground().ignoresSafeArea())
    .preferredColorScheme(.dark)
  }
}
#endif

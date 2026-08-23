import LazenskyCommanderCore
import SwiftUI

private enum CommanderDashboardPreviewFixtures {
  static let normalDay: Schedule = decode(
    events: """
      {"stableId":"breakfast","date":"2026-08-20","start":"07:30","end":"08:00","title":"Snídaně","location":"Jídelna","kind":"meal","mealType":"Snídaně"},
      {"stableId":"iodobrom","date":"2026-08-20","start":"09:00","end":"09:30","title":"Jodobromová koupel","location":"Balneo","kind":"procedure","procedureType":"Jodobromová koupel"},
      {"stableId":"whirlpool","date":"2026-08-20","start":"10:00","end":"10:30","title":"Vířivá vana","location":"Vodní léčba","kind":"procedure","procedureType":"Vířivá vana"},
      {"stableId":"lunch","date":"2026-08-20","start":"12:00","end":"12:45","title":"Oběd","location":"Jídelna","kind":"meal","mealType":"Oběd"},
      {"stableId":"massage","date":"2026-08-20","start":"14:00","end":"14:20","title":"Klasická masáž","location":"Rehabilitace","kind":"procedure","procedureType":"Klasická masáž"},
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
        now: now,
        isSynchronizing: false,
        synchronize: {}
      )
      .background(CommanderDashboardPalette.background.ignoresSafeArea())
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

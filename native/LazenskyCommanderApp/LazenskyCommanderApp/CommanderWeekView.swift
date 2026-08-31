import LazenskyCommanderCore
import SwiftUI

struct CommanderWeekView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    Group {
      if let schedule = model.latestSchedule {
        if let days = try? CommanderWeekPresentation.make(
          schedule: schedule, now: .now, overrides: model.leadTimeOverrides
        ) {
          if days.isEmpty {
            CommanderScheduleEmptyView(title: "Rozpis neobsahuje žádné události")
          } else {
            List {
              ForEach(days, id: \.date) { day in
                Section {
                  ForEach(day.events, id: \.event.stableId) { item in
                    CommanderWeekEventRow(item: item)
                  }
                } header: {
                  Text(day.date, format: CommanderScheduleDateStyle.day)
                    .textCase(nil)
                }
              }
            }
            .scrollContentBackground(.hidden)
          }
        } else {
          CommanderScheduleEmptyView(title: "Rozpis nelze zobrazit")
        }
      } else {
        CommanderScheduleEmptyView(title: "Rozpis ještě není načten")
      }
    }
    .background(CommanderDashboardPalette.background)
    .navigationTitle("Týden")
    .navigationBarTitleDisplayMode(.inline)
  }
}

private struct CommanderWeekEventRow: View {
  let item: CommanderDashboardEvent

  private var departureStyle: Date.FormatStyle {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    return calendar.isDate(item.startAt, inSameDayAs: item.leaveAt)
      ? CommanderScheduleDateStyle.clock : CommanderScheduleDateStyle.departure
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      CommanderEventIconView(event: item.event, size: 44)
      VStack(alignment: .leading, spacing: 5) {
        Text("\(item.startAt.formatted(CommanderScheduleDateStyle.clock)) – \(item.endAt.formatted(CommanderScheduleDateStyle.clock))")
          .font(.subheadline.monospacedDigit())
          .foregroundStyle(CommanderDashboardPalette.commanderPurpleLight)
        Text(item.event.title).font(.headline)
        Text(item.event.location).foregroundStyle(.secondary)
        Text(item.event.kind == .meal ? "Jídlo" : "Procedura")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Odchod \(item.leaveAt.formatted(departureStyle))")
          .font(.subheadline.monospacedDigit())
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

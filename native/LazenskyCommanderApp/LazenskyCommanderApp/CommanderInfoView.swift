import LazenskyCommanderCore
import SwiftUI

struct CommanderInfoView: View {
  @ObservedObject var model: CommanderViewModel

  private let labels = [
    "spa": "Lázně", "dateFrom": "Pobyt od", "dateTo": "Pobyt do",
    "room": "Pokoj", "doctor": "Lékař", "mealShift": "Stravovací směna"
  ]

  var body: some View {
    Group {
      if let schedule = model.latestSchedule {
        let fields = CommanderInfoPresentation.fields(stay: schedule.stay)
        if fields.isEmpty {
          CommanderScheduleEmptyView(title: "Informace o pobytu nejsou uvedeny")
        } else {
          List(fields, id: \.key) { field in
            LabeledContent(labels[field.key] ?? field.key, value: field.value)
          }
          .scrollContentBackground(.hidden)
        }
      } else {
        CommanderScheduleEmptyView(title: "Rozpis ještě není načten")
      }
    }
    .background(CommanderDashboardPalette.background)
    .navigationTitle("Info")
    .navigationBarTitleDisplayMode(.inline)
  }
}

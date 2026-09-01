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
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
              CommanderPageHeader(title: "Info", subtitle: "Údaje z rozpisu")
              CommanderScreenTitle(title: "Info", subtitle: "Praktické údaje k pobytu")
              CommanderInfoPanel(title: "Pobyt", systemImage: "info.circle") {
                ForEach(fields, id: \.key) { field in
                  CommanderInfoRow(title: labels[field.key] ?? field.key, value: field.value)
                }
              }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
          }
          .contentMargins(.top, 6, for: .scrollContent)
          .scrollIndicators(.hidden)
        }
      } else {
        CommanderScheduleEmptyView(title: "Rozpis ještě není načten")
      }
    }
    .background(CommanderDashboardPalette.backgroundGradient.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }
}

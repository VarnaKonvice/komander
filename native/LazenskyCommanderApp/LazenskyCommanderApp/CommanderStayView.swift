import LazenskyCommanderCore
import SwiftUI

struct CommanderStayView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
      if let schedule = model.latestSchedule {
        if let stay = try? CommanderStayPresentation.make(schedule: schedule, now: context.date) {
          List {
            Section("Pobyt") {
              if let period = stay.period {
                LabeledContent("Od", value: period.dateFrom.formatted(CommanderScheduleDateStyle.day))
                LabeledContent("Do", value: period.dateTo.formatted(CommanderScheduleDateStyle.day))
                LabeledContent("Počet dnů", value: String(period.totalDays))
                if let current = period.currentDay {
                  LabeledContent("Dnešní den pobytu", value: "\(current) z \(period.totalDays)")
                } else {
                  Text(period.phase == .upcoming ? "Pobyt ještě nezačal" : "Pobyt skončil")
                    .foregroundStyle(.secondary)
                }
              } else {
                Text("Termín pobytu není k dispozici").foregroundStyle(.secondary)
              }
            }
            Section("Procedury") {
              LabeledContent("Ukončené podle rozpisu", value: "\(stay.completedProcedures) / \(stay.totalProcedures)")
            }
            if !stay.procedures.isEmpty {
              Section("Podle procedury · ukončené / celkem") {
                ForEach(stay.procedures, id: \.name) { procedure in
                  LabeledContent(procedure.name, value: "\(procedure.completed) / \(procedure.total)")
                }
              }
            }
          }
          .scrollContentBackground(.hidden)
        } else {
          CommanderScheduleEmptyView(title: "Souhrn pobytu nelze zobrazit")
        }
      } else {
        CommanderScheduleEmptyView(title: "Rozpis ještě není načten")
      }
    }
    .background(CommanderDashboardPalette.background)
    .navigationTitle("Pobyt")
    .navigationBarTitleDisplayMode(.inline)
  }
}

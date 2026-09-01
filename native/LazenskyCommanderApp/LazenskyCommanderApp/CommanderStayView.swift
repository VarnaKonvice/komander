import LazenskyCommanderCore
import SwiftUI

struct CommanderStayView: View {
  @ObservedObject var model: CommanderViewModel

  var body: some View {
    TimelineView(.periodic(from: Calendar.current.startOfDay(for: .now), by: 60)) { context in
      if let schedule = model.latestSchedule {
        if let stay = try? CommanderStayPresentation.make(schedule: schedule, now: context.date) {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
              CommanderPageHeader(
                title: "Pobyt",
                subtitle: stay.period.flatMap { periodSubtitle($0) }
              )
              CommanderScreenTitle(title: "Pobyt", subtitle: "Průběh lázeňského programu")
              CommanderStayProgressCard(stay: stay)

              CommanderInfoPanel(title: "Termín", systemImage: "calendar") {
                if let period = stay.period {
                  CommanderInfoRow(title: "Od", value: CommanderDateText.numericDate(period.dateFrom))
                  CommanderInfoRow(title: "Do", value: CommanderDateText.numericDate(period.dateTo))
                  CommanderInfoRow(title: "Počet dnů", value: String(period.totalDays))
                  if let current = period.currentDay {
                    CommanderInfoRow(title: "Dnešní den", value: "\(current) z \(period.totalDays)")
                  } else {
                    Text(period.phase == .upcoming ? "Pobyt ještě nezačal" : "Pobyt skončil")
                      .foregroundStyle(.secondary)
                      .padding(14)
                      .frame(maxWidth: .infinity, alignment: .leading)
                  }
                } else {
                  Text("Termín pobytu není k dispozici")
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }

              CommanderInfoPanel(title: "Procedury", systemImage: "checkmark.circle") {
                CommanderInfoRow(title: "Ukončené podle rozpisu", value: "\(stay.completedProcedures) / \(stay.totalProcedures)")
              }

              if !stay.procedures.isEmpty {
                CommanderInfoPanel(title: "Podle procedury", systemImage: "list.bullet.rectangle") {
                  ForEach(stay.procedures, id: \.name) { procedure in
                    CommanderInfoRow(title: procedure.name, value: "\(procedure.completed) / \(procedure.total)")
                  }
                }
              }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
          }
          .contentMargins(.top, 6, for: .scrollContent)
          .scrollIndicators(.hidden)
        } else {
          CommanderScheduleEmptyView(title: "Souhrn pobytu nelze zobrazit")
        }
      } else {
        CommanderScheduleEmptyView(title: "Rozpis ještě není načten")
      }
    }
    .background(CommanderDashboardPalette.backgroundGradient.ignoresSafeArea())
    .toolbar(.hidden, for: .navigationBar)
  }

  private func periodSubtitle(_ period: CommanderStayPeriod) -> String {
    switch period.phase {
    case .active:
      if let currentDay = period.currentDay {
        return "\(currentDay). den z \(period.totalDays)"
      }
      return "\(period.totalDays) dnů"
    case .upcoming:
      return "Pobyt ještě nezačal"
    case .finished:
      return "Pobyt skončil"
    }
  }
}

private struct CommanderStayProgressCard: View {
  let stay: CommanderStayPresentation

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(primaryTitle)
            .font(.title2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
          Text(primarySubtitle)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        CommanderNeutralStateVisual(accent: CommanderDashboardPalette.waterBlue, size: 46)
      }

      progressLine(title: "Pobyt", value: stayProgressValue, fraction: stayProgressFraction)
      progressLine(
        title: "Procedury ukončené podle rozpisu",
        value: "\(stay.completedProcedures) / \(stay.totalProcedures)",
        fraction: procedureFraction
      )
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .background(CommanderDashboardPalette.glassStrong)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(CommanderDashboardPalette.glassBorder, lineWidth: 1)
    }
  }

  private var primaryTitle: String {
    guard let period = stay.period else { return "Termín není v rozpisu" }
    if let currentDay = period.currentDay {
      return "\(currentDay). den z \(period.totalDays)"
    }
    switch period.phase {
    case .upcoming:
      return "\(period.totalDays) dnů pobytu"
    case .finished:
      return "\(period.totalDays) dnů podle rozpisu"
    case .active:
      return "\(period.totalDays) dnů pobytu"
    }
  }

  private var primarySubtitle: String {
    guard let period = stay.period else { return "Zobrazují se jen dostupné údaje." }
    return "\(CommanderDateText.numericDate(period.dateFrom)) – \(CommanderDateText.numericDate(period.dateTo))"
  }

  private var stayProgressValue: String {
    guard let period = stay.period else { return "není k dispozici" }
    if let current = period.currentDay {
      return "\(current) / \(period.totalDays)"
    }
    return period.phase == .finished ? "\(period.totalDays) / \(period.totalDays)" : "0 / \(period.totalDays)"
  }

  private var stayProgressFraction: Double {
    guard let period = stay.period, period.totalDays > 0 else { return 0 }
    if let current = period.currentDay {
      return Double(current) / Double(period.totalDays)
    }
    return period.phase == .finished ? 1 : 0
  }

  private var procedureFraction: Double {
    guard stay.totalProcedures > 0 else { return 0 }
    return Double(stay.completedProcedures) / Double(stay.totalProcedures)
  }

  private func progressLine(title: String, value: String, fraction: Double) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.72))
        Spacer(minLength: 8)
        Text(value)
          .font(.subheadline.weight(.bold).monospacedDigit())
          .foregroundStyle(.white)
      }
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.14))
          Capsule()
            .fill(CommanderDashboardPalette.waterBlue)
            .frame(width: max(8, proxy.size.width * min(max(fraction, 0), 1)))
        }
      }
      .frame(height: 9)
    }
  }
}

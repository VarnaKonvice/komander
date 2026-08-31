import LazenskyCommanderCore
import SwiftUI

struct CommanderDaySummaryView: View {
  let summary: CommanderDaySummary

  private let columns = [GridItem(.adaptive(minimum: 132), alignment: .leading)]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CommanderSectionTitle(title: "Souhrn dne", systemImage: "calendar")
      if let context = summary.dinnerContext, let minutes = summary.minutesUntilDinner {
        VStack(alignment: .leading, spacing: 4) {
          Text(context == .proceduresEnded ? "Procedury jsou pro dnešek ukončené" : "Dnes bez procedur")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CommanderDashboardPalette.commanderPurpleLight)
          Text("Do večeře \(duration(minutes))")
            .font(.subheadline.monospacedDigit())
        }
      }
      LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
        metric("Procedury", value: String(summary.procedureCount))
        if let first = summary.firstEventStartAt {
          metric("První událost", value: first.formatted(CommanderScheduleDateStyle.clock))
        }
        if let start = summary.lastEventStartAt, let end = summary.lastEventEndAt {
          metric("Poslední událost", value: "\(start.formatted(CommanderScheduleDateStyle.clock)) – \(end.formatted(CommanderScheduleDateStyle.clock))")
        }
        if let end = summary.lastProcedureEndAt {
          metric("Konec procedur", value: end.formatted(CommanderScheduleDateStyle.clock))
        }
        if let dinner = summary.dinnerStartAt {
          metric("Večeře", value: dinner.formatted(CommanderScheduleDateStyle.clock))
        }
        if let interval = summary.freeBeforeDinner, let minutes = summary.freeBeforeDinnerMinutes {
          VStack(alignment: .leading, spacing: 3) {
            metric("Volno před večeří", value: duration(minutes))
            Text("\(interval.start.formatted(CommanderScheduleDateStyle.clock)) – \(interval.end.formatted(CommanderScheduleDateStyle.clock))")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }

  private func duration(_ minutes: Int) -> String {
    Duration.seconds(minutes * 60).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated).locale(Locale(identifier: "cs_CZ"))
    )
  }
}

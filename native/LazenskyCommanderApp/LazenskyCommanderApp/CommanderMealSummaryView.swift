import LazenskyCommanderCore
import SwiftUI

struct CommanderMealSummaryView: View {
  let meals: [CommanderDashboardEvent]

  private let columns = [GridItem(.adaptive(minimum: 132), spacing: 8)]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CommanderSectionTitle(title: "Jídlo", systemImage: "fork.knife")
      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(meals, id: \.event.stableId) { item in
          HStack(spacing: 9) {
            CommanderEventIconView(event: item.event, size: 36)
            VStack(alignment: .leading, spacing: 2) {
              Text(item.event.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
              Text(item.startAt, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
          .background(CommanderDashboardPalette.surface.opacity(item.phase == .past ? 0.45 : 0.82))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .opacity(item.phase == .past ? 0.64 : 1)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}

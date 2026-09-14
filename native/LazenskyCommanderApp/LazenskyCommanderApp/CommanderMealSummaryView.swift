import LazenskyCommanderCore
import SwiftUI

struct CommanderMealSummaryView: View {
  let meals: [CommanderDashboardEvent]

  private let columns = [GridItem(.adaptive(minimum: 154), spacing: 10)]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CommanderSectionTitle(title: "Jídlo", systemImage: "fork.knife")
      LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
        ForEach(meals, id: \.event.stableId) { item in
          HStack(alignment: .top, spacing: 10) {
            CommanderEventIconView(event: item.event, size: 42)
            VStack(alignment: .leading, spacing: 5) {
              Text(item.startAt, format: .dateTime.hour().minute())
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(CommanderDashboardPalette.mealGreen)
              Text(item.event.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
              if !item.event.location.isEmpty {
                Text(item.event.location)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.white.opacity(0.74))
                  .lineLimit(2)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
          .background(CommanderDashboardPalette.glass.opacity(item.phase == .past ? 0.56 : 1))
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(CommanderDashboardPalette.mealGreen.opacity(item.phase == .past ? 0.22 : 0.42), lineWidth: 1)
          }
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .opacity(item.phase == .past ? 0.64 : 1)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}

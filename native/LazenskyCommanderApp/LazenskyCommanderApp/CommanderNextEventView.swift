import LazenskyCommanderCore
import SwiftUI

struct CommanderNextEventView: View {
  let item: CommanderDashboardEvent
  let now: Date

  private var detail: String {
    let target = item.leaveAt > now ? item.leaveAt : item.startAt
    let prefix = item.leaveAt > now ? "Odchod za" : "Začátek za"
    let minutes = max(0, Int(ceil(target.timeIntervalSince(now) / 60)))
    return "\(prefix) \(minutes) min"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CommanderSectionTitle(title: "Co následuje", systemImage: "arrow.right.circle")
      HStack(alignment: .center, spacing: 12) {
        CommanderEventIconView(event: item.event, size: 48)
        VStack(alignment: .leading, spacing: 3) {
          Text(item.event.title)
            .font(.headline)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
          if !item.event.location.isEmpty {
            Text(item.event.location)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.68))
          }
          Text(detail)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CommanderDashboardPalette.waterBlue)
        }
        Spacer(minLength: 8)
        Text(item.startAt, format: .dateTime.hour().minute())
          .font(.title3.bold().monospacedDigit())
          .foregroundStyle(.white)
      }
      .padding(14)
      .background(CommanderDashboardPalette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .accessibilityElement(children: .combine)
  }
}

import LazenskyCommanderCore
import SwiftUI

struct CommanderNextEventView: View {
  let item: CommanderDashboardEvent
  let now: Date
  var title = "Co následuje"

  private var detail: String {
    let target = item.leaveAt > now ? item.leaveAt : item.startAt
    let prefix = item.leaveAt > now ? "Odchod za" : "Začátek za"
    let minutes = max(0, Int(ceil(target.timeIntervalSince(now) / 60)))
    return "\(prefix) \(minutes) min"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CommanderSectionTitle(title: title, systemImage: "arrow.right.circle")
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          CommanderEventIconView(event: item.event, size: 54)
          VStack(alignment: .leading, spacing: 6) {
            Text(detail)
              .font(.title2.weight(.heavy).monospacedDigit())
              .foregroundStyle(accent)
              .fixedSize(horizontal: false, vertical: true)
            Text(item.event.title)
              .font(.headline.weight(.bold))
              .foregroundStyle(.white)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          Text(item.startAt, format: .dateTime.hour().minute())
            .font(.title3.bold().monospacedDigit())
            .foregroundStyle(.white)
        }
        if !item.event.location.isEmpty {
          Label(item.event.location, systemImage: "mappin.and.ellipse")
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
      }
      .padding(16)
      .background(CommanderDashboardPalette.glass)
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(accent.opacity(0.45), lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .accessibilityElement(children: .combine)
  }

  private var accent: Color {
    CommanderDashboardPalette.eventAccent(for: item.event)
  }
}

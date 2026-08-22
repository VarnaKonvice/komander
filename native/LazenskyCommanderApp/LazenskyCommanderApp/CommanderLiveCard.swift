import Foundation
import LazenskyCommanderCore
import SwiftUI

struct CommanderLiveCard: View {
  let schedule: Schedule?
  let now: Date

  private var liveState: CommanderLiveStateResult {
    CommanderLiveStateCalculator.compute(schedule: schedule, now: now)
  }

  private var icon: CommanderIconMap.Icon? {
    liveState.event.flatMap(CommanderVisualAssets.icon(for:))
  }

  private var commanderPurple: Color {
    Color(hex: CommanderVisualAssets.colors?.brand.commanderPurple ?? "#6E56CF")
  }

  private var procedureAccent: Color {
    Color(hex: CommanderVisualAssets.accent(for: icon))
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if liveState.event != nil, let image = CommanderVisualAssets.image(for: icon?.key) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(width: 54, height: 54)
          .background(Color.white.opacity(0.94))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(procedureAccent, lineWidth: 2)
          }
          .accessibilityHidden(true)
      }

      content

      Spacer(minLength: 4)

      countdown
    }
    .padding(14)
    .foregroundStyle(.white)
    .background(commanderPurple)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(procedureAccent)
        .frame(width: 4)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var content: some View {
    switch liveState.state {
    case .upcoming:
      eventContent(status: "NADCHÁZÍ", secondaryTimeLabel: "Začátek")
    case .leaveNow:
      eventContent(status: "VYRAZIT", secondaryTimeLabel: "Začátek")
    case .inProgress:
      eventContent(status: "Právě probíhá", secondaryTimeLabel: "Konec")
    case .dayDone:
      VStack(alignment: .leading, spacing: 4) {
        Text("PROGRAM DOKONČEN")
          .font(.caption.bold())
        Text("Dnešní program je dokončený.")
          .font(.headline)
      }
    case .noSchedule:
      VStack(alignment: .leading, spacing: 4) {
        Text("LÁZEŇSKÝ COMMANDER")
          .font(.caption.bold())
        Text("Žádný dnešní program")
          .font(.headline)
      }
    }
  }

  private func eventContent(status: String, secondaryTimeLabel: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(status)
        .font(liveState.state == .leaveNow ? .headline.bold() : .caption.bold())
        .foregroundStyle(liveState.state == .leaveNow ? procedureAccent : .white.opacity(0.86))
      Text(liveState.event?.title ?? "Lázeňský Commander")
        .font(.headline)
        .lineLimit(2)
      if let location = liveState.event?.location, !location.isEmpty {
        Text(location)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
      }
      if let date = liveState.state == .inProgress ? liveState.endAt : liveState.startAt {
        HStack(spacing: 4) {
          Text(secondaryTimeLabel)
          Text(date, style: .time)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.78))
      }
    }
  }

  @ViewBuilder
  private var countdown: some View {
    switch liveState.state {
    case .upcoming:
      timer(label: "Odchod za", target: liveState.leaveAt)
    case .leaveNow:
      timer(label: "Začátek za", target: liveState.startAt)
    case .inProgress:
      timer(label: "Do konce", target: liveState.endAt)
    case .dayDone, .noSchedule:
      EmptyView()
    }
  }

  private func timer(label: String, target: Date?) -> some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.78))
      if let target {
        Text(target, style: .timer)
          .font(.title3.bold().monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
  }
}

private extension Color {
  init(hex: String) {
    let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255,
      green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255
    )
  }
}

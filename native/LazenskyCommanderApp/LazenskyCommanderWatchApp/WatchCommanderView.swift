import LazenskyCommanderCore
import SwiftUI

struct WatchCommanderView: View {
  let model: WatchCommanderModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let liveState = CommanderLiveStateCalculator.compute(
        schedule: WatchScheduleExpiryPolicy.activeSchedule(model.schedule, at: context.date),
        now: context.date,
        overrides: model.leadTimeOverrides
      )
      WatchCommanderStateView(liveState: liveState, now: context.date)
    }
  }
}

private struct WatchCommanderStateView: View {
  let liveState: CommanderLiveStateResult
  let now: Date

  private var icon: CommanderIconMap.Icon? {
    WatchVisualAssets.icon(for: liveState.event)
  }

  private var commanderPurple: Color {
    Color(hex: WatchVisualAssets.colors?.brand.commanderPurple ?? "#6E56CF")
  }

  private var eventAccent: Color {
    Color(hex: WatchVisualAssets.accent(for: liveState.event))
  }

  private var stateAccent: Color {
    switch liveState.state {
    case .upcoming:
      if let leaveAt = liveState.leaveAt, leaveAt.timeIntervalSince(now) <= 30 * 60 {
        return Color(hex: "#F2A93B")
      }
      return eventAccent
    case .leaveNow:
      return Color(hex: "#FF5A52")
    case .inProgress:
      return Color(hex: "#50B863")
    case .dayDone, .noSchedule:
      return Color.white.opacity(0.72)
    }
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color(hex: "#0E1530"), commanderPurple.opacity(0.40)],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()
      ScrollView {
        VStack(spacing: 8) {
          stateHeader
          if let event = liveState.event {
            eventContent(event)
          } else {
            emptyContent
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
    }
    .foregroundStyle(.white)
  }

  @ViewBuilder
  private var stateHeader: some View {
    switch liveState.state {
    case .upcoming:
      if let leaveAt = liveState.leaveAt, leaveAt.timeIntervalSince(now) <= 30 * 60 {
        status("ODCHOD ZA", prominent: false)
      } else {
        status("NÁSLEDUJE", prominent: false)
      }
    case .leaveNow:
      status("VYRAZIT TEĎ", prominent: true)
    case .inProgress:
      status(liveState.event?.kind == .meal ? "Právě jídlo" : "Právě probíhá", prominent: false)
    case .dayDone:
      status("PROGRAM DOKONČEN", prominent: false)
    case .noSchedule:
      status("LÁZEŇSKÝ COMMANDER", prominent: false)
    }
  }

  private func status(_ text: String, prominent: Bool) -> some View {
    VStack(spacing: 5) {
      Capsule()
        .fill(stateAccent)
        .frame(width: 44, height: 3)
      Text(text)
        .font(prominent ? .headline.bold() : .caption.bold())
        .multilineTextAlignment(.center)
        .foregroundStyle(prominent ? stateAccent : .white.opacity(0.88))
    }
  }

  private func eventContent(_ event: ScheduleEvent) -> some View {
    VStack(spacing: 6) {
      Image(systemName: CommanderBrandAssets.procedureSymbol(
        iconKey: icon?.key,
        title: event.title,
        isMeal: event.kind == .meal
      ))
      .font(.system(size: 31, weight: .semibold))
      .foregroundStyle(eventAccent)
      .frame(width: 54, height: 54)
      .background(eventAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12).stroke(eventAccent.opacity(0.72), lineWidth: 1.5)
      }
      .accessibilityHidden(true)

      Text(event.title)
        .font(.headline)
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.72)

      if !event.location.isEmpty {
        Text(event.location)
          .font(.caption)
          .foregroundStyle(.white.opacity(0.8))
          .multilineTextAlignment(.center)
          .lineLimit(2)
      }

      eventTiming
    }
  }

  @ViewBuilder
  private var eventTiming: some View {
    switch liveState.state {
    case .upcoming:
      if let leaveAt = liveState.leaveAt, leaveAt.timeIntervalSince(now) <= 30 * 60 {
        countdown(label: "Odchod za", target: leaveAt, secondaryLabel: "Začátek", secondaryDate: liveState.startAt)
      } else {
        countdown(label: "Následuje za", target: liveState.startAt, secondaryLabel: "Začátek", secondaryDate: liveState.startAt)
      }
    case .leaveNow:
      countdown(label: "VYRAZIT TEĎ", target: liveState.startAt, secondaryLabel: "Začátek", secondaryDate: liveState.startAt)
    case .inProgress:
      countdown(label: "Do konce", target: liveState.endAt, secondaryLabel: "Konec", secondaryDate: liveState.endAt)
    case .dayDone, .noSchedule:
      EmptyView()
    }
  }

  private func countdown(label: String, target: Date?, secondaryLabel: String, secondaryDate: Date?) -> some View {
    VStack(spacing: 2) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.76))
      if let target {
        Text(target, style: .timer)
          .font(.title3.bold().monospacedDigit())
          .foregroundStyle(stateAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      if let secondaryDate {
        HStack(spacing: 3) {
          Text(secondaryLabel)
          Text(secondaryDate, style: .time)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.72))
      }
    }
  }

  @ViewBuilder
  private var emptyContent: some View {
    switch liveState.state {
    case .dayDone:
      Text("Dnešní program je dokončený.")
        .font(.headline)
        .multilineTextAlignment(.center)
    case .noSchedule:
      Text("Žádný dostupný program")
        .font(.headline)
        .multilineTextAlignment(.center)
    case .upcoming, .leaveNow, .inProgress:
      EmptyView()
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

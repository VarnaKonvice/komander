import LazenskyCommanderCore
import SwiftUI

struct WatchCommanderView: View {
  let model: WatchCommanderModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let liveState = CommanderLiveStateCalculator.compute(
        schedule: model.schedule,
        now: context.date,
        overrides: model.leadTimeOverrides
      )
      WatchCommanderStateView(liveState: liveState, model: model)
    }
  }
}

private struct WatchCommanderStateView: View {
  let liveState: CommanderLiveStateResult
  let model: WatchCommanderModel

  private var icon: CommanderIconMap.Icon? {
    WatchVisualAssets.icon(for: liveState.event)
  }

  private var commanderPurple: Color {
    Color(hex: WatchVisualAssets.colors?.brand.commanderPurple ?? "#6E56CF")
  }

  private var accent: Color {
    Color(hex: WatchVisualAssets.accent(for: liveState.event))
  }

  var body: some View {
    ZStack {
      commanderPurple.ignoresSafeArea()
      ScrollView {
        VStack(spacing: 8) {
          stateHeader
          if let event = liveState.event {
            eventContent(event)
          } else {
            emptyContent
          }
          standaloneAlarmControls
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
    }
    .foregroundStyle(.white)
  }

  private var standaloneAlarmControls: some View {
    VStack(spacing: 5) {
      Divider().overlay(.white.opacity(0.28))
      Toggle(
        "Samostatné alarmy Watch",
        isOn: Binding(
          get: { model.standaloneAlarmsEnabled },
          set: { enabled in
            Task { await model.setStandaloneAlarmsEnabled(enabled) }
          }
        )
      )
      .font(.caption2)
      .disabled(model.isUpdatingStandaloneAlarms)

      Text(standaloneAlarmStatus)
        .font(.caption2)
        .foregroundStyle(standaloneAlarmStatusColor)
        .multilineTextAlignment(.center)
    }
    .padding(.top, 4)
  }

  private var standaloneAlarmStatus: String {
    if let error = model.notificationError { return error }
    guard model.standaloneAlarmsEnabled else { return "Samostatné alarmy vypnuty" }
    switch model.notificationAuthorization {
    case .authorized:
      return "Samostatné alarmy zapnuty"
    case .denied:
      return "Notifikace nejsou povoleny"
    case .notDetermined:
      return "Čeká na povolení notifikací"
    }
  }

  private var standaloneAlarmStatusColor: Color {
    model.standaloneAlarmState.isOperational ? .white.opacity(0.78) : .yellow
  }

  @ViewBuilder
  private var stateHeader: some View {
    switch liveState.state {
    case .upcoming:
      status("NADCHÁZÍ", prominent: false)
    case .leaveNow:
      status("VYRAZIT", prominent: true)
    case .inProgress:
      status("Právě probíhá", prominent: false)
    case .dayDone:
      status("PROGRAM DOKONČEN", prominent: false)
    case .noSchedule:
      status("LÁZEŇSKÝ COMMANDER", prominent: false)
    }
  }

  private func status(_ text: String, prominent: Bool) -> some View {
    VStack(spacing: 5) {
      Capsule()
        .fill(accent)
        .frame(width: 44, height: 3)
      Text(text)
        .font(prominent ? .headline.bold() : .caption.bold())
        .multilineTextAlignment(.center)
        .foregroundStyle(prominent ? accent : .white.opacity(0.88))
    }
  }

  private func eventContent(_ event: ScheduleEvent) -> some View {
    VStack(spacing: 6) {
      if let icon {
        Image(icon.key, bundle: .main)
          .resizable()
          .scaledToFit()
          .frame(width: 54, height: 54)
          .background(.white)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: 2)
          }
          .accessibilityHidden(true)
      }

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
      countdown(label: "Odchod za", target: liveState.leaveAt, secondaryLabel: "Začátek", secondaryDate: liveState.startAt)
    case .leaveNow:
      countdown(label: "Začátek za", target: liveState.startAt, secondaryLabel: "Začátek", secondaryDate: liveState.startAt)
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

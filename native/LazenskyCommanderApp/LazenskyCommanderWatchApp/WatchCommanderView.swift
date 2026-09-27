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
      WatchCommanderStateView(liveState: liveState, model: model)
    }
  }
}

private struct WatchCommanderStateView: View {
  let liveState: CommanderLiveStateResult
  let model: WatchCommanderModel

  private var icon: CommanderIconMap.Icon? { WatchVisualAssets.icon(for: liveState.event) }
  private var eventAccent: Color { Color(commanderPresentationHex: WatchVisualAssets.accent(for: liveState.event)) }

  private var stateAccent: Color {
    switch liveState.state {
    case .upcoming, .leaveNow, .inProgress:
      return liveState.event == nil ? CommanderBrandAssets.Presentation.neutral : eventAccent
    case .dayDone, .noSchedule:
      return CommanderBrandAssets.Presentation.neutral
    }
  }

  private var status: String {
    switch liveState.state {
    case .upcoming: "Odchod za"
    case .leaveNow: "Vyrazit teď"
    case .inProgress: liveState.event?.kind == .meal ? "Právě jídlo" : "Právě probíhá"
    case .dayDone: "Skončilo"
    case .noSchedule: "Žádný program"
    }
  }

  private var deadline: Date? {
    switch liveState.state {
    case .upcoming: liveState.leaveAt
    case .leaveNow: liveState.startAt
    case .inProgress: liveState.endAt
    case .dayDone, .noSchedule: nil
    }
  }

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 4) {
        HStack {
          if let event = liveState.event {
            CommanderProcedureArtwork(
              iconKey: icon?.key,
              title: event.title,
              size: 40,
              kind: event.kind
            )
          }
          Spacer(minLength: 12)
          if let event = liveState.event {
            Text(event.title)
              .font(.system(size: 13, weight: .bold))
              .foregroundStyle(eventAccent)
              .lineLimit(2)
              .minimumScaleFactor(0.78)
              .multilineTextAlignment(.trailing)
          }
        }
        Text(status)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(stateAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
        Group {
          if let deadline {
            Text(deadline, style: .timer)
          } else {
            Text(liveState.state == .dayDone ? "Hotovo" : "—")
          }
        }
        .font(.system(size: geometry.size.width < 170 ? 46 : 56, weight: .heavy, design: .rounded).monospacedDigit())
        .foregroundStyle(stateAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: .infinity)
        .layoutPriority(2)

        if let event = liveState.event {
          Text(event.title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(eventAccent)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(event.title)
          if !event.location.isEmpty {
            Label(event.location, systemImage: "mappin.circle.fill")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(Color(commanderPresentationHex: CommanderBrandAssets.Colors.locationBlue))
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity)
              .background(stateAccent.opacity(0.17), in: Capsule())
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6)
      .padding(.top, 2)
      .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
    }
    .background(.black)
    .accessibilityElement(children: .contain)
  }
}

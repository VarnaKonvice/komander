import LazenskyCommanderCore
import SwiftUI

struct WatchCommanderView: View {
  let model: WatchCommanderModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let liveState = CommanderLiveStateCalculator.compute(
        schedule: WatchScheduleExpiryPolicy.activeSchedule(model.schedule, at: context.date),
        now: context.date, overrides: model.leadTimeOverrides
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

  private var timing: CommanderCountdownPresentation { .init(liveState: liveState) }
  private var status: String { timing.status }
  private var countdownLabel: String? {
    liveState.state == .leaveNow || liveState.state == .inProgress ? timing.countdownLabel : nil
  }
  private var referenceLabel: String? { timing.referenceLabel }
  private var referenceDate: Date? { timing.referenceDate }
  private var countdownText: String? { timing.countdownText(at: liveState.now) }

  var body: some View {
    ScrollView(.vertical) {
      VStack(spacing: 5) {
        ZStack {
          HStack {
            CommanderBrandAssets.circularMark
              .resizable()
              .scaledToFit()
              .frame(width: 30, height: 30)
              .accessibilityLabel("Lázeňský Commander")
            Spacer(minLength: 0)
          }

          VStack(spacing: 1) {
            Image(systemName: timing.symbol)
              .font(.system(size: 20, weight: .semibold))
              .foregroundStyle(stateAccent)

            Text(status)
              .font(.system(size: 10.5, weight: .bold))
              .foregroundStyle(stateAccent)
              .lineLimit(1)
              .minimumScaleFactor(0.82)
          }
          .frame(maxWidth: 88)
        }
        .frame(height: 34)

        if let countdownLabel {
          Text(countdownLabel)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(CommanderBrandAssets.Presentation.neutral)
        }

        Text(countdownText ?? (liveState.state == .dayDone ? "Hotovo" : "—"))
          .font(.system(size: 50, weight: .heavy, design: .rounded).monospacedDigit())
          .foregroundStyle(stateAccent)
          .lineLimit(1)
          .minimumScaleFactor(0.60)
          .frame(maxWidth: .infinity)
          .multilineTextAlignment(.center)
          .accessibilityLabel(countdownText ?? status)

        if let referenceLabel, let referenceDate {
          HStack(spacing: 4) {
            Image(systemName: "clock.fill")
              .font(.system(size: 10, weight: .semibold))
            Text(referenceLabel)
              .font(.system(size: 10.5, weight: .medium))
            Text(referenceDate.formatted(date: .omitted, time: .shortened))
              .font(.system(size: 11.5, weight: .bold).monospacedDigit())
          }
          .foregroundStyle(stateAccent)
        }

        if let event = liveState.event {
          Divider()
            .overlay(stateAccent.opacity(0.45))

          HStack(alignment: .center, spacing: 7) {
            CommanderProcedureArtwork(
              iconKey: icon?.key,
              title: event.title,
              size: 32,
              kind: event.kind
            )

            Text(event.title)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(eventAccent)
              .lineLimit(2)
              .minimumScaleFactor(0.86)
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel(event.title)
          }

          if !event.location.isEmpty {
            Label(event.location, systemImage: "mappin.circle.fill")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Color(commanderPresentationHex: CommanderBrandAssets.Colors.locationBlue))
              .lineLimit(1)
              .minimumScaleFactor(0.82)
              .padding(.horizontal, 8)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(stateAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
          }
        }

        if let error = model.cacheError ?? model.transportError ?? model.notificationError {
          Text(error)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
    }
    .defaultScrollAnchor(.top)
    .contentMargins(.top, 0, for: .scrollContent)
    .scrollIndicators(.hidden)
    .background(.black)
    .accessibilityElement(children: .contain)
  }
}

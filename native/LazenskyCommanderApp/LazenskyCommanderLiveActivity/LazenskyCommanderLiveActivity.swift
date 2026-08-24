import ActivityKit
import AlarmKit
import SwiftUI
import UIKit
import WidgetKit

@main
struct LazenskyCommanderLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LazenskyCommanderAlarmLiveActivity()
  }
}

struct LazenskyCommanderAlarmLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self) { context in
      CommanderAlarmLockScreenView(context: context)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 42)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.metadata?.title ?? "Lázeňský Commander")
              .font(.headline)
              .lineLimit(1)
            if let location = context.attributes.metadata?.location, !location.isEmpty {
              Text(location)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: true)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Label("Začátek", systemImage: "clock")
              .foregroundStyle(.secondary)
            Spacer()
            Text(CommanderAlarmTime.startTime(from: context.attributes.metadata?.startAt))
              .fontWeight(.semibold)
          }
          .font(.subheadline)
        }
      } compactLeading: {
        CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 22)
      } compactTrailing: {
        CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: false)
      } minimal: {
        CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 20)
      }
      .keylineTint(.teal)
    }
  }
}

private struct CommanderAlarmLockScreenView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  var body: some View {
    HStack(spacing: 14) {
      CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 52)

      VStack(alignment: .leading, spacing: 3) {
        Text(context.attributes.metadata?.title ?? "Lázeňský Commander")
          .font(.headline)
          .lineLimit(2)
        if let location = context.attributes.metadata?.location, !location.isEmpty {
          Text(location)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Text("Začátek \(CommanderAlarmTime.startTime(from: context.attributes.metadata?.startAt))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: true)
        .multilineTextAlignment(.trailing)
    }
    .padding()
  }
}

private struct CommanderAlarmCountdownContext: View {
  let mode: AlarmPresentationState.Mode
  let showsLabel: Bool

  var body: some View {
    VStack(alignment: .trailing, spacing: 1) {
      if showsLabel {
        Text(label)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      CommanderAlarmCountdown(mode: mode)
        .font(showsLabel ? .headline.monospacedDigit() : .caption2.monospacedDigit())
        .foregroundStyle(.teal)
        .lineLimit(1)
    }
  }

  private var label: String {
    switch mode {
    case .alert:
      "Čas vyrazit"
    case .countdown, .paused:
      "Vyrazit za"
    @unknown default:
      "Vyrazit za"
    }
  }
}

private struct CommanderAlarmCountdown: View {
  let mode: AlarmPresentationState.Mode

  @ViewBuilder
  var body: some View {
    switch mode {
    case .countdown(let countdown):
      Text(countdown.fireDate, style: .timer)
    case .paused(let paused):
      Text(CommanderAlarmTime.duration(paused.totalCountdownDuration - paused.previouslyElapsedDuration))
    case .alert:
      Text("Teď")
    @unknown default:
      Text("--:--")
    }
  }
}

private struct CommanderAlarmIcon: View {
  let iconKey: String?
  let size: CGFloat

  var body: some View {
    Group {
      if let image = Self.image(for: iconKey) {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      } else {
        Color.clear
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private static func image(for iconKey: String?) -> UIImage? {
    guard let requestedKey = iconKey.flatMap({ $0.isEmpty ? nil : $0 }) else { return nil }
    return load(requestedKey)
  }

  private static func load(_ key: String) -> UIImage? {
    guard let url = Bundle.main.url(forResource: key, withExtension: "png") else { return nil }
    return UIImage(contentsOfFile: url.path)
  }
}

private enum CommanderAlarmTime {
  static func startTime(from localISO: String?) -> String {
    guard let localISO, localISO.count >= 16 else { return "--:--" }
    let start = localISO.index(localISO.startIndex, offsetBy: 11)
    let end = localISO.index(start, offsetBy: 5)
    return String(localISO[start..<end])
  }

  static func duration(_ seconds: TimeInterval) -> String {
    let remaining = max(0, Int(seconds.rounded(.up)))
    return String(format: "%02d:%02d", remaining / 60, remaining % 60)
  }
}

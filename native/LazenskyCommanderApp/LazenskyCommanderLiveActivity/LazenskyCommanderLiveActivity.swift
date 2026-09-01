import ActivityKit
import AlarmKit
import SwiftUI
import UIKit
import WidgetKit

private enum CommanderActivityPalette {
  static let background = Color(red: 0.05, green: 0.09, blue: 0.22)
  static let backgroundLift = Color(red: 0.08, green: 0.17, blue: 0.34)
  static let departure = Color(red: 1.0, green: 0.79, blue: 0.28)
  static let location = Color(red: 0.44, green: 0.84, blue: 1.0)
  static let success = Color(red: 0.32, green: 0.88, blue: 0.42)

  static var gradient: LinearGradient {
    LinearGradient(
      colors: [backgroundLift, background],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
}

@main
struct LazenskyCommanderLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LazenskyCommanderAlarmLiveActivity()
    LazenskyCommanderProcedureLiveActivity()
  }
}

struct LazenskyCommanderAlarmLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<CommanderAlarmMetadata>.self) { context in
      CommanderAlarmLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityPalette.background)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 44)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 3) {
            Text(context.attributes.metadata?.title ?? "Lázeňský Commander")
              .font(.headline.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(1)
            if let location = context.attributes.metadata?.location, !location.isEmpty {
              Label(location, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CommanderActivityPalette.location)
                .lineLimit(1)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: true, size: .regular)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Label("Začátek", systemImage: "clock")
              .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(CommanderAlarmTime.startTime(from: context.attributes.metadata?.startAt))
              .fontWeight(.semibold)
              .foregroundStyle(.white)
          }
          .font(.subheadline)
        }
      } compactLeading: {
        CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 22)
      } compactTrailing: {
        CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: false, size: .compact)
      } minimal: {
        CommanderAlarmIcon(iconKey: context.attributes.metadata?.iconKey, size: 20)
      }
      .keylineTint(CommanderActivityPalette.location)
    }
  }
}

struct LazenskyCommanderProcedureLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CommanderProcedureLiveActivityAttributes.self) { context in
      CommanderProcedureLockScreenView(context: context)
        .activityBackgroundTint(CommanderActivityPalette.background)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          CommanderAlarmIcon(iconKey: context.attributes.iconKey, size: 44)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(alignment: .leading, spacing: 3) {
            Text(context.isStale ? "Dokončeno" : "Právě probíhá")
              .font(.caption.weight(.semibold))
              .foregroundStyle(context.isStale ? Color.white.opacity(0.6) : CommanderActivityPalette.success)
            Text(context.attributes.title)
              .font(.headline.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(1)
            if !context.attributes.location.isEmpty {
              Label(context.attributes.location, systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CommanderActivityPalette.location)
                .lineLimit(1)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CommanderProcedureTiming(
            endAt: context.attributes.endAt,
            isStale: context.isStale,
            compact: false
          )
        }
        DynamicIslandExpandedRegion(.bottom) {
          if context.isStale {
            Label("Procedura skončila", systemImage: "checkmark.circle.fill")
              .font(.subheadline)
              .foregroundStyle(CommanderActivityPalette.success)
          } else {
            HStack {
              Label("Konec", systemImage: "clock")
                .foregroundStyle(.white.opacity(0.68))
              Spacer()
              Text(context.attributes.endAt, style: .time)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
            }
            .font(.subheadline)
          }
        }
      } compactLeading: {
        CommanderAlarmIcon(iconKey: context.attributes.iconKey, size: 22)
      } compactTrailing: {
        CommanderProcedureTiming(
          endAt: context.attributes.endAt,
          isStale: context.isStale,
          compact: true
        )
      } minimal: {
        Image(systemName: context.isStale ? "checkmark" : "waveform.path.ecg")
          .foregroundStyle(CommanderActivityPalette.success)
      }
      .keylineTint(CommanderActivityPalette.success)
    }
  }
}

private struct CommanderProcedureLockScreenView: View {
  let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      CommanderActivityBrandHeader(iconKey: context.attributes.iconKey)

      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 7) {
          Text(context.isStale ? "Dokončeno" : "Právě probíhá")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(context.isStale ? Color.white.opacity(0.62) : CommanderActivityPalette.success)
          Text(context.attributes.title)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(2)
          if !context.attributes.location.isEmpty {
            CommanderActivityLocationPill(location: context.attributes.location)
          }
          Text("Konec \(context.attributes.endAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.68))
        }

        Spacer(minLength: 8)

        CommanderProcedureTiming(
          endAt: context.attributes.endAt,
          isStale: context.isStale,
          compact: false
        )
      }
    }
    .padding(18)
    .background(CommanderActivityPalette.gradient)
  }
}

private struct CommanderProcedureTiming: View {
  let endAt: Date
  let isStale: Bool
  let compact: Bool

  var body: some View {
    Group {
      if isStale {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(CommanderActivityPalette.success)
      } else {
        VStack(alignment: .trailing, spacing: 1) {
          if !compact {
            Text("Do konce")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.white.opacity(0.68))
          }
          Text(endAt, style: .timer)
            .font(compact ? .caption2.monospacedDigit() : .title2.weight(.heavy).monospacedDigit())
            .foregroundStyle(CommanderActivityPalette.success)
            .lineLimit(1)
        }
      }
    }
  }
}

private struct CommanderAlarmLockScreenView: View {
  let context: ActivityViewContext<AlarmAttributes<CommanderAlarmMetadata>>

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      CommanderActivityBrandHeader(iconKey: context.attributes.metadata?.iconKey)

      CommanderAlarmCountdownContext(mode: context.state.mode, showsLabel: true, size: .large)
        .multilineTextAlignment(.leading)

      VStack(alignment: .leading, spacing: 8) {
        Text(context.attributes.metadata?.title ?? "Lázeňský Commander")
          .font(.title3.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(2)
        if let location = context.attributes.metadata?.location, !location.isEmpty {
          CommanderActivityLocationPill(location: location)
        }
        Text("Začátek \(CommanderAlarmTime.startTime(from: context.attributes.metadata?.startAt))")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.72))
      }
    }
    .padding(18)
    .background(CommanderActivityPalette.gradient)
  }
}

private struct CommanderAlarmCountdownContext: View {
  let mode: AlarmPresentationState.Mode
  let showsLabel: Bool
  var size: CommanderAlarmCountdownSize = .regular

  var body: some View {
    VStack(alignment: size == .large ? .leading : .trailing, spacing: 2) {
      if showsLabel {
        Text(label)
          .font(size == .large ? .headline.weight(.bold) : .caption2.weight(.bold))
          .foregroundStyle(size == .large ? CommanderActivityPalette.departure : .white.opacity(0.7))
          .lineLimit(1)
      }
      CommanderAlarmCountdown(mode: mode)
        .font(countdownFont)
        .foregroundStyle(CommanderActivityPalette.departure)
        .lineLimit(1)
    }
  }

  private var countdownFont: Font {
    switch size {
    case .compact:
      .caption2.weight(.bold).monospacedDigit()
    case .regular:
      .headline.weight(.heavy).monospacedDigit()
    case .large:
      .system(size: 40, weight: .heavy, design: .rounded).monospacedDigit()
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

private enum CommanderAlarmCountdownSize {
  case compact, regular, large
}

private struct CommanderActivityBrandHeader: View {
  let iconKey: String?

  var body: some View {
    HStack(spacing: 10) {
      CommanderBrandAssets.circularMark
        .resizable()
        .scaledToFit()
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text("Lázeňský Commander")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
        Text("Buď připravený včas")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.white.opacity(0.66))
      }
      Spacer(minLength: 8)
      CommanderAlarmIcon(iconKey: iconKey, size: 30)
    }
  }
}

private struct CommanderActivityLocationPill: View {
  let location: String

  var body: some View {
    Label(location, systemImage: "mappin.and.ellipse")
      .font(.headline.weight(.bold))
      .foregroundStyle(.white)
      .lineLimit(2)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(CommanderActivityPalette.location.opacity(0.22))
      .clipShape(RoundedRectangle(cornerRadius: 8))
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

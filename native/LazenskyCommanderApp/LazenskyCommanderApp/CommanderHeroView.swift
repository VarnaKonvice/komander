import LazenskyCommanderCore
import SwiftUI

struct CommanderHeroView: View {
  let presentation: CommanderDashboardPresentation

  private var item: CommanderDashboardEvent? {
    presentation.currentEvent
  }

  private var statusColor: Color {
    switch presentation.mode {
    case .leaveNow: CommanderDashboardPalette.timeGold
    case .inProgress: CommanderDashboardPalette.inProgress
    case .dayDone, .noSchedule, .unsynchronized: CommanderDashboardPalette.neutral
    case .upcoming: CommanderDashboardPalette.commanderPurple
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      switch presentation.mode {
      case .upcoming:
        eventHeader(status: "CO TEĎ", statusColor: .white.opacity(0.72))
        if let startAt = item?.startAt {
          Text("Za \(minutes(until: startAt)) min")
            .font(.largeTitle.bold())
            .foregroundStyle(.white)
            .monospacedDigit()
        }
        eventTiming(primaryLabel: "Začátek", primaryDate: item?.startAt, secondaryLabel: "Vyrazit", secondaryDate: item?.leaveAt)
      case .leaveNow:
        eventHeader(status: "ČAS VYRAZIT", statusColor: CommanderDashboardPalette.timeGold)
        if let startAt = item?.startAt {
          VStack(alignment: .leading, spacing: 3) {
            Text("Začátek za")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white.opacity(0.72))
            Text(startAt, style: .timer)
              .font(.largeTitle.bold().monospacedDigit())
              .foregroundStyle(CommanderDashboardPalette.timeGold)
          }
        }
        eventTiming(primaryLabel: "Začátek", primaryDate: item?.startAt)
      case .inProgress:
        eventHeader(status: "PRÁVĚ PROBÍHÁ", statusColor: CommanderDashboardPalette.inProgress)
        if let endAt = item?.endAt {
          VStack(alignment: .leading, spacing: 3) {
            Text("Do konce")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white.opacity(0.72))
            Text(endAt, style: .timer)
              .font(.largeTitle.bold().monospacedDigit())
              .foregroundStyle(.white)
          }
        }
        eventTiming(primaryLabel: "Konec", primaryDate: item?.endAt)
      case .dayDone:
        restingState(
          title: "Dnešní program je dokončený.",
          color: CommanderDashboardPalette.inProgress
        )
      case .noSchedule:
        restingState(
          title: "Na dnešek není program.",
          color: CommanderDashboardPalette.commanderPurple
        )
      case .unsynchronized:
        restingState(
          title: "Rozpis ještě není načten.",
          color: CommanderDashboardPalette.commanderPurple
        )
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(CommanderDashboardPalette.elevatedSurface)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(statusColor)
        .frame(width: 4)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(statusColor.opacity(0.42), lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private func eventHeader(status: String, statusColor: Color) -> some View {
    if let event = item?.event {
      HStack(alignment: .center, spacing: 14) {
        CommanderEventIconView(event: event, size: 72)
        VStack(alignment: .leading, spacing: 5) {
          Text(status)
            .font(.subheadline.bold())
            .foregroundStyle(statusColor)
          Text(event.title)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
          if !event.location.isEmpty {
            Label(event.location, systemImage: "mappin.and.ellipse")
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.74))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private func eventTiming(
    primaryLabel: String,
    primaryDate: Date?,
    secondaryLabel: String? = nil,
    secondaryDate: Date? = nil
  ) -> some View {
    HStack(spacing: 18) {
      if let primaryDate {
        timeValue(label: primaryLabel, date: primaryDate)
      }
      if let secondaryLabel, let secondaryDate {
        timeValue(label: secondaryLabel, date: secondaryDate)
      }
    }
  }

  private func timeValue(label: String, date: Date) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.white.opacity(0.62))
      Text(date, format: .dateTime.hour().minute())
        .font(.headline.monospacedDigit())
        .foregroundStyle(.white)
    }
  }

  private func restingState(title: String, color: Color) -> some View {
    HStack(spacing: 14) {
      CommanderNeutralStateVisual(accent: color, size: 48)
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(.white)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func minutes(until date: Date) -> Int {
    max(0, Int(ceil(date.timeIntervalSince(presentation.now) / 60)))
  }
}

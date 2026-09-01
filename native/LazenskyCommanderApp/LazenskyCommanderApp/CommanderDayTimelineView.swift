import LazenskyCommanderCore
import SwiftUI

struct CommanderDayTimelineView: View {
  let items: [CommanderDashboardEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: CommanderDesignTokens.Spacing.small) {
      Text("Dnešní program")
        .commanderFont(.section)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .accessibilityAddTraits(.isHeader)
      LazyVStack(spacing: CommanderDesignTokens.Spacing.eventRows) {
        ForEach(items, id: \.event.stableId) { item in
          CommanderEventRow(item: item)
        }
      }
    }
  }
}

struct CommanderEventRow: View {
  let item: CommanderDashboardEvent

  private var accent: Color { CommanderEventAppearance.accent(for: item.event) }

  private var departureText: String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let time = item.leaveAt.formatted(CommanderScheduleDateStyle.clock)
    return calendar.isDate(item.startAt, inSameDayAs: item.leaveAt)
      ? time : "\(CommanderDateText.shortDay(item.leaveAt)) \(time)"
  }

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.startAt.formatted(CommanderScheduleDateStyle.clock))
        Text(item.endAt.formatted(CommanderScheduleDateStyle.clock))
      }
      .commanderFont(.time)
      .monospacedDigit()
      .foregroundStyle(accent)
      .fixedSize(horizontal: true, vertical: false)
      .frame(width: 55, alignment: .leading)
      CommanderSymbolBadge(
        symbol: CommanderEventAppearance.symbol(for: item.event), color: accent, size: 30
      )
      details.layoutPriority(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(
      accent: item.phase == .current ? accent : nil,
      surface: .eventRow
    )
    .accessibilityElement(children: .combine)
    .accessibilityValue(item.phase == .current ? "Právě probíhá" : "")
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(item.event.title)
        .commanderFont(.eventTitle)
        .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      if !item.event.location.isEmpty {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            location.fixedSize()
            Spacer(minLength: 0)
            departure.fixedSize()
          }
          VStack(alignment: .leading, spacing: 2) {
            location.fixedSize(horizontal: false, vertical: true)
            departure.fixedSize(horizontal: false, vertical: true)
          }
        }
      } else {
        departure
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var location: some View {
    Label(item.event.location, systemImage: "mappin.circle.fill")
      .commanderFont(.location)
      .foregroundStyle(accent)
  }

  private var departure: some View {
    Text("Odchod \(departureText)")
      .commanderFont(.departure)
      .monospacedDigit()
      .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
  }
}

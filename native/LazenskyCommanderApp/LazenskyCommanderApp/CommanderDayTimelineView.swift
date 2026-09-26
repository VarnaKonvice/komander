import LazenskyCommanderCore
import SwiftUI

struct CommanderDayTimelineView: View {
  let items: [CommanderDashboardEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Dnešní program")
          .commanderFont(.section)
          .foregroundStyle(.white)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 8)
        Text(eventCountText)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(CommanderDesignTokens.Colors.textSecondary)
      }
      LazyVStack(spacing: 5) {
        ForEach(items, id: \.event.stableId) { item in
          CommanderEventRow(item: item, compact: true)
        }
      }
    }
    .padding(10)
    .commanderCard(accent: CommanderDesignTokens.Colors.procedureCyan, surface: .depthCard)
  }

  private var eventCountText: String {
    switch items.count {
    case 1: "1 událost"
    case 2...4: "\(items.count) události"
    default: "\(items.count) událostí"
    }
  }
}

struct CommanderEventRow: View {
  let item: CommanderDashboardEvent
  var compact = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var accent: Color { CommanderEventAppearance.accent(for: item.event) }
  private var isPast: Bool { item.phase == .past }
  private var isCurrent: Bool { item.phase == .current }
  private var rowAccent: Color { accent }
  private var isSingleWordTitle: Bool {
    !item.event.title.contains { $0.isWhitespace }
  }
  private var timeRange: String {
    "\(item.startAt.formatted(CommanderScheduleDateStyle.clock))–\(item.endAt.formatted(CommanderScheduleDateStyle.clock))"
  }

  private var departureText: String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
    let time = item.leaveAt.formatted(CommanderScheduleDateStyle.clock)
    return calendar.isDate(item.startAt, inSameDayAs: item.leaveAt)
      ? time : "\(CommanderDateText.shortDay(item.leaveAt)) \(time)"
  }

  var body: some View {
    HStack(spacing: 10) {
      CommanderSymbolBadge(
        symbol: CommanderEventAppearance.symbol(for: item.event),
        color: rowAccent,
        size: CommanderDesignTokens.Size.primaryBadge
      )

      VStack(alignment: .leading, spacing: 3) {
        Text(timeRange)
          .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 18, weight: .bold))
          .monospacedDigit()
          .foregroundStyle(CommanderDesignTokens.Colors.textPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.9)

        Text(item.event.title)
          .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 24.5 : 20.5, weight: .bold))
          .foregroundStyle(rowAccent)
          .allowsTightening(true)
          .lineLimit(isSingleWordTitle ? 1 : nil)
          .minimumScaleFactor(isSingleWordTitle ? 0.90 : 1)
          .fixedSize(horizontal: false, vertical: true)

        if !item.event.location.isEmpty {
          Label(item.event.location, systemImage: "mappin.circle.fill")
            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 20 : 17, weight: .semibold))
            .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .layoutPriority(1)

      Divider()
        .overlay(CommanderDesignTokens.Colors.textSecondary.opacity(0.24))
        .padding(.vertical, 4)
        .accessibilityHidden(true)

      departure
    }
    .padding(.horizontal, 11)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .commanderCard(accent: accent, surface: .eventRow)
    .overlay {
      if isCurrent {
        RoundedRectangle(cornerRadius: CommanderDesignTokens.Radius.eventRow)
          .strokeBorder(
            LinearGradient(
              colors: [rowAccent.opacity(0.96), Color.white.opacity(0.72), rowAccent.opacity(0.82)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 1.6
          )
          .shadow(color: rowAccent.opacity(0.28), radius: 2.4)
          .allowsHitTesting(false)
      }
    }
    .overlay(alignment: .leading) {
      if isCurrent {
        Capsule()
          .fill(rowAccent)
          .frame(width: 4)
          .padding(.vertical, 11)
          .offset(x: 3)
          .shadow(color: rowAccent.opacity(0.38), radius: 2)
          .allowsHitTesting(false)
      }
    }
    .grayscale(isPast ? 0.55 : 0)
    .saturation(isPast ? 0.30 : 1)
    .opacity(isPast ? 0.72 : 1)
    .accessibilityElement(children: .combine)
    .accessibilityValue(isCurrent ? "Právě probíhá" : isPast ? "Dokončeno" : "")
  }

  private var departure: some View {
    HStack(spacing: 5) {
      Image(systemName: "figure.walk")
        .font(.system(size: 20, weight: .medium))
        .accessibilityHidden(true)
      VStack(alignment: .trailing, spacing: 2) {
        Text("Odchod").font(.system(size: 14, weight: .semibold))
        Text(departureText)
          .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 22 : 19, weight: .bold))
          .monospacedDigit()
      }
    }
    .foregroundStyle(CommanderDesignTokens.Colors.eventSupportingText)
    .fixedSize(horizontal: true, vertical: true)
  }
}

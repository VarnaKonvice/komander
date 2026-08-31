import LazenskyCommanderCore
import SwiftUI

struct CommanderDayTimelineView: View {
  let items: [CommanderDashboardEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      CommanderSectionTitle(title: "Program dne", systemImage: "list.bullet")
      LazyVStack(spacing: 8) {
        ForEach(items, id: \.event.stableId) { item in
          CommanderTimelineRow(item: item)
        }
      }
    }
  }
}

private struct CommanderTimelineRow: View {
  let item: CommanderDashboardEvent

  private var icon: CommanderIconMap.Icon? {
    CommanderVisualAssets.icon(for: item.event)
  }

  private var accent: Color {
    Color(commanderHex: CommanderVisualAssets.accent(for: icon))
  }

  private var rowOpacity: Double {
    item.phase == .past ? 0.52 : 1
  }

  var body: some View {
    HStack(alignment: .center, spacing: 11) {
      VStack(spacing: 2) {
        Text(item.startAt, format: .dateTime.hour().minute())
          .font(.subheadline.bold().monospacedDigit())
        Text(item.endAt, format: .dateTime.hour().minute())
          .font(.caption.monospacedDigit())
          .foregroundStyle(.white.opacity(0.56))
      }
      .frame(minWidth: 48)

      Rectangle()
        .fill(item.phase == .current ? CommanderDashboardPalette.inProgress : accent)
        .frame(width: item.phase == .current ? 4 : 2, height: 46)

      CommanderEventIconView(event: item.event, size: 42)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 7) {
          Text(item.event.title)
            .font(.headline)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
          if item.phase == .current {
            Text("TEĎ")
              .font(.caption2.bold())
              .foregroundStyle(CommanderDashboardPalette.inProgress)
          }
        }
        if !item.event.location.isEmpty {
          Text(item.event.location)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.66))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(item.phase == .current ? CommanderDashboardPalette.elevatedSurface : CommanderDashboardPalette.surface.opacity(0.72))
    .overlay {
      if item.phase == .current {
        RoundedRectangle(cornerRadius: 8)
          .stroke(CommanderDashboardPalette.inProgress.opacity(0.55), lineWidth: 1)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .opacity(rowOpacity)
    .accessibilityElement(children: .combine)
  }
}

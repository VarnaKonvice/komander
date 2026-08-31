import LazenskyCommanderCore
import SwiftUI

enum CommanderDashboardPalette {
  static let background = Color(red: 0.025, green: 0.022, blue: 0.075)
  static let surface = Color(commanderHex: CommanderBrandAssets.Colors.brandSurfaceDark)
  static let elevatedSurface = Color(red: 0.105, green: 0.075, blue: 0.19)
  static let commanderPurple = Color(commanderHex: CommanderBrandAssets.Colors.commanderPurple)
  static let commanderPurpleLight = Color(commanderHex: CommanderBrandAssets.Colors.commanderPurpleLight)
  static let waterBlue = Color(commanderHex: CommanderBrandAssets.Colors.waterBlue)
  static let timeGold = Color(commanderHex: CommanderBrandAssets.Colors.timeGold)
  static let inProgress = Color(commanderHex: CommanderVisualAssets.colors?.state.inProgress ?? "#22C55E")
  static let neutral = Color.white.opacity(0.62)
}

struct CommanderNeutralStateVisual: View {
  var accent = CommanderDashboardPalette.commanderPurple
  var size: CGFloat = 48

  var body: some View {
    CommanderBrandAssets.smallGlyph
      .resizable()
      .scaledToFit()
      .padding(size * 0.14)
      .frame(width: size, height: size)
      .background(CommanderDashboardPalette.surface)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(accent.opacity(0.55), lineWidth: 1)
      }
      .accessibilityHidden(true)
  }
}

struct CommanderEventIconView: View {
  let event: ScheduleEvent
  var size: CGFloat = 52

  private var icon: CommanderIconMap.Icon? {
    CommanderVisualAssets.icon(for: event)
  }

  private var accent: Color {
    Color(commanderHex: CommanderVisualAssets.accent(for: icon))
  }

  @ViewBuilder
  var body: some View {
    if let icon, let image = CommanderVisualAssets.image(for: icon.key) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(accent.opacity(0.9), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
  }
}

struct CommanderSectionTitle: View {
  let title: String
  var systemImage: String? = nil

  var body: some View {
    HStack(spacing: 8) {
      if let systemImage {
        Image(systemName: systemImage)
          .foregroundStyle(CommanderDashboardPalette.waterBlue)
          .accessibilityHidden(true)
      }
      Text(title)
        .font(.headline)
        .foregroundStyle(.white)
      Spacer(minLength: 0)
    }
  }
}

extension Color {
  init(commanderHex: String) {
    let value = commanderHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var rgb: UInt64 = 0
    Scanner(string: value).scanHexInt64(&rgb)
    self.init(
      red: Double((rgb >> 16) & 0xff) / 255,
      green: Double((rgb >> 8) & 0xff) / 255,
      blue: Double(rgb & 0xff) / 255
    )
  }
}

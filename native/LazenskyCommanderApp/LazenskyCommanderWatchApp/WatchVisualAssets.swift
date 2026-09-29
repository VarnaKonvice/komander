import Foundation
import LazenskyCommanderCore

enum WatchVisualAssets {
  static var iconMap: CommanderIconMap? { CommanderBrandAssets.iconMap }
  static var colors: CommanderColorMap? { CommanderBrandAssets.colors }

  static func icon(for event: ScheduleEvent?) -> CommanderIconMap.Icon? {
    event.flatMap { iconMap?.classify($0) }
  }

  static func accent(for event: ScheduleEvent?) -> String {
    guard let event else { return CommanderBrandAssets.Colors.primaryPurple }
    return CommanderBrandAssets.procedureAccentHex(
      iconKey: icon(for: event)?.key,
      title: event.title,
      isMeal: event.kind == .meal
    )
  }

  static func accent(for icon: CommanderIconMap.Icon?) -> String {
    guard let icon else { return CommanderBrandAssets.Colors.primaryPurple }
    return CommanderBrandAssets.procedureAccentHex(
      iconKey: icon.key,
      title: icon.label,
      isMeal: icon.key.hasPrefix("meal_")
    )
  }

}

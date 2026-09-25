import Foundation
import LazenskyCommanderCore

enum CommanderVisualAssets {
  static let iconMap: CommanderIconMap? = decode("icon-map")
  static let colors: CommanderColorMap? = decode("colors")

  static func icon(for event: ScheduleEvent) -> CommanderIconMap.Icon? {
    iconMap?.classify(event)
  }

  static func accent(for event: ScheduleEvent) -> String {
    let icon = icon(for: event)
    return CommanderBrandAssets.procedureAccentHex(
      iconKey: icon?.key,
      title: event.title,
      isMeal: event.kind == .meal
    )
  }

  static func symbol(for event: ScheduleEvent) -> String {
    let icon = icon(for: event)
    return CommanderBrandAssets.procedureSymbol(
      iconKey: icon?.key,
      title: event.title,
      isMeal: event.kind == .meal
    )
  }

  static func accent(for icon: CommanderIconMap.Icon?) -> String {
    guard let icon else {
      return CommanderBrandAssets.ProcedureFamily.fallback.accentHex
    }
    return CommanderBrandAssets.procedureAccentHex(
      iconKey: icon.key,
      title: icon.label,
      isMeal: icon.key.hasPrefix("meal_")
    )
  }

  static func accent(forIconKey key: String?) -> String {
    guard let key, let icon = iconMap?.icons.first(where: { $0.key == key }) else {
      return CommanderBrandAssets.ProcedureFamily.fallback.accentHex
    }
    return CommanderBrandAssets.procedureAccentHex(
      iconKey: icon.key,
      title: icon.label,
      isMeal: icon.key.hasPrefix("meal_")
    )
  }

  private static func decode<Value: Decodable>(_ name: String) -> Value? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
    return try? JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }

}

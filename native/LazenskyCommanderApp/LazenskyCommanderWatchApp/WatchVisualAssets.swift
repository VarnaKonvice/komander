import Foundation
import LazenskyCommanderCore

enum WatchVisualAssets {
  static let iconMap: CommanderIconMap? = decode("icon-map")
  static let colors: CommanderColorMap? = decode("colors")

  static func icon(for event: ScheduleEvent?) -> CommanderIconMap.Icon? {
    event.flatMap { iconMap?.classify($0) }
  }

  static func accent(for icon: CommanderIconMap.Icon?) -> String {
    guard let icon else {
      return colors?.brand.commanderPurple ?? iconMap?.fallback.accent ?? "#6E56CF"
    }
    let colorKey = icon.key.hasPrefix("meal_") ? "meal" : icon.key
    return colors?.procedures[colorKey] ?? icon.accent
  }

  private static func decode<Value: Decodable>(_ name: String) -> Value? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
    return try? JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }
}

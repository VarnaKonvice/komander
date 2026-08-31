import Foundation
import LazenskyCommanderCore
import UIKit

enum CommanderVisualAssets {
  static let iconMap: CommanderIconMap? = decode("icon-map")
  static let colors: CommanderColorMap? = decode("colors")

  static func icon(for event: ScheduleEvent) -> CommanderIconMap.Icon? {
    iconMap?.classify(event)
  }

  static func accent(for icon: CommanderIconMap.Icon?) -> String {
    guard let icon else {
      return colors?.brand.commanderPurple ?? iconMap?.fallback.accent ?? "#6E56CF"
    }
    let colorKey = icon.key.hasPrefix("meal_") ? "meal" : icon.key
    return colors?.procedures[colorKey] ?? icon.accent
  }

  @MainActor
  static func image(for iconKey: String?) -> UIImage? {
    guard let requestedKey = iconKey.flatMap({ $0.isEmpty ? nil : $0 }) else { return nil }
    return loadImage(requestedKey)
  }

  private static func decode<Value: Decodable>(_ name: String) -> Value? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }
    return try? JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
  }

  @MainActor
  private static func loadImage(_ key: String) -> UIImage? {
    guard let url = Bundle.main.url(forResource: key, withExtension: "png") else { return nil }
    return UIImage(contentsOfFile: url.path)
  }
}

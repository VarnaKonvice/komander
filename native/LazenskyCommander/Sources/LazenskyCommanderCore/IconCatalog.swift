import Foundation

public struct CommanderIconMap: Codable, Equatable, Sendable {
  public struct Icon: Codable, Equatable, Sendable {
    public let key: String
    public let label: String
    public let watchLabel: String
    public let accent: String
    public let priority: Int
    public let keywords: [String]
  }
  public struct Fallback: Codable, Equatable, Sendable {
    public let key: String?
    public let label: String
    public let accent: String
  }
  public let version: Int
  public let icons: [Icon]
  public let fallback: Fallback

  public func classify(_ event: ScheduleEvent) -> Icon? {
    let source = normalized([event.title, event.procedureType ?? "", event.mealType ?? ""].joined(separator: " "))
    let matches = icons.enumerated().compactMap { index, icon -> (icon: Icon, keywordLength: Int, index: Int)? in
      let keywordLength = icon.keywords
        .map(normalized)
        .filter { !$0.isEmpty && source.contains($0) }
        .map(\.count)
        .max()
      guard let keywordLength else { return nil }
      return (icon, keywordLength, index)
    }
    return matches.sorted {
      if $0.icon.priority != $1.icon.priority { return $0.icon.priority > $1.icon.priority }
      if $0.keywordLength != $1.keywordLength { return $0.keywordLength > $1.keywordLength }
      return $0.index < $1.index
    }.first?.icon
  }

  private func normalized(_ value: String) -> String {
    value.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "cs_CZ"))
  }
}

public struct CommanderColorMap: Codable, Equatable, Sendable {
  public struct Brand: Codable, Equatable, Sendable {
    public let commanderPurple: String
    public let commanderPurpleDark: String
  }

  public struct State: Codable, Equatable, Sendable {
    public let upcoming: String
    public let leaveNow: String
    public let inProgress: String
    public let dayDone: String

    private enum CodingKeys: String, CodingKey {
      case upcoming
      case leaveNow = "leave_now"
      case inProgress = "in_progress"
      case dayDone = "day_done"
    }
  }

  public let brand: Brand
  public let procedures: [String: String]
  public let state: State
}

import Foundation

public enum ScheduleChannel: String, Codable, Equatable, Sendable {
  case production
  case e2e
}

public struct AppConfiguration: Sendable {
  public static let productionScheduleURL = URL(string: "https://raw.githubusercontent.com/VarnaKonvice/komander/main/data/schedule.json")!

  public var scheduleURL: URL
  public var channel: ScheduleChannel

  public init(scheduleURL: URL = productionScheduleURL, channel: ScheduleChannel? = nil) {
    self.scheduleURL = scheduleURL
    self.channel = channel ?? Self.inferChannel(from: scheduleURL)
  }

  private static func inferChannel(from url: URL) -> ScheduleChannel {
    url.absoluteString.contains("/lc/e2e-") ? .e2e : .production
  }
}

public protocol ScheduleServing: Sendable {
  func fetchSchedule() async throws -> Schedule
}

@available(macOS 12.0, iOS 15.0, *)
public struct URLSessionScheduleService: ScheduleServing {
  public let configuration: AppConfiguration
  private let session: URLSession

  public init(configuration: AppConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  public func fetchSchedule() async throws -> Schedule {
    var components = URLComponents(url: configuration.scheduleURL, resolvingAgainstBaseURL: false)
    var queryItems = components?.queryItems ?? []
    queryItems.append(URLQueryItem(name: "lc", value: UUID().uuidString))
    components?.queryItems = queryItems
    let requestURL = components?.url ?? configuration.scheduleURL

    var request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
    request.setValue("no-cache", forHTTPHeaderField: "Pragma")

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let schedule = try JSONDecoder().decode(Schedule.self, from: data)
    try NativeAlarmContract.validateCanonical(schedule)
    return schedule
  }
}

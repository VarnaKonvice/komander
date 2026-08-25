import Foundation

public enum ScheduleChannel: String, Equatable, Sendable {
  case production
  case e2e
}

public struct AppConfiguration: Sendable {
  public static let productionScheduleURL = URL(string: "https://raw.githubusercontent.com/VarnaKonvice/komander/main/data/schedule.json")!
  public static let e2eScheduleURL = URL(string: "https://raw.githubusercontent.com/VarnaKonvice/komander/lc/e2e-alarm-test-v1/data/e2e-test-schedule.json")!

  public var scheduleURL: URL
  public var channel: ScheduleChannel

  public init(
    scheduleURL: URL = AppConfiguration.productionScheduleURL,
    channel: ScheduleChannel = .production
  ) {
    self.scheduleURL = scheduleURL
    self.channel = channel
  }

  public static var e2e: AppConfiguration {
    AppConfiguration(scheduleURL: e2eScheduleURL, channel: .e2e)
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
    let (data, response) = try await session.data(from: configuration.scheduleURL)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let schedule = try JSONDecoder().decode(Schedule.self, from: data)
    try NativeAlarmContract.validateCanonical(schedule)
    return schedule
  }
}

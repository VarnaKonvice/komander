import Foundation

public struct AppConfiguration: Sendable {
  public var scheduleURL: URL

  public init(scheduleURL: URL = URL(string: "https://raw.githubusercontent.com/VarnaKonvice/komander/lc/e2e-alarm-test-v1/data/e2e-test-schedule.json")!) {
    self.scheduleURL = scheduleURL
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
    try NativeAlarmContract.validate(schedule)
    return schedule
  }
}

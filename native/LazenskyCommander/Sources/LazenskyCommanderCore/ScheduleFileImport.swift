import Foundation

public enum ScheduleFileImport {
  public static let maximumByteCount = 5 * 1024 * 1024

  public static func decode(_ data: Data) throws -> Schedule {
    guard data.count <= maximumByteCount else {
      throw CocoaError(.fileReadTooLarge)
    }
    let schedule = try JSONDecoder().decode(Schedule.self, from: data)
    try NativeAlarmContract.validateCanonical(schedule)
    return schedule
  }
}

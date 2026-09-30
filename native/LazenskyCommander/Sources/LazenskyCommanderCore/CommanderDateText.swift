import Foundation

public enum CommanderDateText {
  public static func shortDay(_ date: Date) -> String {
    capitalize(format(date, pattern: "E d. M."))
  }

  public static func numericDate(_ date: Date) -> String {
    format(date, pattern: "d. M. yyyy")
  }

  public static func numericDate(isoDate: String) -> String? {
    guard let date = try? NativeAlarmContract.dateTime(date: isoDate, time: "00:00") else { return nil }
    return numericDate(date)
  }

  private static func format(_ date: Date, pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "cs_CZ")
    formatter.timeZone = TimeZone(identifier: "Europe/Prague")!
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }

  private static func capitalize(_ value: String) -> String {
    guard let first = value.first else { return value }
    return String(first).uppercased(with: Locale(identifier: "cs_CZ")) + value.dropFirst()
  }
}

import Foundation

public enum ScheduleCalendarExport {
  public static func make(schedule: Schedule, overrides: LeadTimeOverrides = .init(),
                          generatedAt: Date = Date()) throws -> String {
    try NativeAlarmContract.validateCanonical(schedule)
    let projection = try CommanderScheduleProjection(schedule: schedule, overrides: overrides)
    let utc = formatter(timeZone: TimeZone(secondsFromGMT: 0)!)
    let local = formatter(timeZone: TimeZone(identifier: "Europe/Prague")!)
    var lines = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Bohanes Technologies//Lazensky Commander//CS",
      "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "X-WR-CALNAME:Lázeňský Commander",
      "X-WR-TIMEZONE:Europe/Prague",
      "BEGIN:VTIMEZONE", "TZID:Europe/Prague", "X-LIC-LOCATION:Europe/Prague",
      "BEGIN:DAYLIGHT", "DTSTART:19960331T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0200",
      "TZNAME:CEST", "RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU", "END:DAYLIGHT",
      "BEGIN:STANDARD", "DTSTART:19961027T030000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100",
      "TZNAME:CET", "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU", "END:STANDARD", "END:VTIMEZONE"
    ]
    for item in projection.events {
      // Encode IDs losslessly so punctuation cannot create collisions or extra ICS lines.
      let identity = Data(item.event.stableId.utf8).map { String(format: "%02x", $0) }.joined()
      let leave = item.alarm.leaveAt.replacingOccurrences(of: "T", with: " ")
      lines += [
        "BEGIN:VEVENT", "UID:commander-\(identity)@lazensky-commander",
        "DTSTAMP:\(utc.string(from: generatedAt))Z",
        "DTSTART;TZID=Europe/Prague:\(local.string(from: item.startAt))",
        "DTEND;TZID=Europe/Prague:\(local.string(from: item.endAt))",
        "SUMMARY:\(escape(item.event.title))", "LOCATION:\(escape(item.event.location))",
        "DESCRIPTION:\(escape("Lázeňský Commander\nOdejít nejpozději: " + leave))",
        "CATEGORIES:\(CommanderEventSemantics.calendarCategory(item.event))", "END:VEVENT"
      ]
    }
    lines.append("END:VCALENDAR")
    return lines.map(fold).joined(separator: "\r\n") + "\r\n"
  }

  private static func formatter(timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
    return formatter
  }

  private static func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: ";", with: "\\;")
      .replacingOccurrences(of: ",", with: "\\,")
  }

  private static func fold(_ line: String) -> String {
    var result = ""
    var byteCount = 0
    for scalar in line.unicodeScalars {
      let text = String(scalar)
      let size = text.utf8.count
      if byteCount + size > 75 {
        result += "\r\n "
        byteCount = 1
      }
      result += text
      byteCount += size
    }
    return result
  }
}

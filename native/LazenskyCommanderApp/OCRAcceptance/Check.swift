import CoreGraphics
import Foundation
import ImageIO
import LazenskyCommanderCore

@main
enum OCRAcceptance {
  struct Corpus: Decodable { let cases: [Scenario] }
  struct Cell: Decodable {
    let text: String
    let x, y, w, h: Double
    let confidence: Float
  }
  struct Expected: Decodable, Equatable {
    let date, start, end, title, location, kind: String
    init(_ event: ScheduleEvent) {
      date = event.date
      start = event.start
      end = event.end
      title = event.title
      location = event.location
      kind = event.kind.rawValue
    }
  }
  struct Scenario: Decodable {
    let name: String
    let pages: [[Cell]]
    let review: Int
    let events: [Expected]?
  }

  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[0])))
    let lexicon = try CommanderSpaOCRLexicon.loadBundled(override: URL(fileURLWithPath: args[1]))
    let now = Date(timeIntervalSince1970: 1_795_161_600)
    for scenario in corpus.cases {
      let pages = scenario.pages.map { cells in
        let lines = cells.map { cell in
          CommanderOCRLine(text: cell.text, confidence: cell.confidence,
            bounds: .init(x: cell.x, y: cell.y, width: cell.w, height: cell.h), alternatives: [], words: [])
        }
        return CommanderOCRReconciler.fromSingle(.init(text: lines.map(\.text).joined(separator: "\n"),
          pixelWidth: 1600, pixelHeight: 2200, averageConfidence: 0.99, lines: lines))
      }
      let result = CommanderDocumentExtractor.extract(pages, lexicon: lexicon)
      try check(result.reviewCount == scenario.review, "\(scenario.name): \(result.rows)")
      if let expected = scenario.events {
        let schedule = try CommanderCanonicalScheduleBuilder.build(from: result, now: now)
        try check(schedule.events.map(Expected.init) == expected, "\(scenario.name): \(schedule.events)")
      } else {
        try check((try? CommanderCanonicalScheduleBuilder.build(from: result, now: now)) == nil, "\(scenario.name): accepted unresolved rows")
      }
      print("PASS \(scenario.name)")
    }
    let row = CommanderDocumentCandidateRow(rawText: "ABC-17", dateToken: nil, timeToken: nil,
      endTimeToken: nil, title: "ABC-17", location: nil, meal: nil, issue: "Nejasné datum")
    try check(CommanderDocumentExtractor.correct(row, date: "31.11.2026", start: "10:30", end: "", title: "ABC-17", location: "") == nil, "accepted invalid day")
    try check(CommanderDocumentExtractor.correct(row, date: "20.11.2026", start: "10:30", end: "09:30", title: "ABC-17", location: "") == nil, "accepted earlier end")
    if let repaired = CommanderDocumentExtractor.correct(row, date: "20.11.2026", start: "10:30", end: "", title: "ABC-17", location: "") {
      let schedule = try CommanderCanonicalScheduleBuilder.build(from: .init(facility: nil, rows: [repaired]), now: now)
      try check(schedule.events.first?.procedureType == nil && schedule.events.first?.start == "10:30", "unknown title wrongly classified")
    } else { try check(false, "correction rejected") }
    print("PASS row correction")
    for path in args.dropFirst(2) {
      let url = URL(fileURLWithPath: path)
      guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
      let page = try await CommanderOnDeviceOCR.recognize(cgImage: image)
      if ProcessInfo.processInfo.environment["LC_OCR_DIAGNOSTICS"] == "1" {
        for line in page.lines {
          print("LINE \(line.bounds) \(line.confidence) \(line.text) ALT \(line.alternatives)")
        }
      }
      let result = CommanderDocumentExtractor.extract(CommanderOCRReconciler.fromSingle(page), lexicon: lexicon)
      let status = result.readyWithoutQuestions ? "READY" : "REVIEW"
      print("VISION \(url.lastPathComponent) \(status) \(result.rows.count) rows \(result.reviewCount) issues")
      for row in result.rows { print("  \(row.dateToken ?? "?") \(row.timeToken ?? "?") \(row.title) \(row.issue ?? "")") }
    }
  }

  static func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw NSError(domain: "OCRAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }
}

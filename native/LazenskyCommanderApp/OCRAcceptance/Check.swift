import CoreGraphics
import Foundation
import ImageIO
import LazenskyCommanderCore
import PDFKit

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
    let paperDetails: PaperScheduleDetails?
    let expectedRows: Int?
    let expectedHeaderIssue: String?
  }

  static func main() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let corpusURL = URL(fileURLWithPath: args[0])
    let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL))
    let whole = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: corpusURL.deletingLastPathComponent().appendingPathComponent("full-document-ocr.json")))
    let lexicon = try CommanderSpaOCRLexicon.loadBundled(override: URL(fileURLWithPath: args[1]))
    let now = Date(timeIntervalSince1970: 1_795_161_600)
    for scenario in corpus.cases + whole.cases {
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
      if let count = scenario.expectedRows {
        try check(result.rows.count == count, "\(scenario.name): unexpected scheduled count")
      }
      if let key = scenario.expectedHeaderIssue {
        try check(result.headerIssues[key] != nil, "\(scenario.name): missing editable header issue")
      }
      if let details = scenario.paperDetails {
        try check(result.details == details, "\(scenario.name): unexpected paper header or prescriptions \((result.details?.fields.keys.sorted()) ?? [])")
      }
      if let expected = scenario.events {
        let schedule = try CommanderCanonicalScheduleBuilder.build(from: result, now: now)
        try check(schedule.events.map(Expected.init) == expected, "\(scenario.name): \(schedule.events)")
        if let details = scenario.paperDetails {
          let restored = try JSONDecoder().decode(Schedule.self, from: JSONEncoder().encode(schedule))
          try check(restored.paperDetails == details, "Local paper metadata failed round trip")
          let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lc-paper-test-\(UUID().uuidString)")
          defer { try? FileManager.default.removeItem(at: directory) }
          let local = directory.appendingPathComponent("schedule.json")
          let key = "lc-paper-test.\(UUID().uuidString)"
          let store = UserDefaultsScheduleSnapshotStore(key: key, paperFile: local)
          try await store.save(schedule)
          try check(UserDefaults.standard.data(forKey: key) == nil &&
                    LocalPaperScheduleFile.read(from: local) == schedule, "Paper data must stay in the private file")
          let payload = try NativeAlarmContract.payload(schedule: schedule)
          let serialized = try JSONEncoder().encode(payload)
          try check(payload.alarms.count == expected.count && !String(decoding: serialized, as: UTF8.self).contains("TEST-X"),
                    "Alarm payload contains paper-only information")
        }
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
      var pages: [CommanderOCRPage] = []
      var usedText = 0
      if url.pathExtension.lowercased() == "pdf" {
        guard let pdf = PDFDocument(url: url), let cg = CGPDFDocument(url as CFURL) else { throw CocoaError(.fileReadCorruptFile) }
        for index in 0..<pdf.pageCount {
          guard let page = pdf.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
          if let text = CommanderPDFText.read(page) {
            pages.append(text)
            usedText += 1
          } else {
            guard let raw = cg.page(at: index + 1) else { throw CocoaError(.fileReadCorruptFile) }
            let bounds = raw.getBoxRect(.mediaBox)
            let scale = min(4, 2200 / max(bounds.width, bounds.height))
            let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
              throw CocoaError(.fileReadCorruptFile)
            }
            let target = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(gray: 1, alpha: 1); context.fill(target)
            context.concatenate(raw.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(raw)
            guard let image = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
            pages.append(try await CommanderOnDeviceOCR.recognize(cgImage: image))
          }
        }
      } else {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw CocoaError(.fileReadCorruptFile) }
        pages = [try await CommanderOnDeviceOCR.recognize(cgImage: image)]
      }
      let result = CommanderDocumentExtractor.extract(pages.map(CommanderOCRReconciler.fromSingle), lexicon: lexicon)
      let status = result.readyWithoutQuestions ? "READY" : "REVIEW"
      print("DOCUMENT \(status) \(result.rows.count) rows \(result.reviewCount) issues \(usedText)/\(pages.count) pages with text")
      if url.lastPathComponent == "whole-document-mixed.pdf" {
        try check(usedText == 1 && pages.count == 2 && result.readyWithoutQuestions &&
                  result.rows.count == 2 && result.details?.fields["room"] == "317" &&
                  result.details?.prescriptions.count == 1, "mixed PDF regression")
      }
    }
  }

  static func check(_ condition: Bool, _ message: String) throws {
    guard condition else { throw NSError(domain: "OCRAcceptance", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  }
}

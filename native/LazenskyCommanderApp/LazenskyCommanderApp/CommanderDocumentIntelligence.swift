import CoreGraphics
import Foundation
import LazenskyCommanderCore

enum CommanderDocumentQualityLevel: String, Codable, Sendable {
  case good
  case usable
  case retryRecommended
}

struct CommanderDocumentImageQuality: Codable, Equatable, Sendable {
  let level: CommanderDocumentQualityLevel
  let score: Float
  let brightness: Float
  let contrast: Float
  let sharpness: Float
  let issues: [String]

  static func assess(_ image: CGImage) -> CommanderDocumentImageQuality {
    let width = 160
    let height = max(1, Int(Double(width) * Double(image.height) / Double(max(1, image.width))))
    var pixels = [UInt8](repeating: 0, count: width * height)
    let space = CGColorSpaceCreateDeviceGray()
    pixels.withUnsafeMutableBytes { raw in
      guard let context = CGContext(
        data: raw.baseAddress,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: space,
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      ) else { return }
      context.interpolationQuality = .medium
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    guard !pixels.isEmpty else {
      return .init(level: .retryRecommended, score: 0, brightness: 0, contrast: 0, sharpness: 0, issues: ["Fotografii nelze vyhodnotit"])
    }

    let mean = Float(pixels.reduce(0) { $0 + Int($1) }) / Float(pixels.count)
    var variance: Double = 0
    var edge: Double = 0
    var edgeCount = 0
    for y in 0..<height {
      for x in 0..<width {
        let index = y * width + x
        let d = Double(Float(pixels[index]) - mean)
        variance += d * d
        if x + 1 < width { edge += abs(Double(pixels[index]) - Double(pixels[index + 1])); edgeCount += 1 }
        if y + 1 < height { edge += abs(Double(pixels[index]) - Double(pixels[index + width])); edgeCount += 1 }
      }
    }
    let contrast = Float(sqrt(variance / Double(max(1, pixels.count))))
    let sharpness = Float(edge / Double(max(1, edgeCount)))
    var issues: [String] = []
    if min(image.width, image.height) < 900 { issues.append("Nízké rozlišení") }
    if mean < 45 { issues.append("Fotografie je příliš tmavá") }
    if mean > 235 { issues.append("Fotografie je přeexponovaná") }
    if contrast < 20 { issues.append("Slabý kontrast textu") }
    if sharpness < 7.5 { issues.append("Fotografie může být rozmazaná") }

    let resolution = min(1, Float(min(image.width, image.height)) / 1400)
    let exposure = 1 - min(1, abs(mean - 145) / 130)
    let contrastScore = min(1, contrast / 48)
    let sharpnessScore = min(1, sharpness / 18)
    let score = 0.2 * resolution + 0.2 * exposure + 0.25 * contrastScore + 0.35 * sharpnessScore
    let level: CommanderDocumentQualityLevel = score >= 0.62 && issues.count <= 1 ? .good : score >= 0.42 ? .usable : .retryRecommended
    return .init(level: level, score: score, brightness: mean / 255, contrast: contrast / 128, sharpness: sharpness / 32, issues: issues)
  }
}

enum CommanderOCRMergeState: String, Codable, Sendable { case agreed, reconciled, singleSource, conflict }

struct CommanderMergedOCRLine: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
  let bounds: CommanderOCRRect
  let state: CommanderOCRMergeState
  let criticalConflict: Bool
  let alternateText: String?
}

struct CommanderMergedOCRPage: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
  let lines: [CommanderMergedOCRLine]
  let criticalConflicts: Int
  var requiresClientReview: Bool { criticalConflicts > 0 }
}

enum CommanderOCRReconciler {
  static func fromSingle(_ page: CommanderOCRPage) -> CommanderMergedOCRPage {
    let lines = page.lines.map(single)
    let confidence = lines.isEmpty ? 0 : lines.reduce(0) { $0 + $1.confidence } / Float(lines.count)
    return .init(text: lines.map(\.text).joined(separator: "\n"), confidence: confidence, lines: lines, criticalConflicts: 0)
  }

  static func combine(_ pages: [CommanderMergedOCRPage]) -> CommanderMergedOCRPage {
    let lines = pages.flatMap(\.lines)
    let confidence = lines.isEmpty ? 0 : lines.reduce(0) { $0 + $1.confidence } / Float(lines.count)
    return .init(text: pages.map(\.text).joined(separator: "\n"), confidence: confidence, lines: lines, criticalConflicts: lines.filter(\.criticalConflict).count)
  }
  static func merge(_ first: CommanderOCRPage, _ second: CommanderOCRPage) -> CommanderMergedOCRPage {
    var used = Set<Int>()
    var output: [CommanderMergedOCRLine] = []
    for a in first.lines {
      var bestIndex: Int?
      var bestDistance = Double.greatestFiniteMagnitude
      for (index, b) in second.lines.enumerated() where !used.contains(index) {
        let dy = abs(centerY(a.bounds) - centerY(b.bounds))
        let dx = abs(centerX(a.bounds) - centerX(b.bounds))
        let distance = dy * 4 + dx
        if dy <= 0.035 && dx <= 0.32 && distance < bestDistance {
          bestDistance = distance
          bestIndex = index
        }
      }
      guard let index = bestIndex else { output.append(single(a)); continue }
      used.insert(index)
      output.append(mergeLine(a, second.lines[index]))
    }
    for (index, line) in second.lines.enumerated() where !used.contains(index) { output.append(single(line)) }
    output.sort {
      if abs($0.bounds.y - $1.bounds.y) < 0.012 { return $0.bounds.x < $1.bounds.x }
      return $0.bounds.y < $1.bounds.y
    }
    let confidence = output.isEmpty ? 0 : output.reduce(0) { $0 + $1.confidence } / Float(output.count)
    return .init(
      text: output.map(\.text).joined(separator: "\n"),
      confidence: confidence,
      lines: output,
      criticalConflicts: output.filter(\.criticalConflict).count
    )
  }

  static func normalize(_ value: String) -> String {
    let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
    var result = ""
    var lastWasSpace = false
    for scalar in folded.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        result.unicodeScalars.append(scalar)
        lastWasSpace = false
      } else if CharacterSet.whitespacesAndNewlines.contains(scalar), !lastWasSpace {
        result.append(" ")
        lastWasSpace = true
      }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func similarity(_ a: String, _ b: String) -> Float {
    if a == b { return 1 }
    let aa = Array(a), bb = Array(b)
    if aa.isEmpty || bb.isEmpty { return 0 }
    var previous = Array(0...bb.count)
    var current = Array(repeating: 0, count: bb.count + 1)
    for i in 1...aa.count {
      current[0] = i
      for j in 1...bb.count {
        current[j] = min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (aa[i - 1] == bb[j - 1] ? 0 : 1))
      }
      swap(&previous, &current)
    }
    return 1 - Float(previous[bb.count]) / Float(max(aa.count, bb.count))
  }

  private static func mergeLine(_ a: CommanderOCRLine, _ b: CommanderOCRLine) -> CommanderMergedOCRLine {
    let na = normalize(a.text), nb = normalize(b.text)
    let criticalA = criticalTokens(a.text), criticalB = criticalTokens(b.text)
    let criticalConflict = criticalA != criticalB && (!criticalA.isEmpty || !criticalB.isEmpty)
    if !na.isEmpty && na == nb {
      let chosen = a.confidence >= b.confidence ? a : b
      return .init(text: chosen.text, confidence: min(1, max(a.confidence, b.confidence) + 0.06), bounds: chosen.bounds, state: .agreed, criticalConflict: false, alternateText: nil)
    }
    let similarity = similarity(na, nb)
    let winner = a.confidence >= b.confidence ? a : b
    let loser = a.confidence >= b.confidence ? b : a
    if !criticalConflict && similarity >= 0.88 {
      return .init(text: winner.text, confidence: min(1, max(a.confidence, b.confidence) + 0.02), bounds: winner.bounds, state: .reconciled, criticalConflict: false, alternateText: loser.text)
    }
    return .init(text: winner.text, confidence: max(a.confidence, b.confidence), bounds: winner.bounds, state: .conflict, criticalConflict: criticalConflict, alternateText: loser.text)
  }

  private static func single(_ line: CommanderOCRLine) -> CommanderMergedOCRLine {
    .init(text: line.text, confidence: line.confidence * 0.92, bounds: line.bounds, state: .singleSource, criticalConflict: false, alternateText: nil)
  }

  private static func criticalTokens(_ text: String) -> Set<String> {
    let patterns = [#"\b(?:[01]?\d|2[0-3])[:.]\d{2}\b"#, #"\b(?:[0-3]?\d)[./-](?:[01]?\d)(?:[./-](?:\d{2}|\d{4}))?\b"#]
    var result = Set<String>()
    for (index, pattern) in patterns.enumerated() {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(text.startIndex..., in: text)
      for match in regex.matches(in: text, range: range) {
        guard let swiftRange = Range(match.range, in: text) else { continue }
        var token = String(text[swiftRange])
        if index == 0 { token = token.replacingOccurrences(of: ".", with: ":") }
        result.insert((index == 0 ? "T:" : "D:") + token)
      }
    }
    return result
  }

  private static func centerX(_ rect: CommanderOCRRect) -> Double { rect.x + rect.width / 2 }
  private static func centerY(_ rect: CommanderOCRRect) -> Double { rect.y + rect.height / 2 }
}

struct CommanderProcedureMatch: Codable, Equatable, Sendable {
  let procedureID: String
  let name: String
  let category: String
  let matchedTerm: String
  let score: Float
  let safeForNameCorrection: Bool
}

struct CommanderFacilityMatch: Codable, Equatable, Sendable {
  let facilityID: String
  let name: String
  let spaLocation: String
  let score: Float
}

struct CommanderDocumentHints: Codable, Equatable, Sendable {
  let facility: CommanderFacilityMatch?
  let procedures: [CommanderProcedureMatch]
}

final class CommanderSpaOCRLexicon: @unchecked Sendable {
  private struct Root: Codable { let procedures: [Procedure]; let facilities: [Facility] }
  private struct Procedure: Codable { let id: String; let name: String; let category: String; let terms: [String] }
  private struct Facility: Codable {
    let id: String
    let name: String
    let spaLocation: String
    enum CodingKeys: String, CodingKey { case id, name; case spaLocation = "spa_location" }
  }
  private struct ProcedureTerm { let normalized: String; let procedure: Procedure; let term: String }

  private let data: Root
  private let procedureTerms: [ProcedureTerm]

  private init(data: Root) {
    self.data = data
    self.procedureTerms = data.procedures.flatMap { procedure in
      procedure.terms.compactMap { term in
        let normalized = CommanderOCRReconciler.normalize(term)
        return normalized.count >= 3 ? ProcedureTerm(normalized: normalized, procedure: procedure, term: term) : nil
      }
    }
  }

  static func loadBundled() throws -> CommanderSpaOCRLexicon {
    guard let url = Bundle.main.url(forResource: "commander-ocr-lexicon-v1", withExtension: "json") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return CommanderSpaOCRLexicon(data: try JSONDecoder().decode(Root.self, from: Data(contentsOf: url)))
  }

  func match(fullText: String, candidateLines: [String]) -> CommanderDocumentHints {
    let normalizedText = CommanderOCRReconciler.normalize(fullText)
    var facility: CommanderFacilityMatch?
    for item in data.facilities {
      let name = CommanderOCRReconciler.normalize(item.name)
      let location = CommanderOCRReconciler.normalize(item.spaLocation)
      var score: Float = 0
      if name.count >= 3 && normalizedText.contains(name) { score = 1 }
      else if location.count >= 4 && normalizedText.contains(location) { score = 0.62 }
      if score > 0, facility == nil || score > facility!.score {
        facility = .init(facilityID: item.id, name: item.name, spaLocation: item.spaLocation, score: score)
      }
    }

    var matches: [String: CommanderProcedureMatch] = [:]
    for raw in candidateLines {
      let line = CommanderOCRReconciler.normalize(stripCriticalNumbers(raw))
      guard line.count >= 3 else { continue }
      var best: (ProcedureTerm, Float)?
      var second: Float = 0
      for candidate in procedureTerms {
        let score: Float
        if line.contains(candidate.normalized) || candidate.normalized.contains(line) {
          score = Float(min(line.count, candidate.normalized.count)) / Float(max(line.count, candidate.normalized.count))
        } else {
          if abs(line.count - candidate.normalized.count) > max(8, candidate.normalized.count / 2) { continue }
          score = CommanderOCRReconciler.similarity(line, candidate.normalized)
        }
        if best == nil || score > best!.1 {
          second = best?.1 ?? 0
          best = (candidate, score)
        } else if score > second { second = score }
      }
      guard let best, best.1 >= 0.86 else { continue }
      let safe = best.1 >= 0.94 && best.1 - second >= 0.035
      let match = CommanderProcedureMatch(procedureID: best.0.procedure.id, name: best.0.procedure.name, category: best.0.procedure.category, matchedTerm: best.0.term, score: best.1, safeForNameCorrection: safe)
      if matches[match.procedureID] == nil || match.score > matches[match.procedureID]!.score { matches[match.procedureID] = match }
    }
    return .init(facility: facility, procedures: matches.values.sorted { $0.score > $1.score })
  }

  private func stripCriticalNumbers(_ text: String) -> String {
    text.replacingOccurrences(of: #"\b(?:[01]?\d|2[0-3])[:.]\d{2}\b|\b(?:[0-3]?\d)[./-](?:[01]?\d)(?:[./-](?:\d{2}|\d{4}))?\b"#, with: " ", options: .regularExpression)
  }
}

struct CommanderDocumentCandidateRow: Codable, Equatable, Sendable {
  let rawText: String
  let dateToken: String?
  let timeToken: String?
  let endTimeToken: String?
  let meal: String?
  let procedure: CommanderProcedureMatch?
  let confidence: Float
  let requiresReview: Bool
}

struct CommanderDocumentExtraction: Codable, Equatable, Sendable {
  let facility: CommanderFacilityMatch?
  let rows: [CommanderDocumentCandidateRow]
  let reviewCount: Int
  var readyWithoutQuestions: Bool { !rows.isEmpty && reviewCount == 0 }
}

enum CommanderDocumentExtractor {
  static func extract(_ page: CommanderMergedOCRPage, lexicon: CommanderSpaOCRLexicon) -> CommanderDocumentExtraction {
    let whole = lexicon.match(fullText: page.text, candidateLines: page.lines.map(\.text))
    var rows: [CommanderDocumentCandidateRow] = []
    var currentDate: String?
    for line in page.lines {
      if let date = firstMatch(#"\b(?:[0-3]?\d)[./-](?:[01]?\d)(?:[./-](?:\d{2}|\d{4}))?\b"#, in: line.text) { currentDate = date }
      let times = allMatches(#"\b(?:[01]?\d|2[0-3])[:.]\d{2}\b"#, in: line.text).map { $0.replacingOccurrences(of: ".", with: ":") }
      let time = times.first
      let endTime = times.count > 1 ? times[1] : nil
      let normalized = CommanderOCRReconciler.normalize(line.text)
      let meal: String? = normalized.contains("snidane") ? "breakfast" : normalized.contains("obed") ? "lunch" : normalized.contains("vecere") ? "dinner" : nil
      let procedure = lexicon.match(fullText: line.text, candidateLines: [line.text]).procedures.first
      if time == nil && procedure == nil && meal == nil { continue }

      var confidence = line.confidence
      if procedure?.safeForNameCorrection == true { confidence = min(1, confidence + 0.04) }
      let requiresReview = line.criticalConflict ||
        (time == nil) ||
        (currentDate == nil) ||
        (time != nil && line.confidence < 0.68) ||
        (procedure == nil && meal == nil) ||
        (procedure != nil && procedure?.safeForNameCorrection == false && line.confidence < 0.76)
      rows.append(.init(
        rawText: line.text,
        dateToken: currentDate,
        timeToken: time,
        endTimeToken: endTime,
        meal: meal,
        procedure: procedure,
        confidence: confidence,
        requiresReview: requiresReview
      ))
    }
    return .init(facility: whole.facility, rows: rows, reviewCount: rows.filter(\.requiresReview).count)
  }

  private static func allMatches(_ pattern: String, in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let full = NSRange(text.startIndex..., in: text)
    return regex.matches(in: text, range: full).compactMap { match in
      guard let range = Range(match.range, in: text) else { return nil }
      return String(text[range])
    }
  }

  private static func firstMatch(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let full = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: full), let range = Range(match.range, in: text) else { return nil }
    return String(text[range])
  }
}


enum CommanderCanonicalScheduleBuilder {
  static func build(from extraction: CommanderDocumentExtraction, now: Date = Date()) throws -> Schedule {
    guard extraction.reviewCount == 0, !extraction.rows.isEmpty else {
      throw NSError(
        domain: "LazenskyCommander.OCR",
        code: 20,
        userInfo: [NSLocalizedDescriptionKey: "Rozpis obsahuje údaje, které je potřeba před aktivací zkontrolovat."]
      )
    }

    let version = max(1, Int(now.timeIntervalSince1970))
    var events: [ScheduleEvent] = []
    for (index, row) in extraction.rows.enumerated() {
      guard let dateToken = row.dateToken,
            let date = canonicalDate(dateToken, near: now),
            let start = row.timeToken else {
        throw NSError(
          domain: "LazenskyCommander.OCR",
          code: 21,
          userInfo: [NSLocalizedDescriptionKey: "U jedné položky chybí datum nebo čas."]
        )
      }

      let isMeal = row.meal != nil
      guard isMeal || row.procedure != nil else {
        throw NSError(
          domain: "LazenskyCommander.OCR",
          code: 22,
          userInfo: [NSLocalizedDescriptionKey: "Jednu položku nelze bezpečně určit jako proceduru nebo jídlo."]
        )
      }

      let end = row.endTimeToken ?? start
      let title: String
      let procedureType: String?
      let mealType: String?
      if let meal = row.meal {
        title = mealTitle(meal)
        procedureType = nil
        mealType = title
      } else if let procedure = row.procedure {
        title = procedure.safeForNameCorrection ? procedure.name : cleanedSourceTitle(row.rawText, fallback: procedure.name)
        procedureType = procedure.name
        mealType = nil
      } else {
        continue
      }

      let stableId = "ocr-\(version)-\(index + 1)"
      events.append(ScheduleEvent(
        stableId: stableId,
        date: date,
        start: start,
        end: end,
        title: title,
        location: "Neuvedeno v rozpisu",
        kind: isMeal ? .meal : .procedure,
        procedureType: procedureType,
        mealType: mealType,
        leadTimeMinutes: isMeal ? 10 : 20
      ))
    }

    events.sort { ($0.date, $0.start, $0.stableId) < ($1.date, $1.start, $1.stableId) }
    guard let firstDate = events.first?.date, let lastDate = events.last?.date else {
      throw NSError(
        domain: "LazenskyCommander.OCR",
        code: 23,
        userInfo: [NSLocalizedDescriptionKey: "Z rozpisu nevznikla žádná použitelná událost."]
      )
    }

    let iso = ISO8601DateFormatter()
    let schedule = Schedule(
      schemaVersion: 1,
      scheduleVersion: version,
      updatedAt: iso.string(from: now),
      stay: [
        "spa": extraction.facility?.name ?? "Lázeňský pobyt",
        "dateFrom": firstDate,
        "dateTo": lastDate,
        "source": "Lokální OCR · klientský rozpis"
      ],
      events: events,
      settings: ScheduleSettings(
        defaultLeadTimeMinutes: 20,
        procedureTypeOverrides: [:],
        mealOverrides: ["Snídaně": 10, "Oběd": 10, "Večeře": 10]
      )
    )
    try NativeAlarmContract.validateCanonical(schedule)
    return schedule
  }

  private static func canonicalDate(_ token: String, near reference: Date) -> String? {
    let pieces = token
      .replacingOccurrences(of: "/", with: ".")
      .replacingOccurrences(of: "-", with: ".")
      .split(separator: ".")
      .compactMap { Int($0) }
    guard pieces.count >= 2 else { return nil }
    let day = pieces[0]
    let month = pieces[1]
    let calendar = Calendar(identifier: .gregorian)
    let timeZone = TimeZone(identifier: "Europe/Prague")!
    var prague = calendar
    prague.timeZone = timeZone
    let referenceYear = prague.component(.year, from: reference)

    let years: [Int]
    if pieces.count >= 3 {
      let raw = pieces[2]
      years = [raw < 100 ? 2000 + raw : raw]
    } else {
      years = [referenceYear - 1, referenceYear, referenceYear + 1]
    }

    let candidates = years.compactMap { year -> Date? in
      var c = DateComponents()
      c.calendar = prague
      c.timeZone = timeZone
      c.year = year
      c.month = month
      c.day = day
      c.hour = 12
      return prague.date(from: c)
    }
    guard let chosen = candidates.min(by: { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }) else { return nil }
    let formatter = DateFormatter()
    formatter.calendar = prague
    formatter.timeZone = timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: chosen)
  }

  private static func mealTitle(_ value: String) -> String {
    switch value {
    case "breakfast": return "Snídaně"
    case "lunch": return "Oběd"
    case "dinner": return "Večeře"
    default: return value
    }
  }

  private static func cleanedSourceTitle(_ raw: String, fallback: String) -> String {
    var value = raw
    value = value.replacingOccurrences(
      of: #"\b(?:[01]?\d|2[0-3])[:.]\d{2}\b|\b(?:[0-3]?\d)[./-](?:[01]?\d)(?:[./-](?:\d{2}|\d{4}))?\b"#,
      with: " ",
      options: .regularExpression
    )
    value = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–—|:;")))
    return value.count >= 3 ? value : fallback
  }
}

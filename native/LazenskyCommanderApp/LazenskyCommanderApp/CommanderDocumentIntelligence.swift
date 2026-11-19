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
    let lines = page.lines.flatMap(cells)
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

  private static func cells(_ line: CommanderOCRLine) -> [CommanderMergedOCRLine] {
    var groups: [[CommanderOCRWord]] = []
    for word in line.words.filter({ $0.bounds.width > 0 }).sorted(by: { $0.bounds.x < $1.bounds.x }) {
      if let previous = groups.last?.last, word.bounds.x - previous.bounds.x - previous.bounds.width <= 0.035 {
        groups[groups.count - 1].append(word)
      } else {
        groups.append([word])
      }
    }
    guard groups.count > 1 else { return [single(line)] }
    return groups.compactMap { group in
      guard let left = group.first?.bounds.x, let right = group.map({ $0.bounds.x + $0.bounds.width }).max(),
            let top = group.map(\.bounds.y).min(), let bottom = group.map({ $0.bounds.y + $0.bounds.height }).max() else { return nil }
      let original = single(line)
      return .init(text: group.map(\.text).joined(separator: " "), confidence: original.confidence,
        bounds: .init(x: left, y: top, width: right - left, height: bottom - top),
        state: original.state, criticalConflict: original.criticalConflict, alternateText: original.alternateText)
    }
  }

  private static func single(_ line: CommanderOCRLine) -> CommanderMergedOCRLine {
    let primary = criticalTokens(line.text)
    let alternate = line.alternatives.dropFirst().first { line.confidence - $0.confidence <= 0.025 && criticalTokens($0.text) != primary }
    return .init(text: line.text, confidence: line.confidence >= 0.5 ? max(0.69, line.confidence) : line.confidence, bounds: line.bounds,
      state: alternate == nil ? .singleSource : .conflict, criticalConflict: alternate != nil, alternateText: alternate?.text)
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

  static func loadBundled(override: URL? = nil) throws -> CommanderSpaOCRLexicon {
    guard let url = override ?? Bundle.main.url(forResource: "commander-ocr-lexicon-v1", withExtension: "json") else {
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
  var endTimeToken: String?
  let title: String
  var location: String?
  let meal: String?
  var issue: String?
  var requiresReview: Bool { issue != nil }
}

struct CommanderDocumentExtraction: Codable, Equatable, Sendable {
  let facility: CommanderFacilityMatch?
  var rows: [CommanderDocumentCandidateRow]
  var details: PaperScheduleDetails? = nil
  var headerIssues: [String: String] = [:]
  var reviewCount: Int { rows.filter(\.requiresReview).count + headerIssues.count }
  var hasRecognizedContent: Bool {
    !rows.isEmpty || details != nil || !headerIssues.isEmpty
  }
  var readyWithoutQuestions: Bool { !rows.isEmpty && reviewCount == 0 }
}


final class CommanderPaperDocumentReader {
  static let fields: [(key: String, label: String)] = [
    ("patient", "Pacient"),
    ("spa", "Lázně"),
    ("dateFrom", "Pobyt od"),
    ("dateTo", "Pobyt do"),
    ("building", "Budova"),
    ("floor", "Patro"),
    ("room", "Pokoj"),
    ("doctor", "Ošetřující lékař"),
    ("diagnosis", "Diagnóza"),
    ("mealShift", "Stravovací směna"),
    ("notes", "Poznámka")
  ]
  private static let aliases: [String: String] = [
    "pacient": "patient",
    "jmeno": "patient",
    "jmeno pacienta": "patient",
    "klient": "patient",
    "prijmeni a jmeno": "patient",
    "jmeno a prijmeni": "patient",
    "lazne": "spa",
    "zarizeni": "spa",
    "lecebna": "spa",
    "pobyt": "period",
    "termin": "period",
    "termin pobytu": "period",
    "doba pobytu": "period",
    "datum nastupu": "dateFrom",
    "datum prijezdu": "dateFrom",
    "pobyt od": "dateFrom",
    "od": "dateFrom",
    "nastup": "dateFrom",
    "datum ukonceni": "dateTo",
    "datum odjezdu": "dateTo",
    "pobyt do": "dateTo",
    "do": "dateTo",
    "ukonceni pobytu": "dateTo",
    "budova": "building",
    "pavilon": "building",
    "patro": "floor",
    "podlazi": "floor",
    "pokoj": "room",
    "cislo pokoje": "room",
    "ubytovani": "room",
    "ubytovan": "room",
    "lekar": "doctor",
    "osetrujici lekar": "doctor",
    "lekarka": "doctor",
    "diagnoza": "diagnosis",
    "dg": "diagnosis",
    "hlavni diagnoza": "diagnosis",
    "stravovaci smena": "mealShift",
    "strava": "mealShift",
    "poznamka": "notes"
  ]
  private static let label = try! NSRegularExpression(pattern: "(?i)(?<![\\p{L}\\d])(" +
    aliases.keys.sorted { $0.count > $1.count }.map { key in
      key.map { character in
        switch character {
        case " ": return "\\s+"
        case "a": return "[aá]"
        case "c": return "[cč]"
        case "d": return "[dď]"
        case "e": return "[eéě]"
        case "i": return "[ií]"
        case "n": return "[nň]"
        case "o": return "[oó]"
        case "r": return "[rř]"
        case "s": return "[sš]"
        case "t": return "[tť]"
        case "u": return "[uúů]"
        case "y": return "[yý]"
        case "z": return "[zž]"
        default: return String(character)
        }
      }.joined()
    }.joined(separator: "|") + ")\\.?\\s*:")
  private static let periodDate = try! NSRegularExpression(pattern: #"\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}\s*[./]\s*\d{1,2}\s*[./]\s*\d{4})\b"#)
  private static let quantity = try! NSRegularExpression(pattern: #"(?i)^\s*(\d{1,3})\s*(?:[x×]|krát|ks)?\s*$"#)
  private static let counted = try! NSRegularExpression(pattern: #"(?i)^(.+?)\s+(\d{1,3})\s*[x×](?:\s+(.+))?$"#)
  private(set) var issues: [String: String] = [:]
  private var values: [String: String] = [:]
  private var prescriptions: [SchedulePrescription] = []
  var details: PaperScheduleDetails? {
    values.isEmpty && prescriptions.isEmpty ? nil : .init(fields: values, prescriptions: prescriptions)
  }

  static func key(_ text: String) -> String { CommanderOCRReconciler.normalize(text) }
  static func summaryHeading(_ text: String) -> Bool {
    key(text).range(of: #"^(?:(?:seznam|souhrn|prehled|rozpis)\s+)?(?:predepsane|predepsanych|ordinovane|ordinovanych|indikovane|indikovanych)\s+(?:procedury|procedur|terapie|terapii|vykony|vykonu)\b|^(?:predpis|souhrn|prehled)\s+(?:procedur|terapii|vykonu)\b"#, options: .regularExpression) != nil
  }
  static func dailyHeading(_ text: String) -> Bool {
    key(text).range(of: #"^(?:denni|casovy|terminovy|procedurovy)\s+rozpis\b|^rozpis\s+(?:procedur|terapii|lecby)\b|^naplanovane\s+(?:procedury|terapie)\b"#, options: .regularExpression) != nil
  }
  static func furniture(_ text: String) -> Bool {
    key(text).range(of: #"^(?:strana|str|tisk|vytisteno|datum tisku|vytvoreno|kontakt|telefon|tel|mobil|email|www|https|ico|dic|psc|adresa|recepce|provozni doba|lecebny prukaz|razitko|podpis|poznamka|pouceni|vysvetlivky|celkem)(?:\s|$)"#, options: .regularExpression) != nil
  }
  static func countHeader(_ key: String) -> Bool {
    ["pocet", "pocet x", "predepsano", "pocet procedur", "pocet opakovani", "mnozstvi"].contains(key)
  }
  static func procedureHeader(_ key: String) -> Bool {
    ["procedura", "nazev", "nazev procedury", "terapie", "nazev terapie", "vykon"].contains(key)
  }
  private static func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
    regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
  }

  func captureHeader(_ cells: [String], inSchedule: Bool, startAtBeginning: Bool, canonicalDate: (String) -> String?) -> Bool {
    guard !startAtBeginning else { return false }
    let matches = cells.map { Self.matches(Self.label, $0) }
    if inSchedule {
      let keys = zip(cells, matches).flatMap { cell, labels in
        labels.compactMap { Range($0.range(at: 1), in: cell).flatMap { Self.aliases[Self.key(String(cell[$0]))] } }
      }
      if !keys.contains(where: { ["patient", "doctor", "diagnosis", "period", "dateFrom", "dateTo"].contains($0) }) { return false }
    }
    var captured = false
    var index = 0
    while index < cells.count {
      let cell = cells[index]
      let labels = matches[index]
      var useNext = false
      if labels.isEmpty, !inSchedule, let key = Self.aliases[Self.key(cell)],
         index + 1 < cells.count, matches[index + 1].isEmpty, Self.aliases[Self.key(cells[index + 1])] == nil {
        set(key, cells[index + 1], canonicalDate: canonicalDate)
        captured = true
        useNext = true
      }
      for (offset, label) in labels.enumerated() {
        guard let range = Range(label.range, in: cell), let keyRange = Range(label.range(at: 1), in: cell),
              let key = Self.aliases[Self.key(String(cell[keyRange]))] else { continue }
        let next = offset + 1 < labels.count ? Range(labels[offset + 1].range, in: cell)?.lowerBound : nil
        let value = String(cell[range.upperBound..<(next ?? cell.endIndex)])
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           next == nil, index + 1 < cells.count, matches[index + 1].isEmpty, Self.aliases[Self.key(cells[index + 1])] == nil {
          set(key, cells[index + 1], canonicalDate: canonicalDate)
          useNext = true
        } else {
          set(key, value, canonicalDate: canonicalDate)
        }
        captured = true
      }
      index += useNext ? 2 : 1
    }
    return captured
  }

  private func add(_ key: String, _ value: String) {
    if let old = values[key], Self.key(old) != Self.key(value) {
      issues[key] = "V podkladech jsou pro tento údaj různé hodnoty."
    } else {
      values[key] = value
    }
  }

  private func set(_ key: String, _ raw: String, canonicalDate: (String) -> String?) {
    let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t|;,"))
    guard !value.isEmpty else { return }
    if key == "period" {
      let dates = Self.matches(Self.periodDate, value).compactMap { Range($0.range, in: value).flatMap { canonicalDate(String(value[$0])) } }
      if dates.count == 2 {
        add("dateFrom", dates[0]); add("dateTo", dates[1])
      } else { issues["dateFrom"] = "Termín pobytu se nepodařilo přečíst včetně roku." }
    } else if key == "dateFrom" || key == "dateTo" {
      if let date = canonicalDate(value) { add(key, date) }
      else { issues[key] = "Datum pobytu se nepodařilo přečíst včetně roku." }
    } else { add(key, value) }
  }

  func capturePrescription(_ cells: [String], titleIndex: Int?, countIndex: Int?, noteIndex: Int?) {
    guard let first = cells.first else { return }
    func value(_ index: Int?) -> String? { index.map { cells[$0].trimmingCharacters(in: .whitespacesAndNewlines) } }
    var title = value(titleIndex) ?? first
    var note = value(noteIndex)
    var count: Int?
    func number(_ text: String) -> Int? {
      Self.matches(Self.quantity, text).first.flatMap { Range($0.range(at: 1), in: text) }.flatMap { Int(text[$0]) }
    }
    if let explicit = value(countIndex) {
      count = number(explicit)
    } else if cells.count == 1, let match = Self.matches(Self.counted, title).first,
              let nameRange = Range(match.range(at: 1), in: title), let countRange = Range(match.range(at: 2), in: title) {
      count = Int(title[countRange])
      note = Range(match.range(at: 3), in: title).map { String(title[$0]) }
      title = String(title[nameRange])
    } else if titleIndex == nil && cells.count >= 2, let quantity = number(cells[1]) {
      count = quantity
      if cells.count > 2 { note = cells.dropFirst(2).joined(separator: " ") }
    }
    guard count.map({ $0 > 0 }) ?? (titleIndex != nil),
          title.range(of: #"\p{L}"#, options: .regularExpression) != nil,
          !Self.furniture(title), !Self.procedureHeader(Self.key(title)) else { return }
    let entry = SchedulePrescription(title: title, count: count, note: note == "" ? nil : note)
    if !prescriptions.contains(where: {
      Self.key($0.title) == Self.key(entry.title) && $0.count == entry.count && Self.key($0.note ?? "") == Self.key(entry.note ?? "")
    }) { prescriptions.append(entry) }
  }
}

enum CommanderDocumentExtractor {
  private static let dates = try! NSRegularExpression(pattern: #"(?<![\p{L}\d:])(?:\d{4}-\d{2}-\d{2}|\d{1,2}\s*[./]\s*\d{1,2}(?:\s*[./]\s*\d{4}|\s*\.)?)(?![\d:/])"#)
  private static let clock = try! NSRegularExpression(pattern: #"(?<![\p{L}\d:])\d{1,2}\s*:\s*\d{2}(?![\d:])"#)
  private static let place = try! NSRegularExpression(pattern: #"(?i)(?:^|\s)(?:m[íi]stnost|budova|pavilon|patro|kabina|ordinace|m[íi]sto)\s+\S.*$"#)
  private static let timeHeads = ["cas", "zacatek", "cas zacatku", "od", "cas od", "zacina", "hodina"]
  private static let startsWithClock = try! NSRegularExpression(pattern: #"(?i)^\s*(?:[|–—•-]\s*)?(?:v\s+)?[0-9O]{1,2}\s*:\s*[0-9O]{2}(?![\d:])"#)
  private static let dateHeadingPattern = try! NSRegularExpression(pattern: #"(?i)^\s*(?:(?:pond[eě]l[ií]|[uú]ter[yý]|st[rř]eda|[cč]tvrtek|p[aá]tek|sobota|ned[eě]le|datum)\s*[:,]?\s*)?(?:\d{4}-\d{2}-\d{2}|\d{1,2}\s*[./]\s*\d{1,2}(?:\s*[./]\s*\d{4}|\s*\.)?)\s*(?:(?:pond[eě]l[ií]|[uú]ter[yý]|st[rř]eda|[cč]tvrtek|p[aá]tek|sobota|ned[eě]le))?\s*$"#)
  private static let headers = timeHeads + ["datum", "den", "misto", "mistnost", "budova", "do", "konec", "cas do", "odchod", "cas odchodu", "poznamka", "kod", "trvani", "poradi"]

  static func extract(_ page: CommanderMergedOCRPage, lexicon: CommanderSpaOCRLexicon) -> CommanderDocumentExtraction {
    extract([page], lexicon: lexicon)
  }

  static func extract(_ pages: [CommanderMergedOCRPage], lexicon: CommanderSpaOCRLexicon) -> CommanderDocumentExtraction {
    struct Key: Hashable {
      let date: String?
      let time: String?
      let title: String
      let unresolved: String?
    }
    var keys: [Key] = []
    var groups: [Key: [CommanderDocumentCandidateRow]] = [:]
    let document = CommanderPaperDocumentReader()
    for row in pages.flatMap({ parsePage($0, document: document) }) {
      let key = Key(date: row.dateToken, time: row.timeToken, title: nameKey(row.title),
                    unresolved: row.dateToken == nil || row.timeToken == nil || row.title.isEmpty ? row.rawText : nil)
      if groups[key] == nil { keys.append(key) }
      groups[key, default: []].append(row)
    }
    var rows = keys.compactMap { key -> CommanderDocumentCandidateRow? in
      guard let values = groups[key], var best = values.first(where: { !$0.requiresReview }) ?? values.first else { return nil }
      let ends = Set(values.compactMap(\.endTimeToken))
      let places = values.compactMap(\.location)
      let distinctPlaces = Set(places.map { $0.lowercased() })
      if ends.count == 1 { best.endTimeToken = ends.first }
      if distinctPlaces.count == 1 { best.location = places.first }
      if ends.count > 1 || distinctPlaces.count > 1 { best.issue = "Snímky se liší v čase konce nebo místě." }
      return best
    }
    let facility = lexicon.match(fullText: pages.map(\.text).joined(separator: "\n"), candidateLines: []).facility
    if pages.count > 1 {
      let valid = rows.filter { !$0.requiresReview }
      for index in rows.indices where !rows[index].requiresReview {
        let row = rows[index]
        if valid.contains(where: { other in
          guard row.dateToken == other.dateToken, nameKey(row.title) == nameKey(other.title),
                let first = row.timeToken, let second = other.timeToken, first != second else { return false }
          return abs(clockMinutes(first) - clockMinutes(second)) <= 4
        }) {
          rows[index].issue = "Na snímcích jsou dva podobné časy. Zkontroluj, zda jde o stejnou položku."
        }
      }
    }
    var result = CommanderDocumentExtraction(facility: facility, rows: rows,
      details: document.details, headerIssues: document.issues)
    result.headerIssues = validateHeader(result, unresolved: result.headerIssues)
    return result
  }

  private static func center(_ line: CommanderMergedOCRLine) -> Double { line.bounds.y + line.bounds.height / 2 }

  private static func parsePage(_ page: CommanderMergedOCRPage, document: CommanderPaperDocumentReader) -> [CommanderDocumentCandidateRow] {
    let lines = page.lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let starts = lines.filter { timeHeads.contains(nameKey($0.text)) }
    for first in starts {
      if let second = starts.first(where: { abs(center(first) - center($0)) < 0.015 && $0.bounds.x - first.bounds.x > 0.30 }) {
        let gutter = second.bounds.x - 0.07
        if !lines.contains(where: { $0.bounds.x < gutter && $0.bounds.x + $0.bounds.width > gutter }) {
          return parseLane(lines.filter { $0.bounds.x < gutter }, document: document) + parseLane(lines.filter { $0.bounds.x >= gutter }, document: document)
        }
      }
    }
    return parseLane(lines, document: document)
  }

  private static func parseLane(_ input: [CommanderMergedOCRLine], document: CommanderPaperDocumentReader) -> [CommanderDocumentCandidateRow] {
    let lines = input.sorted { center($0) < center($1) }
    let heights = lines.map(\.bounds.height).filter { $0 > 0 }.sorted()
    let tolerance = heights.isEmpty ? 0.006 : min(0.014, max(0.004, heights[heights.count / 2] * 0.58))
    var result: [CommanderDocumentCandidateRow] = []
    var date: String?
    var yearContext: String?
    var columns: [(x: Double, name: String)] = []
    var summary = false
    var inSchedule = false
    var seenMetadata = false
    var prescriptionColumns: [(x: Double, name: String)] = []
    var index = 0
    while index < lines.count {
      let anchor = center(lines[index])
      var cells = [lines[index]]
      index += 1
      while index < lines.count && center(lines[index]) - anchor <= tolerance {
        cells.append(lines[index])
        index += 1
      }
      cells.sort { $0.bounds.x < $1.bounds.x }
      var raw = cells.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " | ")
      let texts = cells.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
      let normalized = texts.map(nameKey)
      if CommanderPaperDocumentReader.summaryHeading(raw) {
        summary = true; inSchedule = false; columns = []; prescriptionColumns = []; date = nil
        continue
      }
      if CommanderPaperDocumentReader.dailyHeading(raw) {
        summary = false; inSchedule = true; columns = []; date = nil
        continue
      }
      if normalized.contains(where: CommanderPaperDocumentReader.procedureHeader),
         normalized.contains(where: CommanderPaperDocumentReader.countHeader), !normalized.contains(where: timeHeads.contains) {
        prescriptionColumns = zip(cells, normalized).map { ($0.0.bounds.x, $0.1) }
        summary = true; inSchedule = false; columns = []; date = nil
        continue
      }
      if normalized.contains(where: timeHeads.contains), normalized.contains(where: CommanderPaperDocumentReader.procedureHeader) {
        columns = zip(cells, normalized).map { ($0.0.bounds.x, $0.1) }
          .filter { headers.contains($0.1) || CommanderPaperDocumentReader.procedureHeader($0.1) }
        summary = false; inSchedule = true
        continue
      }
      let heading = cells.first {
        !matches(dateHeadingPattern, in: $0.text).isEmpty &&
        nameKey($0.text).range(of: #"\b(?:pondeli|utery|streda|ctvrtek|patek|sobota|nedele)\b"#, options: .regularExpression) != nil
      }
      let joined = texts.joined(separator: " ")
      let dateHeading = heading != nil || (!matches(dateHeadingPattern, in: joined).isEmpty && (!seenMetadata || inSchedule || summary))
      if CommanderPaperDocumentReader.furniture(raw) && !nameKey(raw).hasPrefix("poznamka") { continue }
      let startsWithTime = !matches(startsWithClock, in: raw).isEmpty
      if !summary, document.captureHeader(texts, inSchedule: inSchedule, startAtBeginning: startsWithTime,
                                         canonicalDate: { resolveDate($0, context: nil) }) { seenMetadata = true; continue }
      if summary && !dateHeading {
        func at(_ predicate: (String) -> Bool) -> Int? {
          cells.firstIndex { cell in prescriptionColumns.contains { predicate($0.name) && abs(cell.bounds.x - $0.x) <= 0.055 } }
        }
        document.capturePrescription(texts, titleIndex: at(CommanderPaperDocumentReader.procedureHeader),
          countIndex: at(CommanderPaperDocumentReader.countHeader), noteIndex: at { $0 == "poznamka" })
        continue
      }
      if dateHeading {
        summary = false; inSchedule = true
        let headingText = heading?.text ?? joined
        let good = heading.map { !$0.criticalConflict && $0.confidence >= 0.66 }
          ?? cells.allSatisfy { !$0.criticalConflict && $0.confidence >= 0.66 }
        date = good ? matches(dates, in: headingText).first.flatMap { resolveDate(String(headingText[$0.range]), context: yearContext) } : nil
        if let date { yearContext = date }
        continue
      }
      if CommanderPaperDocumentReader.furniture(raw) { continue }
      if !inSchedule && seenMetadata && columns.isEmpty { continue }
      // A separate time cell anchors the title. Distant marginal notes do not belong to it.
      if columns.isEmpty, cells.count > 1, let first = cells.first,
         first.text.range(of: #"^\s*\d{1,2}\s*:\s*\d{2}\s*$"#, options: .regularExpression) != nil {
        cells = cells.filter { $0.bounds.x - first.bounds.x <= 0.32 || !matches(place, in: $0.text).isEmpty }
        raw = cells.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " | ")
      }
      let good = cells.allSatisfy { !$0.criticalConflict && $0.confidence >= 0.66 }
      let firstClock = matches(clock, in: raw).first?.range.lowerBound
      var dateMatches = matches(dates, in: raw).filter { match in
        let value = String(raw[match.range])
        return dateHeading || value.contains("/") || value.hasSuffix(".") || value.filter { $0 == "." }.count >= 2
          || value.contains("-") || firstClock.map { match.range.lowerBound < $0 } == true
      }
      let tableStartAt = cells.contains { cell in
        columns.contains { timeHeads.contains($0.name) && abs($0.x - cell.bounds.x) <= 0.055 }
          && !matches(clock, in: cell.text).isEmpty
      }
      let dateBeforeTime = dateMatches.first.map {
        !matches(startsWithClock, in: String(raw[$0.range.upperBound...])).isEmpty
      } == true
      if (!dateMatches.isEmpty && (startsWithTime || tableStartAt || dateBeforeTime)) {
        date = dateMatches.count == 1 && good ? resolveDate(String(raw[dateMatches[0].range]), context: yearContext) : nil
        if let date { yearContext = date }
      } else { dateMatches = [] }
      var eventCells: [String] = []
      var locations: [String] = []
      var leaveCount = 0
      let hasStartColumn = columns.contains { timeHeads.contains($0.name) }
      var foundStart = !hasStartColumn
      var labelledEnd: String?
      var badEnd = false
      for cell in cells {
        let column = columns.min { abs($0.x - cell.bounds.x) < abs($1.x - cell.bounds.x) }
        let field = column.flatMap { abs($0.x - cell.bounds.x) <= 0.055 ? $0.name : nil }
        let text = cell.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if field == "misto" || field == "mistnost" || field == "budova" {
          locations.append(text)
        } else if field == "odchod" || field == "cas odchodu" {
          leaveCount += matches(clock, in: text).count
        } else if field == "do" || field == "konec" || field == "cas do" {
          labelledEnd = matches(clock, in: text).first.flatMap { time(String(text[$0.range])) }
          badEnd = labelledEnd == nil && !["", "-", "–", "—"].contains(text)
        } else if !["poznamka", "kod", "trvani", "poradi"].contains(field ?? "") {
          if let field, timeHeads.contains(field), !matches(clock, in: text).isEmpty { foundStart = true }
          eventCells.append(text)
        }
      }
      let missingStart = !foundStart
      let contents = eventCells.joined(separator: " | ")
      var withoutDate = dateMatches.count == 1 ? contents.replacingOccurrences(of: String(raw[dateMatches[0].range]), with: " ") : contents
      if let location = matches(place, in: withoutDate).first {
        locations.append(withoutDate[location.range].trimmingCharacters(in: .whitespacesAndNewlines))
        withoutDate = String(withoutDate[..<location.range.lowerBound])
      }
      let departurePattern = #"(?i)\b(?:čas\s+)?odchod\s*[:]?\s*\d{1,2}\s*:\s*\d{2}"#
      if withoutDate.range(of: departurePattern, options: .regularExpression) != nil {
        leaveCount += 1
        withoutDate = withoutDate.replacingOccurrences(of: departurePattern, with: " ", options: .regularExpression)
      }
      let times = matches(clock, in: withoutDate)
      let title = clean(clock.stringByReplacingMatches(in: withoutDate, range: NSRange(withoutDate.startIndex..., in: withoutDate), withTemplate: " ").replacingOccurrences(of: "|", with: " "))
      if times.isEmpty && leaveCount == 0 && !badEnd && labelledEnd == nil &&
        title.isEmpty { continue }
      let procedureCell = cells.contains { cell in
        columns.contains { CommanderPaperDocumentReader.procedureHeader($0.name) && abs($0.x - cell.bounds.x) <= 0.055 }
          && cell.text.range(of: #"\p{L}"#, options: .regularExpression) != nil
      }
      let timed = startsWithTime || tableStartAt ||
        !matches(startsWithClock, in: withoutDate.trimmingCharacters(in: CharacterSet(charactersIn: " |"))).isEmpty
      let incompleteTableRow = procedureCell && (labelledEnd != nil || badEnd || leaveCount > 0)
      if (!timed && !incompleteTableRow) || (title.range(of: #"\p{L}"#, options: .regularExpression) == nil && times.isEmpty) { continue }
      var start = (1...2).contains(times.count) ? time(String(withoutDate[times[0].range])) : nil
      var end = labelledEnd ?? (times.count == 2 ? time(String(withoutDate[times[1].range])) : nil)
      let separatedTimes = times.count == 2 && withoutDate[times[0].range.upperBound..<times[1].range.lowerBound].range(of: #"(?i)^\s*(?:[-–—|]|do|až)?\s*$"#, options: .regularExpression) == nil
      if separatedTimes || missingStart { start = nil; end = nil }
      let issue: String?
      if !good { issue = "Některé údaje v řádku nejsou dobře čitelné." }
      else if date == nil { issue = "Chybí jednoznačné datum včetně roku." }
      else if start == nil || badEnd || (times.count == 2 && end == nil) || (end.map { $0 < (start ?? "") } ?? false) { issue = "Čas procedury není jednoznačný." }
      else if title.isEmpty { issue = "Chybí název procedury nebo jídla." }
      else { issue = nil }
      result.append(makeRow(raw, date: date, start: start, end: end, title: title,
                            location: locations.isEmpty ? nil : locations.joined(separator: ", "), issue: issue))
    }
    return result
  }

  static func validateHeader(_ extraction: CommanderDocumentExtraction, unresolved: [String: String]) -> [String: String] {
    var issues = unresolved
    let from = extraction.details?.fields["dateFrom"]
    let to = extraction.details?.fields["dateTo"]
    let invalid = from.map { resolveDate($0, context: nil) != $0 } == true ||
      to.map { resolveDate($0, context: nil) != $0 } == true ||
      (from != nil && to != nil && from! > to!)
    let outside = extraction.rows.compactMap(\.dateToken).contains { day in
      from.map { day < $0 } == true || to.map { day > $0 } == true
    }
    if invalid || outside { issues["dateFrom"] = "Termín pobytu nesouhlasí s daty denního rozpisu." }
    return issues
  }

  static func headerDate(_ value: String) -> String? { resolveDate(value, context: nil) }

  static func correct(_ row: CommanderDocumentCandidateRow, date: String, start: String, end: String, title: String, location: String) -> CommanderDocumentCandidateRow? {
    let endInput = end.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let finish = endInput.isEmpty ? nil : time(endInput)
    guard let resolved = resolveDate(date.trimmingCharacters(in: .whitespacesAndNewlines), context: nil),
          let start = time(start.trimmingCharacters(in: .whitespacesAndNewlines)), !name.isEmpty,
          endInput.isEmpty || (finish.map { $0 >= start } == true) else { return nil }
    return makeRow(row.rawText, date: resolved, start: start, end: finish, title: name,
                   location: location.trimmingCharacters(in: .whitespacesAndNewlines), issue: nil)
  }

  private static func makeRow(_ raw: String, date: String?, start: String?, end: String?, title: String, location: String?, issue: String?) -> CommanderDocumentCandidateRow {
    let meals = ["snidane": "Snídaně", "obed": "Oběd", "vecere": "Večeře"]
    return .init(rawText: raw, dateToken: date, timeToken: start, endTimeToken: end, title: title,
                 location: location == "" ? nil : location, meal: meals[nameKey(title)], issue: issue)
  }

  private static func clockMinutes(_ value: String) -> Int {
    let fields = value.split(separator: ":")
    return (Int(fields[0]) ?? 0) * 60 + (Int(fields[1]) ?? 0)
  }

  private static func nameKey(_ text: String) -> String { CommanderOCRReconciler.normalize(text) }
  private static func clean(_ value: String) -> String {
    value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: " -–—|:;"))
  }

  private static func matches(_ regex: NSRegularExpression, in value: String) -> [(range: Range<String.Index>, match: NSTextCheckingResult)] {
    regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap { match in
      Range(match.range, in: value).map { ($0, match) }
    }
  }

  private static func time(_ value: String) -> String? {
    let parts = value.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    let minutes = parts[1].trimmingCharacters(in: .whitespaces)
    guard minutes.count == 2, let hour = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let minute = Int(minutes), (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
    return String(format: "%02d:%02d", hour, minute)
  }

  private static func resolveDate(_ value: String, context: String?) -> String? {
    let token = value.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    var parts = token.replacingOccurrences(of: "/", with: ".").split(separator: ".", omittingEmptySubsequences: false)
    if token.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
      parts = Array(token.split(separator: "-").reversed())
    }
    guard (2...3).contains(parts.count), let day = Int(parts[0]), let month = Int(parts[1]) else { return nil }
    let year: Int
    if parts.count == 3, parts[2].count == 4, let explicit = Int(parts[2]) { year = explicit }
    else if parts.count == 2, let nearby = context?.split(separator: "-"), let nearbyYear = Int(nearby[0]), let nearbyMonth = Int(nearby[1]) {
      year = nearbyYear + (nearbyMonth - month > 6 ? 1 : month - nearbyMonth > 6 ? -1 : 0)
    } else { return nil }
    let calendar = Calendar(identifier: .gregorian)
    guard (1900...9999).contains(year), (1...12).contains(month), day > 0,
          let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
          let days = calendar.range(of: .day, in: .month, for: first), days.contains(day) else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}

enum CommanderCanonicalScheduleBuilder {
  static func build(from extraction: CommanderDocumentExtraction, now: Date = Date()) throws -> Schedule {
    guard extraction.readyWithoutQuestions else {
      throw NSError(domain: "LazenskyCommander.OCR", code: 20,
        userInfo: [NSLocalizedDescriptionKey: "Rozpis obsahuje údaje, které je potřeba před použitím zkontrolovat."])
    }
    struct Key: Hashable {
      let date: String
      let start: String
      let end: String
      let title: String
      let place: String?
    }
    let version = max(1, Int(now.timeIntervalSince1970))
    var seen: Set<Key> = []
    var events: [ScheduleEvent] = []
    let sorted = extraction.rows.sorted { ($0.dateToken ?? "", $0.timeToken ?? "", $0.title) < ($1.dateToken ?? "", $1.timeToken ?? "", $1.title) }
    for row in sorted {
      guard let date = row.dateToken, let start = row.timeToken else { throw CocoaError(.fileReadCorruptFile) }
      let end = row.endTimeToken ?? start
      guard seen.insert(Key(date: date, start: start, end: end, title: row.title, place: row.location)).inserted else { continue }
      events.append(ScheduleEvent(stableId: "ocr-\(version)-\(events.count + 1)", date: date, start: start, end: end,
        title: row.title, location: row.location ?? "Neuvedeno v rozpisu",
        kind: row.meal == nil ? .procedure : .meal, procedureType: nil, mealType: row.meal,
        leadTimeMinutes: row.meal == nil ? 20 : 10))
    }
    guard let firstDate = events.first?.date, let lastDate = events.last?.date else { throw CocoaError(.fileReadCorruptFile) }
    let schedule = Schedule(schemaVersion: 1, scheduleVersion: version, updatedAt: ISO8601DateFormatter().string(from: now),
      stay: ["spa": extraction.details?.fields["spa"] ?? extraction.facility?.name ?? "Lázeňský pobyt",
        "dateFrom": extraction.details?.fields["dateFrom"] ?? firstDate,
        "dateTo": extraction.details?.fields["dateTo"] ?? lastDate, "source": "Lokální OCR · klientský rozpis"],
      events: events, settings: ScheduleSettings(defaultLeadTimeMinutes: 20, procedureTypeOverrides: [:],
        mealOverrides: ["Snídaně": 10, "Oběd": 10, "Večeře": 10]), paperDetails: extraction.details)
    try NativeAlarmContract.validateCanonical(schedule)
    return schedule
  }
}

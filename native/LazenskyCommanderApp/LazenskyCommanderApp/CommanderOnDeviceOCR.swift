import CoreGraphics
import CoreImage
import Foundation
import PDFKit
import ImageIO
@preconcurrency import Vision

struct CommanderOCRRect: Codable, Equatable, Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

struct CommanderOCRCandidate: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
}

struct CommanderOCRWord: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
  let bounds: CommanderOCRRect
}

struct CommanderOCRLine: Codable, Equatable, Sendable {
  let text: String
  let confidence: Float
  let bounds: CommanderOCRRect
  let alternatives: [CommanderOCRCandidate]
  let words: [CommanderOCRWord]
}

struct CommanderOCRPage: Codable, Equatable, Sendable {
  let text: String
  let pixelWidth: Int
  let pixelHeight: Int
  let averageConfidence: Float
  let lines: [CommanderOCRLine]

  var hasText: Bool { !lines.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum CommanderOnDeviceOCR {
  private static let rendering = CIContext(options: [.cacheIntermediates: false])
  private static let dayHeading = try! NSRegularExpression(pattern: #"\b(?:\d{4}-\d{2}-\d{2}|\d{1,2}[./]\d{1,2}[./]\d{4})\b"#)
  private static let clock = try! NSRegularExpression(pattern: #"\b\d{1,2}\s*:\s*\d{2}\b"#)

  static func recognize(cgImage: CGImage, orientation: CGImagePropertyOrientation = .up,
                        customWords: [String] = []) async throws -> CommanderOCRPage {
    try await Task.detached(priority: .userInitiated) {
      let original = try read(cgImage, orientation: orientation, customWords: customWords)
      var best = original
      if orientation == .up, let corrected = rectify(cgImage) {
        let page = try read(corrected, orientation: .up, customWords: customWords)
        if score(page) > 0 && score(original) <= score(page) * 1.12 { best = page }
      }
      if score(best) > 0 { return best }

      let quality = CommanderDocumentImageQuality.assess(cgImage)
      let input = CIImage(cgImage: cgImage)
      let enhanced = input.applyingFilter("CIColorControls", parameters: [
        kCIInputSaturationKey: 0, kCIInputContrastKey: quality.brightness < 0.25 ? 1.25 : 1.15,
        kCIInputBrightnessKey: quality.brightness < 0.25 ? 0.20 : 0
      ])
      let image = rendering.createCGImage(enhanced, from: enhanced.extent) ?? cgImage
      for rotation: CGImagePropertyOrientation in [orientation, .right, .left, .down] {
        let retry = try read(image, orientation: rotation, customWords: customWords)
        if score(retry) > score(best) { best = retry }
      }
      return best
    }.value
  }

  private static func score(_ page: CommanderOCRPage) -> Double {
    var firstDatePresent = false
    var count = 0
    var total = 0.0
    for line in page.lines {
      // Vision can read a sideways line while its coordinates span several rows.
      guard line.bounds.width * Double(page.pixelWidth) > line.bounds.height * Double(page.pixelHeight) * 1.25 else { continue }
      let range = NSRange(line.text.startIndex..., in: line.text)
      if dayHeading.firstMatch(in: line.text, range: range) != nil { firstDatePresent = true }
      let times = clock.numberOfMatches(in: line.text, range: range)
      guard times > 0 else { continue }
      let weight = 0.5 + Double(line.confidence) * 0.5
      total += Double(times) * weight + (firstDatePresent ? 2 : 0)
      count += times
    }
    return count > 0 ? total : 0
  }

  private static func rectify(_ image: CGImage) -> CGImage? {
    let request = VNDetectRectanglesRequest()
    request.minimumSize = 0.49
    request.minimumConfidence = 0.9
    request.quadratureTolerance = 23
    request.maximumObservations = 1
    guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil,
          let rectangle = request.results?.first else { return nil }
    let bounds = rectangle.boundingBox
    guard bounds.width * bounds.height > 0.50, bounds.minX > 0.015, bounds.minY > 0.015,
          bounds.maxX < 0.985, bounds.maxY < 0.985 else { return nil }
    func vector(_ point: CGPoint) -> CIVector {
      CIVector(x: point.x * Double(image.width), y: point.y * Double(image.height))
    }
    let corrected = CIImage(cgImage: image).applyingFilter("CIPerspectiveCorrection", parameters: [
      "inputTopLeft": vector(rectangle.topLeft), "inputTopRight": vector(rectangle.topRight),
      "inputBottomLeft": vector(rectangle.bottomLeft), "inputBottomRight": vector(rectangle.bottomRight)
    ])
    guard corrected.extent.width <= Double(image.width) * 1.4, corrected.extent.height <= Double(image.height) * 1.4 else { return nil }
    return rendering.createCGImage(corrected, from: corrected.extent)
  }

  private static func read(_ image: CGImage, orientation: CGImagePropertyOrientation,
                           customWords: [String]) throws -> CommanderOCRPage {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.automaticallyDetectsLanguage = true
    request.customWords = Array(Set(customWords.filter { !$0.isEmpty })).sorted()
    if let supported = try? request.supportedRecognitionLanguages() {
      let preferred = ["cs-CZ", "sk-SK", "en-US"].filter(supported.contains)
      if !preferred.isEmpty { request.recognitionLanguages = preferred }
    }
    try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
    let observations = request.results ?? []
    let slopes = observations.compactMap { observation -> Double? in
      let span = observation.topRight.x - observation.topLeft.x
      guard span > 0.06 else { return nil }
      let slope = (observation.topLeft.y - observation.topRight.y) / span
      return abs(slope) < 0.45 ? slope : nil
    }.sorted()
    let slope = slopes.count >= 3 ? slopes[slopes.count / 2] : 0
    let lines = observations.compactMap { makeLine($0, slope: slope) }
      .sorted { ($0.bounds.y, $0.bounds.x) < ($1.bounds.y, $1.bounds.x) }
    let weights = lines.reduce(into: (sum: Float(0), count: Float(0))) { total, line in
      let length = Float(max(1, line.text.count))
      total.sum += line.confidence * length
      total.count += length
    }
    let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
    return .init(text: lines.map(\.text).joined(separator: "\n"),
      pixelWidth: rotated ? image.height : image.width, pixelHeight: rotated ? image.width : image.height,
      averageConfidence: weights.count > 0 ? weights.sum / weights.count : 0, lines: lines)
  }

  private static let tokens = try! NSRegularExpression(pattern: #"\S+"#)

  private static func makeLine(_ observation: VNRecognizedTextObservation, slope: Double) -> CommanderOCRLine? {
    let candidates = observation.topCandidates(3)
    guard let best = candidates.first else { return nil }
    let alternatives = candidates.map { CommanderOCRCandidate(text: $0.string, confidence: $0.confidence) }
    let full = NSRange(best.string.startIndex..., in: best.string)
    let words = tokens.matches(in: best.string, range: full).compactMap { match -> CommanderOCRWord? in
      guard let range = Range(match.range, in: best.string), let rectangle = try? best.boundingBox(for: range) else { return nil }
      return .init(text: String(best.string[range]), confidence: best.confidence,
                   bounds: normalizedTopLeft(rectangle.boundingBox, slope: slope))
    }
    return .init(text: best.string, confidence: best.confidence,
      bounds: normalizedTopLeft(observation.boundingBox, slope: slope), alternatives: alternatives, words: words)
  }

  private static func normalizedTopLeft(_ rect: CGRect, slope: Double) -> CommanderOCRRect {
    .init(x: rect.minX, y: 1 - rect.maxY - slope * (rect.midX - 0.5), width: rect.width, height: rect.height)
  }
}


enum CommanderPDFText {
  static func read(_ page: PDFPage) -> CommanderOCRPage? {
    guard page.rotation == 0, let source = page.string else { return nil }
    let box = page.bounds(for: .mediaBox)
    guard box.width > 0, box.height > 0, source.utf16.count <= 120_000 else { return nil }
    let text = source as NSString
    let token = try! NSRegularExpression(pattern: #"\S+"#)
    var offset = 0
    var lines: [CommanderOCRLine] = []
    func rectangle(_ value: CGRect) -> CommanderOCRRect {
      .init(x: (value.minX - box.minX) / box.width,
        y: (box.maxY - value.maxY) / box.height, width: value.width / box.width, height: value.height / box.height)
    }
    while offset < text.length {
      let range = text.lineRange(for: NSRange(location: offset, length: 0))
      offset = NSMaxRange(range)
      var bounds = CGRect.null
      let words = token.matches(in: source, range: range).compactMap { match -> CommanderOCRWord? in
        guard NSMaxRange(match.range) <= page.numberOfCharacters,
              let selection = page.selection(for: match.range) else { return nil }
        let rect = selection.bounds(for: page)
        guard !rect.isEmpty, rect.intersects(box) else { return nil }
        bounds = bounds.union(rect)
        return .init(text: text.substring(with: match.range), confidence: 1, bounds: rectangle(rect))
      }
      guard !words.isEmpty, !bounds.isNull else { continue }
      lines.append(.init(text: words.map(\.text).joined(separator: " "), confidence: 1,
                         bounds: rectangle(bounds), alternatives: [], words: words))
    }
    let combined = lines.map(\.text).joined(separator: "\n")
    guard combined.filter({ $0.isLetter || $0.isNumber }).count >= 8 else { return nil }
    return .init(text: combined, pixelWidth: Int(box.width), pixelHeight: Int(box.height), averageConfidence: 1, lines: lines)
  }
}

import CoreGraphics
import Foundation
import ImageIO
import Vision

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
  static func recognize(
    cgImage: CGImage,
    orientation: CGImagePropertyOrientation = .up,
    customWords: [String] = []
  ) async throws -> CommanderOCRPage {
    try await withCheckedThrowingContinuation { continuation in
      let request = VNRecognizeTextRequest { request, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
        var lines = observations.compactMap(makeLine)
        lines.sort { lhs, rhs in
          if abs(lhs.bounds.y - rhs.bounds.y) < 0.012 { return lhs.bounds.x < rhs.bounds.x }
          return lhs.bounds.y < rhs.bounds.y
        }

        let weighted = lines.reduce(into: (sum: Float(0), weight: Float(0))) { partial, line in
          let weight = Float(max(1, line.text.count))
          partial.sum += line.confidence * weight
          partial.weight += weight
        }
        let average = weighted.weight > 0 ? weighted.sum / weighted.weight : 0
        continuation.resume(returning: CommanderOCRPage(
          text: lines.map(\.text).joined(separator: "\n"),
          pixelWidth: cgImage.width,
          pixelHeight: cgImage.height,
          averageConfidence: average,
          lines: lines
        ))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.automaticallyDetectsLanguage = true
      request.customWords = Array(Set(customWords.filter { !$0.isEmpty })).sorted()

      if let supported = try? request.supportedRecognitionLanguages() {
        let preferred = ["cs-CZ", "sk-SK", "en-US"].filter(supported.contains)
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
      }

      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
          try handler.perform([request])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func makeLine(_ observation: VNRecognizedTextObservation) -> CommanderOCRLine? {
    let candidates = observation.topCandidates(3)
    guard let best = candidates.first else { return nil }
    let alternatives = candidates.map { CommanderOCRCandidate(text: $0.string, confidence: $0.confidence) }
    var words: [CommanderOCRWord] = []

    best.string.enumerateSubstrings(
      in: best.string.startIndex..<best.string.endIndex,
      options: [.byWords, .substringNotRequired]
    ) { _, range, _, _ in
      guard let rectangle = try? best.boundingBox(for: range) else { return }
      let text = String(best.string[range])
      words.append(CommanderOCRWord(
        text: text,
        confidence: best.confidence,
        bounds: normalizedTopLeft(rectangle.boundingBox)
      ))
    }

    return CommanderOCRLine(
      text: best.string,
      confidence: best.confidence,
      bounds: normalizedTopLeft(observation.boundingBox),
      alternatives: alternatives,
      words: words
    )
  }

  private static func normalizedTopLeft(_ rect: CGRect) -> CommanderOCRRect {
    CommanderOCRRect(
      x: rect.origin.x,
      y: 1 - rect.origin.y - rect.height,
      width: rect.width,
      height: rect.height
    )
  }
}

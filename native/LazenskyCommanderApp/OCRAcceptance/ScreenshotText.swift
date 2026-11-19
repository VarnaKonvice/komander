import Foundation
import Vision

@main
enum ScreenshotText {
  static func main() throws {
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    try VNImageRequestHandler(url: url).perform([request])
    for row in request.results ?? [] {
      if let text = row.topCandidates(1).first?.string { print(text) }
    }
  }
}

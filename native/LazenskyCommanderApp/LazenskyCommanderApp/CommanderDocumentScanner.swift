import CoreGraphics
import Foundation
import PDFKit
import SwiftUI
import VisionKit

struct CommanderDocumentScanner: UIViewControllerRepresentable {
  let onComplete: ([CGImage]) -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
    let controller = VNDocumentCameraViewController()
    controller.delegate = context.coordinator
    return controller
  }

  func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

  @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
    let parent: CommanderDocumentScanner
    init(parent: CommanderDocumentScanner) { self.parent = parent }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
      let images = (0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage }
      controller.dismiss(animated: true) { self.parent.onComplete(images) }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
      controller.dismiss(animated: true) { self.parent.onCancel() }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
      controller.dismiss(animated: true) { self.parent.onCancel() }
    }
  }
}

enum CommanderDocumentImageSource {
  static func image(from data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 4200
    ] as CFDictionary)
  }

  static func recognize(from url: URL) async throws -> [CommanderOCRPage] {
    if url.pathExtension.lowercased() == "pdf" {
      guard let document = PDFDocument(url: url), (1...60).contains(document.pageCount) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      var result: [CommanderOCRPage] = []
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
        if let text = CommanderPDFText.read(page) {
          result.append(text)
        } else {
          let bounds = page.bounds(for: .mediaBox)
          let scale = 2400 / max(1, bounds.width, bounds.height)
          let thumbnail = page.thumbnail(of: CGSize(width: max(1, bounds.width * scale),
                                                    height: max(1, bounds.height * scale)), for: .mediaBox)
          guard let image = thumbnail.cgImage else { throw CocoaError(.fileReadCorruptFile) }
          result.append(try await CommanderOnDeviceOCR.recognize(cgImage: image))
        }
      }
      return result
    }
    guard let image = image(from: try Data(contentsOf: url)) else { throw CocoaError(.fileReadCorruptFile) }
    return [try await CommanderOnDeviceOCR.recognize(cgImage: image)]
  }
}

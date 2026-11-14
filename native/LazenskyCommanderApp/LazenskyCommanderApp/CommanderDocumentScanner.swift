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
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  static func images(from url: URL) throws -> [CGImage] {
    let ext = url.pathExtension.lowercased()
    if ext == "pdf" {
      guard let document = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
      var result: [CGImage] = []
      for index in 0..<document.pageCount {
        guard let page = document.page(at: index) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let targetWidth: CGFloat = 2200
        let targetHeight = max(1, targetWidth * bounds.height / max(1, bounds.width))
        let thumbnail = page.thumbnail(of: CGSize(width: targetWidth, height: targetHeight), for: .mediaBox)
        if let image = thumbnail.cgImage { result.append(image) }
      }
      return result
    }
    let data = try Data(contentsOf: url)
    guard let image = image(from: data) else { throw CocoaError(.fileReadCorruptFile) }
    return [image]
  }
}

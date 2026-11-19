import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/lc-ocr-fixtures"
try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
let root = URL(fileURLWithPath: path, isDirectory: true)
let size = CGSize(width: 1600, height: 2000)
let ciContext = CIContext()
let colorSpace = CGColorSpaceCreateDeviceRGB()
let heading = "20.11.2026"
let procedure = "10:30   Procedura ABC-17   místnost 205"
let meal = "12:00–12:30   Oběd"
let next = "21.11.2026"
let hydro = "08:00   Hydrojet"

func document(_ rows: [String], columnLayout: Bool = false) -> CIImage {
  let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
    bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor)
  ctx.fill(CGRect(origin: .zero, size: size))
  ctx.setFillColor(NSColor(white: 0.97, alpha: 1).cgColor)
  ctx.fill(CGRect(x: 100, y: 120, width: 1400, height: 1760))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  func draw(_ text: String, x: Int, y: Int, font: CGFloat = 52, bold: Bool = false) {
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
      .font: NSFont.systemFont(ofSize: font, weight: bold ? .bold : .regular), .foregroundColor: NSColor.black
    ])
  }
  if columnLayout {
    draw(heading, x: 190, y: 1610, font: 67, bold: true)
    for (index, value) in ["Začátek", "Procedura", "Místnost"].enumerated() {
      draw(value, x: [190, 560, 1140][index], y: 1430, font: 51, bold: true)
    }
    for (number, row) in [["10:30", "Procedura ABC-17", "205"], ["12:00", "Oběd", "208"]].enumerated() {
      for (index, value) in row.enumerated() {
        draw(value, x: [190, 560, 1140][index], y: 1300 - 130 * number, font: index == 2 ? 43 : 51)
      }
    }
  } else {
    for (index, row) in rows.enumerated() {
      let isDate = row.count == 10 && row.contains(".")
      draw(row, x: 190, y: 1610 - 139 * index, font: isDate ? 67 : 51, bold: isDate)
    }
  }
  NSGraphicsContext.restoreGraphicsState()
  return CIImage(cgImage: ctx.makeImage()!)
}

func save(_ name: String, _ input: CIImage) {
  let image = ciContext.createCGImage(input, from: input.extent.integral)!
  let url = root.appendingPathComponent(name + ".png")
  let sink = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(sink, image, nil)
  precondition(CGImageDestinationFinalize(sink))
}

let sample = document([heading, procedure, meal, next, hydro])
save("01-rovny", sample)
save("02-rotace-90", sample.oriented(.right))
save("03-slabe-svetlo", sample.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.27, kCIInputContrastKey: 0.64]))
save("04-rozostreni", sample.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4.2]).cropped(to: sample.extent))
let shadow = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 220, y: 450),
  "inputPoint1": CIVector(x: 1030, y: 1320), "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0.65),
  "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!.cropped(to: sample.extent)
save("05-stin", shadow.composited(over: sample))
let rotated = sample.transformed(by: CGAffineTransform(translationX: -800, y: -1000))
  .transformed(by: CGAffineTransform(rotationAngle: 0.09)).transformed(by: CGAffineTransform(translationX: 800, y: 1000))
save("06-sikmy", rotated.composited(over: CIImage(color: CIColor(red: 0.13, green: 0.13, blue: 0.13)).cropped(to: sample.extent)).cropped(to: sample.extent))
let perspective = sample.applyingFilter("CIPerspectiveTransform", parameters: [
  "inputTopLeft": CIVector(x: 240,y: 1990), "inputTopRight": CIVector(x: 1520,y: 1830),
  "inputBottomLeft": CIVector(x: 38,y: 120), "inputBottomRight": CIVector(x: 1580,y: 65)
])
save("07-perspektiva", perspective.composited(over: CIImage(color: CIColor(red: 0.13, green: 0.13, blue: 0.13)).cropped(to: sample.extent)).cropped(to: sample.extent))
save("08-sloupce", document([], columnLayout: true))
save("09-cast-a", document([heading, procedure, meal]))
save("10-cast-b", document([heading, meal, next, hydro]))
save("11-nejasny-cas", document([heading, "09:00 Masáž 10:00 Hydrojet"]))
save("12-lehke-rozostreni", sample.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.0]).cropped(to: sample.extent))

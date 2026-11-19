import AppKit
import CoreGraphics
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let width = 800
let height = 1100
let space = CGColorSpaceCreateDeviceRGB()
var media = CGRect(x: 0, y: 0, width: width, height: height)
let url = destination.appendingPathComponent("whole-document-mixed.pdf")
let pdf = CGContext(url as CFURL, mediaBox: &media, nil)!

func draw(_ canvas: CGContext, rows: [(Int, [(Int, String)])]) {
  canvas.setFillColor(gray: 1, alpha: 1)
  canvas.fill(media)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
  for (y, cells) in rows {
    for (x, text) in cells {
      (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black
      ])
    }
  }
  NSGraphicsContext.restoreGraphicsState()
}
let head: [(Int, [(Int, String)])] = [
  (1015, [(70, "Léčebný průkaz")]),
  (950, [(70, "Pacient: Testovací Osoba"), (540, "Pokoj: 317")]),
  (900, [(70, "Pobyt: 02.11.2026 – 07.11.2026")]),
  (850, [(70, "Ošetřující lékař: MUDr. Příklad"), (550, "Dg.: TEST-X")]),
  (800, [(70, "08:00–16:00 provoz recepce")]),
  (700, [(70, "Předepsané procedury")]),
  (650, [(70, "Název procedury"), (390, "Počet"), (570, "Poznámka")]),
  (600, [(70, "Procedura ABC-17"), (390, "2"), (570, "vleže")]),
  (500, [(70, "Denní rozpis")]),
  (450, [(70, "Pondělí 02.11.2026")]),
  (400, [(70, "Čas"), (240, "Procedura"), (620, "Místnost")]),
  (350, [(70, "09:30"), (240, "Procedura ABC-17"), (620, "Místnost 21")]),
  (120, [(70, "Vytištěno 04.11.2026 12:05")])
]
let daily: [(Int, [(Int, String)])] = [
  (1015, [(70, "Léčebný průkaz")]),
  (935, [(70, "Úterý 03.11.2026")]),
  (860, [(70, "10:30"), (240, "Procedura XZ-40")]),
  (160, [(70, "Kontakt: recepce")])
]
pdf.beginPDFPage(nil)
draw(pdf, rows: head)
pdf.endPDFPage()
let bitmap = CGContext(data: nil, width: width * 2, height: height * 2, bitsPerComponent: 8,
  bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
bitmap.scaleBy(x: 2, y: 2)
draw(bitmap, rows: daily)
pdf.beginPDFPage(nil)
pdf.draw(bitmap.makeImage()!, in: media)
pdf.endPDFPage()
pdf.closePDF()

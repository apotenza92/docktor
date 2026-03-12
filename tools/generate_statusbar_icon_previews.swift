#!/usr/bin/env swift

import AppKit

struct PreviewSpec {
    let size: Int
}

let specs: [PreviewSpec] = [
    .init(size: 16),
    .init(size: 18),
    .init(size: 20),
    .init(size: 24),
    .init(size: 32)
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let outputDir = cwd.appendingPathComponent("artifacts/statusbar-icon-previews", isDirectory: true)

func lucidePoint(_ x: CGFloat, _ y: CGFloat, in rect: NSRect) -> NSPoint {
    NSPoint(
        x: rect.minX + rect.width * (x / 24.0),
        y: rect.minY + rect.height * ((24.0 - y) / 24.0)
    )
}

func drawStatusBarGlyph(pointSize: CGFloat, color: NSColor) -> NSImage {
    let size = NSSize(width: pointSize, height: pointSize)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    color.setStroke()

    func newStrokePath() -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 2.0
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        return path
    }

    let inset: CGFloat = max(0.65, pointSize * 0.055)
    let glyphRect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
    let strokeWidth = 2.0 * min(glyphRect.width, glyphRect.height) / 24.0

    let leaf = newStrokePath()
    leaf.lineWidth = strokeWidth
    leaf.move(to: lucidePoint(11.0, 20.0, in: glyphRect))
    leaf.curve(to: lucidePoint(9.8, 6.1, in: glyphRect),
               controlPoint1: lucidePoint(7.2, 18.0, in: glyphRect),
               controlPoint2: lucidePoint(6.9, 9.7, in: glyphRect))
    leaf.curve(to: lucidePoint(19.0, 2.0, in: glyphRect),
               controlPoint1: lucidePoint(15.5, 5.0, in: glyphRect),
               controlPoint2: lucidePoint(17.0, 4.48, in: glyphRect))
    leaf.curve(to: lucidePoint(21.0, 10.0, in: glyphRect),
               controlPoint1: lucidePoint(20.0, 4.0, in: glyphRect),
               controlPoint2: lucidePoint(21.0, 6.18, in: glyphRect))
    leaf.curve(to: lucidePoint(11.0, 20.0, in: glyphRect),
               controlPoint1: lucidePoint(21.0, 15.5, in: glyphRect),
               controlPoint2: lucidePoint(16.22, 20.0, in: glyphRect))
    leaf.close()
    leaf.stroke()

    let vein = newStrokePath()
    vein.lineWidth = strokeWidth
    vein.move(to: lucidePoint(2.0, 21.0, in: glyphRect))
    vein.curve(to: lucidePoint(7.08, 15.0, in: glyphRect),
               controlPoint1: lucidePoint(2.0, 18.0, in: glyphRect),
               controlPoint2: lucidePoint(3.85, 15.64, in: glyphRect))
    vein.curve(to: lucidePoint(13.0, 12.0, in: glyphRect),
               controlPoint1: lucidePoint(9.5, 14.52, in: glyphRect),
               controlPoint2: lucidePoint(12.0, 13.0, in: glyphRect))
    vein.stroke()

    return image
}

func composite(glyph: NSImage, canvasSize: Int, background: NSColor) -> NSImage {
    let s = CGFloat(canvasSize)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    background.setFill()
    rect.fill()
    glyph.draw(in: rect)

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "DockmintStatusBarPreview",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"]
        )
    }
    try data.write(to: url, options: .atomic)
}

try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

for spec in specs {
    let blackGlyph = drawStatusBarGlyph(pointSize: CGFloat(spec.size), color: .black)
    let whiteGlyph = drawStatusBarGlyph(pointSize: CGFloat(spec.size), color: .white)

    let templateURL = outputDir.appendingPathComponent("statusbar_template_\(spec.size).png")
    let lightURL = outputDir.appendingPathComponent("statusbar_on_light_\(spec.size).png")
    let darkURL = outputDir.appendingPathComponent("statusbar_on_dark_\(spec.size).png")

    try writePNG(blackGlyph, to: templateURL)
    try writePNG(composite(glyph: blackGlyph, canvasSize: spec.size, background: .white), to: lightURL)
    try writePNG(composite(glyph: whiteGlyph, canvasSize: spec.size, background: NSColor(calibratedWhite: 0.08, alpha: 1.0)), to: darkURL)

    print("Wrote \(templateURL.path)")
    print("Wrote \(lightURL.path)")
    print("Wrote \(darkURL.path)")
}

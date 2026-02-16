#!/usr/bin/env swift

import AppKit

struct IconSpec {
    let size: Int
    let filename: String
}

let specs: [IconSpec] = [
    .init(size: 16, filename: "icon_16x16.png"),
    .init(size: 32, filename: "icon_16x16@2x.png"),
    .init(size: 32, filename: "icon_32x32.png"),
    .init(size: 64, filename: "icon_32x32@2x.png"),
    .init(size: 128, filename: "icon_128x128.png"),
    .init(size: 256, filename: "icon_128x128@2x.png"),
    .init(size: 256, filename: "icon_256x256.png"),
    .init(size: 512, filename: "icon_256x256@2x.png"),
    .init(size: 512, filename: "icon_512x512.png"),
    .init(size: 1024, filename: "icon_512x512@2x.png"),
]

let fm = FileManager.default
let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = cwd.appendingPathComponent("DockActioner/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let contentsURL = iconset.appendingPathComponent("Contents.json")

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high
    let canvas = NSRect(x: 0, y: 0, width: s, height: s)
    NSColor.clear.setFill()
    canvas.fill()

    // Base rounded square with subtle depth that renders well in Tahoe-style icon treatments.
    let outerInset = s * 0.06
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outer = roundedRect(outerRect, radius: s * 0.23)

    let baseGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.14, green: 0.24, blue: 0.34, alpha: 1.0),
        NSColor(calibratedRed: 0.08, green: 0.15, blue: 0.23, alpha: 1.0)
    ])!
    baseGradient.draw(in: outer, angle: -90)

    let sheen = roundedRect(outerRect.insetBy(dx: s * 0.02, dy: s * 0.02), radius: s * 0.20)
    NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
    sheen.fill()

    // Unique square-like glyph: frame + paired tiles + diagonal connector.
    let glyphRect = outerRect.insetBy(dx: s * 0.24, dy: s * 0.24)
    let frame = roundedRect(glyphRect, radius: max(4, s * 0.08))
    frame.lineWidth = max(2.5, s * 0.07)
    NSColor(calibratedWhite: 1.0, alpha: 0.96).setStroke()
    frame.stroke()

    let module = max(5.0, round(glyphRect.width * 0.29))
    let moduleInset = max(3.0, round(glyphRect.width * 0.15))

    let topLeft = NSRect(
        x: glyphRect.minX + moduleInset,
        y: glyphRect.maxY - moduleInset - module,
        width: module,
        height: module
    )
    let bottomRight = NSRect(
        x: glyphRect.maxX - moduleInset - module,
        y: glyphRect.minY + moduleInset,
        width: module,
        height: module
    )

    NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
    roundedRect(topLeft, radius: max(1.0, module * 0.2)).fill()
    roundedRect(bottomRight, radius: max(1.0, module * 0.2)).fill()

    let connector = NSBezierPath()
    connector.lineWidth = max(2.2, s * 0.05)
    connector.lineCapStyle = .round
    connector.move(to: NSPoint(x: topLeft.maxX - module * 0.1, y: topLeft.minY + module * 0.1))
    connector.line(to: NSPoint(x: bottomRight.minX + module * 0.1, y: bottomRight.maxY - module * 0.1))
    connector.stroke()

    // Soft vignette to improve recognition at very small sizes.
    let vignette = NSGradient(colors: [
        NSColor(calibratedWhite: 0.0, alpha: 0.0),
        NSColor(calibratedWhite: 0.0, alpha: 0.18)
    ])!
    vignette.draw(in: outer, relativeCenterPosition: NSPoint(x: 0.0, y: -0.2))

    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "DockActionerIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"]) }
    try data.write(to: url, options: .atomic)
}

guard fm.fileExists(atPath: iconset.path) else {
    fputs("Missing iconset directory: \(iconset.path)\n", stderr)
    exit(1)
}

for spec in specs {
    let image = drawIcon(size: spec.size)
    let out = iconset.appendingPathComponent(spec.filename)
    try writePNG(image, to: out)
    print("Wrote \(out.path)")
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

try contents.data(using: .utf8)?.write(to: contentsURL, options: .atomic)
print("Updated \(contentsURL.path)")
